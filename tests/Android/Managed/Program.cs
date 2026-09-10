using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using MelonLoader.Java;
using MelonLoader.Utils;

unsafe class Program
{
    static JNIEnv* environment;
    static int localDeletes, globalDeletes, stringReleases, arrays, resets, closes, position;
    static bool pending, failClose, missingRead;
    static readonly string Text = "资源/😀\0末尾";
    static nint textBuffer;
    static readonly Dictionary<nint, byte[]> Buffers = new();
    static readonly byte[] Data = Enumerable.Range(0, 200000).Select(i => (byte)i).ToArray();
    static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    static void Set(JNIEnv.FunctionTable* table, string name, nint function) =>
        *(nint*)((byte*)table + (int)Marshal.OffsetOf<JNIEnv.FunctionTable>(name)) = function;

    static void Main()
    {
        var table = (JNIEnv.FunctionTable*)NativeMemory.AllocZeroed((nuint)sizeof(JNIEnv.FunctionTable));
        environment = (JNIEnv*)NativeMemory.AllocZeroed((nuint)sizeof(JNIEnv));
        *(nint*)environment = (nint)table;
        Set(table, "NewGlobalRef", (nint)(delegate* unmanaged[Stdcall]<JNIEnv*, nint, nint>)&Identity);
        Set(table, "GetObjectClass", (nint)(delegate* unmanaged[Stdcall]<JNIEnv*, nint, nint>)&Identity);
        Set(table, "DeleteLocalRef", (nint)(delegate* unmanaged[Stdcall]<JNIEnv*, nint, void>)&DeleteLocal);
        Set(table, "DeleteGlobalRef", (nint)(delegate* unmanaged[Stdcall]<JNIEnv*, nint, void>)&DeleteGlobal);
        Set(table, "GetStringLength", (nint)(delegate* unmanaged[Stdcall]<JNIEnv*, nint, int>)&StringLength);
        Set(table, "GetStringChars", (nint)(delegate* unmanaged[Stdcall]<JNIEnv*, nint, byte*, nint>)&StringChars);
        Set(table, "ReleaseStringChars", (nint)(delegate* unmanaged[Stdcall]<JNIEnv*, nint, nint, void>)&ReleaseChars);
        Set(table, "GetMethodID", (nint)(delegate* unmanaged[Stdcall]<JNIEnv*, nint, nint, nint, nint>)&Method);
        Set(table, "CallBooleanMethodA", (nint)(delegate* unmanaged[Stdcall]<JNIEnv*, nint, nint, nint, byte>)&BooleanCall);
        Set(table, "CallIntMethodA", (nint)(delegate* unmanaged[Stdcall]<JNIEnv*, nint, nint, nint, int>)&IntCall);
        Set(table, "CallLongMethodA", (nint)(delegate* unmanaged[Stdcall]<JNIEnv*, nint, nint, nint, long>)&LongCall);
        Set(table, "CallVoidMethodA", (nint)(delegate* unmanaged[Stdcall]<JNIEnv*, nint, nint, nint, void>)&VoidCall);
        Set(table, "NewByteArray", (nint)(delegate* unmanaged[Stdcall]<JNIEnv*, int, nint>)&NewArray);
        Set(table, "GetByteArrayRegion", (nint)(delegate* unmanaged[Stdcall]<JNIEnv*, nint, int, int, sbyte*, void>)&CopyRegion);
        Set(table, "ExceptionCheck", (nint)(delegate* unmanaged[Stdcall]<JNIEnv*, byte>)&ExceptionCheck);
        Set(table, "ExceptionClear", (nint)(delegate* unmanaged[Stdcall]<JNIEnv*, void>)&ExceptionClear);
        Set(table, "ExceptionDescribe", (nint)(delegate* unmanaged[Stdcall]<JNIEnv*, void>)&ExceptionDescribe);
        var vmTable = (JavaVM.FunctionTable*)NativeMemory.AllocZeroed((nuint)sizeof(JavaVM.FunctionTable));
        *(nint*)((byte*)vmTable + (int)Marshal.OffsetOf<JavaVM.FunctionTable>("GetEnv")) =
            (nint)(delegate* unmanaged[Stdcall]<JavaVM*, nint*, int, JNI.Result>)&GetEnv;
        var vm = (JavaVM*)NativeMemory.AllocZeroed((nuint)sizeof(JavaVM));
        *(nint*)vm = (nint)vmTable;
        JNI.Initialize((nint)vm);
        textBuffer = Marshal.StringToHGlobalUni(Text);
        using (var text = new JString { Handle = 1 })
            Check(text.GetString() == Text && stringReleases == 1, "JNI UTF-16 must retain surrogate pairs and NUL.");
        Marshal.FreeHGlobal(textBuffer);

        var local = new JObject(10, JNI.ReferenceType.Local);
        Exception? wrongThread = null;
        var thread = new Thread(() => { try { local.Dispose(); } catch (Exception e) { wrongThread = e; } });
        thread.Start(); thread.Join();
        Check(wrongThread is InvalidOperationException && local.Valid(), "Wrong-thread dispose must preserve local reference.");
        local.Dispose();
        var transferred = new JObject(11, JNI.ReferenceType.Local);
        using (var owner = new JObject(transferred)) Check(!transferred.Valid(), "Transfer must clear source.");
        var before = localDeletes;
        AbandonLocal();
        GC.Collect(); GC.WaitForPendingFinalizers();
        Check(localDeletes == before, "Finalizer must not delete a local JNI reference.");
        var globalsBefore = globalDeletes;
        AbandonGlobal();
        GC.Collect(); GC.WaitForPendingFinalizers();
        Check(globalDeletes == globalsBefore + 1, "Global finalizer must attach and release reference.");
        Console.WriteLine("PASS JNI UTF-16, transfer, explicit thread ownership and finalizers");

        var stream = new APKAssetManager.APKAssetStream(new JObject(20, JNI.ReferenceType.Global));
        var output = new byte[70002];
        Check(stream.Read(output, 1, 70000) == 65536, "Large read must be bounded.");
        Check(output.AsSpan(1, 65536).SequenceEqual(Data.AsSpan(0, 65536)), "Direct JNI copy must honor offset.");
        Check(stream.Read(output, 1, 500) == 500, "Short fixture read must complete.");
        Check(arrays == 1, "Repeated reads must reuse Java buffer.");
        stream.Seek(stream.Position, SeekOrigin.Begin);
        stream.Seek(100000, SeekOrigin.Begin);
        Check(resets == 0, "Forward/same seeks must avoid reset.");
        stream.Seek(12, SeekOrigin.Begin);
        Check(resets == 1 && stream.Position == 12, "Backward seek must reset once.");
        globalsBefore = globalDeletes;
        failClose = true;
        try { stream.Dispose(); throw new Exception("Close error was hidden."); }
        catch (IOException) { }
        Check(!pending && !stream.CanRead && !stream.CanSeek && globalDeletes == globalsBefore + 2,
            "Failed close must clear Java exception and release stream and buffer.");
        stream.Dispose();
        Check(closes == 1, "Dispose must be idempotent.");
        Console.WriteLine("PASS asset buffer reuse, direct copy, seek and failed-close cleanup");
        missingRead = true;
        using (var unavailableStream = new JObject(21, JNI.ReferenceType.Global))
        {
            try { _ = new APKAssetManager.APKAssetStream(unavailableStream); throw new Exception("Missing Java method was accepted."); }
            catch (IOException exception) { Check(exception.Message.Contains("read([BII)I"), "Method diagnostic must include signature."); }
        }
        Check(!pending, "Method lookup failure must clear Java exception.");
        Console.WriteLine("PASS asset stream missing-method diagnostics");
        LoaderBehaviorTests.Run();
        // Function tables remain allocated until process exit: finalizers can still call JNI.
    }

