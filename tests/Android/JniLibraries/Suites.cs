using System.Diagnostics;
using System.Runtime.CompilerServices;
using Java.Interop;
using Rxmxnx.JNetInterface;
using Rxmxnx.JNetInterface.Lang;
using Rxmxnx.JNetInterface.Native;
using Rxmxnx.JNetInterface.Native.Access;
using Rxmxnx.JNetInterface.Native.References;
using Rxmxnx.JNetInterface.Primitives;
using Rxmxnx.JNetInterface.Types;
using Rxmxnx.JNetInterface.Types.Metadata;
using Baseline = MelonLoader.Java;

namespace LemonLoader.Tests.JniLibraries;

public static class Suites
{
    private const string Text = "JNI \u65e5\u672c\u8a9e \ud83d\ude00\0tail";
    private const int Iterations = 10000;

    public static void Run(string candidate, nint vm, nint env, Action<string> log, nint assetManager = 0, nint classLoader = 0)
    {
        log($"BEGIN {candidate}");
        switch (candidate)
        {
            case "java-interop": JavaInterop(vm, env, log, assetManager, classLoader); break;
            case "jnet": JNet(vm, log, assetManager); break;
            case "baseline": Current(vm, log, assetManager); break;
            default: throw new ArgumentException("Unknown candidate.", nameof(candidate));
        }
        log($"PASS ALL {candidate}");
    }

    private static void Check(bool condition, string name, Action<string> log)
    {
        if (!condition) throw new InvalidOperationException($"FAIL {name}");
        log($"PASS {name}");
    }

    private static void Benchmark(string name, Action operation, Action<string> log)
    {
        for (int i = 0; i < 1000; i++) operation();
        for (int sample = 0; sample < 3; sample++)
        {
            long allocated = GC.GetAllocatedBytesForCurrentThread();
            var timer = Stopwatch.StartNew();
            for (int i = 0; i < Iterations; i++) operation();
            timer.Stop();
            log($"BENCH {name} sample={sample} n={Iterations} ms={timer.Elapsed.TotalMilliseconds:F3} bytes={GC.GetAllocatedBytesForCurrentThread() - allocated}");
        }
    }

    private static void Worker(Action operation)
    {
        Exception? error = null;
        var worker = new Thread(() => { try { operation(); } catch (Exception e) { error = e; } });
        worker.Start();
        if (!worker.Join(TimeSpan.FromSeconds(30))) throw new TimeoutException("JNI worker timeout.");
        if (error != null) throw new InvalidOperationException("Worker failed.", error);
    }

