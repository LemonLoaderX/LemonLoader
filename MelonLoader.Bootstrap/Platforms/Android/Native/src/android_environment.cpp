#include "state.hpp"
#include "jni_utils.hpp"
#include "process_lock.hpp"

#include <android/asset_manager_jni.h>
#include <dlfcn.h>

#include <cstdlib>
#include <filesystem>
#include <string>

namespace lemon::bootstrap {
namespace {

std::string get_file_path(JNIEnv* env, jobject file) {
    if (file == nullptr) {
        return {};
    }
    jclass file_class = env->GetObjectClass(file);
    jmethodID get_path = required_method(env,
        file_class, "getAbsolutePath", "()Ljava/lang/String;");
    auto value = static_cast<jstring>(checked_object_call(env, file, get_path));
    std::string result = java_string(env, value);
    env->DeleteLocalRef(value);
    env->DeleteLocalRef(file_class);
    return result;
}

// Keep the process-wide default on both runtime profiles. Android CoreCLR's
// Java trust store does not cover other OpenSSL consumers loaded by a game/Mod.
void configure_android_certificate_store() {
    const char* certificate_directories[] = {
        "/apex/com.android.conscrypt/cacerts",
        "/system/etc/security/cacerts",
    };

    std::error_code error;
    for (const char* directory : certificate_directories) {
        if (!std::filesystem::is_directory(directory, error)) {
            error.clear();
            continue;
        }
        if (setenv("SSL_CERT_DIR", directory, 0) != 0) {
            const int code = errno;
            log_error(std::string("Could not configure Android system certificate directory '") +
                      directory + "': " + std::error_code(code, std::generic_category()).message());
        }
        return;
    }
    log_error("Android system certificate directory was not found");
}

}  // namespace

bool initialize_android_environment(JNIEnv* env) {
    jclass unity_player = env->FindClass("com/unity3d/player/UnityPlayer");
    if (clear_java_exception(env, "FindClass(UnityPlayer)") || unity_player == nullptr) {
        return false;
    }
    jfieldID activity_field = env->GetStaticFieldID(
        unity_player, "currentActivity", "Landroid/app/Activity;");
    if (clear_java_exception(env, "Resolve UnityPlayer.currentActivity") || !activity_field) {
        env->DeleteLocalRef(unity_player);
        return false;
    }
    jobject activity = env->GetStaticObjectField(unity_player, activity_field);
    if (clear_java_exception(env, "UnityPlayer.currentActivity") || activity == nullptr) {
        env->DeleteLocalRef(unity_player);
        return false;
    }

    jclass activity_class = env->GetObjectClass(activity);
    jmethodID get_package_name = required_method(env,
        activity_class, "getPackageName", "()Ljava/lang/String;");
    jmethodID get_files_dir = required_method(env,
        activity_class, "getFilesDir", "()Ljava/io/File;");
    jmethodID get_external_files_dir = required_method(env,
        activity_class, "getExternalFilesDir", "(Ljava/lang/String;)Ljava/io/File;");
    jmethodID get_assets = required_method(env,
        activity_class, "getAssets", "()Landroid/content/res/AssetManager;");

    auto package_value = static_cast<jstring>(
        checked_object_call(env, activity, get_package_name));
    jobject files_directory = checked_object_call(env, activity, get_files_dir);
    jobject external_directory = checked_object_call(env,
        activity, get_external_files_dir, nullptr);
    jobject assets = checked_object_call(env, activity, get_assets);
    if (clear_java_exception(env, "Activity path discovery")) {
        return false;
    }

    runtime_paths.package_name = java_string(env, package_value);
    const std::filesystem::path files_path = get_file_path(env, files_directory);
    const std::filesystem::path external_path = get_file_path(env, external_directory);
    if (files_path.empty() || !files_path.is_absolute() ||
        (!external_path.empty() && !external_path.is_absolute()) || !assets) {
        log_error("Android returned an invalid files directory or AssetManager");
        return false;
    }
    runtime_paths.internal_data_directory = files_path.parent_path().string();
    runtime_paths.dotnet_directory =
        (files_path.parent_path() / "dotnet").string();
    runtime_paths.base_directory = external_path.empty()
        ? (files_path / "MelonLoader").string()
        : (external_path / "MelonLoader").string();
    static ProcessLock runtime_lock;
    std::error_code lock_error;
    const auto lock_path = files_path / ".lemonloader-runtime.lock";
    if (!runtime_lock.acquire(lock_path, lock_error)) {
        log_error("Could not exclusively lock runtime files at '" + lock_path.string() +
                  "': " + lock_error.message() +
                  ". Another application process may already be using LemonLoader.");
        return false;
    }
    asset_manager = AAssetManager_fromJava(env, assets);
    asset_manager_object = env->NewGlobalRef(assets);
    const auto get_loader = env->GetMethodID(activity_class, "getClassLoader", "()Ljava/lang/ClassLoader;");
    if (clear_java_exception(env, "Resolve application ClassLoader") || !get_loader) return false;
    const auto loader = env->CallObjectMethod(activity, get_loader);
    if (clear_java_exception(env, "Get application ClassLoader") || !loader) return false;
    application_class_loader = env->NewGlobalRef(loader);
    env->DeleteLocalRef(loader);

    env->DeleteLocalRef(assets);
    if (external_directory != nullptr) {
        env->DeleteLocalRef(external_directory);
    }
    env->DeleteLocalRef(files_directory);
    env->DeleteLocalRef(package_value);
    env->DeleteLocalRef(activity_class);
    env->DeleteLocalRef(activity);
    env->DeleteLocalRef(unity_player);

    if (clear_java_exception(env, "Retain Android AssetManager") ||
        asset_manager == nullptr || asset_manager_object == nullptr || application_class_loader == nullptr ||
        runtime_paths.base_directory.empty() ||
        runtime_paths.dotnet_directory.empty()) {
        log_error("Android runtime path or AssetManager discovery failed");
        return false;
    }
    return true;
}

bool prepare_android_runtime() {
    const auto set_environment = [](const char* name, const char* value) {
        if (setenv(name, value, 1) == 0) return true;
        const int code = errno;
        log_error(std::string("Could not set environment variable ") + name + ": " +
                  std::error_code(code, std::generic_category()).message());
        return false;
    };
    const char* existing_path = getenv("PATH");
    const std::string path = runtime_paths.dotnet_directory + ':' +
        (existing_path == nullptr ? "" : existing_path);
    if (!set_environment("MELONLOADER_BASE_DIR", runtime_paths.base_directory.c_str()) ||
        !set_environment("MELONLOADER_DOTNET_ROOT", runtime_paths.dotnet_directory.c_str()) ||
        !set_environment("MELONLOADER_ANDROID_PACKAGE", runtime_paths.package_name.c_str()) ||
        !set_environment("MELONLOADER_BOOTSTRAP_KIND", "ndk") ||
        !set_environment("MELONLOADER_MANAGED_RUNTIME_BACKEND", "coreclr") ||
        !set_environment("DOTNET_ROOT", runtime_paths.dotnet_directory.c_str()) ||
        !set_environment("PATH", path.c_str())) return false;
    configure_android_certificate_store();
    configure_crash_reporting();

    using mallopt_fn = int (*)(int, int);
    auto mallopt_value = reinterpret_cast<mallopt_fn>(dlsym(RTLD_DEFAULT, "mallopt"));
    if (mallopt_value != nullptr && mallopt_value(-204, 0) == 0) {
        log_line("[WARNING] Bionic heap pointer tagging opt-out is unavailable");
    }
    return true;
}

}  // namespace lemon::bootstrap
