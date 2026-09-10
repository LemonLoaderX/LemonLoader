#include <sys/mman.h>
#include <unistd.h>
#include <cassert>
#include <iostream>
#include <filesystem>
#include "runtime.cpp"
#include "arm64_il2cpp_resolver.cpp"
#include "android_crypto.cpp"
#include "asset_file.hpp"
#include "jni_utils.hpp"
#include "process_lock.hpp"
#include <sys/wait.h>

static std::string last_error;
static bool fail_logger = false;
static int emergency_logs = 0;
static int hook_status = 0, destroy_calls = 0;
static bool throw_destroy = false;
extern "C" int DobbyHook(void*, void*, void** original) { *original = reinterpret_cast<void*>(0x7890); return hook_status; }
extern "C" int DobbyDestroy(void*) {
    ++destroy_calls;
    if (throw_destroy) throw std::runtime_error("destroy fixture");
    return hook_status;
}
extern "C" void dobby_set_near_trampoline_required(bool) {}
extern "C" int __android_log_write(int, const char*, const char*) { ++emergency_logs; return 0; }
namespace lemon::bootstrap {
RuntimePaths runtime_paths;
JavaVM* java_vm = nullptr;
void* unity_handle = nullptr;
void log_line(const std::string&) {}
void log_error(const std::string& message) {
    if (fail_logger) throw std::bad_alloc();
    last_error = message;
}
}
static std::string asset_data = "small buffered asset";
static size_t asset_position = 0;
static bool fail_read = false, truncate_read = false;
static int closed_assets = 0;
static AAsset asset;
AAsset* AAssetManager_open(AAssetManager*, const char*, int) { asset_position = 0; return &asset; }
int64_t AAsset_getLength64(AAsset*) { return asset_data.size(); }
int AAsset_read(AAsset*, void* target, size_t length) {
    if (fail_read) return -1;
    if (truncate_read) return 0;
    size_t count = std::min(length, asset_data.size() - asset_position);
    std::memcpy(target, asset_data.data() + asset_position, count);
    asset_position += count;
    return static_cast<int>(count);
}
void AAsset_close(AAsset*) { ++closed_assets; }

static bool pending = false;
static int deletes = 0, releases = 0, method_calls = 0;
static int descriptions = 0;
static bool describe_clears = true, fail_description = true;
static std::u16string java_text(u"path/\U0001f600\0end", 11);
static jboolean exception_check(JNIEnv*) { return pending; }
static jthrowable exception_occurred(JNIEnv*) { return reinterpret_cast<jthrowable>(1); }
static void exception_clear(JNIEnv*) { pending = false; }
static void exception_describe(JNIEnv*) {
    assert(pending); // Must describe the original exception before ExceptionClear.
    ++descriptions;
    if (describe_clears) pending = false;
}
static jclass object_class(JNIEnv*, jobject) { return reinterpret_cast<jclass>(2); }
static jmethodID method_id(JNIEnv*, jclass, const char* name, const char*) {
    assert(!pending);
    if (!fail_description && std::string(name) == "toString") return reinterpret_cast<jmethodID>(4);
    pending = true; return nullptr;
}
static void delete_local(JNIEnv*, jobject) { ++deletes; }
static jsize string_length(JNIEnv*, jstring) { return java_text.size(); }
static const jchar* string_chars(JNIEnv*, jstring, jboolean*) { return reinterpret_cast<const jchar*>(java_text.data()); }
static void release_chars(JNIEnv*, jstring, const jchar*) { ++releases; }
static jstring new_string(JNIEnv*, const jchar* text, jsize size) {
    java_text.assign(reinterpret_cast<const char16_t*>(text), size);
    return reinterpret_cast<jstring>(3);
}
static jobject object_call(JNIEnv*, jobject, jmethodID, va_list) {
    assert(!pending);
    ++method_calls;
    return reinterpret_cast<jstring>(3);
}
static JNIEnv* current_env = nullptr;
static jint get_env(JavaVM*, void** result, jint) { *result = current_env; return JNI_OK; }
static jclass find_class(JNIEnv*, const char*) { pending = true; return nullptr; }

