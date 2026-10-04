using MelonLoader.Java;
using System.Runtime.CompilerServices;

namespace LemonLoader.Tests.JniLibraries;

public static class Suites
{
    public static void Run(string candidate, nint vm, nint env, Action<string> log)
    {
        JNI.Initialize(vm);
        string text = "JNI \u65e5\u672c\u8a9e \ud83d\ude00\0tail";
        using var value = JNI.NewString(text);
        Check(value.GetString() == text, "UTF16/NUL", log);
        using var type = JNI.FindClass("java/lang/String");
        var length = type.GetMethodID("length", "()I");
        foreach (string signature in new[] { "(I", "()", "([)I", "(Ljava.lang.String;)I" })
        {
            try { _ = type.GetMethodID("invalid", signature); throw new Exception("Malformed signature accepted."); }
            catch (ArgumentException) { }
        }
        try { _ = JNI.CallMethod<int>(value, length, new JValue(1)); throw new Exception("Wrong argument count accepted."); }
        catch (ArgumentException) { log("PASS signature/count validation"); }
        Check(JNI.CallMethod<int>(value, length) == text.Length, "instance call", log);
        try { _ = type.GetStaticMethodID("length", "()I"); throw new Exception("Accepted wrong lookup mode."); }
        catch (JThrowableException e) { Check(e.JavaClassName.Contains("NoSuchMethod"), "lookup exception", log); }
        Check(JNI.CallMethod<int>(value, length) == text.Length, "cache isolation", log);
        using var integers = JNI.FindClass("java/lang/Integer");
        var parse = integers.GetStaticMethodID("parseInt", "(Ljava/lang/String;)I");
        using var invalid = JNI.NewString("invalid");
        try { _ = JNI.CallStaticMethod<int>(integers, parse, invalid); throw new Exception("Exception was lost."); }
        catch (JThrowableException e) { Check(e.Message.Contains("invalid") && e.JavaClassName.Contains("NumberFormat"), "Java exception", log); }
        Check(!JNI.ExceptionCheck(), "exception cleared", log);
        using var builder = JNI.FindClass("java/lang/StringBuilder");
        using var instance = builder.NewObject<JObject>("()V");
        Check(builder.CallMethod<int>(instance, "length", "()I") == 0, "constructor", log);
        using var nullValue = JNI.Borrow<JObject>(0, JNI.ReferenceType.Global);
        Check(nullValue.IsNull, "Java null", log);
        using var weak = value.ToGlobal<JString>();
        using var weakRef = JNI.NewWeakGlobalRef<JString>(weak);
        using var promoted = weakRef.ToLocal<JString>();
        Check(promoted.GetString() == text, "weak promotion", log);
        using var number = JNI.NewString("42");
        Check(JNI.CallStaticMethod<int>(integers, parse, number) == 42, "recovery", log);
        using var bytes = JNI.NewArray<sbyte>(4);
        JNI.SetArrayRegion(bytes, 0, 4, new sbyte[] { 1, 2, 3, 4 });
        Check(JNI.GetArrayElements(bytes).SequenceEqual(new sbyte[] { 1, 2, 3, 4 }), "region copy", log);
        try { JNI.SetArrayRegion(bytes, 0, 4, new sbyte[1]); throw new Exception("Unsafe source length accepted."); }
        catch (ArgumentOutOfRangeException) { log("PASS source bounds"); }
        using var booleans = JNI.NewArray<bool>(3);
        JNI.SetArrayRegion(booleans, 0, (ReadOnlySpan<bool>)new[] { true, false, true });
        Check(JNI.GetArrayElements(booleans).SequenceEqual(new[] { true, false, true }), "boolean region", log);
        using var objects = JNI.NewObjectArray(2, type, value);
        using var element = objects[0];
        Check(element.GetString() == text, "object array", log);
        using var booleanType = JNI.FindClass("java/lang/Boolean");
        using var javaTrue = booleanType.GetStaticObjectField<JObject>("TRUE", "Ljava/lang/Boolean;");
        Check(booleanType.CallMethod<bool>(javaTrue, "booleanValue", "()Z"), "static object field", log);
        var trueField = booleanType.GetStaticFieldID("TRUE", "Ljava/lang/Boolean;");
        try { _ = JNI.GetStaticField<int>(booleanType, trueField); throw new Exception("Wrong field type accepted."); }
        catch (ArgumentException) { log("PASS field type validation"); }
        var local = JNI.NewStringLocal("local");
        JNI.DeleteLocalRef(local); local.Dispose();
        Check(!local.Valid(), "reference invalidated", log);
        JObject escaped;
        using (JNI.LocalFrame()) escaped = JNI.NewStringLocal("frame");
        Check(!escaped.Valid(), "frame expired", log);
        escaped.Dispose();
        using var localRead = JNI.NewStringLocal("thread-local");
        Exception? wrongThread = null;
        var wrongWorker = new Thread(() =>
        {
            try { _ = JNI.CallMethod<int>(localRead, length); }
            catch (Exception e) { wrongThread = e; }
        });
        wrongWorker.Start(); wrongWorker.Join();
        Check(wrongThread is InvalidOperationException && localRead.Valid(), "wrong-thread local rejected", log);
        Exception? error = null;
        var worker = new Thread(() =>
        {
            try
            {
                for (int i = 0; i < 2; i++)
                    using (JNI.AttachCurrentThread())
                    {
                        Check(value.GetString() == text, "worker global", log);
                        using var cached = JNI.FindClass("java/lang/String");
                        Check(cached.GetMethodID("length", "()I").Handle == length.Handle, "shared cache", log);
                    }
            }
            catch (Exception e) { error = e; }
        });
        worker.Start(); worker.Join();
        if (error != null) throw error;
        try { _ = new JValue((object)42u); throw new Exception("Unsupported argument accepted."); }
        catch (ArgumentException) { log("PASS argument validation"); }
        log("PASS ALL migrated JNI");
    }
    private static void Check(bool ok, string name, Action<string> log)
    { if (!ok) throw new Exception(name); log("PASS " + name); }
}
