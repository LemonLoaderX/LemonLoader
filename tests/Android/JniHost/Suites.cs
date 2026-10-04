using MelonLoader.Android;
using Java.Interop;
using System.Runtime.CompilerServices;

namespace LemonLoader.Tests.JniHost;

public static class Suites
{
    public static void Run(Action<string> log)
    {
        using var thread = AndroidJava.AttachCurrentThread();
        Hardening.Run(log);
        try { JavaBinding.BindInstance<Func<JavaStringBuilder, DayOfWeek>>("java/lang/StringBuilder", "length"); throw new Exception("Unsafe enum return accepted."); }
        catch (ArgumentException) { log("PASS unsupported primitive rejected"); }
        var parse = JavaBinding.BindStatic<Func<string, int>>("java/lang/Integer", "parseInt");
        Check(parse("42") == 42, "typed static/string marshaling", log);
        try { parse("invalid"); throw new Exception("Java error lost."); }
        catch (JavaException e)
        {
            Check(e.Message.Contains("invalid") && e.JavaStackTrace?.Contains("NumberFormatException") == true, "Java exception/stack", log);
            e.Dispose();
        }
        Check(!JniEnvironment.Exceptions.ExceptionCheck() && parse("123") == 123, "exception recovery", log);
        var create = JavaBinding.BindConstructor<Func<string, JavaStringBuilder>>("java/lang/StringBuilder");
        var append = JavaBinding.BindInstance<Func<JavaStringBuilder, string, JavaStringBuilder>>("java/lang/StringBuilder", "append");
        var text = JavaBinding.BindInstance<Func<JavaStringBuilder, string>>("java/lang/StringBuilder", "toString");
        const string unicode = "JNI \u65e5\u672c\u8a9e \ud83d\ude00\0tail";
        using var builder = create(unicode);
        using (var returned = append(builder, "!")) Check(text(returned) == unicode + "!", "typed peer/UTF16/NUL", log);
        Check(text(builder) == unicode + "!", "independent returned peer", log);
        var copy = JavaBinding.BindStatic<Func<sbyte[], int, sbyte[]>>("java/util/Arrays", "copyOf");
        Check(copy(new sbyte[] { 1, 2, 3 }, 2).SequenceEqual(new sbyte[] { 1, 2 }), "primitive array marshaling", log);
        var date = JavaBinding.BindStatic<Func<int, int, int, int, int, int, int, JavaDateTime>>("java/time/LocalDateTime", "of");
        var dateText = JavaBinding.BindInstance<Func<JavaDateTime, string>>("java/time/LocalDateTime", "toString");
        using (var time = date(2026, 10, 4, 12, 34, 56, 7))
            Check(dateText(time) == "2026-10-04T12:34:56.000000007", "large delegate marshaling", log);
        var objects = JavaBinding.BindStatic<Func<JavaObjectArray<JavaObject>, string>>("java/util/Arrays", "toString");
        using var entries = new JavaObjectArray<JavaObject>(0);
        Check(objects(entries) == "[]", "object array marshaling", log);
        using var strings = new JavaObjectArray<string>(new[] { "a", "b" });
        Check(strings.ToArray().SequenceEqual(new[] { "a", "b" }), "string array marshaling", log);
        using var array = new JavaSByteArray(4);
        array.CopyFrom(new sbyte[] { 1, 2, 3, 4 }, 0, 0, 4);
        Check(array.ToArray().SequenceEqual(new sbyte[] { 1, 2, 3, 4 }), "upstream primitive array", log);
        int before = AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount;
        var abandoned = AbandonPeer();
        GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect();
        Check(!abandoned.IsAlive && AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount == before, "peer finalizer release", log);
        var reference = builder.PeerReference;
        var registered = AndroidJava.Runtime.ValueManager.PeekPeer(reference);
        Check(registered != null && JniEnvironment.Types.IsSameObject(registered.PeerReference, reference), "peer registry", log);
        Exception? error = null;
        var worker = new Thread(() =>
        {
            try
            {
                Hardening.CheckScopes(log);
                for (int i = 0; i < 2; i++) { using var scope = AndroidJava.AttachCurrentThread(); Check(text(builder) == unicode + "!", "worker typed peer", log); }
            }
            catch (Exception e) { error = e; }
        });
        worker.Start(); worker.Join();
        if (error != null) throw error;
        var expired = create("disposed"); expired.Dispose(); expired.Dispose();
        try { text(expired); throw new Exception("Disposed receiver accepted."); }
        catch (ObjectDisposedException) { log("PASS disposed peer rejected"); }
        var createInput = JavaBinding.BindConstructor<Func<sbyte[], JavaInputStream>>("java/io/ByteArrayInputStream");
        var data = Enumerable.Range(0, 200000).Select(i => unchecked((sbyte)i)).ToArray();
        using (var warmup = new MelonLoader.Utils.APKAssetManager.APKAssetStream(createInput(new sbyte[] { 1 }))) warmup.ReadByte();
        int referencesBefore = AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount;
        using (var stream = new MelonLoader.Utils.APKAssetManager.APKAssetStream(createInput(data)))
        {
            var buffer = new byte[70002];
            Check(stream.Read(buffer, 1, 70000) == 65536 && buffer[1] == 0 && buffer[65536] == 255, "stream bounded direct copy/offset", log);
            int references = AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount;
            Check(stream.Read(buffer, 1, 500) == 500 && AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount == references, "stream Java buffer reuse", log);
            stream.Seek(100000, SeekOrigin.Begin);
            stream.Seek(12, SeekOrigin.Begin);
            Check(stream.ReadByte() == 12, "stream seek/backward reset", log);
        }
        Check(AndroidJava.Runtime.ObjectReferenceManager.GlobalReferenceCount == referencesBefore, "stream peer/buffer cleanup", log);
        var length = JavaBinding.BindInstance<Func<JavaStringBuilder, int>>("java/lang/StringBuilder", "length");
        for (int i = 0; i < 1000; i++) _ = length(builder);
        long allocated = GC.GetAllocatedBytesForCurrentThread();
        var timing = System.Diagnostics.Stopwatch.StartNew();
        for (int i = 0; i < 10000; i++) _ = length(builder);
        timing.Stop();
        log($"MEASURE typed cached length 10000: {timing.Elapsed.TotalMilliseconds:F2} ms, {(GC.GetAllocatedBytesForCurrentThread() - allocated) / 10000.0:F2} bytes/call");
        log("PASS ALL migrated JNI");
    }
    [MethodImpl(MethodImplOptions.NoInlining)]
    private static WeakReference AbandonPeer()
    {
        var value = JavaBinding.BindConstructor<Func<string, JavaStringBuilder>>("java/lang/StringBuilder")("abandoned");
        return new WeakReference(value);
    }
    private static void Check(bool ok, string name, Action<string> log) { if (!ok) throw new Exception(name); log("PASS " + name); }
}

[JniTypeSignature("java/lang/StringBuilder", GenerateJavaPeer = false)]
public sealed class JavaStringBuilder : JavaObject
{
    private static readonly JniPeerMembers members = new("java/lang/StringBuilder", typeof(JavaStringBuilder));
    public override JniPeerMembers JniPeerMembers => members;
    public JavaStringBuilder(ref JniObjectReference reference, JniObjectReferenceOptions options) : base(ref reference, options) { }
}

[JniTypeSignature("java/time/LocalDateTime", GenerateJavaPeer = false)]
public sealed class JavaDateTime : JavaObject
{
    public JavaDateTime(ref JniObjectReference reference, JniObjectReferenceOptions options) : base(ref reference, options) { }
}
