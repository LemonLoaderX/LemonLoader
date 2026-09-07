#include "state.hpp"

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
    if (!env->ExceptionCheck()) {
        return false;
    }
    env->ExceptionDescribe();
    env->ExceptionClear();
    log_error("Android CoreCLR crypto initialization failed while " + context);
    return true;
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
    if (std::filesystem::is_regular_file(root / "libSystem.Security.Cryptography.Native.OpenSsl.so")) {
        // Experimental Bionic packs carry their own OpenSSL pair. Never fall back to BoringSSL.
        for (const char* name : {"libcrypto.so", "libssl.so"}) {
            if (dlopen((root / name).c_str(), RTLD_NOW | RTLD_LOCAL) == nullptr) {
                log_error(std::string("Bionic OpenSSL preload failed: ") + dlerror());
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
        return true;
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
    if (loader_class == nullptr || clear_jni_exception(env, "finding the APK crypto bridge")) {
        log_error("The Patcher did not install the Android CoreCLR crypto dex into the APK");
        return false;
    }
    jmethodID load_library = env->GetStaticMethodID(
        loader_class,
        "load",
        "(Ljava/lang/String;)V");
    jstring library_path = env->NewStringUTF(crypto_library.c_str());
    if (load_library != nullptr && library_path != nullptr) {
        env->CallStaticVoidMethod(loader_class, load_library, library_path);
    }
    const bool load_failed = load_library == nullptr || library_path == nullptr ||
        clear_jni_exception(env, "loading the Android crypto native library");
    if (!load_failed) {
        android_crypto_module = dlopen(
            crypto_library.c_str(),
            RTLD_NOW | RTLD_NOLOAD | RTLD_LOCAL);
        android_crypto_loader_class = static_cast<jclass>(env->NewGlobalRef(loader_class));
    }

    if (library_path != nullptr) {
        env->DeleteLocalRef(library_path);
    }
    env->DeleteLocalRef(loader_class);

    if (load_failed || android_crypto_module == nullptr ||
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
