using System;
using System.Runtime.InteropServices;
using System.Text;


#if NET6_0_OR_GREATER
using MelonLoader.CoreClrUtils;
#endif

namespace MelonLoader.InternalUtils;

public static unsafe class BootstrapInterop
{
    internal static BootstrapLibrary Library { get; private set; }
#if ANDROID
    // Resolved separately so an older bootstrap can still load this assembly.
    private static delegate* unmanaged[Cdecl]<nint*, nint, int> _tryNativeHookDetach;
#endif

    internal static void SetDefaultConsoleTitleWithGameName(string gameName, string gameVersion = null)
    {
        if (LoaderConfig.Current.Console.DontSetTitle)
            return;

        var versionStr = $"{Core.GetVersionString()} - {gameName} {gameVersion ?? ""}";

        if (LoaderConfig.Current.Loader.DebugMode)
            versionStr = "[D] " + versionStr;

        MelonUtils.SetConsoleTitle(versionStr);
    }

#if WINDOWS
    private const int MF_BYCOMMAND = 0x00000000;

    private const int MF_ENABLED = 0x00000000;
    private const int MF_GRAYED = 0x00000001;
    private const int MF_DISABLED = 0x00000002;
    public const int SC_CLOSE = 0xF060;

    [DllImport("user32.dll")]
    private static extern int EnableMenuItem(IntPtr hMenu, uint uIDEnableItem, uint uEnable);

    [DllImport("user32.dll")]
    private static extern IntPtr GetSystemMenu(IntPtr hWnd, byte bRevert);

    public static void EnableCloseButton(IntPtr mainWindow)
    {
        EnableMenuItem(GetSystemMenu(mainWindow, 0), SC_CLOSE, MF_BYCOMMAND | MF_ENABLED);
    }

    public static void DisableCloseButton(IntPtr mainWindow)
    {
        EnableMenuItem(GetSystemMenu(mainWindow, 0), SC_CLOSE, MF_BYCOMMAND | MF_DISABLED | MF_GRAYED);
    }
#endif

    public static void NativeHookAttach(nint target, nint detour)
    {
#if NET6_0_OR_GREATER && !ANDROID
        // SanityCheckDetour is able to wrap and fix the bad method in a delegate where possible, so we pass the detour by ref.
        // Herp: Wine/Proton are missing the PssCaptureSnapshot export from kernel32.dll so we skip CoreClrDelegateFixer.SanityCheckDetour under that runtime
        if (!MelonUtils.IsUnderWineOrSteamProton()
            && !CoreClrDelegateFixer.SanityCheckDetour(ref detour))
            return;
#endif

        NativeHookAttachDirect(target, detour);

#if NET6_0_OR_GREATER
        NativeStackWalk.RegisterHookAddr((ulong)target, $"Mod-requested detour of 0x{target:X} -> 0x{detour:X}");
#endif
    }

    internal static unsafe void NativeHookAttachDirect(nint target, nint detour)
    {
        Library.NativeHookAttach((nint*)target, detour);
    }

    public static unsafe void NativeHookDetach(nint target, nint detour)
    {
        TryNativeHookDetach(target, detour);
    }

    internal static bool TryNativeHookDetach(nint target, nint detour)
    {
#if ANDROID
        if (_tryNativeHookDetach != null)
        {
            if (_tryNativeHookDetach((nint*)target, detour) == 0)
                return false;
        }
        else
#endif
        {
            // Legacy bootstraps expose no result. Preserve their existing behavior.
            NativeHookDetachDirect(target, detour);
        }

#if NET6_0_OR_GREATER
        NativeStackWalk.UnregisterHookAddr((ulong)target);
#endif
        return true;
    }
    
    internal static unsafe void NativeHookDetachDirect(nint target, nint detour)
    {
        Library.NativeHookDetach((nint*)target, detour);
    }

    // Herp: This unfortunately needs to return a string with the error message
    // Mono doesn't seem to rethrow Exceptions to mono_runtime_invoke properly in some rare cases
    internal static string Initialize(nint bootstrapHandle)
    {
        try
        {
            Library = new NativeLibrary<BootstrapLibrary>(bootstrapHandle).Instance;
#if ANDROID
            _tryNativeHookDetach = (delegate* unmanaged[Cdecl]<nint*, nint, int>)
                NativeLibrary.AgnosticGetProcAddress(bootstrapHandle, "TryNativeHookDetach");
#endif
        }
        catch (Exception ex)
        {
            return GetExceptionText(ex);
        }

        try
        {
            Core.Initialize();
            return null;
        }
        catch (Exception ex)
        {
            TryLogManagedFailure("Failed to initialize MelonLoader", ex);
            return GetExceptionText(ex);
        }
    }

    internal static int Start()
    {
        try
        {
            return Core.Start() ? 0 : 1;
        }
        catch (Exception ex)
        {
            TryLogManagedFailure("Failed to start MelonLoader", ex);
            return 1;
        }
    }

    private static string GetExceptionText(Exception exception)
    {
        try
        {
            return exception.ToString();
        }
        catch
        {
            return exception.GetType().FullName ?? "Managed exception";
        }
    }

    private static void TryLogManagedFailure(string context, Exception exception)
    {
        try
        {
            MelonLogger.Error(context);
            MelonLogger.Error(exception);
            return;
        }
        catch
        {
        }

#if ANDROID
        try
        {
            byte[] message = Encoding.UTF8.GetBytes(context + ":\n" + GetExceptionText(exception));
            fixed (byte* messagePointer = message)
                Library.LogManagedException(messagePointer, message.Length);
        }
        catch
        {
            // A failure reporter must never escape the managed start callback.
        }
#else
        try
        {
            Console.Error.WriteLine(context + ": " + GetExceptionText(exception));
        }
        catch
        {
        }
#endif
    }

#if ANDROID
    public static void DestroyArm64ValueReturnAdapter(nint adapter) =>
        Library.DestroyArm64ValueReturnAdapter(adapter);
#endif
}
