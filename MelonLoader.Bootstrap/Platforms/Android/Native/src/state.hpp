#pragma once

#include <android/asset_manager.h>
#include <jni.h>

#include <string>
#include "utf.hpp"

namespace lemon::bootstrap {

struct RuntimePaths {
    std::string package_name;
    std::string base_directory;
    std::string internal_data_directory;
    std::string dotnet_directory;
    std::string runtime_rid = "android-arm64";
};

extern JavaVM* java_vm;
extern void* unity_handle;
extern AAssetManager* asset_manager;
extern jobject asset_manager_object;
extern RuntimePaths runtime_paths;

void log_line(const std::string& message);
void log_error(const std::string& message);
void reset_latest_log();
void configure_logging(uint32_t max_logs, bool capture_player_logs);

bool initialize_android_environment(JNIEnv* env);
bool extract_runtime_assets();
bool prepare_android_runtime();
bool initialize_android_crypto(const std::string& runtime_directory);
const void* resolve_android_crypto_pinvoke(
    const char* library_name,
    const char* entrypoint_name);

bool install_symbol_redirect();
bool initialize_managed_runtime();
void start_managed_runtime();

}  // namespace lemon::bootstrap