    private static void Current(nint vm, Action<string> log, nint assetManager)
    {
        var timer = Stopwatch.StartNew();
        Baseline.JNI.Initialize(vm);
        using var text = Baseline.JNI.NewString(Text);
        log($"INIT baseline ms={timer.Elapsed.TotalMilliseconds:F3}");
        Check(text.GetString() == Text, "UTF16/NUL", log);
        using var type = Baseline.JNI.FindClass("java/lang/String");
        var length = type.GetMethodID("length", "()I");
        Check(Baseline.JNI.CallMethod<int>(text, length) == Text.Length, "instance call", log);
        if (Baseline.JNI.ExceptionCheck()) throw new Exception("Unexpected Java exception.");
        using var integers = Baseline.JNI.FindClass("java/lang/Integer");
        var parse = integers.GetStaticMethodID("parseInt", "(Ljava/lang/String;)I");
        using var number = Baseline.JNI.NewString("42");
        Check(Baseline.JNI.CallStaticMethod<int>(integers, parse, new Baseline.JValue(number)) == 42, "static call", log);
        if (Baseline.JNI.ExceptionCheck()) throw new Exception("Unexpected Java exception.");
        using var invalid = Baseline.JNI.NewString("invalid");
        _ = Baseline.JNI.CallStaticMethod<int>(integers, parse, new Baseline.JValue(invalid));
        Check(Baseline.JNI.ExceptionCheck(), "Java exception detected", log);
        Baseline.JNI.ExceptionClear();
        Check(Baseline.JNI.CallStaticMethod<int>(integers, parse, new Baseline.JValue(number)) == 42, "exception recovery", log);
        if (Baseline.JNI.ExceptionCheck()) throw new Exception("Unexpected Java exception.");
        using var bytes = Baseline.JNI.NewArray<sbyte>(1024);
        sbyte[] source = Enumerable.Range(0, 1024).Select(i => (sbyte)i).ToArray();
        Baseline.JNI.SetArrayRegion(bytes, 0, source.Length, source);
        Check(Baseline.JNI.GetArrayElements<sbyte>(bytes).SequenceEqual(source), "byte array", log);
        Worker(() =>
        {
            Check(VmAccess.GetEnv(vm) == 0, "worker initially detached", log);
            try { Check(text.GetString() == Text, "global reference worker", log); }
            finally { Baseline.JNI.DetachCurrentThread(); }
            Check(VmAccess.GetEnv(vm) == 0, "worker detached", log);
        });
        Benchmark("baseline/cached-length", () => { if (Baseline.JNI.CallMethod<int>(text, length) != Text.Length || Baseline.JNI.ExceptionCheck()) throw new Exception(); }, log);
        Benchmark("baseline/string-roundtrip", () => { using var s = Baseline.JNI.NewString(Text); if (s.GetString() != Text) throw new Exception(); }, log);
        if (assetManager != 0)
        {
            // Borrow Loader's global reference. Never dispose the borrowed handle.
            var manager = new Baseline.JObject(assetManager, Baseline.JNI.ReferenceType.Global);
            try
            {
                using var managerType = Baseline.JNI.GetObjectClass(manager);
                using var path = Baseline.JNI.NewString("LemonLoader/payload.json");
                using var stream = Baseline.JNI.CallObjectMethod<Baseline.JObject>(manager,
                    managerType.GetMethodID("open", "(Ljava/lang/String;)Ljava/io/InputStream;"), new Baseline.JValue(path));
                if (Baseline.JNI.ExceptionCheck()) { Baseline.JNI.ExceptionClear(); throw new IOException("Asset open failed."); }
                using var streamType = Baseline.JNI.GetObjectClass(stream);
                int count = Baseline.JNI.CallMethod<int>(stream, streamType.GetMethodID("read", "([BII)I"), new Baseline.JValue(bytes), new Baseline.JValue(0), new Baseline.JValue(1024));
                Baseline.JNI.CallVoidMethod(stream, streamType.GetMethodID("close", "()V"));
                Check(count > 0 && !Baseline.JNI.ExceptionCheck(), "APK asset stream", log);
            }
            finally { manager.Handle = 0; manager.Dispose(); }
        }
    }

