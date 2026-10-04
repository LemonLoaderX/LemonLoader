#if ANDROID
#nullable enable
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using Java.Interop;

namespace MelonLoader.Android;

/// <summary>Java interface callbacks; dispose registrations after Java stops using the proxy.</summary>
public static unsafe class JavaCallbacks
{
    private static readonly ConcurrentDictionary<long, Dictionary<string, JavaCallbackHandler>> registrations = new();
    private static long nextRegistrationId;
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate nint NativeDispatch(nint environment, nint declaringClass, long registrationId, nint member, nint arguments);
    private static readonly NativeDispatch nativeDispatch = Dispatch;
    private static readonly Lazy<JavaCallbackBridge> bridge = new(() => JavaCallbackBridge.Load(nativeDispatch));

    public static JavaCallback<TPeer> Create<TPeer>(params JavaCallbackMethod[] methods) where TPeer : JavaObject
    {
        ArgumentNullException.ThrowIfNull(methods);
        using var thread = AndroidJava.AttachCurrentThread();
        var signature = AndroidJava.Runtime.TypeManager.GetTypeSignature(typeof(TPeer));
        if (!signature.IsValid || signature.ArrayRank != 0 || signature.SimpleReference == null)
            throw new ArgumentException("Callback peers require a Java interface JniTypeSignature.");
        var handlers = new Dictionary<string, JavaCallbackHandler>(StringComparer.Ordinal);
        foreach (var method in methods)
        {
            var handler = new JavaCallbackHandler(method);
            if (!handlers.TryAdd(handler.Member, handler))
                throw new ArgumentException("Duplicate callback: " + handler.Member, nameof(methods));
        }
        if (handlers.Count == 0) throw new ArgumentException("At least one callback is required.", nameof(methods));
        long registrationId = Interlocked.Increment(ref nextRegistrationId);
        registrations[registrationId] = handlers;
        try
        {
            var support = bridge.Value;
            JniArgumentValue argument = new(registrationId);
            var helper = JniEnvironment.Object.NewObject(support.Type.PeerReference, support.Constructor, &argument);
            try
            {
                using var names = new JavaObjectArray<string>(handlers.Keys.ToArray());
                var name = JniEnvironment.Strings.NewString(signature.SimpleReference);
                try
                {
                    JniArgumentValue* args = stackalloc JniArgumentValue[2] { new(name), new(names.PeerReference) };
                    var proxy = JniEnvironment.InstanceMethods.CallObjectMethod(helper, support.Proxy, args);
                    var peer = JavaObjectMarshaling.ReadLocalResult<TPeer>(ref proxy)
                        ?? throw new InvalidCastException("Callback proxy does not implement the requested Java interface.");
                    return new JavaCallback<TPeer>(registrationId, peer);
                }
                finally { JniObjectReference.Dispose(ref name); }
            }
            finally { JniObjectReference.Dispose(ref helper); }
        }
        catch { Remove(registrationId); throw; }
    }

    internal static void Remove(long registrationId)
    {
        if (registrationId != 0) registrations.TryRemove(registrationId, out _);
    }

    private static nint Dispatch(nint environment, nint declaringClass, long registrationId, nint member, nint arguments)
    {
        // No managed exception may escape the reverse P/Invoke boundary.
        try
        {
            using var thread = AndroidJava.AttachCurrentThread();
            var nameReference = new JniObjectReference(member, JniObjectReferenceType.Local);
            string name = JniEnvironment.Strings.ToString(nameReference) ?? "";
            if (!registrations.TryGetValue(registrationId, out var handlers) && name == "run.()V") return 0;
            if (handlers == null || !handlers.TryGetValue(name, out var handler))
                throw new ObjectDisposedException("Java callback", "Callback registration has ended or the method is not registered.");
            return handler.InvokeAndReturn(new JniObjectReference(arguments, JniObjectReferenceType.Local));
        }
        catch (Exception exception)
        {
            try
            {
                using var thread = AndroidJava.AttachCurrentThread();
                JniEnvironment.Exceptions.ExceptionClear();
                using var failure = new JniType("java/lang/RuntimeException");
                JniEnvironment.Exceptions.ThrowNew(failure.PeerReference, exception.ToString());
            }
            catch { }
            finally
            {
                try { if (exception is JavaException javaException) javaException.Dispose(); }
                catch { }
            }
            return 0;
        }
    }
}
#endif
