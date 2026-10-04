#if ANDROID
#nullable enable
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using Java.Interop;

namespace MelonLoader.Android;

public readonly record struct JavaCallbackMethod(string Name, Delegate Handler);

/// <summary>An owned Java interface proxy and its managed callback registrations.</summary>
public sealed class JavaCallback<TPeer> : IDisposable where TPeer : JavaObject
{
    public TPeer Peer { get; }
    private long token;
    internal JavaCallback(long token, TPeer peer) { this.token = token; Peer = peer; }
    public void Dispose()
    {
        long value = Interlocked.Exchange(ref token, 0);
        if (value == 0) return;
        JavaCallbacks.Remove(value);
        Peer.Dispose();
        GC.SuppressFinalize(this);
    }
    ~JavaCallback() { try { JavaCallbacks.Remove(Interlocked.Exchange(ref token, 0)); } catch { } }
}

/// <summary>Java interface callbacks; dispose registrations after Java stops using the proxy.</summary>
public static unsafe class JavaCallbacks
{
    private sealed record Handler(Delegate Callback, Type[] Arguments, Type Result);
    private static readonly ConcurrentDictionary<long, Dictionary<string, Handler>> callbacks = new();
    private static readonly Lazy<Bridge> bridge = new(CreateBridge);
    private static long next;
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate nint InvokeCallback(nint env, nint type, long token, nint member, nint arguments);
    private static readonly InvokeCallback invoke = Invoke;

    public static JavaCallback<TPeer> Create<TPeer>(params JavaCallbackMethod[] methods) where TPeer : JavaObject
    {
        using var thread = AndroidJava.AttachCurrentThread();
        var signature = AndroidJava.Runtime.TypeManager.GetTypeSignature(typeof(TPeer));
        if (!signature.IsValid || signature.ArrayRank != 0 || signature.SimpleReference == null)
            throw new ArgumentException("Callback peers require a Java interface JniTypeSignature.");
        var handlers = new Dictionary<string, Handler>(StringComparer.Ordinal);
        foreach (var method in methods)
        {
            ArgumentNullException.ThrowIfNull(method.Handler);
            if (string.IsNullOrWhiteSpace(method.Name)) throw new ArgumentException("Callback name is required.");
            var definition = method.Handler.GetType().GetMethod("Invoke")!;
            var arguments = definition.GetParameters().Select(p => p.ParameterType).ToArray();
            if (arguments.Any(t => t.IsByRef || t.IsPointer)) throw new ArgumentException("Callback arguments cannot be pointers or ref values.");
            string member = method.Name + ".(" + string.Concat(arguments.Select(Descriptor)) + ")" + Descriptor(definition.ReturnType);
            handlers.Add(member, new Handler(method.Handler, arguments, definition.ReturnType));
        }
        if (handlers.Count == 0) throw new ArgumentException("At least one callback is required.");
        long token = Interlocked.Increment(ref next);
        callbacks[token] = handlers;
        try
        {
            var b = bridge.Value;
            JniArgumentValue arg = new(token);
            var helper = JniEnvironment.Object.NewObject(b.Type.PeerReference, b.Constructor, &arg);
            try
            {
                var names = new JavaObjectArray<string>(handlers.Keys.ToArray());
                var name = JniEnvironment.Strings.NewString(signature.SimpleReference);
                try
                {
                    JniArgumentValue* args = stackalloc JniArgumentValue[2] { new(name), new(names.PeerReference) };
                    var proxy = JniEnvironment.InstanceMethods.CallObjectMethod(helper, b.Proxy, args);
                    var peer = JavaBinding.ReadValue<TPeer>(ref proxy);
                    if (peer == null) throw new InvalidCastException("Callback proxy does not implement the requested Java interface.");
                    return new JavaCallback<TPeer>(token, peer);
                }
                finally { JniObjectReference.Dispose(ref name); names.Dispose(); }
            }
            finally { JniObjectReference.Dispose(ref helper); }
        }
        catch { callbacks.TryRemove(token, out _); throw; }
    }

    internal static void Remove(long token) { if (token != 0) callbacks.TryRemove(token, out _); }
    private static string Descriptor(Type type)
    {
        return JavaBinding.Signature(type);
    }