    private static unsafe void JavaInterop(nint vm, nint env, Action<string> log, nint assetManager, nint classLoader)
    {
        AppContext.SetSwitch("Java.Interop.RuntimeFeature.ManagedPeerNativeRegistration", false);
        var timer = Stopwatch.StartNew();
        using var runtime = new ExistingRuntime(vm, env, classLoader);
        var text = JniEnvironment.Strings.NewString(Text);
        log($"INIT java-interop ms={timer.Elapsed.TotalMilliseconds:F3}");
        try
        {
            Check(JniEnvironment.Strings.ToString(text) == Text, "UTF16/NUL", log);
            using var type = new JniType("java/lang/String");
            var length = type.GetInstanceMethod("length", "()I");
            Check(JniEnvironment.InstanceMethods.CallIntMethod(text, length) == Text.Length, "instance call", log);
            bool badMode = false;
            try { _ = type.GetStaticMethod("length", "()I"); }
            catch (InvalidOperationException e) { badMode = e.Message.Contains("NoSuchMethod"); }
            Check(badMode && JniEnvironment.InstanceMethods.CallIntMethod(text, length) == Text.Length, "static/instance cache isolation", log);
            using var integers = new JniType("java/lang/Integer");
            var parse = integers.GetStaticMethod("parseInt", "(Ljava/lang/String;)I");
            var number = JniEnvironment.Strings.NewString("42");
            var invalid = JniEnvironment.Strings.NewString("invalid");
            var bytes = JniEnvironment.Arrays.NewByteArray(1024);
            try
            {
                JniArgumentValue arg = new(number);
                Check(JniEnvironment.StaticMethods.CallStaticIntMethod(integers.PeerReference, parse, &arg) == 42, "static call", log);
                bool thrown = false;
                try { arg = new(invalid); _ = JniEnvironment.StaticMethods.CallStaticIntMethod(integers.PeerReference, parse, &arg); }
                catch (Exception e) { thrown = e.Message.Contains("NumberFormatException") && e.Message.Contains("invalid"); log($"EXCEPTION {e.GetType().FullName}: {e.Message}"); }
                Check(thrown, "Java exception translated", log);
                Check(!JniEnvironment.Exceptions.ExceptionCheck(), "Java exception cleared", log);
                arg = new(number);
                Check(JniEnvironment.StaticMethods.CallStaticIntMethod(integers.PeerReference, parse, &arg) == 42, "exception recovery", log);
                sbyte[] source = Enumerable.Range(0, 1024).Select(i => (sbyte)i).ToArray();
                sbyte[] target = new sbyte[1024];
                fixed (sbyte* s = source, t = target)
                {
                    JniEnvironment.Arrays.SetByteArrayRegion(bytes, 0, 1024, s);
                    JniEnvironment.Arrays.GetByteArrayRegion(bytes, 0, 1024, t);
                }
                Check(target.SequenceEqual(source), "byte array", log);
                bool bounds = false;
                try
                {
                    sbyte one = 0;
                    JniEnvironment.Arrays.GetByteArrayRegion(bytes, 1024, 1, &one);
                }
                catch (InvalidOperationException e) { bounds = e.Message.Contains("IndexOutOfBounds"); }
                Check(bounds && !JniEnvironment.Exceptions.ExceptionCheck(), "array bounds exception/recovery", log);
                int localsBefore = JniEnvironment.LocalReferenceCount;
                for (int i = 0; i < 100; i++)
                {
                    var local = JniEnvironment.Strings.NewString("local");
                    JniObjectReference.Dispose(ref local);
                    JniObjectReference.Dispose(ref local);
                    if (local.IsValid) throw new Exception("Deleted reference still valid.");
                }
                Check(JniEnvironment.LocalReferenceCount == localsBefore, "local ownership/repeated disposal", log);
                var global = text.NewGlobalRef();
                try
                {
                    Worker(() =>
                    {
                        Check(VmAccess.GetEnv(vm) == 0, "worker initially detached", log);
                        for (int scope = 0; scope < 2; scope++)
                        {
                            // Refresh the library's thread environment after each detach.
                            runtime.AttachCurrentThread();
                            try
                            {
                                Check(JniEnvironment.Strings.ToString(global) == Text, "global reference worker", log);
                                if (classLoader != 0)
                                {
                                    using var applicationClass = new JniType("com/unity3d/player/UnityPlayer");
                                    Check(applicationClass.PeerReference.IsValid, "application class on CLR worker", log);
                                }
                            }
                            finally { VmAccess.Detach(vm); }
                            Check(VmAccess.GetEnv(vm) == 0, "worker detached externally", log);
                        }
                    });
                }
                finally { JniObjectReference.Dispose(ref global); }
                Benchmark("java-interop/cached-length", () => { if (JniEnvironment.InstanceMethods.CallIntMethod(text, length) != Text.Length) throw new Exception(); }, log);
                Benchmark("java-interop/string-roundtrip", () => { var s = JniEnvironment.Strings.NewString(Text); try { if (JniEnvironment.Strings.ToString(s) != Text) throw new Exception(); } finally { JniObjectReference.Dispose(ref s); } }, log);
                if (assetManager != 0)
                {
                    var manager = new JniObjectReference(assetManager, JniObjectReferenceType.Global);
                    using var managerType = new JniType("android/content/res/AssetManager");
                    using var streamType = new JniType("java/io/InputStream");
                    var path = JniEnvironment.Strings.NewString("LemonLoader/payload.json");
                    try
                    {
                        arg = new(path);
                        var stream = JniEnvironment.InstanceMethods.CallObjectMethod(manager, managerType.GetInstanceMethod("open", "(Ljava/lang/String;)Ljava/io/InputStream;"), &arg);
                        try
                        {
                            JniArgumentValue* readArgs = stackalloc JniArgumentValue[3] { new(bytes), new(0), new(1024) };
                            int count = JniEnvironment.InstanceMethods.CallIntMethod(stream, streamType.GetInstanceMethod("read", "([BII)I"), readArgs);
                            JniEnvironment.InstanceMethods.CallVoidMethod(stream, streamType.GetInstanceMethod("close", "()V"));
                            Check(count > 0, "APK asset stream", log);
                        }
                        finally { JniObjectReference.Dispose(ref stream); }
                    }
                    finally { JniObjectReference.Dispose(ref path); }
                }
            }
            finally { JniObjectReference.Dispose(ref number); JniObjectReference.Dispose(ref invalid); JniObjectReference.Dispose(ref bytes); }
        }
        finally { JniObjectReference.Dispose(ref text); }
    }

