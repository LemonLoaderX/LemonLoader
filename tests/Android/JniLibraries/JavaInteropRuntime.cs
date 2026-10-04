using Java.Interop;

namespace LemonLoader.Tests.JniLibraries;

internal sealed class ExistingRuntime : JniRuntime
{
    public ExistingRuntime(nint vm, nint env, nint classLoader = 0) : base(new CreationOptions
    {
        InvocationPointer = vm,
        EnvironmentPointer = env,
        JniVersion = JniVersion.v1_6,
        DestroyRuntimeOnDispose = false,
        ClassLoader = new JniObjectReference(classLoader, JniObjectReferenceType.Global),
        TypeManager = new JniTypeManager(),
        ObjectReferenceManager = new References(),
        ValueManager = new Values()
    }) { }

    public override Exception? GetExceptionForThrowable(ref JniObjectReference reference, JniObjectReferenceOptions options)
    {
        // Basic JNI does not need JavaException's managed-peer registration.
        try
        {
            using var type = new JniType("java/lang/Throwable");
            var message = JniEnvironment.InstanceMethods.CallObjectMethod(reference,
                type.GetInstanceMethod("toString", "()Ljava/lang/String;"));
            try { return new InvalidOperationException(JniEnvironment.Strings.ToString(message)); }
            finally { JniObjectReference.Dispose(ref message); }
        }
        finally { JniObjectReference.Dispose(ref reference, options); }
    }

    private sealed class References : JniObjectReferenceManager
    {
        public override int GlobalReferenceCount => 0;
        public override int WeakGlobalReferenceCount => 0;
    }

    // Evaluation uses raw JNI references rather than managed Java peer bindings.
    private sealed class Values : ReflectionJniValueManager
    {
        public override void WaitForGCBridgeProcessing() { }
        public override void CollectPeers() { }
        public override void AddPeer(IJavaPeerable value) { }
        public override void RemovePeer(IJavaPeerable value) { }
        public override void FinalizePeer(IJavaPeerable value) { }
        public override IJavaPeerable? PeekPeer(JniObjectReference reference) => null;
        public override List<JniSurfacedPeerInfo> GetSurfacedPeers() => [];
    }
}
