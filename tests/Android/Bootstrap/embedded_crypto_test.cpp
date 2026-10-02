#include <cassert>
#include <cstdarg>
#include <fstream>
#include <iostream>
#define LEMON_EMBEDDED_CRYPTO_DEX 1
#include "android_crypto.cpp"

asm(".section .rodata\n.global lemon_crypto_dex_start\nlemon_crypto_dex_start:\n"
    ".space 112\n.global lemon_crypto_dex_end\nlemon_crypto_dex_end:\n.text\n");

namespace {
enum class Failure { none, loader, constructor, buffer, module, export_missing, initialize, retain };
Failure failure;
bool pending;
int opens, closes, initializations, buffers, objects, deletes;
JNIEnv* current_env;
const auto loader = reinterpret_cast<jobject>(0x123);
const auto buffer = reinterpret_cast<jobject>(0x456);
const auto module = reinterpret_cast<void*>(0x789);
std::string error;
jboolean exception_check(JNIEnv*) { return pending; }
jthrowable exception_occurred(JNIEnv*) { return nullptr; }
void exception_clear(JNIEnv*) { pending = false; }
void exception_describe(JNIEnv*) {}
void delete_local(JNIEnv*, jobject) { ++deletes; }
jclass find_class(JNIEnv*, const char* name) {
    assert(std::strcmp(name, "dalvik/system/InMemoryDexClassLoader") == 0);
    if (failure == Failure::loader) { pending = true; return nullptr; }
    return reinterpret_cast<jclass>(1);
}
jmethodID get_method(JNIEnv*, jclass, const char* name, const char* signature) {
    assert(std::strcmp(name, "<init>") == 0);
    assert(std::strcmp(signature, "(Ljava/nio/ByteBuffer;Ljava/lang/ClassLoader;)V") == 0);
    if (failure == Failure::constructor) { pending = true; return nullptr; }
    return reinterpret_cast<jmethodID>(2);
}
jobject direct_buffer(JNIEnv*, void* address, jlong size) {
    assert(address == lemon::bootstrap::lemon_crypto_dex_start && size == 112);
    ++buffers;
    return failure == Failure::buffer ? nullptr : buffer;
}
jobject new_object(JNIEnv*, jclass, jmethodID, va_list args) {
    assert(va_arg(args, jobject) == buffer);
    assert(va_arg(args, jobject) == nullptr);
    ++objects;
    return loader;
}
jobject global_ref(JNIEnv*, jobject value) {
    assert(value == loader);
    return failure == Failure::retain ? nullptr : value;
}
jint get_env(JavaVM*, void** env, jint version) {
    assert(version == JNI_VERSION_1_6);
    *env = current_env;
    return JNI_OK;
}
jint initialize(JavaVM* vm, jobject value) {
    assert(vm == lemon::bootstrap::java_vm && value == loader);
    ++initializations;
    return failure == Failure::initialize ? JNI_ERR : JNI_VERSION_1_6;
}
void reset(Failure value) {
    failure = value;
    pending = false;
    opens = closes = initializations = buffers = objects = deletes = 0;
    lemon::bootstrap::android_crypto_module = nullptr;
    lemon::bootstrap::android_crypto_loader = nullptr;
    error.clear();
}
}

extern "C" void* __wrap_dlopen(const char*, int flags) {
    assert(flags == (RTLD_NOW | RTLD_LOCAL));
    ++opens;
    return failure == Failure::module ? nullptr : module;
}
extern "C" int __wrap_dlclose(void* handle) { assert(handle == module); ++closes; return 0; }
extern "C" void* __wrap_dlsym(void* handle, const char* name) {
    assert(handle == module);
    if (std::strcmp(name, "AndroidCryptoNative_InitWithClassLoader") == 0)
        return failure == Failure::export_missing ? nullptr : reinterpret_cast<void*>(&initialize);
    assert(std::strcmp(name, "crypto_fixture") == 0);
    return reinterpret_cast<void*>(0x987);
}
namespace lemon::bootstrap {
RuntimePaths runtime_paths;
JavaVM* java_vm;
void log_error(const std::string& message) { error = message; }
}

int main(int argc, char** argv) {
    assert(argc == 2);
    const auto root = std::filesystem::path(argv[1]);
    std::filesystem::create_directories(root);
    std::ofstream(root / "libSystem.Security.Cryptography.Native.Android.so") << "fixture";
    JNINativeInterface table{};
    table.ExceptionCheck = exception_check;
    table.ExceptionOccurred = exception_occurred;
    table.ExceptionClear = exception_clear;
    table.ExceptionDescribe = exception_describe;
    table.FindClass = find_class;
    table.GetMethodID = get_method;
    table.NewDirectByteBuffer = direct_buffer;
    table.NewObjectV = new_object;
    table.NewGlobalRef = global_ref;
    table.DeleteLocalRef = delete_local;
    JNIEnv env{&table};
    current_env = &env;
    JNIInvokeInterface vm_table{};
    vm_table.GetEnv = get_env;
    JavaVM vm{&vm_table};
    lemon::bootstrap::java_vm = &vm;
    using namespace lemon::bootstrap;
    for (auto mode : {Failure::loader, Failure::constructor, Failure::buffer, Failure::module,
                      Failure::export_missing, Failure::initialize, Failure::retain}) {
        reset(mode);
        assert(!initialize_android_crypto(root.string()));
        assert(!android_crypto_module && !pending);
        assert(closes == (mode == Failure::export_missing ? 1 : 0));
        if (mode == Failure::constructor)
            assert(deletes == 1 && buffers == 0 && opens == 0);
    }
    reset(Failure::none);
    assert(initialize_android_crypto(root.string()));
    assert(initialize_android_crypto(root.string()));
    assert(opens == 1 && initializations == 1 && buffers == 1 && objects == 1 && closes == 0);
    assert(android_crypto_loader == loader && android_crypto_module == module);
    assert(resolve_android_crypto_pinvoke("System.Security.Cryptography.Native.Android", "crypto_fixture") == reinterpret_cast<void*>(0x987));
    assert(resolve_android_crypto_pinvoke("unrelated", "crypto_fixture") == nullptr);
    std::cout << "PASS embedded crypto loader, failures, lifetime and exact P/Invoke module reuse\n";
}
