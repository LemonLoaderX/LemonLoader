using Il2CppInterop.HarmonySupport;
using Il2CppInterop.Runtime.Injection;
using Il2CppInterop.Runtime.Startup;
using MelonLoader.Support.Preferences;
using System;
using System.Reflection;
using System.Runtime.InteropServices;
using MelonLoader.CoreClrUtils;
using UnityEngine;
using Il2CppInterop.Common;
using Microsoft.Extensions.Logging;
using MelonLoader.Utils;
using System.IO;
using MelonLoader.InternalUtils;
using HarmonyLib.Public.Patching;

[assembly: MelonLoader.PatchShield]

namespace MelonLoader.Support
{
    internal static class Main
    {
        internal static ISupportModule_From Interface;
        internal static InteropInterface Interop;
        internal static GameObject obj = null;
        internal static SM_Component component = null;

        private static Assembly Il2Cppmscorlib = null;
        private static Type streamType = null;

        private static ISupportModule_To Initialize(ISupportModule_From interface_from)
        {
            Interface = interface_from; 

            foreach (var file in Directory.GetFiles(MelonEnvironment.Il2CppAssembliesDirectory, "*.dll"))
            {
                try
                {
                    Assembly.LoadFrom(file);
                }
                catch { }
            }

            UnityMappers.RegisterMappers();
#if !ANDROID
            if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
            {
                System.Runtime.InteropServices.NativeLibrary.SetDllImportResolver(typeof(Il2CppInteropRuntime).Assembly,
                    MacOsIl2CppInteropLibraryResolver);
            }
#endif

            var unityVersion = new Version(
                InternalUtils.UnityInformationHandler.EngineVersion.Major,
                InternalUtils.UnityInformationHandler.EngineVersion.Minor,
                InternalUtils.UnityInformationHandler.EngineVersion.Build);
            Il2CppInteropRuntime runtime = Il2CppInteropRuntime.Create(new()
            {
                DetourProvider = new MelonDetourProvider(),
#if ANDROID
                IsAndroid = true,
                InjectionTargetResolver = target =>
                    BootstrapInterop.Library.ResolveArm64Il2CppInjectionTarget(
                        (uint)target,
                        (uint)unityVersion.Major,
                        (uint)unityVersion.Minor,
                        (uint)unityVersion.Build),
#endif
                UnityVersion = unityVersion
            }).AddLogger(new InteropLogger())
              .AddHarmonySupport();

            Interop = new InteropInterface();
            Interface.SetInteropSupportInterface(Interop);
            runtime.Start();

#if ANDROID
            // Il2CppInterop must inspect wrapper methods before Harmony calls GetMethodBody.
            PatchManager.ResolvePatcher -= ManagedMethodPatcher.TryResolve;
            PatchManager.ResolvePatcher -= NativeDetourMethodPatcher.TryResolve;
            PatchManager.ResolvePatcher += ManagedMethodPatcher.TryResolve;
            PatchManager.ResolvePatcher += NativeDetourMethodPatcher.TryResolve;
#endif

            if (!LoaderConfig.Current.UnityEngine.DisableConsoleLogCleaner)
                ConsoleCleaner();

#if ANDROID
            AndroidLifecycle.Init();
            MonoEnumeratorWrapper.Register();
            SM_Component.Create();
#else
            MonoEnumeratorWrapper.Register();

            GetSceneManagerMethods(out MethodInfo sceneLoaded,
                out MethodInfo sceneUnloaded);
            if (sceneLoaded == null)
            {
                MelonLogger.Warning("Failed to find Internal_SceneLoaded method");
                MelonLogger.Warning("Falling back to SupportModule Component Creation");
                SM_Component.Create();
            }
            else
                SceneHandler.Init(sceneLoaded, sceneUnloaded);
#endif

            return new SupportModule_To();
        }

        private static void GetSceneManagerMethods(out MethodInfo sceneLoaded,
            out MethodInfo sceneUnloaded)
        {
            sceneLoaded = null;
            sceneUnloaded = null;
            Type scenemanager = null;
            try
            {
                Assembly unityengine = Assembly.Load("UnityEngine.CoreModule");
                if (unityengine != null)
                    scenemanager = unityengine.GetType("UnityEngine.SceneManagement.SceneManager");

                if (scenemanager == null)
                {
                    unityengine = Assembly.Load("UnityEngine");
                    if (unityengine != null)
                        scenemanager = unityengine.GetType("UnityEngine.SceneManagement.SceneManager");
                }
            }
            catch { scenemanager = null; }
            if (scenemanager == null)
                return;

            sceneLoaded = scenemanager.GetMethod("Internal_SceneLoaded", BindingFlags.Public | BindingFlags.Static);
            sceneUnloaded = scenemanager.GetMethod("Internal_SceneUnloaded", BindingFlags.Public | BindingFlags.Static);
        }

