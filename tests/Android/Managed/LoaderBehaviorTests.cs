using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using MelonLoader;
using MelonLoader.NativeUtils;
using MelonLoader.Support;

static class LoaderBehaviorTests
{
    static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    internal static unsafe void Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "lemonloader-tests-" + Guid.NewGuid().ToString("N"));
        var previous = Environment.GetEnvironmentVariable("MELONLOADER_BASE_DIR");
        try
        {
            Environment.SetEnvironmentVariable("MELONLOADER_BASE_DIR", root);
            LoaderConfig.InitializeAndroid();
            var path = Path.Combine(root, "UserData", "Loader.cfg");
            Check(File.Exists(path), "Missing configuration must be created.");
            File.WriteAllText(path, "[invalid");
            MelonLogger.Warnings.Clear();
            LoaderConfig.InitializeAndroid();
            Check(File.ReadAllText(path) == "[invalid" && MelonLogger.Warnings.Single().Contains(path),
                "Malformed config must remain intact and report its path.");
            File.Delete(path);
            Directory.CreateDirectory(path);
            MelonLogger.Warnings.Clear();
            LoaderConfig.InitializeAndroid();
            Check(MelonLogger.Warnings.Single().Contains("Could not save"), "Save failure must be reported.");
            Directory.Delete(Path.Combine(root, "UserData"), true);
            File.WriteAllText(Path.Combine(root, "UserData"), "occupied");
            MelonLogger.Warnings.Clear();
            LoaderConfig.InitializeAndroid();
            Check(MelonLogger.Warnings.Single().Contains("configuration directory"), "Directory failure must be reported.");
        }
        finally { Environment.SetEnvironmentVariable("MELONLOADER_BASE_DIR", previous); Directory.Delete(root, true); }
        Console.WriteLine("PASS configuration creation, malformed file preservation and write diagnostics");

        MelonLogger.Warnings.Clear();
        Check(!SceneHandler.Init(null!, null!) && MelonLogger.Warnings.Count == 2, "Missing scene methods must warn.");
        var method = typeof(LoaderBehaviorTests).GetMethod(nameof(Run), BindingFlags.Static | BindingFlags.NonPublic)!;
        Check(SceneHandler.Init(method, method), "Available methods must install hooks.");
        var getter = typeof(SceneHandler).GetMethod("GetBuildIndex", BindingFlags.Static | BindingFlags.NonPublic)!;
        var scene = new UnityEngine.SceneManagement.Scene();
        Check((int)getter.Invoke(null, [scene])! == 7, "Available build index must be returned.");
        UnityEngine.SceneManagement.Scene.Missing = true;
        MelonLogger.Warnings.Clear();
        Check((int)getter.Invoke(null, [scene])! == -1 && (int)getter.Invoke(null, [scene])! == -1 && MelonLogger.Warnings.Count == 1,
            "Missing stripped scene getter must degrade and warn once.");
        Console.WriteLine("PASS scene callback capability and stripped build-index fallback");

        var roots = (System.Collections.ICollection)typeof(NativeHook<Func<int>>)
            .GetField("_gcProtect", BindingFlags.Static | BindingFlags.NonPublic)!.GetValue(null)!;
        int before = roots.Count;
        var hook = new FixtureHook { Detour = 1 };
        hook.Attach();
        Check(roots.Count == before + 1, "Attach must retain trampoline.");
        hook.Detach();
        Check(roots.Count == before && !hook.IsHooked, "Detach must release original root before clearing field.");
        var checkedHook = new DetachCheckingHook { Target = 2, Detour = 1 };
        MelonLoader.NativeLibrary.DetachExport = (nint)(delegate* unmanaged[Cdecl]<nint*, nint, int>)&CheckedDetach;
        Check(MelonLoader.InternalUtils.BootstrapInterop.Initialize(1) == null, "Checked bootstrap must initialize.");
        checkedHook.Attach();
        FailDetach = true;
        var unregisters = MelonLoader.CoreClrUtils.NativeStackWalk.Unregisters;
        try { checkedHook.Detach(); throw new Exception("Detach failure was hidden."); }
        catch (InvalidOperationException) { }
        Check(checkedHook.IsHooked && roots.Count == before + 1, "Failed native detach must retain hook and root.");
        Check(MelonLoader.CoreClrUtils.NativeStackWalk.Unregisters == unregisters, "Failure must retain stack-walk registration.");
        FailDetach = false;
        checkedHook.Detach();
        Check(!checkedHook.IsHooked && roots.Count == before, "Successful native detach must release root.");
        Check(MelonLoader.CoreClrUtils.NativeStackWalk.Unregisters == unregisters + 1, "Success must unregister hook.");
        nint original = 2;
        MelonLoader.InternalUtils.BootstrapInterop.NativeHookDetach((nint)(&original), 1);
        Check(original == 2, "Public checked path must preserve the caller pointer.");
        MelonLoader.NativeLibrary.DetachExport = 0;
        Check(MelonLoader.InternalUtils.BootstrapInterop.Initialize(1) == null, "Missing optional export must not prevent loading.");
        var legacy = new DetachCheckingHook { Target = 2, Detour = 1 };
        legacy.Attach();
        legacy.Detach();
        Check(!legacy.IsHooked && roots.Count == before && MelonLoader.InternalUtils.BootstrapLibrary.LegacyDetachCalls == 1,
            "Older bootstraps must retain legacy detach behavior.");
        MelonLoader.InternalUtils.BootstrapInterop.NativeHookDetach((nint)(&original), 1);
        Check(original == 2, "Public legacy path must preserve the caller pointer.");
        Console.WriteLine("PASS native hook trampoline root release");
    }
    static bool FailDetach;
    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvCdecl) })]
    static unsafe int CheckedDetach(nint* target, nint detour) => FailDetach ? 0 : 1;
    sealed class FixtureHook : NativeHook<Func<int>>
    {
        internal override unsafe void HookAttach() { _trampoline = () => 7; }
        internal override unsafe void HookDetach() { _trampoline = null!; _trampolineHandle = 0; }
    }
    sealed class DetachCheckingHook : NativeHook<Func<int>>
    {
        internal override unsafe void HookAttach() { _trampoline = () => 7; }
    }
}

