using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Runtime.Loader;
using System.Text;
using MelonLoader.InternalUtils;

namespace MelonLoader.NativeHost;

internal static unsafe class NativeEntryPoint
{
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int StartDelegate();

    private static StartDelegate? startDel;

    // The argument should first hold the bootstrap handle, and return the start function ptr
    [UnmanagedCallersOnly]
    private static int NativeEntry(nint* startFunc) => NativeEntryImpl(startFunc);

    private static int CoreClrNativeEntry(nint startFunc) => NativeEntryImpl((nint*)startFunc);

    private static int NativeEntryImpl(nint* startFunc)
    {
        nint bootstrapHandle = 0;
        try
        {
            if (startFunc == null)
                return 1;

            bootstrapHandle = *startFunc;
            var currentAsm = typeof(NativeEntryPoint).Assembly;

            var asm = AssemblyLoadContext.Default.LoadFromAssemblyPath(currentAsm.Location);
            var type = asm.GetType("MelonLoader.NativeHost.NativeEntryPoint", true)!;
            var init = type.GetMethod(nameof(Initialize), BindingFlags.Static | BindingFlags.NonPublic)!;
            return (int)init.Invoke(null, [ (nint)startFunc])!;
        }
        catch (Exception ex)
        {
            TryLogEarlyException(bootstrapHandle, ex);
            if (startFunc != null)
                *startFunc = 0;
            return 1;
        }
    }

    private static void TryLogEarlyException(nint bootstrapHandle, Exception exception)
    {
        try
        {
            TryLogEarlyMessage(
                bootstrapHandle,
                "Managed NativeHost entry failed:\n" + exception);
        }
        catch
        {
            // The managed entry must never throw back through the native hosting ABI.
        }
    }

    private static void TryLogEarlyMessage(nint bootstrapHandle, string message)
    {
        if (bootstrapHandle == 0)
            return;

        try
        {
            nint export = System.Runtime.InteropServices.NativeLibrary.GetExport(
                bootstrapHandle,
                "LogManagedException");
            byte[] encodedMessage = Encoding.UTF8.GetBytes(message);
            fixed (byte* messagePointer = encodedMessage)
            {
                var logManagedException =
                    (delegate* unmanaged[Cdecl]<byte*, int, void>)export;
                logManagedException(messagePointer, encodedMessage.Length);
            }
        }
        catch
        {
            // The managed entry must never throw back through the native hosting ABI.
        }
    }

    private unsafe static int Initialize(nint* startFunc)
    {
        AssemblyLoadContext.Default.Resolving += OnResolveAssembly;
        
        //Have to invoke through a proxy so that we don't load MelonLoader.dll before the above line
        return CallInit(startFunc);
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static int CallInit(nint* startFunc)
    {
        var bootstrapHandle = *startFunc;
        string err = BootstrapInterop.Initialize(bootstrapHandle);
        if (err != null)
        {
            TryLogEarlyMessage(
                bootstrapHandle,
                "Managed MelonLoader initialization failed:\n" + err);
            *startFunc = 0;
            return 1;
        }

        startDel = BootstrapInterop.Start;
        *startFunc = Marshal.GetFunctionPointerForDelegate(startDel);
        return 0;
    }

    private static Assembly? OnResolveAssembly(AssemblyLoadContext alc, AssemblyName name)
    {
        var ourDir = Path.GetDirectoryName(typeof(NativeEntryPoint).Assembly.Location)!;

        var potentialDllPath = Path.Combine(ourDir, name.Name + ".dll");

        return File.Exists(potentialDllPath) ? alc.LoadFromAssemblyPath(potentialDllPath) : null;
    }
}
