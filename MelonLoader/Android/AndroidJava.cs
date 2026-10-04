#if ANDROID
#nullable enable
using System;
using System.Threading;
using Java.Interop;

namespace MelonLoader.Android;

/// <summary>Process hosting and scoped access to the game's Java VM.</summary>
public static unsafe class AndroidJava
{
    private static readonly object gate = new();
    private static LoaderJavaRuntime? runtime;
    [ThreadStatic] private static int depth;
    [ThreadStatic] private static bool detach;
    [ThreadStatic] private static long nextScope, currentScope;
    public static JniRuntime Runtime => runtime ?? throw new InvalidOperationException("Android Java hosting is not initialized.");

    internal static void Initialize(nint vm, nint classLoader = 0)
    {
        lock (gate)
        {
            if (runtime != null) throw new InvalidOperationException("Java hosting is already initialized.");
            if (vm == 0) throw new ArgumentException("A borrowed Java VM is required.", nameof(vm));
            AppContext.SetSwitch("Java.Interop.RuntimeFeature.ManagedPeerNativeRegistration", false);
            runtime = new LoaderJavaRuntime(vm, classLoader);
        }
    }

    /// <summary>Use on the same thread, in reverse order, without crossing await.</summary>
    public static ThreadScope AttachCurrentThread()
    {
        if (depth != 0) return BeginScope();
        var vm = Runtime.InvocationPointer;
        nint env = 0;
        var get = (delegate* unmanaged<nint, nint*, int, int>)(*(nint**)vm)[6];
        int status = get(vm, &env, 0x10006);
        if (status != 0 && status != -2) throw new InvalidOperationException($"GetEnv failed: {status}.");
        if (depth == 0) detach = status == -2;
        // Explicit attach refreshes Java.Interop's TLS after a previous detach.
        Runtime.AttachCurrentThread();
        return BeginScope();
    }

    private static ThreadScope BeginScope()
    {
        long parent = currentScope;
        currentScope = ++nextScope;
        return new ThreadScope(Environment.CurrentManagedThreadId, ++depth, currentScope, parent);
    }

    internal static ThreadScope AttachFinalizerThread()
    {
        var scope = AttachCurrentThread();
        // JavaObject's finalizer reads JniEnvironment.Runtime before calling the
        // value manager, which may already attach this CLR-owned finalizer thread.
        if (depth == 1) detach = true;
        return scope;
    }

    public ref struct ThreadScope
    {
        private readonly int thread, level;
        private readonly long id, parent;
        private bool disposed;
        internal ThreadScope(int thread, int level, long id, long parent)
        { this.thread = thread; this.level = level; this.id = id; this.parent = parent; }
        public void Dispose()
        {
            if (disposed || id == 0) return;
            if (thread != Environment.CurrentManagedThreadId || level != depth || id != currentScope)
                throw new InvalidOperationException("Java thread scopes must end in reverse order on their creating thread.");
            currentScope = parent;
            disposed = true;
            if (--depth == 0 && detach)
            {
                detach = false;
                var vm = Runtime.InvocationPointer;
                int result = ((delegate* unmanaged<nint, int>)(*(nint**)vm)[5])(vm);
                if (result != 0) throw new InvalidOperationException($"DetachCurrentThread failed: {result}.");
            }
        }
    }
}
#endif
