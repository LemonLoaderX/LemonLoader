#if ANDROID
#nullable enable
using System;
using System.Collections.Generic;
using Java.Interop;

namespace MelonLoader.Java;

internal sealed class LoaderJniRuntime : JniRuntime
{
    [ThreadStatic] private static bool convertingException;
    internal JniObjectReference ApplicationClassLoader { get; private set; }
    internal LoaderJniRuntime(IntPtr vm, IntPtr env) : base(new CreationOptions
    {
        InvocationPointer = vm, EnvironmentPointer = env, JniVersion = JniVersion.v1_6,
        DestroyRuntimeOnDispose = false, TypeManager = new JniTypeManager(),
        ObjectReferenceManager = new References(), ValueManager = new Values()
    }) { }

    internal void SetClassLoader(JniObjectReference value)
    {
        if (ApplicationClassLoader.IsValid) throw new InvalidOperationException("Application classloader is already configured.");
        ApplicationClassLoader = value.NewGlobalRef();
    }

    public override Exception? GetExceptionForThrowable(ref JniObjectReference reference, JniObjectReferenceOptions options)
    {
        if (convertingException)
        {
            JniObjectReference.Dispose(ref reference, options);
            return new JThrowableException();
        }
        convertingException = true;
        JThrowable? throwable = null;
        try
        {
            throwable = JNI.Wrap<JThrowable>(reference.NewGlobalRef());
            using var type = new JniType("java/lang/Throwable");
            var summary = JniEnvironment.InstanceMethods.CallObjectMethod(reference,
                type.GetInstanceMethod("toString", "()Ljava/lang/String;"));
            string message;
            try { message = JniEnvironment.Strings.ToString(summary) ?? "A Java operation failed."; }
            finally { JniObjectReference.Dispose(ref summary); }
            string className = JniEnvironment.Types.GetJniTypeNameFromInstance(reference) ?? "java/lang/Throwable";
            string stack = "";
            try
            {
                using var log = new JniType("android/util/Log");
                JniArgumentValue argument = new(reference);
                unsafe
                {
                    var trace = JniEnvironment.StaticMethods.CallStaticObjectMethod(log.PeerReference,
                        log.GetStaticMethod("getStackTraceString", "(Ljava/lang/Throwable;)Ljava/lang/String;"), &argument);
                    try { stack = JniEnvironment.Strings.ToString(trace) ?? ""; }
                    finally { JniObjectReference.Dispose(ref trace); }
                }
            }
            catch { JniEnvironment.Exceptions.ExceptionClear(); }
            return new JThrowableException(throwable, className, message, stack);
        }
        catch
        {
            JniEnvironment.Exceptions.ExceptionClear();
            return new JThrowableException(throwable, "java.lang.Throwable", "A Java operation failed while converting its exception.", "");
        }
        finally { convertingException = false; JniObjectReference.Dispose(ref reference, options); }
    }

    private sealed class References : JniObjectReferenceManager
    {
        public override int GlobalReferenceCount => 0;
        public override int WeakGlobalReferenceCount => 0;
    }
    private sealed class Values : ReflectionJniValueManager
    {
        public override void WaitForGCBridgeProcessing() { }
        public override void CollectPeers() { }
        public override void AddPeer(IJavaPeerable value) { }
        public override void RemovePeer(IJavaPeerable value) { }
        public override void FinalizePeer(IJavaPeerable value) { }
        public override IJavaPeerable? PeekPeer(JniObjectReference reference) => null;
        public override List<JniSurfacedPeerInfo> GetSurfacedPeers() => new();
    }
}
#endif