        private static IntPtr MacOsIl2CppInteropLibraryResolver(string libraryName, Assembly assembly, DllImportSearchPath? searchPath)
        {
            if (libraryName == "GameAssembly")
            {
                string gameAssemblyPath = Path.Combine(MelonEnvironment.GameExecutablePath, "Contents", "Frameworks", $"{libraryName}.dylib");
                return System.Runtime.InteropServices.NativeLibrary.Load(gameAssemblyPath);
            }
            return IntPtr.Zero;
        }

        private static void ConsoleCleaner()
        {
            // Il2CppSystem.Console.SetOut(new Il2CppSystem.IO.StreamWriter(Il2CppSystem.IO.Stream.Null));
            try
            {
                Il2Cppmscorlib = Assembly.Load("Il2Cppmscorlib");
                if (Il2Cppmscorlib == null)
                    throw new Exception("Unable to Find Assembly Il2Cppmscorlib!");

                streamType = Il2Cppmscorlib.GetType("Il2CppSystem.IO.Stream");
                if (streamType == null)
                    throw new Exception("Unable to Find Type Il2CppSystem.IO.Stream!");

                PropertyInfo propertyInfo = streamType.GetProperty("Null", BindingFlags.Static | BindingFlags.Public);
                if (propertyInfo == null)
                    throw new Exception("Unable to Find Property Il2CppSystem.IO.Stream.Null!");

                MethodInfo nullStreamField = propertyInfo.GetGetMethod();
                if (nullStreamField == null)
                    throw new Exception("Unable to Find Get Method of Property Il2CppSystem.IO.Stream.Null!");

                object nullStream = nullStreamField.Invoke(null, new object[0]);
                if (nullStream == null)
                    throw new Exception("Unable to Get Value of Property Il2CppSystem.IO.Stream.Null!");

                Type streamWriterType = Il2Cppmscorlib.GetType("Il2CppSystem.IO.StreamWriter");
                if (streamWriterType == null)
                    throw new Exception("Unable to Find Type Il2CppSystem.IO.StreamWriter!");

                object nullStreamWriter = null;
                ConstructorInfo[] constructors = streamWriterType.GetConstructors();
                foreach (var ctor in constructors)
                {
                    ParameterInfo[] parameters = ctor.GetParameters();
                    if (parameters.Length == 1 && parameters[0].ParameterType == streamType)
                    {
                        nullStreamWriter = ctor.Invoke(new[] { nullStream });
                        break;
                    }
                    else if (parameters.Length == 4 && parameters[0].ParameterType == streamType)
                    {
                        Type encodingType = Il2Cppmscorlib.GetType("Il2CppSystem.Text.Encoding");
                        if (encodingType == null)
                            throw new Exception("Unable to Find Type Il2CppSystem.Text.Encoding!");

                        MethodInfo getUtf8Method = encodingType.GetProperty("UTF8", BindingFlags.Static | BindingFlags.Public)?.GetGetMethod();
                        if (getUtf8Method == null)
                            throw new Exception("Unable to Find Method Il2CppSystem.Text.Encoding.get_UTF8!");

                        object utf8Encoding = getUtf8Method.Invoke(null, null);
                        if (utf8Encoding == null)
                            throw new Exception("Unable to Get Value of Il2CppSystem.Text.Encoding.UTF8!");

                        nullStreamWriter = ctor.Invoke(new[] { nullStream, utf8Encoding, 1024, false });
                        break;
                    }
                }

                if (nullStreamWriter == null)
                    throw new Exception("Unable to Find Suitable Constructor of Type Il2CppSystem.IO.StreamWriter!");

                Type consoleType = Il2Cppmscorlib.GetType("Il2CppSystem.Console");
                if (consoleType == null)
                    throw new Exception("Unable to Find Type Il2CppSystem.Console!");

                MethodInfo setOutMethod = consoleType.GetMethod("SetOut", BindingFlags.Static | BindingFlags.Public);
                if (setOutMethod == null)
                    throw new Exception("Unable to Find Method Il2CppSystem.Console.SetOut!");

                setOutMethod.Invoke(null, new[] { nullStreamWriter });
            }
            catch (Exception ex) { MelonLogger.Warning($"Console Cleaner Failed: {ex}"); }
        }
    }

    internal sealed class MelonDetourProvider : IDetourProvider
    {
        private static readonly MethodInfo GetValueTypeReturnSize =
            typeof(IDetourProvider).Assembly
                .GetType("Il2CppInterop.Runtime.Injection.ValueTypeReturnRegistry", false)
                ?.GetMethod(
                    "GetReturnSize",
                    BindingFlags.Public | BindingFlags.Static,
                    null,
                    new[] { typeof(Delegate) },
                    null);

        public IDetour Create<TDelegate>(nint original, TDelegate target) where TDelegate : Delegate
        {
            var returnSize = GetRegisteredReturnSize(target);
            return new MelonDetour(original, target, returnSize);
        }

        private static int GetRegisteredReturnSize(Delegate target) =>
            GetValueTypeReturnSize?.Invoke(null, new object[] { target }) is int returnSize
                ? returnSize
                : 0;

        private sealed class MelonDetour : IDetour
        {
            private nint _detourFrom;
            private nint _originalPtr;
            
