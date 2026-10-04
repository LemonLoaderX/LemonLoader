using System.Collections;
using System.Reflection;
using Java.Interop;
using MelonLoader.Android;

namespace LemonLoader.Tests.JniHost;

internal static class Hardening
{
    internal static void Run(Action<string> log)
    {
        var length = JavaBinding.BindInstance<Func<JavaObject, int>>("java/lang/StringBuilder", "length");
        using var unrelated = new JavaObject();
        try { length(unrelated); throw new Exception("Unrelated receiver accepted."); }
        catch (ArgumentException) { log("PASS wrong receiver rejected before JNI"); }
        using var valid = JavaBinding.BindConstructor<Func<JavaStringBuilder>>("java/lang/StringBuilder")();
        if (length(valid) != 0) throw new Exception("Broad valid receiver rejected.");
        try { JavaBinding.BindConstructor<Func<WrongPeer>>("java/lang/StringBuilder"); throw new Exception("Unrelated constructor return accepted."); }
        catch (ArgumentException) { log("PASS wrong constructor return rejected"); }

        var read = typeof(JavaBinding).GetMethod("ReadValue", BindingFlags.NonPublic | BindingFlags.Static)!.MakeGenericMethod(typeof(WrongPeer));
        int locals = JniEnvironment.LocalReferenceCount;
        var reference = unrelated.PeerReference.NewLocalRef();
        try { read.Invoke(null, new object[] { reference }); throw new Exception("Unrepresentable result accepted."); }
        catch (TargetInvocationException e) when (e.InnerException is InvalidCastException) { }
        if (JniEnvironment.LocalReferenceCount != locals) throw new Exception("Failed result conversion leaked a local.");
        log("PASS failed result conversion releases local");

        CheckScopes(log);

        using var payload = new JavaObjectArray<JavaObject>(new[] { unrelated, unrelated, null! });
        using var nestedPayload = new JavaObjectArray<JavaObjectArray<JavaObject>>(new[] { payload, null! });
        using var arguments = new JavaObjectArray<JavaObject>(new JavaObject[] { nestedPayload });
        JavaObject[][]? observed = null;
        Action<JavaObject[][]> callback = values =>
        {
            observed = values;
            if (ReferenceEquals(values[0][0], unrelated) || ReferenceEquals(values[0][0], values[0][1]) ||
                !values[0][0].PeerReference.IsValid || values[0][2] != null || values[1] != null)
                throw new Exception("Callback nested array ownership/null conversion failed.");
        };
        InvokeCallback(callback, arguments);
        int globals = AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount;
        for (int i = 0; i < 3; i++)
        {
            InvokeCallback(callback, arguments);
            if (JniEnvironment.Exceptions.ExceptionCheck() || observed == null || observed[0][0].PeerReference.IsValid ||
                observed[0][1].PeerReference.IsValid || !unrelated.PeerReference.IsValid ||
                AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount != globals)
                throw new Exception("Callback array cleanup leaked or disposed its caller's peer.");
        }
        log("PASS nested callback array independent ownership/release");
        InvokeCallback((Action<JavaObject[][]>)(values =>
        {
            observed = values;
            throw new InvalidOperationException("array-callback-fixture");
        }), arguments);
        if (!JniEnvironment.Exceptions.ExceptionCheck()) throw new Exception("Throwing array callback did not fail.");
        JniEnvironment.Exceptions.ExceptionClear();
        if (observed![0][0].PeerReference.IsValid || !unrelated.PeerReference.IsValid ||
            AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount != globals)
            throw new Exception("Throwing array callback cleanup failed.");
        log("PASS throwing callback array cleanup");

        using var objectArguments = new JavaObjectArray<JavaObject>(new JavaObject[] { payload });
        globals = AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount;
        InvokeCallback((Action<object[]>)(values =>
        {
            if (values[0] is not IJavaPeerable peer || ReferenceEquals(peer, unrelated))
                throw new Exception("Untyped callback peer mismatch: type=" + values[0]?.GetType().FullName + ", reused=" + ReferenceEquals(values[0], unrelated));
        }), objectArguments);
        if (JniEnvironment.Exceptions.ExceptionCheck())
        {
            var failure = JniEnvironment.Exceptions.ExceptionOccurred();
            JniEnvironment.Exceptions.ExceptionClear();
            using var error = new JavaException(ref failure, JniObjectReferenceOptions.CopyAndDispose);
            throw new Exception("Untyped callback conversion failed: " + error);
        }
        if (JniEnvironment.Exceptions.ExceptionCheck() || !unrelated.PeerReference.IsValid ||
            AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount != globals)
            throw new Exception($"Untyped callback array ownership failed: caller={unrelated.PeerReference.IsValid}, global delta={AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount - globals}.");
        log("PASS object callback array ownership");
        JavaObjectArray<JavaObject>? borrowed = null;
        InvokeCallback((Action<JavaObjectArray<JavaObject>>)(value => borrowed = value), objectArguments);
        if (JniEnvironment.Exceptions.ExceptionCheck() || borrowed == null || borrowed.PeerReference.IsValid ||
            !payload.PeerReference.IsValid || AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount != globals)
            throw new Exception("Callback Java array peer ownership failed.");
        log("PASS callback Java array peer ownership");

        using var list = JavaBinding.BindConstructor<Func<WrongPeer>>("java/util/ArrayList")();
        using var invalidPayload = new JavaObjectArray<JavaObject>(new JavaObject[] { list, unrelated });
        using var invalidArguments = new JavaObjectArray<JavaObject>(new JavaObject[] { invalidPayload });
        globals = AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount;
        InvokeCallback((Action<WrongPeer[]>)(_ => throw new Exception("Invalid callback ran.")), invalidArguments);
        if (!JniEnvironment.Exceptions.ExceptionCheck()) throw new Exception("Partial callback conversion did not fail.");
        JniEnvironment.Exceptions.ExceptionClear();
        if (!list.PeerReference.IsValid || !unrelated.PeerReference.IsValid ||
            AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount != globals)
            throw new Exception("Partial callback conversion leaked or disposed its caller's peer.");
        log("PASS partial callback conversion cleanup");
    }

