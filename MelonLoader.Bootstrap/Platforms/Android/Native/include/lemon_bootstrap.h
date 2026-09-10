#pragma once

#include <jni.h>
#include <stdint.h>

#if defined(__GNUC__)
#define LEMON_EXPORT __attribute__((visibility("default")))
#else
#define LEMON_EXPORT
#endif

extern "C" {

LEMON_EXPORT JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved);

LEMON_EXPORT void NativeHookAttach(void** target, void* detour);
LEMON_EXPORT void NativeHookDetach(void** target, void* detour);
// Optional checked entry point: returns 1 on removal, 0 on failure; never writes target.
LEMON_EXPORT int32_t TryNativeHookDetach(void** target, void* detour);
LEMON_EXPORT void LogManagedException(const char* message, int32_t message_length);
LEMON_EXPORT void* CreateArm64ValueReturnAdapter(void* target, uint32_t value_size);
LEMON_EXPORT void DestroyArm64ValueReturnAdapter(void* adapter);
LEMON_EXPORT void* ResolveArm64Il2CppInjectionTarget(
    uint32_t target,
    uint32_t unity_major,
    uint32_t unity_minor,
    uint32_t unity_build);
LEMON_EXPORT void ConfigureLogging(uint32_t max_logs, uint8_t capture_player_logs);
LEMON_EXPORT void LogMsg(
    const void* message_color,
    const uint16_t* message,
    int message_length,
    const void* section_color,
    const uint16_t* section,
    int section_length,
    const uint16_t* stripped_message,
    int stripped_message_length);
LEMON_EXPORT void LogError(
    const uint16_t* message,
    int message_length,
    const uint16_t* section,
    int section_length,
    int warning);
LEMON_EXPORT void LogMelonInfo(
    const void* name_color,
    const uint16_t* name,
    int name_length,
    const uint16_t* info,
    int info_length);
LEMON_EXPORT uint8_t IsConsoleOpen();
LEMON_EXPORT JavaVM* GetJavaVM();

}