            private Delegate _target;
            private IntPtr _managedTargetPtr;
            private IntPtr _targetPtr;
            private readonly int _returnSize;
            
            private GCHandle _pin;

            /// <summary>
            /// Original method
            /// </summary>
            public nint Target => _detourFrom;

            public nint Detour => _targetPtr;
            public nint OriginalTrampoline => _originalPtr;
            
            public MelonDetour(nint detourFrom, Delegate target, int returnSize)
            {
                _detourFrom = detourFrom;
                _target = target;
                _returnSize = returnSize;
                _pin = GCHandle.Alloc(_target);

                // We have to apply immediately because we're gonna be asked for a trampoline right away
                try
                {
                    Apply();
                }
                catch
                {
                    if (_pin.IsAllocated)
                        _pin.Free();
                    throw;
                }
            }

            public unsafe void Apply()
            {
                if (_targetPtr != IntPtr.Zero)
                    return;

                //_targetPtr = Marshal.GetFunctionPointerForDelegate(_target);
                _managedTargetPtr = CoreClrDelegateFixer.GetFixedPointerForDelegate(_target);
                _targetPtr = CreateAndroidArm64ValueReturnAdapter(_managedTargetPtr, _returnSize);
                
                var addr = _detourFrom;
                nint addrPtr = (nint)(&addr);
                
                BootstrapInterop.NativeHookAttachDirect(addrPtr, _targetPtr);
                if (addr == IntPtr.Zero)
                {
#if ANDROID
                    if (_targetPtr != _managedTargetPtr)
                        BootstrapInterop.Library.DestroyArm64ValueReturnAdapter(_targetPtr);
#endif
                    CoreClrDelegateFixer.Unpin(_target.Method);
                    _targetPtr = IntPtr.Zero;
                    _managedTargetPtr = IntPtr.Zero;
                    throw new InvalidOperationException("The native IL2CPP detour could not be installed.");
                }
                NativeStackWalk.RegisterHookAddr((ulong)addrPtr, $"Il2CppInterop detour of 0x{addrPtr:X} -> 0x{_targetPtr:X}");

                _originalPtr = addr;
            }

            private static IntPtr CreateAndroidArm64ValueReturnAdapter(IntPtr target, int returnSize)
            {
#if ANDROID
                if (returnSize <= 0)
                    return target;
                if (returnSize > 16)
                    return target;

                IntPtr adapter = BootstrapInterop.Library.CreateArm64ValueReturnAdapter(
                    target,
                    checked((uint)returnSize));
                if (adapter == IntPtr.Zero)
                    throw new InvalidOperationException(
                        $"Failed to create an ARM64 value-return adapter for a {returnSize}-byte value");

                return adapter;
#else
                return target;
#endif
            }

            public unsafe void Dispose()
            {
                if (_targetPtr == IntPtr.Zero)
                    return;

                var addr = _detourFrom;
                nint addrPtr = (nint)(&addr);

                BootstrapInterop.NativeHookDetachDirect(addrPtr, _targetPtr);
                NativeStackWalk.UnregisterHookAddr((ulong)addrPtr);
                CoreClrDelegateFixer.Unpin(_target.Method);

#if ANDROID
                if (_targetPtr != _managedTargetPtr)
                {
                    BootstrapInterop.Library.DestroyArm64ValueReturnAdapter(_targetPtr);
                }
#endif

                _targetPtr = IntPtr.Zero;
                _managedTargetPtr = IntPtr.Zero;
                _originalPtr = IntPtr.Zero;
                
                if (_pin.IsAllocated)
                    _pin.Free();
            }

            public T GenerateTrampoline<T>()
                where T : Delegate
            {
                if (_originalPtr == IntPtr.Zero)
                    return null;
                return Marshal.GetDelegateForFunctionPointer<T>(_originalPtr);
            }
        }
    }

    internal class InteropLogger
        : Microsoft.Extensions.Logging.ILogger
    {
        private MelonLogger.Instance _logger = new("Il2CppInterop");

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception exception,
            Func<TState, Exception, string> formatter)
        {
            string formattedTxt = formatter(state, exception);
            if (exception != null)
                formattedTxt += Environment.NewLine + exception;

            switch (logLevel)
            {
                case LogLevel.Debug:
                case LogLevel.Trace:
                    MelonDebug.Msg(formattedTxt);
                    break;

                case LogLevel.Critical:
                case LogLevel.Error:
                    _logger.Error(formattedTxt);
                    break;

                case LogLevel.Warning:
                    _logger.Warning(formattedTxt);
                    break;

                case LogLevel.Information:
                case LogLevel.None:
                default:
                    _logger.Msg(formattedTxt);
                    break;
            }
        }

        public bool IsEnabled(LogLevel logLevel)
            => logLevel switch
            {
                LogLevel.Debug or LogLevel.Trace => MelonDebug.IsEnabled(),
                _ => true
            };

        public IDisposable BeginScope<TState>(TState state)
            => throw new NotImplementedException();
    }
}
