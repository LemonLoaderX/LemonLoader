using System.Reflection;
using Java.Interop;
using MelonLoader.Android;

namespace LemonLoader.Tests.JniHost;

internal static class ArgumentCleanup
{
    internal static void Run(Action<string> log)
    {
        using var peer = new JavaObject();
        var method = new JavaBoundMethod(new JniPeerMembers("java/util/Objects", typeof(JavaObject)),
            "equals.(Ljava/lang/Object;Ljava/lang/Object;)Z", JavaInvocationKind.Static,
            new[] { typeof(CleanupValue), typeof(CleanupValue) }, "(Ljava/lang/Object;Ljava/lang/Object;)Z");
        var call = typeof(JavaInvocation).GetMethod("CallMany", BindingFlags.NonPublic | BindingFlags.Static)!
            .MakeGenericMethod(typeof(bool));
        int locals = JniEnvironment.LocalReferenceCount;
        CleanupMarshaler.Released = 0;
        try
        {
            call.Invoke(null, new object?[] { method, null,
                new object[] { new CleanupValue(peer, false), new CleanupValue(peer, true) } });
            throw new Exception("Throwing argument cleanup was ignored.");
        }
        catch (TargetInvocationException exception) when (exception.InnerException is InvalidOperationException) { }
        if (CleanupMarshaler.Released != 2 || JniEnvironment.LocalReferenceCount != locals || !peer.PeerReference.IsValid)
            throw new Exception("Throwing marshaler prevented remaining argument cleanup.");
        log("PASS throwing marshaler releases all argument locals without disposing caller");
    }
}

[JniValueMarshaler(typeof(CleanupMarshaler))]
public sealed record CleanupValue(JavaObject Peer, bool ThrowOnRelease);

public sealed class CleanupMarshaler : JniValueMarshaler
{
    internal static int Released;
    public override object? CreateValue(ref JniObjectReference reference, JniObjectReferenceOptions options,
        Type? targetType = null) => throw new NotSupportedException();
    public override JniValueMarshalerState CreateObjectReferenceArgumentState(object? value,
        ParameterAttributes synchronize = 0) => new(((CleanupValue)value!).Peer.PeerReference.NewLocalRef());
    public override void DestroyArgumentState(object? value, ref JniValueMarshalerState state,
        ParameterAttributes synchronize = 0)
    {
        var reference = state.ReferenceValue;
        JniObjectReference.Dispose(ref reference);
        state = default;
        Released++;
        if (((CleanupValue)value!).ThrowOnRelease)
            throw new InvalidOperationException("cleanup fixture");
    }
}
