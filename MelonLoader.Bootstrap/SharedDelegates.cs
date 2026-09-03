using MelonLoader.Logging;

using System.Runtime.InteropServices;

namespace MelonLoader.Bootstrap;

[UnmanagedFunctionPointer(CallingConvention.Winapi)]
internal unsafe delegate void NativeHookFn(nint* target, nint detour);

#if ANDROID
[UnmanagedFunctionPointer(CallingConvention.Winapi)]
internal delegate nint CreateArm64ValueReturnAdapterFn(nint target, uint valueSize);

[UnmanagedFunctionPointer(CallingConvention.Winapi)]
internal delegate void DestroyArm64ValueReturnAdapterFn(nint adapter);

[UnmanagedFunctionPointer(CallingConvention.Winapi)]
internal delegate nint ResolveArm64Il2CppInjectionTargetFn(
    uint target,
    uint unityMajor,
    uint unityMinor,
    uint unityBuild);

[UnmanagedFunctionPointer(CallingConvention.Winapi)]
internal delegate void ConfigureLoggingFn(uint maxLogs, [MarshalAs(UnmanagedType.U1)] bool capturePlayerLogs);

[UnmanagedFunctionPointer(CallingConvention.Winapi)]
internal unsafe delegate void LogManagedExceptionFn(byte* message, int messageLength);

[UnmanagedFunctionPointer(CallingConvention.Winapi)]
internal unsafe delegate void LogMsgFn(ColorARGB* msgColor, char* msg, int msgLength, ColorARGB* sectionColor, char* section, int sectionLength, char* strippedMSg, int strippedMsgLength);

[UnmanagedFunctionPointer(CallingConvention.Winapi)]
internal unsafe delegate void LogErrorFn(char* msg, int msgLength, char* section, int sectionLength, bool warning);

[UnmanagedFunctionPointer(CallingConvention.Winapi)]
internal unsafe delegate void LogMelonInfoFn(ColorARGB* nameColor, char* name, int nameLength, char* info, int infoLength);
#else
[UnmanagedFunctionPointer(CallingConvention.Winapi, CharSet = CharSet.Unicode)]
internal unsafe delegate void LogMsgFn(ColorARGB* msgColor, string msg, int msgLength, ColorARGB* sectionColor, string section, int sectionLength, string strippedMSg, int strippedMsgLength);

[UnmanagedFunctionPointer(CallingConvention.Winapi, CharSet = CharSet.Unicode)]
internal unsafe delegate void LogErrorFn(string msg, int msgLength, string section, int sectionLength, bool warning);

[UnmanagedFunctionPointer(CallingConvention.Winapi, CharSet = CharSet.Unicode)]
internal unsafe delegate void LogMelonInfoFn(ColorARGB* nameColor, string name, int nameLength, string info, int infoLength);
#endif

[UnmanagedFunctionPointer(CallingConvention.Winapi)]
internal delegate nint PtrRetFn();

[UnmanagedFunctionPointer(CallingConvention.Winapi)]
internal delegate nint CastManagedAssemblyPtrFn(nint ptr);

[UnmanagedFunctionPointer(CallingConvention.Winapi)]
internal delegate void ActionFn();

[UnmanagedFunctionPointer(CallingConvention.Winapi)]
[return: MarshalAs(UnmanagedType.U1)]
internal delegate bool BoolRetFn();

[UnmanagedFunctionPointer(CallingConvention.Winapi)]
internal delegate void GetLoaderConfigFn(ref LoaderConfig config);
