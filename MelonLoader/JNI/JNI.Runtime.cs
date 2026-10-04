#if ANDROID
#nullable enable
using System;
using System.Collections.Generic;
using System.Threading;
using Java.Interop;

namespace MelonLoader.Java;

public static unsafe partial class JNI
{
    private static readonly object runtimeLock = new();
    private static LoaderJniRuntime? runtime;
    internal static IntPtr lastVmPtr;
    [ThreadStatic] private static bool attachedByLoader;
    [ThreadStatic] private static bool threadInitialized;
    [ThreadStatic] internal static int ThreadGeneration;
    [ThreadStatic] private static int scopeDepth;
    [ThreadStatic] private static bool detachOnScopeExit;
    [ThreadStatic] internal static LocalFrameState? CurrentFrame;
    private static readonly Dictionary<string, JClass> classes = new(StringComparer.Ordinal);

    public static IntPtr JavaVM => lastVmPtr;

    public static void Initialize(IntPtr vmPtr)
    {
        lock (runtimeLock)
        {
            if (vmPtr == IntPtr.Zero) vmPtr = lastVmPtr;
            if (vmPtr == IntPtr.Zero) throw new InvalidOperationException("The Java VM has not been initialized.");
            if (runtime != null)
            {
                if (lastVmPtr != vmPtr) throw new InvalidOperationException("Loader cannot change Java VM.");
                EnsureThread();
                return;
            }
            lastVmPtr = vmPtr;
            nint env = GetEnvironment(vmPtr);
            if (env == 0)
            {
                var attach = (delegate* unmanaged<nint, nint*, nint, int>)(*(nint**)vmPtr)[4];
                int result = attach(vmPtr, &env, 0);
                if (result != 0 || env == 0) throw new InvalidOperationException($"AttachCurrentThread failed: {result}.");
                attachedByLoader = true;
            }
            AppContext.SetSwitch("Java.Interop.RuntimeFeature.ManagedPeerNativeRegistration", false);
            runtime = new LoaderJniRuntime(vmPtr, env);
            threadInitialized = true;
        }
    }

    internal static void EnsureThread()
    {
        if (runtime == null) { Initialize(lastVmPtr); return; }
        if (threadInitialized) return;
        bool wasDetached = GetEnvironment(lastVmPtr) == 0;
        runtime.AttachCurrentThread();
        attachedByLoader = wasDetached;
        threadInitialized = true;
    }

    internal static nint GetEnvironment(nint vm)
    {
        nint env = 0;
        var get = (delegate* unmanaged<nint, nint*, int, int>)(*(nint**)vm)[6];
        int status = get(vm, &env, 0x10006);
        if (status != 0 && status != -2) throw new InvalidOperationException($"GetEnv failed: {status}.");
        return status == 0 ? env : 0;
    }

    /// <summary>Attach this thread if needed. Dispose on the same thread before awaiting.</summary>
    public static JniThreadScope AttachCurrentThread()
    {
        bool attached = threadInitialized || (runtime != null && GetEnvironment(lastVmPtr) != 0);
        EnsureThread();
        if (scopeDepth == 0) detachOnScopeExit = !attached && attachedByLoader;
        scopeDepth++;
        return new JniThreadScope(Environment.CurrentManagedThreadId, scopeDepth);
    }

    public sealed class JniThreadScope : IDisposable
    {
        private readonly int thread, depth;
        private bool disposed;
        internal JniThreadScope(int thread, int depth) { this.thread = thread; this.depth = depth; }
        public void Dispose()
        {
            if (disposed) return;
            if (thread != Environment.CurrentManagedThreadId || scopeDepth != depth)
                throw new InvalidOperationException("JNI thread scopes must end in reverse order on their creating thread.");
            if (CurrentFrame != null && scopeDepth == 1 && detachOnScopeExit)
                throw new InvalidOperationException("Dispose local frames before detaching the thread.");
            scopeDepth--;
            if (scopeDepth == 0 && detachOnScopeExit) DetachCurrentThread();
            disposed = true;
        }
    }

    public static void DetachCurrentThread()
    {
        if (!attachedByLoader) return;
        if (scopeDepth != 0 || CurrentFrame != null) throw new InvalidOperationException("Active JNI scopes prevent thread detachment.");
        var detach = (delegate* unmanaged<nint, int>)(*(nint**)lastVmPtr)[5];
        int result = detach(lastVmPtr);
        if (result != 0) throw new InvalidOperationException($"DetachCurrentThread failed: {result}.");
        attachedByLoader = false;
        threadInitialized = false;
        ThreadGeneration++;
        // Java.Interop refreshes its cached JNIEnv on the next explicit attach.
    }

    internal sealed class LocalFrameState
    {
        internal bool Active = true;
        internal readonly LocalFrameState? Parent;
        internal readonly System.Collections.Generic.List<JObject> References = new();
        internal LocalFrameState(LocalFrameState? parent) { Parent = parent; }
    }

    public sealed class JniLocalFrame : IDisposable
    {
        private readonly int thread = Environment.CurrentManagedThreadId;
        private readonly LocalFrameState state;
        internal JniLocalFrame(int capacity)
        {
            EnsureThread();
            if (capacity < 0) throw new ArgumentOutOfRangeException(nameof(capacity));
            JniEnvironment.References.PushLocalFrame(capacity);
            state = new LocalFrameState(CurrentFrame);
            CurrentFrame = state;
        }
        public void Dispose()
        {
            if (!state.Active) return;
            if (thread != Environment.CurrentManagedThreadId || CurrentFrame != state)
                throw new InvalidOperationException("JNI local frames must end in reverse order on their creating thread.");
            foreach (var reference in state.References) reference.Dispose();
            JniEnvironment.References.PopLocalFrame(default);
            state.Active = false;
            CurrentFrame = state.Parent;
            state.References.Clear();
        }
    }

    public static JniLocalFrame LocalFrame(int capacity = 32) => new(capacity);
    public static int GetVersion() { EnsureThread(); return (int)JniEnvironment.JniVersion; }
    public static bool ExceptionCheck() { EnsureThread(); return JniEnvironment.Exceptions.ExceptionCheck(); }
    public static void ExceptionClear() { EnsureThread(); JniEnvironment.Exceptions.ExceptionClear(); }
    public static void ExceptionDescribe() { EnsureThread(); JniEnvironment.Exceptions.ExceptionDescribe(); }

    public static void CheckExceptionAndThrow()
    {
        EnsureThread();
        var exception = JniEnvironment.Exceptions.ExceptionOccurred();
        if (!exception.IsValid) return;
        JniEnvironment.Exceptions.ExceptionClear();
        throw runtime!.GetExceptionForThrowable(ref exception, JniObjectReferenceOptions.CopyAndDispose)!;
    }

    internal static void SetApplicationClassLoader(JObject loader)
    {
        runtime!.SetClassLoader(loader.Reference);
    }

    internal static void ReleaseReference(ref JniObjectReference reference)
    {
        if (threadInitialized) { JniObjectReference.Dispose(ref reference); return; }
        using var thread = AttachCurrentThread();
        JniObjectReference.Dispose(ref reference);
    }

    internal static JniObjectReferenceType ToInteropType(ReferenceType type) => type switch
    {
        ReferenceType.Local => JniObjectReferenceType.Local,
        ReferenceType.Global => JniObjectReferenceType.Global,
        ReferenceType.WeakGlobal => JniObjectReferenceType.WeakGlobal,
        _ => throw new ArgumentOutOfRangeException(nameof(type))
    };
}
#endif
