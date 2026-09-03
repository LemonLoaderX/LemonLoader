using MelonLoader.Bootstrap;

namespace MelonLoader.InternalUtils;

internal class BootstrapLibrary
{
    internal NativeHookFn NativeHookAttach { get; private set; }
    internal NativeHookFn NativeHookDetach { get; private set; }
    internal LogMsgFn LogMsg { get; private set; }
    internal LogErrorFn LogError { get; private set; }
    internal LogMelonInfoFn LogMelonInfo { get; private set; }
    internal BoolRetFn IsConsoleOpen { get; private set; }
#if !ANDROID
    internal ActionFn MonoInstallHooks { get; private set; }
    internal PtrRetFn MonoGetDomainPtr { get; private set; }
    internal PtrRetFn MonoGetRuntimeHandle { get; private set; }
    internal GetLoaderConfigFn GetLoaderConfig { get; private set; }
#else
    internal PtrRetFn GetJavaVM { get; private set; }
    internal CreateArm64ValueReturnAdapterFn CreateArm64ValueReturnAdapter { get; private set; }
    internal DestroyArm64ValueReturnAdapterFn DestroyArm64ValueReturnAdapter { get; private set; }
    internal ResolveArm64Il2CppInjectionTargetFn ResolveArm64Il2CppInjectionTarget { get; private set; }
    internal ConfigureLoggingFn ConfigureLogging { get; private set; }
    internal LogManagedExceptionFn LogManagedException { get; private set; }
#endif
}
