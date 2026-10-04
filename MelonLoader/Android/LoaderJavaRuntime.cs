#if ANDROID
#nullable enable
using System;
using System.Collections.Generic;
using System.Threading;
using Java.Interop;

namespace MelonLoader.Android;

internal sealed class LoaderJavaRuntime : JniRuntime
{
    internal nint ApplicationClassLoader { get; }
    [ThreadStatic] private static int exceptionDepth;
    internal LoaderJavaRuntime(nint vm, nint loader) : base(new CreationOptions
    {
        InvocationPointer = vm, JniVersion = JniVersion.v1_6, DestroyRuntimeOnDispose = false,
        ClassLoader = loader == 0 ? default : new JniObjectReference(loader, JniObjectReferenceType.Global),
        TypeManager = new LoaderTypeManager(), ObjectReferenceManager = new LoaderReferenceManager(), ValueManager = new LoaderValueManager()
    }) { ApplicationClassLoader = loader; }

    public override Exception? GetExceptionForThrowable(ref JniObjectReference reference, JniObjectReferenceOptions options)
    {
        if (!reference.IsValid) return null;
        if (exceptionDepth >= 16)
        {
            JniObjectReference.Dispose(ref reference, options);
            return new InvalidOperationException("Java exception cause chain exceeds the conversion limit.");
        }
        exceptionDepth++;
        try { return new JavaException(ref reference, JniObjectReferenceOptions.Copy); }
        finally { exceptionDepth--; JniObjectReference.Dispose(ref reference, options); }
    }

    private sealed class LoaderTypeManager : ReflectionJniTypeManager
    {
        protected override IEnumerable<Type> GetTypesForSimpleReference(string name)
        {
            if (name == "java/lang/Object") yield return typeof(JavaObject);
            if (name == "java/lang/Throwable") yield return typeof(JavaException);
            foreach (var type in base.GetTypesForSimpleReference(name)) yield return type;
        }
    }

    private sealed class LoaderReferenceManager : JniObjectReferenceManager
    {
        private int globals, weak;
        public override int GlobalReferenceCount => Volatile.Read(ref globals);
        public override int WeakGlobalReferenceCount => Volatile.Read(ref weak);
        public override JniObjectReference CreateGlobalReference(JniObjectReference value)
        { var result = base.CreateGlobalReference(value); if (result.IsValid) Interlocked.Increment(ref globals); return result; }
        public override void DeleteGlobalReference(ref JniObjectReference value)
        { bool valid = value.IsValid; base.DeleteGlobalReference(ref value); if (valid) Interlocked.Decrement(ref globals); }
        public override JniObjectReference CreateWeakGlobalReference(JniObjectReference value)
        { var result = base.CreateWeakGlobalReference(value); if (result.IsValid) Interlocked.Increment(ref weak); return result; }
        public override void DeleteWeakGlobalReference(ref JniObjectReference value)
        { bool valid = value.IsValid; base.DeleteWeakGlobalReference(ref value); if (valid) Interlocked.Decrement(ref weak); }
    }

    private sealed class LoaderValueManager : ReflectionJniValueManager
    {
        private readonly Dictionary<int, List<WeakReference<IJavaPeerable>>> peers = new();
        public override void WaitForGCBridgeProcessing() { }
        public override void CollectPeers()
        {
            lock (peers)
            {
                foreach (var list in peers.Values) list.RemoveAll(w => !w.TryGetTarget(out _));
                var empty = new List<int>();
                foreach (var pair in peers) if (pair.Value.Count == 0) empty.Add(pair.Key);
                foreach (int key in empty) peers.Remove(key);
            }
        }
        public override void AddPeer(IJavaPeerable value)
        {
            lock (peers)
            {
                if (!peers.TryGetValue(value.JniIdentityHashCode, out var list))
                    peers.Add(value.JniIdentityHashCode, list = new());
                list.RemoveAll(w => !w.TryGetTarget(out _));
                foreach (var weak in list)
                    if (weak.TryGetTarget(out var peer) && ReferenceEquals(peer, value)) return;
                list.Add(new WeakReference<IJavaPeerable>(value, trackResurrection: true));
            }
        }
        public override void RemovePeer(IJavaPeerable value)
        {
            lock (peers)
                if (peers.TryGetValue(value.JniIdentityHashCode, out var list))
                {
                    list.RemoveAll(w => !w.TryGetTarget(out var peer) || ReferenceEquals(peer, value));
                    if (list.Count == 0) peers.Remove(value.JniIdentityHashCode);
                }
        }
        public override IJavaPeerable? PeekPeer(JniObjectReference reference)
        {
            if (!reference.IsValid) return null;
            int hash = GetJniIdentityHashCode(reference);
            lock (peers)
            {
                if (!peers.TryGetValue(hash, out var list)) return null;
                foreach (var weak in list)
                    if (weak.TryGetTarget(out var peer) && peer.PeerReference.IsValid &&
                        JniEnvironment.Types.IsSameObject(reference, peer.PeerReference)) return peer;
            }
            return null;
        }
        public override List<JniSurfacedPeerInfo> GetSurfacedPeers()
        {
            var result = new List<JniSurfacedPeerInfo>();
            lock (peers)
                foreach (var pair in peers)
                    foreach (var peer in pair.Value)
                        if (peer.TryGetTarget(out _)) result.Add(new JniSurfacedPeerInfo(pair.Key, peer));
            return result;
        }
        public override void DisposePeer(IJavaPeerable value)
        {
            if (!value.PeerReference.IsValid) return;
            using var thread = AndroidJava.AttachCurrentThread();
            base.DisposePeer(value);
        }
        public override void FinalizePeer(IJavaPeerable value)
        {
            try
            {
                using var thread = AndroidJava.AttachFinalizerThread();
                value.Finalized();
                RemovePeer(value);
                var reference = value.PeerReference;
                JniObjectReference.Dispose(ref reference);
                value.SetPeerReference(default);
            }
            catch (Exception e) { System.Diagnostics.Trace.TraceError("Java peer finalization failed: {0}", e); }
        }
    }
}
#endif
