#if NET6_0_OR_GREATER

using MelonLoader.Modules;
using System;
using System.Diagnostics;
using System.IO;
using MelonLoader.Utils;

namespace MelonLoader.InternalUtils
{
    internal static class Il2CppAssemblyGenerator
    {
        private static readonly string modulePath = Path.Combine(MelonEnvironment.Il2CppAssemblyGeneratorDirectory, "Il2CppAssemblyGenerator.dll");
        public static readonly MelonModule.Info moduleInfo = new MelonModule.Info(modulePath, () => !MelonUtils.IsGameIl2Cpp());

        internal static bool Run()
        {
            if (MelonEnvironment.IsMonoRuntime)
                return true;

#if ANDROID
            if (!Directory.Exists(MelonEnvironment.Il2CppAssembliesDirectory))
            {
                MelonLogger.Error("Pre-generated Android Il2Cpp assemblies were not found.");
                return false;
            }

            string[] interopAssemblies = Directory.GetFiles(
                MelonEnvironment.Il2CppAssembliesDirectory,
                "*.dll",
                SearchOption.TopDirectoryOnly);
            if (interopAssemblies.Length == 0)
            {
                MelonLogger.Error("The Android Il2Cpp assembly directory is empty.");
                return false;
            }

            MelonLogger.MsgDirect($"Using {interopAssemblies.Length} pre-generated Android Il2Cpp assemblies.");
            return true;
#else
            MelonLogger.MsgDirect("Loading Il2CppAssemblyGenerator...");
            var module = MelonModule.Load(moduleInfo);
            if (module == null)
            {
                if (File.Exists(modulePath))
                    MelonLogger.Error("Failed to Load Il2CppAssemblyGenerator!");
                else
                    MelonLogger.Error("Il2CppAssemblyGenerator was Not Found!");
                return false;
            }

            if (MelonUtils.IsWindows)
            {
                IntPtr windowHandle = Process.GetCurrentProcess().MainWindowHandle;

#if WINDOWS
                BootstrapInterop.DisableCloseButton(windowHandle);
#endif
            }

            var ret = module.SendMessage("Run");
            
            if (MelonUtils.IsWindows)
            {
                IntPtr windowHandle = Process.GetCurrentProcess().MainWindowHandle;

#if WINDOWS
                BootstrapInterop.EnableCloseButton(windowHandle);
#endif
            }

            return ret is 0;
#endif
        }
    }
}

#endif
