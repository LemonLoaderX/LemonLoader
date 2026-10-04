using System.Reflection;
using Java.Interop;
using MelonLoader.Android;

namespace LemonLoader.Tests.JniHost;

internal static class Hardening
{
    internal static void Run(Action<string> log)
    {
        CheckDefinitions(log);
        CheckUiWork(log);
#if JNI_HOST_FIXTURE
        ArgumentCleanup.Run(log);
#endif
        var length = JavaBinding.BindInstance<Func<JavaObject, int>>("java/lang/StringBuilder", "length");
        using var unrelated = new JavaObject();
        try { length(unrelated); throw new Exception("Unrelated receiver accepted."); }
        catch (ArgumentException) { log("PASS wrong receiver rejected before JNI"); }
        using var valid = JavaBinding.BindConstructor<Func<JavaStringBuilder>>("java/lang/StringBuilder")();
        if (length(valid) != 0) throw new Exception("Broad valid receiver rejected.");
        try { JavaBinding.BindConstructor<Func<WrongPeer>>("java/lang/StringBuilder"); throw new Exception("Unrelated constructor return accepted."); }
        catch (ArgumentException) { log("PASS wrong constructor return rejected"); }

        var read = typeof(JavaBinding).Assembly.GetType("MelonLoader.Android.JavaObjectMarshaling")!
            .GetMethod("ReadLocalResult", BindingFlags.NonPublic | BindingFlags.Static)!.MakeGenericMethod(typeof(WrongPeer));
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
        }), arguments, typeof(InvalidOperationException));
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
        IJavaPeerable? dynamicArray = null;
        InvokeCallback((Action<object>)(value => dynamicArray = (IJavaPeerable)value), objectArguments);
        if (JniEnvironment.Exceptions.ExceptionCheck() || dynamicArray == null || dynamicArray.PeerReference.IsValid ||
            !payload.PeerReference.IsValid || !unrelated.PeerReference.IsValid ||
            AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount != globals)
            throw new Exception("Runtime-typed callback array ownership failed.");
        log("PASS runtime-typed callback array ownership");

        using var cyclic = new JavaObjectArray<JavaObject>(1);
        cyclic[0] = cyclic;
        using var cyclicArguments = new JavaObjectArray<JavaObject>(new JavaObject[] { cyclic });
        int cyclicGlobals = AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount;
        InvokeCallback((Action<object>)(value => dynamicArray = (IJavaPeerable)value), cyclicArguments);
        if (JniEnvironment.Exceptions.ExceptionCheck() || dynamicArray!.PeerReference.IsValid ||
            !cyclic.PeerReference.IsValid || AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount != cyclicGlobals)
            throw new Exception("Cyclic callback array cleanup failed.");
        log("PASS cyclic callback array peer ownership");
        using var boxed = new JavaObjectArray<object>(new object[] { 42, "value", unrelated });
        using var boxedArguments = new JavaObjectArray<JavaObject>(new JavaObject[] { boxed });
        Action<object[]> boxedCallback = values =>
        {
            if (values[0] is not int number || number != 42 || values[1] is not string text || text != "value" ||
                values[2] is not IJavaPeerable peer || ReferenceEquals(peer, unrelated))
                throw new Exception("Object callback boxing/string conversion changed.");
        };
        InvokeCallback(boxedCallback, boxedArguments);
        if (JniEnvironment.Exceptions.ExceptionCheck()) throw new Exception("Object callback boxing failed.");
        globals = AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount;
        InvokeCallback(boxedCallback, boxedArguments);
        if (JniEnvironment.Exceptions.ExceptionCheck() || !unrelated.PeerReference.IsValid ||
            AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount != globals)
            throw new Exception("Object callback boxing cleanup failed.");
        log("PASS object callback boxing/string ownership");
        globals = AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount;
        JavaObjectArray<JavaObject>? borrowed = null;
        InvokeCallback((Action<JavaObjectArray<JavaObject>>)(value => borrowed = value), objectArguments);
        if (JniEnvironment.Exceptions.ExceptionCheck() || borrowed == null || borrowed.PeerReference.IsValid ||
            !payload.PeerReference.IsValid || AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount != globals)
            throw new Exception("Callback Java array peer ownership failed.");
        log("PASS callback Java array peer ownership");
        using var primitive = new JavaSByteArray(new sbyte[] { 1, 2, 3 });
        using var primitiveArguments = new JavaObjectArray<JavaObject>(new JavaObject[] { primitive });
        JavaSByteArray? primitivePeer = null;
        Action<JavaSByteArray> primitiveCallback = value =>
        {
            primitivePeer = value;
            if (ReferenceEquals(value, primitive) || !value.ToArray().SequenceEqual(new sbyte[] { 1, 2, 3 }))
                throw new Exception("Primitive callback array wrapper changed.");
        };
        InvokeCallback(primitiveCallback, primitiveArguments);
        int primitiveGlobals = AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount;
        InvokeCallback(primitiveCallback, primitiveArguments);
        if (JniEnvironment.Exceptions.ExceptionCheck() || primitivePeer == null || primitivePeer.PeerReference.IsValid ||
            !primitive.PeerReference.IsValid || AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount != primitiveGlobals)
            throw new Exception("Primitive callback array wrapper ownership failed.");
        log("PASS callback primitive array peer ownership");

        using var list = JavaBinding.BindConstructor<Func<WrongPeer>>("java/util/ArrayList")();
        using var invalidPayload = new JavaObjectArray<JavaObject>(new JavaObject[] { list, unrelated });
        using var invalidArguments = new JavaObjectArray<JavaObject>(new JavaObject[] { invalidPayload });
        globals = AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount;
        InvokeCallback((Action<WrongPeer[]>)(_ => throw new Exception("Invalid callback ran.")), invalidArguments, typeof(InvalidCastException));
        if (!list.PeerReference.IsValid || !unrelated.PeerReference.IsValid ||
            AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount != globals)
            throw new Exception("Partial callback conversion leaked or disposed its caller's peer.");
        log("PASS partial callback conversion cleanup");
        using var returnArguments = new JavaObjectArray<JavaObject>(new[] { unrelated });
        InvokeCallback((Func<JavaObject, JavaObject>)(value => value), returnArguments, inspectResult: value =>
        {
            if (!value.IsValid || !JniEnvironment.Types.IsSameObject(value, unrelated.PeerReference))
                throw new Exception("Callback borrowed return was released too soon.");
        });
        if (!unrelated.PeerReference.IsValid) throw new Exception("Callback return disposed caller.");
        log("PASS callback borrowed return lifetime");
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

    private static void InvokeCallback(Delegate callback, JavaObject arguments, Type? expectedException = null,
        Action<JniObjectReference>? inspectResult = null)
    {
        // Exercise production marshaling/invocation without mutating the native registry.
        var handlerType = typeof(JavaCallbacks).Assembly.GetType("MelonLoader.Android.JavaCallbackHandler")!;
        var handler = Activator.CreateInstance(handlerType, BindingFlags.NonPublic | BindingFlags.Instance,
            null, new object[] { new JavaCallbackMethod("test", callback) }, null)!;
        try
        {
            var result = (nint)handlerType.GetMethod("InvokeAndReturn", BindingFlags.NonPublic | BindingFlags.Instance)!
                .Invoke(handler, new object[] { arguments.PeerReference })!;
            var reference = new JniObjectReference(result, JniObjectReferenceType.Local);
            try { inspectResult?.Invoke(reference); }
            finally { JniObjectReference.Dispose(ref reference); }
        }
        catch (TargetInvocationException exception) when (exception.InnerException != null)
        {
            if (expectedException == null || !expectedException.IsInstanceOfType(exception.InnerException))
                System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(exception.InnerException).Throw();
            if (expectedException == typeof(InvalidOperationException) && !exception.InnerException.StackTrace!.Contains(nameof(Hardening)))
                throw new Exception("Callback handler stack was lost.");
            return;
        }
        if (expectedException != null) throw new Exception("Callback did not throw " + expectedException.Name + ".");
    }

    private static void CheckDefinitions(Action<string> log)
    {
        foreach (string name in new[] { "java.lang.Object", "/java/lang/Object", "java//lang/Object" })
        {
            try { JavaBinding.GetStaticField<int>(name, "bad"); throw new Exception("Malformed class accepted."); }
            catch (ArgumentException) { }
        }
        try { JavaBinding.BindStatic<Action>("java/lang/System", "gc.()V"); throw new Exception("Encoded member accepted."); }
        catch (ArgumentException) { }
        var toString = JavaBinding.BindStatic<Func<object[], string>>("java/util/Arrays", "toString");
        if (toString(new object[] { 42, "value" }) != "[42, value]") throw new Exception("Object descriptor mapping failed.");
        var bindings = new Func<int, int>[8];
        Parallel.For(0, bindings.Length, i => bindings[i] = JavaBinding.BindStatic<Func<int, int>>("java/lang/Integer", "bitCount"));
        if (bindings.Any(value => !ReferenceEquals(value, bindings[0])) || bindings[0](7) != 3)
            throw new Exception("Concurrent binding returned different delegates.");
        for (int i = 0; i < 2; i++)
        {
            try { JavaBinding.BindStatic<Action>("java/lang/System", "missingLoaderFixture"); throw new Exception("Missing method accepted."); }
            catch (JavaException exception)
            {
                if (!exception.PeerReference.IsValid) throw new Exception("Disposed Java binding exception replayed.");
                exception.Dispose();
            }
        }
        log("PASS shared descriptor/name validation");
    }

    private static void CheckUiWork(Action<string> log)
    {
        var type = typeof(AndroidThread).GetNestedType("UiWork", BindingFlags.NonPublic)!;
        object Create(Action action) => Activator.CreateInstance(type, BindingFlags.NonPublic | BindingFlags.Instance,
            null, new object[] { action }, null)!;
        void Run(object work) => type.GetMethod("Execute", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(work, null);
        void Cancel(object work) => type.GetMethod("Cancel", BindingFlags.NonPublic | BindingFlags.Instance)!
            .Invoke(work, new object[] { new CancellationToken(true) });
        Task Completion(object work) => ((TaskCompletionSource)type.GetField("Completion", BindingFlags.NonPublic | BindingFlags.Instance)!
            .GetValue(work)!).Task;
        int calls = 0;
        var canceled = Create(() => calls++);
        Cancel(canceled); Run(canceled);
        if (calls != 0 || !Completion(canceled).IsCanceled) throw new Exception("Canceled UI work ran.");
        var completed = Create(() => calls++);
        Run(completed); Run(completed); Cancel(completed);
        if (calls != 1 || !Completion(completed).IsCompletedSuccessfully) throw new Exception("UI work ran twice.");
        using var entered = new ManualResetEventSlim();
        using var release = new ManualResetEventSlim();
        var running = Create(() => { entered.Set(); release.Wait(TimeSpan.FromSeconds(5)); Interlocked.Increment(ref calls); });
        var worker = new Thread(() => Run(running));
        worker.Start();
        try
        {
            if (!entered.Wait(TimeSpan.FromSeconds(5))) throw new Exception("UI work did not start.");
            Cancel(running); Run(running);
        }
        finally { release.Set(); worker.Join(); }
        if (calls != 2 || !Completion(running).IsCanceled) throw new Exception("Running UI cancellation changed execution.");
        log("PASS UI work cancellation/exactly-once");
    }
}

[JniTypeSignature("java/util/ArrayList", GenerateJavaPeer = false)]
public sealed class WrongPeer : JavaObject
{
    public WrongPeer(ref JniObjectReference reference, JniObjectReferenceOptions options) : base(ref reference, options) { }
}
