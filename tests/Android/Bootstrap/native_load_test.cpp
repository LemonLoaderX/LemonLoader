#include <cassert>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include "bootstrap.cpp"

namespace {
enum class Failure { none, missing_export, unity_load, environment, environment_jni,
                     extraction, extraction_jni, redirect };
Failure failure = Failure::none;
bool pending = false, throw_unload = false;
int opens = 0, closes = 0, loads = 0, unloads = 0, global_deletes = 0;
int environment_calls = 0, extraction_calls = 0, redirect_calls = 0;
std::string last_error;

jint unity_load(JavaVM*, void*) {
    ++loads;
    return failure == Failure::unity_load ? JNI_ERR : JNI_VERSION_1_6;
}
void unity_unload(JavaVM*, void*) {
    ++unloads;
    if (throw_unload) throw std::runtime_error("unload fixture");
}
jboolean exception_check(JNIEnv*) { return pending; }
jthrowable exception_occurred(JNIEnv*) { return nullptr; }
void exception_clear(JNIEnv*) { pending = false; }
void exception_describe(JNIEnv*) {}
jmethodID missing_method(JNIEnv*, jclass, const char*, const char*) {
    pending = true;
    return nullptr;
}
void delete_global(JNIEnv*, jobject) { ++global_deletes; }
JNIEnv* current_env;

void fail_jni() {
    lemon::bootstrap::required_method(current_env, reinterpret_cast<jclass>(1),
                                      "missingFixture", "()V");
}
void reset(Failure value) {
    using namespace lemon::bootstrap;
    failure = value;
    pending = throw_unload = false;
    opens = closes = loads = unloads = global_deletes = 0;
    environment_calls = extraction_calls = redirect_calls = 0;
    last_error.clear();
    native_load_state = NativeLoadState::not_started;
    unity_handle = nullptr;
    asset_manager = nullptr;
    asset_manager_object = nullptr;
    runtime_paths = RuntimePaths{};
}
}

extern "C" void* __wrap_dlopen(const char*, int) {
    ++opens;
    return reinterpret_cast<void*>(1);
}
extern "C" int __wrap_dlclose(void*) { ++closes; return 0; }
extern "C" void* __wrap_dlsym(void*, const char* name) {
    if (std::strcmp(name, "JNI_OnLoad") == 0)
        return failure == Failure::missing_export ? nullptr : reinterpret_cast<void*>(&unity_load);
    if (std::strcmp(name, "JNI_OnUnload") == 0)
        return reinterpret_cast<void*>(&unity_unload);
    return nullptr;
}
extern "C" int __android_log_write(int, const char*, const char*) { return 0; }

namespace lemon::bootstrap {
void log_line(const std::string&) {}
void log_error(const std::string& message) { last_error = message; }
void reset_latest_log() {}
bool initialize_android_environment(JNIEnv*) {
    ++environment_calls;
    runtime_paths.base_directory = "fixture";
    asset_manager = reinterpret_cast<AAssetManager*>(2);
    asset_manager_object = reinterpret_cast<jobject>(3);
    if (failure == Failure::environment_jni) fail_jni();
    return failure != Failure::environment;
}
bool extract_runtime_assets() {
    ++extraction_calls;
    if (failure == Failure::extraction_jni) fail_jni();
    return failure != Failure::extraction;
}
bool install_symbol_redirect() {
    ++redirect_calls;
    return failure != Failure::redirect;
}
}

int main() {
    using namespace lemon::bootstrap;
    JNINativeInterface functions{};
    functions.ExceptionCheck = exception_check;
    functions.ExceptionOccurred = exception_occurred;
    functions.ExceptionClear = exception_clear;
    functions.ExceptionDescribe = exception_describe;
    functions.GetMethodID = missing_method;
    functions.DeleteGlobalRef = delete_global;
    JNIEnv env{&functions};
    current_env = &env;

    for (Failure mode : {Failure::missing_export, Failure::unity_load,
                         Failure::environment, Failure::extraction, Failure::redirect,
                         Failure::environment_jni, Failure::extraction_jni}) {
        reset(mode);
        assert(native_load(&env, nullptr, nullptr) == JNI_FALSE);
        const bool initialized = mode != Failure::missing_export && mode != Failure::unity_load;
        assert(opens == 1 && closes == 1);
        assert(unloads == (initialized ? 1 : 0));
        assert(global_deletes == (initialized ? 1 : 0));
        assert(!unity_handle && !asset_manager && !asset_manager_object);
        assert(runtime_paths.base_directory.empty() && !pending);
        if (mode == Failure::environment_jni || mode == Failure::extraction_jni)
            assert(last_error.find("missingFixture()V") != std::string::npos);
        assert(native_unload(&env, nullptr) == JNI_FALSE);
        assert(native_load(&env, nullptr, nullptr) == JNI_FALSE);
        assert(opens == 1 && closes == 1); // Failed loads cannot repeat cleanup or acquire another library.
    }
    std::cout << "PASS NativeLoader failure returns and JNI exceptions roll back Unity and retained assets\n";

    reset(Failure::extraction_jni);
    throw_unload = true;
    assert(native_load(&env, nullptr, nullptr) == JNI_FALSE);
    assert(unloads == 1 && closes == 1 && global_deletes == 1);
    assert(!unity_handle && !asset_manager_object && runtime_paths.base_directory.empty());
    assert(last_error.find("missingFixture()V") != std::string::npos);
    std::cout << "PASS throwing Unity unload still closes the library and preserves the original failure\n";

    reset(Failure::none);
    assert(native_load(&env, nullptr, nullptr) == JNI_TRUE);
    assert(native_load(&env, nullptr, nullptr) == JNI_TRUE);
    assert(native_unload(&env, nullptr) == JNI_TRUE);
    assert(opens == 1 && loads == 1 && environment_calls == 1 && extraction_calls == 1 && redirect_calls == 1);
    assert(closes == 0 && unloads == 0 && global_deletes == 0);
    assert(unity_handle && asset_manager && asset_manager_object);
    std::cout << "PASS successful NativeLoader load remains process-scoped and idempotent\n";
}
