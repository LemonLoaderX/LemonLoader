#include "state.hpp"
#include "jni_utils.hpp"

#include <dlfcn.h>

#include <cstring>
#include <cstdlib>
#include <filesystem>
#include <string>

namespace lemon::bootstrap {
namespace {

void* android_crypto_module = nullptr;
jclass android_crypto_loader_class = nullptr;

bool clear_jni_exception(JNIEnv* env, const std::string& context) {
    return clear_java_exception(env, context.c_str());
}

bool is_android_crypto_library(const char* library_name) {
    if (library_name == nullptr) {
        return false;
    }
    return std::strcmp(
               library_name,
               "System.Security.Cryptography.Native.Android") == 0 ||
        std::strcmp(
               library_name,
               "libSystem.Security.Cryptography.Native.Android") == 0 ||
        std::strcmp(
               library_name,
               "libSystem.Security.Cryptography.Native.Android.so") == 0;
}

}  // namespace

bool initialize_android_crypto(const std::string& runtime_directory) {
    const auto root = std::filesystem::path(runtime_directory);
    if (runtime_paths.runtime_rid == "linux-bionic-arm64") {
        // Experimental Bionic packs carry their own OpenSSL pair. Never fall back to BoringSSL.
        for (const char* name : {"libcrypto.so", "libssl.so", "libSystem.Security.Cryptography.Native.OpenSsl.so"}) {
            if (dlopen((root / name).c_str(), RTLD_NOW | RTLD_LOCAL) == nullptr) {
                const char* detail = dlerror();
                log_error("Bionic OpenSSL preload failed for '" + (root / name).string() +
                          "': " + (detail ? detail : "unknown linker error"));
                return false;
            }
        }
        const char* certificates = "/apex/com.android.conscrypt/cacerts";
        if (!std::filesystem::is_directory(certificates)) {
            certificates = "/system/etc/security/cacerts";
        }
        if (!std::filesystem::is_directory(certificates) ||
            setenv("SSL_CERT_DIR", certificates, 0) != 0) {
            log_error("Bionic system certificate directory is unavailable");
            return false;
        }
        return true;
    }
    const std::filesystem::path crypto_library =
        std::filesystem::path(runtime_directory) /
        "libSystem.Security.Cryptography.Native.Android.so";
    if (!std::filesystem::is_regular_file(crypto_library)) {
        log_error("Android crypto library is missing: '" + crypto_library.string() + "'");
        return false;
    }
    if (android_crypto_module != nullptr) {
        return true;
    }
    if (java_vm == nullptr) {
        log_error("The Java VM is unavailable for the Android CoreCLR crypto runtime");
        return false;
    }

    JNIEnv* env = nullptr;
    if (java_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK ||
        env == nullptr) {
        log_error("The current thread has no JNI environment for Android CoreCLR crypto");
        return false;
    }

    jclass loader_class = env->FindClass(
        "net/dot/android/crypto/LemonLoaderCryptoBootstrap");
    if (clear_jni_exception(env, "finding the APK crypto bridge") || loader_class == nullptr) {
        log_error("Android CoreCLR crypto bridge is unavailable; verify the APK helper DEX and class loader");
        return false;
    }
    jmethodID load_library = required_static_method(env,
        loader_class,
        "load",
        "(Ljava/lang/String;)V");
    jstring library_path = new_java_string(env, crypto_library.string());
    env->CallStaticVoidMethod(loader_class, load_library, library_path);
    const bool load_failed = clear_jni_exception(env, "loading the Android crypto native library") ||
        library_path == nullptr;
    if (!load_failed) {
        android_crypto_module = dlopen(
            crypto_library.c_str(),
            RTLD_NOW | RTLD_NOLOAD | RTLD_LOCAL);
        if (!android_crypto_module) {
            const char* detail = dlerror();
            log_error("Could not retain Android crypto module '" + crypto_library.string() +
                      "': " + (detail ? detail : "unknown linker error"));
        }
        android_crypto_loader_class = static_cast<jclass>(env->NewGlobalRef(loader_class));
    }

    if (library_path != nullptr) {
        env->DeleteLocalRef(library_path);
    }
    env->DeleteLocalRef(loader_class);

    if (clear_jni_exception(env, "retaining the Android crypto bridge") ||
        load_failed || android_crypto_module == nullptr ||
        android_crypto_loader_class == nullptr) {
        log_error("Android CoreCLR crypto native library initialization did not complete");
        return false;
    }
    return true;
}

const void* resolve_android_crypto_pinvoke(
    const char* library_name,
    const char* entrypoint_name) {
    if (android_crypto_module == nullptr || entrypoint_name == nullptr ||
        !is_android_crypto_library(library_name)) {
        return nullptr;
    }
    return dlsym(android_crypto_module, entrypoint_name);
}

}  // namespace lemon::bootstrap
