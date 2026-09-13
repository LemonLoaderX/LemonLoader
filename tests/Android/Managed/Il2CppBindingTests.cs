using System.Runtime.InteropServices;
using MelonLoader.Fixes.Il2CppInterop;
using MelonLoader.InternalUtils;

static class Il2CppBindingTests
{
    internal static void Run()
    {
        try
        {
            AndroidIl2CppInteropFix.Install();
            throw new Exception("Missing Unity handle was accepted.");
        }
        catch (InvalidOperationException) { }

        // No library named GameAssembly or libil2cpp.so is needed. P/Invoke
        // must use the exact host-owned handle for both names.
        string library = OperatingSystem.IsWindows() ? "kernel32.dll" :
            OperatingSystem.IsMacOS() ? "/usr/lib/libSystem.B.dylib" : "libc.so.6";
        BootstrapLibrary.Il2CppHandle = NativeLibrary.Load(library);
        AndroidIl2CppInteropFix.Install();
        Parallel.For(0, 16, _ =>
        {
            int first = OperatingSystem.IsWindows() ? Il2CppInterop.Runtime.IL2CPP.GameWindows() : Il2CppInterop.Runtime.IL2CPP.GameUnix();
            int second = OperatingSystem.IsWindows() ? Il2CppInterop.Runtime.IL2CPP.NativeWindows() : Il2CppInterop.Runtime.IL2CPP.NativeUnix();
            if (first != Environment.ProcessId || second != first)
                throw new Exception("P/Invoke did not use Unity's supplied library handle.");
        });
        // The fixture host, like Unity, retains its handle until process exit.
        Console.WriteLine("PASS IL2CPP P/Invoke borrowed handle, both library names, parallel calls and missing-handle failure");
    }
}

namespace Il2CppInterop.Runtime
{
    static class IL2CPP
    {
        [DllImport("GameAssembly", EntryPoint = "GetCurrentProcessId")]
        internal static extern int GameWindows();
        [DllImport("libil2cpp.so", EntryPoint = "GetCurrentProcessId")]
        internal static extern int NativeWindows();
        [DllImport("GameAssembly", EntryPoint = "getpid")]
        internal static extern int GameUnix();
        [DllImport("libil2cpp.so", EntryPoint = "getpid")]
        internal static extern int NativeUnix();
    }
}