    [MethodImpl(MethodImplOptions.NoInlining)] static void AbandonLocal() => _ = new JObject(12, JNI.ReferenceType.Local);
    [MethodImpl(MethodImplOptions.NoInlining)] static void AbandonGlobal() => _ = new JObject(13, JNI.ReferenceType.Global);
    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvStdcall) })] static JNI.Result GetEnv(JavaVM* vm, nint* env, int version) { *env = (nint)environment; return JNI.Result.Ok; }
    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvStdcall) })] static nint Identity(JNIEnv* env, nint obj) => obj;
    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvStdcall) })] static void DeleteLocal(JNIEnv* env, nint obj) => Interlocked.Increment(ref localDeletes);
    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvStdcall) })] static void DeleteGlobal(JNIEnv* env, nint obj) => Interlocked.Increment(ref globalDeletes);
    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvStdcall) })] static int StringLength(JNIEnv* env, nint obj) => Text.Length;
    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvStdcall) })] static nint StringChars(JNIEnv* env, nint obj, byte* copy) { *copy = 0; return textBuffer; }
    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvStdcall) })] static void ReleaseChars(JNIEnv* env, nint obj, nint chars) => stringReleases++;
    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvStdcall) })] static nint Method(JNIEnv* env, nint obj, nint name, nint signature)
    {
        var method = Marshal.PtrToStringAnsi(name);
        if (missingRead && method == "read") { pending = true; return 0; }
        return method switch { "available" => 1, "read" => 2, "mark" => 3, "markSupported" => 4, "skip" => 5, "reset" => 6, "close" => 7, _ => 0 };
    }
    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvStdcall) })] static byte BooleanCall(JNIEnv* env, nint obj, nint method, nint args) => 1;
    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvStdcall) })] static int IntCall(JNIEnv* env, nint obj, nint method, nint args)
    {
        if (method == 1) return Data.Length;
        var values = (JValue*)args;
        var count = Math.Min(values[2].I, Data.Length - position);
        Data.AsSpan(position, count).CopyTo(Buffers[values[0].L].AsSpan(values[1].I));
        position += count;
        return count == 0 ? -1 : count;
    }
    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvStdcall) })] static long LongCall(JNIEnv* env, nint obj, nint method, nint args) { var count = ((JValue*)args)->J; position += (int)count; return count; }
    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvStdcall) })] static void VoidCall(JNIEnv* env, nint obj, nint method, nint args) { if (method == 6) { resets++; position = 0; } if (method == 7) { closes++; pending = failClose; } }
    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvStdcall) })] static nint NewArray(JNIEnv* env, int count) { var handle = (nint)(100 + ++arrays); Buffers[handle] = new byte[count]; return handle; }
    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvStdcall) })] static void CopyRegion(JNIEnv* env, nint array, int offset, int count, sbyte* output) => Buffers[array].AsSpan(offset, count).CopyTo(new Span<byte>(output, count));
    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvStdcall) })] static byte ExceptionCheck(JNIEnv* env) => (byte)(pending ? 1 : 0);
    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvStdcall) })] static void ExceptionClear(JNIEnv* env) => pending = false;
    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvStdcall) })] static void ExceptionDescribe(JNIEnv* env) { }
}
