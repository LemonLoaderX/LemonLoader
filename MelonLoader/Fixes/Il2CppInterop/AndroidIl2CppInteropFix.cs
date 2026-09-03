#if ANDROID && NET6_0_OR_GREATER

using System;
using System.Reflection;
using System.Runtime.InteropServices;
using Il2CppInterop.Runtime;

namespace MelonLoader.Fixes.Il2CppInterop
{
    internal static class AndroidIl2CppInteropFix
    {
        private static IntPtr _il2CppHandle;

        internal static void Install()
        {
            System.Runtime.InteropServices.NativeLibrary.SetDllImportResolver(
                typeof(IL2CPP).Assembly,
                ResolveLibrary);
        }

        private static IntPtr ResolveLibrary(
            string libraryName,
            Assembly assembly,
            DllImportSearchPath? searchPath)
        {
            if (!string.Equals(libraryName, "GameAssembly", StringComparison.Ordinal))
                return IntPtr.Zero;

            if (_il2CppHandle == IntPtr.Zero)
            {
                _il2CppHandle = System.Runtime.InteropServices.NativeLibrary.Load("libil2cpp.so");
            }

            return _il2CppHandle;
        }
    }
}

#endif