namespace MelonLoader
{
    static class MelonLogger
    {
        internal static readonly List<string> Warnings = new();
        internal static void Warning(string message) => Warnings.Add(message);
        internal static void Error(string message) => throw new Exception(message);
        internal static void Error(Exception exception) => throw exception;
    }
    static class MelonDebug { internal static void Msg(string message) { } }
}
namespace MelonLoader.InternalUtils
{
    unsafe class BootstrapLibrary
    {
        internal static int LegacyDetachCalls;
        internal void NativeHookAttach(nint* target, nint detour) => throw new NotSupportedException();
        internal void NativeHookDetach(nint* target, nint detour) => LegacyDetachCalls++;
        internal void LogManagedException(byte* message, int length) { }
        internal void DestroyArm64ValueReturnAdapter(nint adapter) { }
    }
}
namespace MelonLoader
{
    class NativeLibrary
    {
        internal static nint DetachExport;
        internal static nint AgnosticGetProcAddress(nint handle, string name) => name == "TryNativeHookDetach" ? DetachExport : 0;
    }
    class NativeLibrary<T> where T : new()
    {
        internal T Instance = new();
        internal NativeLibrary(nint handle) { }
    }
    static class Core
    {
        internal static void Initialize() { }
        internal static bool Start() => true;
        internal static string GetVersionString() => "fixture";
    }
    static class MelonUtils { internal static void SetConsoleTitle(string title) { } }
}
namespace MelonLoader.CoreClrUtils
{
    static class NativeStackWalk
    {
        internal static int Unregisters;
        internal static void RegisterHookAddr(ulong address, string name) { }
        internal static void UnregisterHookAddr(ulong address) => Unregisters++;
    }
}
namespace UnityEngine.SceneManagement
{
    enum LoadSceneMode { Single }
    struct Scene
    {
        public static bool Missing;
        public string name => "Fixture";
        public int buildIndex => Missing ? throw new Il2CppInterop.Runtime.MissingIl2CppInternalCallException() : 7;
    }
}
namespace Il2CppInterop.Runtime { class MissingIl2CppInternalCallException : Exception { } }
namespace HarmonyLib
{
    class HarmonyMethod { public HarmonyMethod(MethodInfo method) { } }
    class Harmony { public void Patch(MethodInfo method, HarmonyMethod prefix) { } }
    static class Extensions { public static string FullDescription(this MethodInfo method) => method.Name; }
}
namespace MelonLoader.Support
{
    static class Core { internal static readonly HarmonyLib.Harmony HarmonyInstance = new(); }
    static class Main { internal static readonly Events Interface = new(); }
    class Events
    {
        internal void OnSceneWasLoaded(int index, string name) { }
        internal void OnSceneWasUnloaded(int index, string name) { }
        internal void OnSceneWasInitialized(int index, string name) { }
    }
}