    internal static void CheckScopes(Action<string> log)
    {
        var first = AndroidJava.AttachCurrentThread();
        var stale = first;
        first.Dispose();
        var next = AndroidJava.AttachCurrentThread();
        try { stale.Dispose(); throw new Exception("Stale scope accepted."); }
        catch (InvalidOperationException) { }
        var nested = AndroidJava.AttachCurrentThread();
        try { next.Dispose(); throw new Exception("Out-of-order scope accepted."); }
        catch (InvalidOperationException) { }
        nested.Dispose();
        next.Dispose(); next.Dispose();
        log("PASS stale scope copy/order");
    }

    private static void InvokeCallback(Delegate callback, JavaObject arguments)
    {
        // Exercise the production entry point without requiring Android's DEX loader
        // in the host JVM. The same ownership cases also run in the device probe.
        const long token = -77777;
        var type = typeof(JavaCallbacks);
        var handlerType = type.GetNestedType("Handler", BindingFlags.NonPublic)!;
        var definition = callback.GetType().GetMethod("Invoke")!;
        var handler = Activator.CreateInstance(handlerType, callback,
            definition.GetParameters().Select(p => p.ParameterType).ToArray(), definition.ReturnType);
        var map = (IDictionary)Activator.CreateInstance(typeof(Dictionary<,>).MakeGenericType(typeof(string), handlerType))!;
        map.Add("test", handler);
        var registry = (IDictionary)type.GetField("callbacks", BindingFlags.NonPublic | BindingFlags.Static)!.GetValue(null)!;
        registry.Add(token, map);
        var member = JniEnvironment.Strings.NewString("test");
        try
        {
            type.GetMethod("Invoke", BindingFlags.NonPublic | BindingFlags.Static)!.Invoke(null,
                new object[] { (nint)0, (nint)0, token, member.Handle, arguments.PeerReference.Handle });
        }
        finally { registry.Remove(token); JniObjectReference.Dispose(ref member); }
    }
}

[JniTypeSignature("java/util/ArrayList", GenerateJavaPeer = false)]
public sealed class WrongPeer : JavaObject
{
    public WrongPeer(ref JniObjectReference reference, JniObjectReferenceOptions options) : base(ref reference, options) { }
}