    private static nint Invoke(nint env, nint type, long token, nint member, nint arguments)
    {
        // No managed exception may escape the reverse P/Invoke boundary.
        try
        {
            using var thread = AndroidJava.AttachCurrentThread();
            var nameRef = new JniObjectReference(member, JniObjectReferenceType.Local);
            string name = JniEnvironment.Strings.ToString(nameRef) ?? "";
            if (!callbacks.TryGetValue(token, out var methods) && name == "run.()V") return 0;
            if (methods == null || !methods.TryGetValue(name, out var handler))
                throw new ObjectDisposedException("Java callback", "Callback registration has ended or the method is not registered.");
            var array = new JniObjectReference(arguments, JniObjectReferenceType.Local);
            if (JniEnvironment.Arrays.GetArrayLength(array) != handler.Arguments.Length) throw new ArgumentException("Java callback argument count differs.");
            var values = new object?[handler.Arguments.Length];
            var owned = new List<IJavaPeerable>();
            try
            {
                for (int i = 0; i < values.Length; i++)
                {
                    var item = JniEnvironment.Arrays.GetObjectArrayElement(array, i);
                    try { values[i] = ReadArgument(item, handler.Arguments[i], owned); }
                    finally { JniObjectReference.Dispose(ref item); }
                }
                object? result;
                try { result = handler.Callback.DynamicInvoke(values); }
                catch (TargetInvocationException e) when (e.InnerException != null) { throw e.InnerException; }
                if (handler.Result == typeof(void)) return 0;
                var reference = AndroidJava.Runtime.ValueManager.CreateLocalObjectReferenceArgument(handler.Result, result);
                try { return JniEnvironment.References.NewReturnToJniRef(reference); }
                finally { JniObjectReference.Dispose(ref reference); }
            }
            finally { for (int i = owned.Count - 1; i >= 0; i--) owned[i].Dispose(); }
        }
        catch (Exception e)
        {
            try
            {
                using var thread = AndroidJava.AttachCurrentThread();
                JniEnvironment.Exceptions.ExceptionClear();
                using var failure = new JniType("java/lang/RuntimeException");
                JniEnvironment.Exceptions.ThrowNew(failure.PeerReference, e.ToString());
            }
            catch { }
            return 0;
        }
    }

    private static object? ReadArgument(JniObjectReference reference, Type type, List<IJavaPeerable> owned)
    {
        if (!reference.IsValid) return null;
        // Upstream array marshaling uses GetValue for elements, which can reuse a
        // caller's registered peer. Scoped callback arguments must own new peers.
        if (type.IsArray && !type.GetElementType()!.IsPrimitive)
        {
            var elementType = type.GetElementType()!;
            var array = Array.CreateInstance(elementType, JniEnvironment.Arrays.GetArrayLength(reference));
            for (int i = 0; i < array.Length; i++)
            {
                var item = JniEnvironment.Arrays.GetObjectArrayElement(reference, i);
                try { array.SetValue(ReadArgument(item, elementType, owned), i); }
                finally { JniObjectReference.Dispose(ref item); }
            }
            return array;
        }
        var manager = AndroidJava.Runtime.ValueManager;
        bool peerType = typeof(IJavaPeerable).IsAssignableFrom(type);
        object? value = peerType
            ? manager.CreatePeer(ref reference, JniObjectReferenceOptions.CopyAndDoNotRegister, type)
            : manager.CreateValue(ref reference, JniObjectReferenceOptions.CopyAndDoNotRegister, type);
        if (!peerType && value is IJavaPeerable existing && ReferenceEquals(existing, manager.PeekPeer(reference)))
            value = manager.CreatePeer(ref reference, JniObjectReferenceOptions.CopyAndDoNotRegister, existing.GetType());
        if (value == null) throw new InvalidCastException("Java callback argument cannot be represented as " + type.FullName + ".");
        if (value is IJavaPeerable peer) owned.Add(peer);
        return value;
    }