int main(int argc, char** argv) {
    assert(argc == 2);
    using namespace lemon::bootstrap;
    const std::filesystem::path fixture(argv[1]);
    const auto lock_path = fixture / "runtime.lock";
    {
        ProcessLock owner;
        std::error_code error;
        assert(owner.acquire(lock_path, error));
        pid_t child = fork();
        assert(child >= 0);
        if (child == 0) {
            ProcessLock contender;
            _exit(!contender.acquire(lock_path, error) && error == std::errc::operation_would_block ? 0 : 1);
        }
        int status;
        assert(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    }
    {
        ProcessLock next;
        std::error_code error;
        assert(next.acquire(lock_path, error));
    }
    std::cout << "PASS cross-process runtime exclusion and lock release\n";
    const size_t page = sysconf(_SC_PAGESIZE);
    auto* memory = static_cast<char*>(mmap(nullptr, page * 3, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0));
    assert(memory != MAP_FAILED);
    assert(mprotect(memory + page, page, PROT_READ | PROT_WRITE) == 0);
    uintptr_t begin = reinterpret_cast<uintptr_t>(memory + page);
    il2cpp_code.ranges = {{begin, begin + page}};
    *reinterpret_cast<uint32_t*>(begin + 4) = arm64_ret;
    assert(find_three_argument_wrapper(begin + 8) == 0);
    assert(!is_executable(begin + page - 2));
    assert(!is_executable(begin - 4));
    uint32_t ignored;
    assert(!read_instruction(begin + page, ignored));
    // One valid wrapper, then two valid wrappers targeting the same core.
    auto* code = reinterpret_cast<uint32_t*>(begin);
    code[0] = arm64_ret; code[1] = 0x94000007; code[2] = arm64_ret; code[7] = arm64_ret;
    assert(find_three_argument_wrapper(begin + 32) == begin + 4);
    code[3] = 0x94000005; code[4] = arm64_ret;
    assert(find_three_argument_wrapper(begin + 32) == 0);
    // The known MethodInfo overload must not make the adjacent requested
    // overload look ambiguous. Unknown competing wrappers still fail above.
    assert(find_three_argument_wrapper(begin + 32, begin + 4) == begin + 12);
    munmap(memory, page * 3);
    std::cout << "PASS resolver guarded pages, short ranges and ambiguous wrappers\n";

    runtime_paths.dotnet_directory = (fixture / "runtime").string();
    auto versions = std::filesystem::path(runtime_paths.dotnet_directory) / "shared/Microsoft.NETCore.App";
    std::filesystem::create_directories(versions);
    std::filesystem::create_symlink("loop", versions / "loop");
    assert(find_managed_runtime_directory().empty());
    assert(last_error.find("Could not enumerate") != std::string::npos);
    std::filesystem::remove(versions / "loop");
    std::filesystem::create_directory(versions / "11.0");
    assert(find_managed_runtime_directory() == versions / "11.0");
    std::filesystem::create_directory(versions / "10.0");
    assert(find_managed_runtime_directory().empty());
    assert(last_error.find("Multiple") != std::string::npos);
    assert(!native_boundary("fixture", false, []() -> bool { throw std::runtime_error("detail"); }));
    assert(last_error == "fixture: detail");
    fail_logger = true;
    native_boundary("fixture", []() { throw std::bad_alloc(); });
    fail_logger = false;
    assert(emergency_logs == 1);
    std::cout << "PASS filesystem diagnostics and native exception fallback\n";

    void* const address = reinterpret_cast<void*>(0x1234);
    void* const detour = reinterpret_cast<void*>(0x5678);
    void* target = address;
    NativeHookDetach(&target, detour);
    assert(target == address && destroy_calls == 1);
    assert(TryNativeHookDetach(&target, detour) == 1 && target == address);
    hook_status = -1;
    NativeHookDetach(&target, detour);
    assert(target == address && last_error.find("target=0x1234, detour=0x5678") != std::string::npos);
    assert(TryNativeHookDetach(&target, detour) == 0 && target == address);
    NativeHookAttach(&target, detour);
    assert(target == nullptr && last_error.find("DobbyHook failed with status -1") != std::string::npos);
    assert(last_error.find("target=0x1234, detour=0x5678") != std::string::npos);
    target = address;
    throw_destroy = true;
    assert(TryNativeHookDetach(&target, detour) == 0 && target == address);
    assert(last_error.find("destroy fixture") != std::string::npos);
    throw_destroy = false;
    const int calls = destroy_calls;
    assert(TryNativeHookDetach(nullptr, detour) == 0);
    target = nullptr;
    assert(TryNativeHookDetach(&target, detour) == 0 && destroy_calls == calls);
    hook_status = 0;
    std::cout << "PASS legacy detach pointer contract, checked result and failure context\n";

    std::string failure;
    AAssetManager manager;
    assert(extract_asset_file(&manager, "fixture", fixture / "asset", failure));
    assert(std::filesystem::file_size(fixture / "asset") == asset_data.size());
    assert(!extract_asset_file(&manager, "fixture", "/dev/full", failure));
    assert(failure.find("write/close") != std::string::npos);
    fail_read = true;
    assert(!extract_asset_file(&manager, "fixture", fixture / "asset", failure));
    assert(failure.find("read APK") != std::string::npos);
    fail_read = false; truncate_read = true;
    assert(!extract_asset_file(&manager, "fixture", fixture / "asset", failure));
    assert(failure.find("incomplete") != std::string::npos && closed_assets == 4);
    std::cout << "PASS asset flush failure, read failure, truncation and close\n";

    JNINativeInterface functions{};
    functions.ExceptionCheck = exception_check; functions.ExceptionOccurred = exception_occurred;
    functions.ExceptionClear = exception_clear; functions.GetObjectClass = object_class;
    functions.ExceptionDescribe = exception_describe;
    functions.GetMethodID = method_id; functions.GetStaticMethodID = method_id;
    functions.DeleteLocalRef = delete_local; functions.GetStringLength = string_length;
    functions.GetStringChars = string_chars; functions.ReleaseStringChars = release_chars;
    functions.NewString = new_string; functions.CallObjectMethodV = object_call;
    functions.FindClass = find_class;
    JNIEnv env{&functions};
    current_env = &env;
    JNIInvokeInterface vm_functions{};
    vm_functions.GetEnv = get_env;
    JavaVM vm{&vm_functions};
    java_vm = &vm;
    const auto text = java_string(&env, reinterpret_cast<jstring>(3));
    assert(utf8_to_utf16(text) == java_text && releases == 1);
    new_java_string(&env, text);
    assert(java_string(&env, reinterpret_cast<jstring>(3)) == text);
    assert(!native_boundary("lookup", false, [&]() {
        required_method(&env, reinterpret_cast<jclass>(2), "absent", "()V"); return true;
    }));
    assert(!pending && method_calls == 0 && deletes == 2 && descriptions == 1);
    assert(last_error.find("absent()V") != std::string::npos);
    // Even if toString fails, the original stack was described and all exceptions cleared.
    pending = true;
    assert(clear_java_exception(&env, "failed summary"));
    assert(descriptions == 2 && !pending && deletes == 4);
    assert(last_error.find("failed summary (Java exception details unavailable)") != std::string::npos);
    fail_description = false;
    describe_clears = false;
    pending = true;
    assert(clear_java_exception(&env, "read fixture"));
    assert(descriptions == 3 && !pending && deletes == 7 && method_calls == 1);
    assert(last_error == "JNI failure during read fixture: " + text);
    assert(!clear_java_exception(&env, "no exception") && descriptions == 3);
    assert(utf16_ordinal_less("\xf0\x9f\x98\x80", "\xee\x80\x80"));
    const uint16_t unpaired[] = {0xd800};
    assert(utf16_to_utf8(unpaired, 1) == "\xef\xbf\xbd");
    for (const auto invalid : {"\xc0\x80", "\xed\xa0\x80", "\xf4\x90\x80\x80", "\xe2\x82"}) {
        bool rejected = false;
        try { utf8_to_utf16(invalid); } catch (const std::invalid_argument&) { rejected = true; }
        assert(rejected);
    }
    std::cout << "PASS JNI missing methods, exception cleanup, UTF-16 and ordinal ordering\n";
    const auto crypto_root = fixture / "crypto";
    std::filesystem::create_directory(crypto_root);
    std::ofstream(crypto_root / "libSystem.Security.Cryptography.Native.Android.so").put('x');
    assert(!initialize_android_crypto(crypto_root.string()));
    assert(!pending && last_error.find("APK helper DEX") != std::string::npos);
    std::cout << "PASS missing crypto bridge clears Java exception and reports recovery context\n";
}
