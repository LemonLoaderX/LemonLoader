#if ANDROID && NET6_0_OR_GREATER

using System;
using System.Reflection;
using System.Runtime.InteropServices;
using Il2CppInterop.Runtime;
using MelonLoader.InternalUtils;

namespace MelonLoader.Fixes.Il2CppInterop
{
    internal static class AndroidIl2CppInteropFix
    {
        private static IntPtr _il2CppHandle;

        internal static void Install()
        {
            _il2CppHandle = BootstrapInterop.Library.GetIl2CppLibraryHandle();
            if (_il2CppHandle == IntPtr.Zero)
                throw new InvalidOperationException("Unity's initialized IL2CPP library handle is unavailable. Use a matching Android bootstrap and Loader.");

            System.Runtime.InteropServices.NativeLibrary.SetDllImportResolver(
                typeof(IL2CPP).Assembly,
                ResolveLibrary);
        }

        private static IntPtr ResolveLibrary(
            string libraryName,
            Assembly assembly,
            DllImportSearchPath? searchPath)
        {
            if (!string.Equals(libraryName, "GameAssembly", StringComparison.Ordinal) &&
                !string.Equals(libraryName, "libil2cpp.so", StringComparison.Ordinal))
                return IntPtr.Zero;

            return _il2CppHandle;
        }
    }
}

#endif