    private static void JNet(nint vm, Action<string> log, nint assetManager)
    {
        var timer = Stopwatch.StartNew();
        var machine = JVirtualMachine.GetVirtualMachine(Unsafe.BitCast<nint, JVirtualMachineRef>(vm));
        using var thread = machine.InitializeThread(version: 0x10006);
        using var text = JStringObject.Create(thread, Text.AsSpan());
        log($"INIT jnet ms={timer.Elapsed.TotalMilliseconds:F3} api={machine.AndroidApiLevel}");
        Check(text.Value == Text, "UTF16/NUL", log);
        var length = new JFunctionDefinition<JInt>.Parameterless("length"u8);
        Check(length.Invoke(text).Value == Text.Length, "instance call", log);
        bool badMode = false;
        try { _ = length.StaticInvoke(text.Class); }
        catch (ThrowableException) { badMode = true; thread.PendingException = null; }
        Check(badMode && length.Invoke(text).Value == Text.Length, "static/instance cache isolation", log);
        using var integers = JClassObject.GetClass(thread, "java/lang/Integer"u8);
        var parse = IndeterminateCall.CreateFunctionDefinition<JInt>("parseInt"u8, JArgumentMetadata.Get<JStringObject>());
        using var number = JStringObject.Create(thread, "42".AsSpan());
        Check(parse.StaticFunctionCall(integers, number).IntValue.Value == 42, "static call", log);
        using var invalid = JStringObject.Create(thread, "invalid".AsSpan());
        bool thrown = false;
        try { _ = parse.StaticFunctionCall(integers, invalid); }
        catch (ThrowableException e) { thrown = true; log($"EXCEPTION {e.GetType().FullName}: {e.Message}"); }
        Check(thrown && thread.PendingException != null, "Java exception tracked", log);
        thread.PendingException = null;
        Check(parse.StaticFunctionCall(integers, number).IntValue.Value == 42, "exception recovery", log);
        using var bytes = JArrayObject<JByte>.Create(thread, 1024);
        JByte[] source = Enumerable.Range(0, 1024).Select(i => new JByte((sbyte)i)).ToArray();
        bytes.Set(source, 0);
        Check(bytes.ToArray().SequenceEqual(source), "byte array", log);
        bool bounds = false;
        try { bytes.Get(new JByte[1], 1024); }
        catch (ThrowableException) { bounds = true; thread.PendingException = null; }
        catch (ArgumentOutOfRangeException) { bounds = true; }
        Check(bounds && bytes.ToArray().SequenceEqual(source), "array bounds exception/recovery", log);
        for (int i = 0; i < 100; i++)
        {
            var local = JStringObject.Create(thread, "local".AsSpan());
            local.Dispose();
            local.Dispose();
        }
        log("PASS local ownership/repeated disposal");
        using var global = text.Global;
        Worker(() =>
        {
            Check(VmAccess.GetEnv(vm) == 0, "worker initially detached", log);
            for (int scope = 0; scope < 2; scope++)
            {
                using (var worker = machine.InitializeThread(version: 0x10006))
                using (var local = global.AsLocal<JStringObject>(worker, true))
                {
                    Check(local.Value == Text, "global reference worker", log);
                    if (assetManager != 0)
                    {
                        try
                        {
                            using var applicationClass = JClassObject.GetClass(worker, "com/unity3d/player/UnityPlayer"u8);
                            Check(applicationClass.Reference.Pointer != 0, "application class on CLR worker", log);
                        }
                        catch (ThrowableException e) { log($"LIMIT application class: {e.Message}"); worker.PendingException = null; }
                    }
                }
                Check(VmAccess.GetEnv(vm) == 0, "worker detached", log);
            }
        });
        Benchmark("jnet/cached-length", () => { if (length.Invoke(text).Value != Text.Length) throw new Exception(); }, log);
        Benchmark("jnet/string-roundtrip", () => { using var s = JStringObject.Create(thread, Text.AsSpan()); if (s.Value != Text) throw new Exception(); }, log);
        if (assetManager != 0)
        {
            using var managerType = JClassObject.GetClass(thread, "android/content/res/AssetManager"u8);
            using var manager = new AdoptedLocal(managerType, VmAccess.NewLocal(thread.Reference.Pointer, assetManager));
            using var path = JStringObject.Create(thread, "LemonLoader/payload.json".AsSpan());
            var open = IndeterminateCall.CreateFunctionDefinition(JArgumentMetadata.Create("Ljava/io/InputStream;"u8), "open"u8, JArgumentMetadata.Get<JStringObject>());
            using var stream = open.FunctionCall(manager, path).Object!;
            var read = IndeterminateCall.CreateFunctionDefinition<JInt>("read"u8,
                JArgumentMetadata.Get<JArrayObject<JByte>>(), JArgumentMetadata.Get<JInt>(), JArgumentMetadata.Get<JInt>());
            int count = read.FunctionCall(stream, bytes, new JInt(0), new JInt(1024)).IntValue.Value;
            new JMethodDefinition.Parameterless("close"u8).Invoke(stream);
            Check(count > 0, "APK asset stream", log);
        }
    }

    private sealed class AdoptedLocal : JLocalObject
    {
        public AdoptedLocal(JClassObject type, nint local) : base(new IReferenceType.ClassInitializer
        {
            Class = type,
            LocalReference = Unsafe.BitCast<nint, JObjectLocalRef>(local)
        }) { }
    }
}

internal static unsafe class VmAccess
{
    public static nint GetEnv(nint vm)
    {
        nint env = 0;
        var get = (delegate* unmanaged<nint, nint*, int, int>)(*(nint**)vm)[6];
        return get(vm, &env, 0x10006) == 0 ? env : 0;
    }

    public static void Detach(nint vm)
    {
        var detach = (delegate* unmanaged<nint, int>)(*(nint**)vm)[5];
        if (detach(vm) != 0) throw new InvalidOperationException("DetachCurrentThread failed.");
    }

    public static nint NewLocal(nint env, nint value)
    {
        var copy = (delegate* unmanaged<nint, nint, nint>)(*(nint**)env)[25];
        nint local = copy(env, value);
        if (local == 0) throw new InvalidOperationException("NewLocalRef failed.");
        return local;
    }
}
