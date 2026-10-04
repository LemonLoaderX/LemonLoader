#if ANDROID
#nullable enable
using System;
using System.Threading;
using Java.Interop;

namespace MelonLoader.Android;

public readonly record struct JavaCallbackMethod(string Name, Delegate Handler);

/// <summary>An owned Java interface proxy and its managed callback registrations.</summary>
public sealed class JavaCallback<TPeer> : IDisposable where TPeer : JavaObject
{
    public TPeer Peer { get; }
    private long registrationId;
    internal JavaCallback(long registrationId, TPeer peer) { this.registrationId = registrationId; Peer = peer; }
    public void Dispose()
    {
        long value = Interlocked.Exchange(ref registrationId, 0);
        if (value == 0) return;
        JavaCallbacks.Remove(value);
        Peer.Dispose();
        GC.SuppressFinalize(this);
    }
    ~JavaCallback() { try { JavaCallbacks.Remove(Interlocked.Exchange(ref registrationId, 0)); } catch { } }
}

#endif
