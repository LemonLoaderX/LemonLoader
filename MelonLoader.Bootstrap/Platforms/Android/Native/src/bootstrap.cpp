#include "lemon_bootstrap.h"
#include "state.hpp"
#include "jni_utils.hpp"

#include <dlfcn.h>

#include <memory>
#include <mutex>
#include <string>

namespace lemon::bootstrap {

JavaVM* java_vm = nullptr;
void* unity_handle = nullptr;
AAssetManager* asset_manager = nullptr;
jobject asset_manager_object = nullptr;
RuntimePaths runtime_paths;

namespace {

std::mutex native_loader_mutex;
enum class NativeLoadState {
    not_started,
    loaded,
    failed,
};
NativeLoadState native_load_state = NativeLoadState::not_started;

jboolean native_load_impl(JNIEnv* env, jstring native_library_directory) {
    const std::lock_guard lock(native_loader_mutex);
    if (native_load_state == NativeLoadState::loaded) {
        log_line("Reusing the process-scoped Android bootstrap");
        return JNI_TRUE;
    }
    if (native_load_state == NativeLoadState::failed) {
        log_error("Refusing to retry a failed Android bootstrap load in the same process");
        return JNI_FALSE;
    }
    native_load_state = NativeLoadState::failed;

    std::string unity_library_path = "libunity.so";
    if (native_library_directory != nullptr) {
        const std::string directory = java_string(env, native_library_directory);
        if (!directory.empty()) {
            unity_library_path = directory;
            if (unity_library_path.back() != '/') {
                unity_library_path.push_back('/');
            }
            unity_library_path += "libunity.so";
        }
    }

    void* loaded_unity = dlopen(unity_library_path.c_str(), RTLD_NOW | RTLD_GLOBAL);
    unity_handle = loaded_unity;
    if (unity_handle == nullptr) {
        const char* loader_error = dlerror();
        log_error(
            "Failed to load '" + unity_library_path + "': " +
            (loader_error == nullptr ? "unknown error" : loader_error));
        return JNI_FALSE;
    }
    bool unity_on_load_succeeded = false;
    const auto rollback_unity_load = [&](void* library) noexcept {
        native_boundary("Unity load rollback", [&]() {
            if (asset_manager_object != nullptr) {
                env->DeleteGlobalRef(asset_manager_object);
                asset_manager_object = nullptr;
            }
            asset_manager = nullptr;
            if (unity_on_load_succeeded) {
                using unity_on_unload_fn = void (*)(JavaVM*, void*);
                auto unity_on_unload = reinterpret_cast<unity_on_unload_fn>(
                    dlsym(library, "JNI_OnUnload"));
                if (unity_on_unload != nullptr) {
                    native_boundary("Unity JNI_OnUnload", [&]() {
                        unity_on_unload(java_vm, nullptr);
                    });
                }
            }
            dlclose(library);
            unity_handle = nullptr;
            runtime_paths = RuntimePaths{};
        });
    };
    // Failed JNI operations can throw. Keep rollback active for both ordinary
    // failure returns and exception unwinding until callbacks are published.
    std::unique_ptr<void, decltype(rollback_unity_load)> unity_load_guard(
        loaded_unity, rollback_unity_load);

    using unity_on_load_fn = jint (*)(JavaVM*, void*);
    auto unity_on_load = reinterpret_cast<unity_on_load_fn>(
        dlsym(unity_handle, "JNI_OnLoad"));
    if (unity_on_load == nullptr) {
        log_error("libunity.so does not export JNI_OnLoad");
        return JNI_FALSE;
    }
    const jint unity_version = unity_on_load(java_vm, nullptr);
    if (unity_version <= 0) {
        log_error("libunity.so JNI_OnLoad failed with status " +
                  std::to_string(unity_version));
        return JNI_FALSE;
    }
    unity_on_load_succeeded = true;

    if (!initialize_android_environment(env)) {
        return JNI_FALSE;
    }
    reset_latest_log();
    if (!extract_runtime_assets() || !install_symbol_redirect()) {
        return JNI_FALSE;
    }
    unity_load_guard.release();
    native_load_state = NativeLoadState::loaded;
    log_line("Pure NDK Android bootstrap initialized");
    return JNI_TRUE;
}

jboolean native_load(JNIEnv* env, jobject, jstring directory) {
    return native_boundary("NativeLoader.load", static_cast<jboolean>(JNI_FALSE), [&]() {
        return native_load_impl(env, directory);
    });
}

jboolean native_unload(JNIEnv*, jobject) {
    return native_boundary("NativeLoader.unload", static_cast<jboolean>(JNI_FALSE), []() {
        const std::lock_guard lock(native_loader_mutex);
        // Managed callbacks and hook trampolines can outlive a UnityPlayer Activity.
        // Keep Unity and CoreCLR pinned until process exit, and make the next load idempotent.
        return static_cast<jboolean>(native_load_state == NativeLoadState::loaded ? JNI_TRUE : JNI_FALSE);
    });
}

}  // namespace
}  // namespace lemon::bootstrap

extern "C" LEMON_EXPORT JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
    return lemon::bootstrap::native_boundary("JNI_OnLoad", static_cast<jint>(JNI_ERR), [&]() -> jint {
        lemon::bootstrap::java_vm = vm;
        JNIEnv* env = nullptr;
        if (vm == nullptr || vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
            return JNI_ERR;
        }

        jclass native_loader = env->FindClass("com/unity3d/player/NativeLoader");
        if (native_loader == nullptr) {
            if (env->ExceptionCheck()) {
                env->ExceptionDescribe();
                env->ExceptionClear();
            }
            lemon::bootstrap::log_error("Cannot find com.unity3d.player.NativeLoader");
            return JNI_ERR;
        }

        const JNINativeMethod methods[] = {
            {const_cast<char*>("load"), const_cast<char*>("(Ljava/lang/String;)Z"),
             reinterpret_cast<void*>(&lemon::bootstrap::native_load)},
            {const_cast<char*>("unload"), const_cast<char*>("()Z"),
             reinterpret_cast<void*>(&lemon::bootstrap::native_unload)},
        };
        const jint status = env->RegisterNatives(native_loader, methods, 2);
        env->DeleteLocalRef(native_loader);
        if (status != JNI_OK) {
            if (env->ExceptionCheck()) {
                env->ExceptionDescribe();
                env->ExceptionClear();
            }
            lemon::bootstrap::log_error("RegisterNatives failed with status " +
                                        std::to_string(status));
            return JNI_ERR;
        }
        return JNI_VERSION_1_6;
    });
}