    private sealed record Bridge(JniType Type, JniMethodInfo Constructor, JniMethodInfo Proxy,
        JavaClassLoader Loader, JavaByteBuffer Buffer);
    private static Bridge CreateBridge()
    {
        using var thread = AndroidJava.AttachCurrentThread();
        var host = (LoaderJavaRuntime)AndroidJava.Runtime;
        if (host.ApplicationClassLoader == 0) throw new InvalidOperationException("Android callbacks require the application's ClassLoader.");
        using var resource = typeof(AndroidJava).Assembly.GetManifestResourceStream("MelonLoader.Android.Callbacks.dex")
            ?? throw new FileNotFoundException("Embedded Android callback support is missing.");
        using var memory = new MemoryStream();
        resource.CopyTo(memory);
        var data = memory.ToArray();
        var signed = MemoryMarshal.Cast<byte, sbyte>(data).ToArray();
        var wrap = JavaBinding.BindStatic<Func<sbyte[], JavaByteBuffer>>("java/nio/ByteBuffer", "wrap");
        var buffer = wrap(signed);
        var original = new JniObjectReference(host.ApplicationClassLoader, JniObjectReferenceType.Global);
        using var parent = new JavaClassLoader(ref original, JniObjectReferenceOptions.CopyAndDoNotRegister);
        JavaClassLoader? loader = null;
        try
        {
            var create = JavaBinding.BindConstructor<Func<JavaByteBuffer, JavaClassLoader, JavaClassLoader>>("dalvik/system/InMemoryDexClassLoader");
            loader = create(buffer, parent);
            using var klass = loader.LoadClass("org.lemonloader.interop.NativeCallback");
            var reference = klass.PeerReference;
            var type = new JniType(ref reference, JniObjectReferenceOptions.Copy);
            type.RegisterNativeMethods(new JniNativeMethodRegistration("invoke", "(JLjava/lang/String;[Ljava/lang/Object;)Ljava/lang/Object;", invoke));
            return new Bridge(type, type.GetInstanceMethod("<init>", "(J)V"),
                type.GetInstanceMethod("proxy", "(Ljava/lang/String;[Ljava/lang/String;)Ljava/lang/Object;"), loader, buffer);
        }
        catch { loader?.Dispose(); buffer.Dispose(); throw; }
    }
}

[JniTypeSignature("java/lang/Runnable", GenerateJavaPeer = false)]
public sealed class JavaRunnable : JavaObject
{
    private static readonly JniPeerMembers members = new("java/lang/Runnable", typeof(JavaRunnable), isInterface: true);
    private static readonly Action<JavaRunnable> run = JavaBinding.BindInstance<Action<JavaRunnable>>("java/lang/Runnable", "run");
    public override JniPeerMembers JniPeerMembers => members;
    public JavaRunnable(ref JniObjectReference reference, JniObjectReferenceOptions options) : base(ref reference, options) { }
    public void Run() => run(this);
}

[JniTypeSignature("java/nio/ByteBuffer", GenerateJavaPeer = false)]
internal sealed class JavaByteBuffer : JavaObject
{
    public JavaByteBuffer(ref JniObjectReference reference, JniObjectReferenceOptions options) : base(ref reference, options) { }
}

[JniTypeSignature("java/lang/ClassLoader", GenerateJavaPeer = false)]
internal sealed class JavaClassLoader : JavaObject
{
    private static readonly Func<JavaClassLoader, string, JavaClass> load = JavaBinding.BindInstance<Func<JavaClassLoader, string, JavaClass>>("java/lang/ClassLoader", "loadClass");
    public JavaClassLoader(ref JniObjectReference reference, JniObjectReferenceOptions options) : base(ref reference, options) { }
    internal JavaClass LoadClass(string name) => load(this, name);
}

[JniTypeSignature("java/lang/Class", GenerateJavaPeer = false)]
internal sealed class JavaClass : JavaObject
{
    public JavaClass(ref JniObjectReference reference, JniObjectReferenceOptions options) : base(ref reference, options) { }
}

/// <summary>Dispatch managed work to Android's main thread and observe its completion.</summary>
public static class AndroidThread
{
    private static readonly Action<AndroidActivity, JavaRunnable> post =
        JavaBinding.BindInstance<Action<AndroidActivity, JavaRunnable>>("android/app/Activity", "runOnUiThread");
    public static Task RunAsync(Action action, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(action);
        cancellationToken.ThrowIfCancellationRequested();
        using var thread = AndroidJava.AttachCurrentThread();
        using var activity = UnityPlayer.CurrentActivity ?? throw new InvalidOperationException("Unity Activity is unavailable.");
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        JavaCallback<JavaRunnable>? callback = null;
        callback = JavaCallbacks.Create<JavaRunnable>(new JavaCallbackMethod("run", (Action)(() =>
        {
            try { if (!completion.Task.IsCompleted) { action(); completion.TrySetResult(); } }
            catch (Exception e) { completion.TrySetException(e); }
            finally { callback!.Dispose(); }
        })));
        try { post(activity, callback.Peer); }
        catch { callback.Dispose(); throw; }
        var cancellation = cancellationToken.Register(() =>
        {
            completion.TrySetCanceled(cancellationToken);
            callback.Dispose();
        });
        return Observe(completion.Task, cancellation);
    }

    private static async Task Observe(Task task, CancellationTokenRegistration cancellation)
    { try { await task.ConfigureAwait(false); } finally { cancellation.Dispose(); } }
}
#endif
