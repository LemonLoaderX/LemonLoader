#include "lemon_bootstrap.h"
#include "plthook.h"
#include "state.hpp"

#include <dlfcn.h>
#include <link.h>
#include <sys/mman.h>
#include <unistd.h>

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <iterator>
#include <map>
#include <mutex>
#include <vector>
#include <string>

extern "C" {
int DobbyHook(void* target, void* replacement, void** original);
int DobbyDestroy(void* target);
void dobby_set_near_trampoline_required(bool require);

extern const unsigned char lemon_arm64_return_8[];
extern const unsigned char lemon_arm64_return_8_end[];
extern const unsigned char lemon_arm64_return_8_target[];
extern const unsigned char lemon_arm64_return_16[];
extern const unsigned char lemon_arm64_return_16_end[];
extern const unsigned char lemon_arm64_return_16_target[];
}

namespace lemon::bootstrap {
namespace {

using dlsym_fn = void* (*)(void*, const char*);
using il2cpp_init_fn = void* (*)(const char*);
using il2cpp_runtime_invoke_fn = void* (*)(void*, void*, void**, void**);
using il2cpp_method_get_name_fn = const char* (*)(void*);
using coreclr_error_writer_callback_fn = void (*)(const char*);
using coreclr_initialize_fn = int (*)(
    const char*, const char*, int, const char**, const char**, void**, unsigned int*);
using coreclr_create_delegate_fn = int (*)(
    void*, unsigned int, const char*, const char*, const char*, void**);
using coreclr_shutdown_fn = int (*)(void*, unsigned int);
using coreclr_set_error_writer_fn = int (*)(coreclr_error_writer_callback_fn);
using native_entry_fn = int (*)(void**);
using managed_start_fn = int (*)();

dlsym_fn original_dlsym = nullptr;
il2cpp_init_fn original_il2cpp_init = nullptr;
il2cpp_runtime_invoke_fn original_runtime_invoke = nullptr;
il2cpp_method_get_name_fn method_get_name = nullptr;
managed_start_fn managed_start = nullptr;
void* managed_runtime_module = nullptr;
std::once_flag managed_initialize_once;
std::atomic<bool> managed_started{false};
std::atomic<bool> managed_start_invoked{false};
void coreclr_error(const char* message) {
    log_error(std::string("coreclr: ") + (message == nullptr ? "<null>" : message));
}

std::filesystem::path find_managed_runtime_directory() {
    const std::filesystem::path root =
        std::filesystem::path(runtime_paths.dotnet_directory) / "shared" /
        "Microsoft.NETCore.App";
    std::filesystem::path selected;
    std::error_code error;
    for (const auto& entry : std::filesystem::directory_iterator(root, error)) {
        if (!entry.is_directory()) {
            continue;
        }
        if (selected.empty() || entry.path().filename() > selected.filename()) {
            selected = entry.path();
        }
    }
    return selected;
}

std::filesystem::path find_managed_runtime_engine() {
    return find_managed_runtime_directory() / "libcoreclr.so";
}

std::string build_trusted_platform_assemblies(
    const std::filesystem::path& runtime_directory,
    const std::filesystem::path& managed_directory) {
    std::map<std::string, std::string> assemblies;
    for (const std::filesystem::path& directory : {runtime_directory, managed_directory}) {
        std::error_code error;
        for (const auto& entry : std::filesystem::directory_iterator(directory, error)) {
            if (error) {
                break;
            }
            if (!entry.is_regular_file(error) || error || entry.path().extension() != ".dll") {
                continue;
            }
            assemblies.try_emplace(entry.path().filename().string(), entry.path().string());
        }
        if (error) {
            log_error("Could not enumerate managed assemblies in '" + directory.string() + "'");
            return {};
        }
    }

    std::string result;
    for (const auto& [name, path] : assemblies) {
        static_cast<void>(name);
        if (!result.empty()) {
            result.push_back(':');
        }
        result += path;
    }
    return result;
}

bool load_and_verify_managed_runtime() {
    const std::filesystem::path engine_path = find_managed_runtime_engine();
    managed_runtime_module = dlopen(engine_path.c_str(), RTLD_NOW | RTLD_LOCAL);
    if (managed_runtime_module == nullptr) {
        log_error("Could not acquire the loaded Android managed runtime module");
        return false;
    }

    const bool has_coreclr_host_surface =
        dlsym(managed_runtime_module, "coreclr_initialize") != nullptr &&
        dlsym(managed_runtime_module, "coreclr_create_delegate") != nullptr &&
        dlsym(managed_runtime_module, "coreclr_shutdown") != nullptr;
    const bool has_monovm_identity =
        dlsym(managed_runtime_module, "monovm_initialize") != nullptr ||
        dlsym(managed_runtime_module, "mono_jit_init_version") != nullptr;
    if (!has_coreclr_host_surface || has_monovm_identity) {
        log_error("Loaded managed runtime does not have an unambiguous CoreCLR identity");
        dlclose(managed_runtime_module);
        managed_runtime_module = nullptr;
        return false;
    }

    log_line("Managed runtime backend verified: coreclr");
    return true;
}

void* il2cpp_init_detour(const char* domain_name) {
    void* domain = original_il2cpp_init == nullptr
        ? nullptr
        : original_il2cpp_init(domain_name);
    initialize_managed_runtime();
    return domain;
}

void* runtime_invoke_detour(void* method, void* object, void** arguments, void** exception) {
    void* result = original_runtime_invoke == nullptr
        ? nullptr
        : original_runtime_invoke(method, object, arguments, exception);
    if (managed_started.load()) {
        return result;
    }
    if (method == nullptr || method_get_name == nullptr) {
        return result;
    }

    const char* name = method_get_name(method);
    if (name != nullptr && std::strstr(name, "Internal_ActiveSceneChanged") != nullptr) {
        start_managed_runtime();
    }
    return result;
}

void* dlsym_detour(void* handle, const char* symbol) {
    void* original = original_dlsym == nullptr
        ? nullptr
        : original_dlsym(handle, symbol);
    if (symbol == nullptr) {
        return original;
    }

    if (std::strcmp(symbol, "il2cpp_init") == 0) {
        original_il2cpp_init = reinterpret_cast<il2cpp_init_fn>(original);
        method_get_name = reinterpret_cast<il2cpp_method_get_name_fn>(
            original_dlsym(handle, "il2cpp_method_get_name"));
        return reinterpret_cast<void*>(&il2cpp_init_detour);
    }
    if (std::strcmp(symbol, "il2cpp_runtime_invoke") == 0) {
        original_runtime_invoke = reinterpret_cast<il2cpp_runtime_invoke_fn>(original);
        method_get_name = reinterpret_cast<il2cpp_method_get_name_fn>(
            original_dlsym(handle, "il2cpp_method_get_name"));
        return reinterpret_cast<void*>(&runtime_invoke_detour);
    }
    return original;
}

bool initialize_managed_runtime_impl() {
    if (!prepare_android_runtime()) {
        return false;
    }
    const std::filesystem::path managed_directory =
        std::filesystem::path(runtime_paths.base_directory) / "MelonLoader" / "net6";
    const std::filesystem::path native_host =
        managed_directory / "MelonLoader.NativeHost.dll";

    void* entry_pointer = nullptr;
    coreclr_shutdown_fn shutdown_coreclr = nullptr;
    void* coreclr_host_handle = nullptr;
    unsigned int coreclr_domain_id = 0;
    bool coreclr_initialized = false;
    const auto rollback_coreclr = [&]() {
        if (!coreclr_initialized || shutdown_coreclr == nullptr ||
            coreclr_host_handle == nullptr || coreclr_domain_id == 0) {
            return;
        }
        const int shutdown_status = shutdown_coreclr(
            coreclr_host_handle,
            coreclr_domain_id);
        if (shutdown_status != 0) {
            log_error("coreclr_shutdown failed while rolling back managed startup with status " +
                      std::to_string(shutdown_status));
        }
        coreclr_host_handle = nullptr;
        coreclr_domain_id = 0;
        coreclr_initialized = false;
    };
    const std::filesystem::path runtime_directory = find_managed_runtime_directory();
        if (!initialize_android_crypto(runtime_directory.string())) {
            return false;
        }
        if (!load_and_verify_managed_runtime()) {
            return false;
        }
        auto initialize = reinterpret_cast<coreclr_initialize_fn>(
            dlsym(managed_runtime_module, "coreclr_initialize"));
        auto create_delegate = reinterpret_cast<coreclr_create_delegate_fn>(
            dlsym(managed_runtime_module, "coreclr_create_delegate"));
        auto set_error_writer = reinterpret_cast<coreclr_set_error_writer_fn>(
            dlsym(managed_runtime_module, "coreclr_set_error_writer"));
        shutdown_coreclr = reinterpret_cast<coreclr_shutdown_fn>(
            dlsym(managed_runtime_module, "coreclr_shutdown"));
        if (initialize == nullptr || create_delegate == nullptr || shutdown_coreclr == nullptr) {
            log_error("The selected CoreCLR does not expose its native hosting interface");
            return false;
        }
        if (set_error_writer != nullptr) {
            set_error_writer(&coreclr_error);
        }

        const std::string trusted_platform_assemblies =
            build_trusted_platform_assemblies(runtime_directory, managed_directory);
        const std::string native_search_directories =
            runtime_directory.string() + ':' + managed_directory.string();
        const std::string pinvoke_override = std::to_string(
            reinterpret_cast<uintptr_t>(&resolve_android_crypto_pinvoke));
        if (trusted_platform_assemblies.empty()) {
            return false;
        }
        const char* property_keys[]{
            "TRUSTED_PLATFORM_ASSEMBLIES",
            "APP_PATHS",
            "APP_NI_PATHS",
            "NATIVE_DLL_SEARCH_DIRECTORIES",
            "PLATFORM_RESOURCE_ROOTS",
            "APP_CONTEXT_BASE_DIRECTORY",
            "RUNTIME_IDENTIFIER",
            "System.Globalization.Invariant",
            "System.Globalization.PredefinedCulturesOnly",
            "System.Reflection.Metadata.MetadataUpdater.IsSupported",
            "PINVOKE_OVERRIDE",
        };
        const char* property_values[]{
            trusted_platform_assemblies.c_str(),
            managed_directory.c_str(),
            managed_directory.c_str(),
            native_search_directories.c_str(),
            runtime_directory.c_str(),
            managed_directory.c_str(),
            std::filesystem::is_regular_file(runtime_directory / "libSystem.Security.Cryptography.Native.OpenSsl.so")
                ? "linux-bionic-arm64" : "android-arm64",
            "true",
            "true",
            "false",
            pinvoke_override.c_str(),
        };
        int status = initialize(
            native_host.c_str(),
            "LemonLoader",
            static_cast<int>(std::size(property_keys)),
            property_keys,
            property_values,
            &coreclr_host_handle,
            &coreclr_domain_id);
        if (status < 0 || coreclr_host_handle == nullptr || coreclr_domain_id == 0) {
            char status_hex[11]{};
            std::snprintf(
                status_hex,
                sizeof(status_hex),
                "0x%08X",
                static_cast<uint32_t>(status));
            log_error(
                "coreclr_initialize failed with status " + std::to_string(status) +
                " (" + status_hex + "), host=" +
                (coreclr_host_handle == nullptr ? "null" : "set") +
                ", domain=" + std::to_string(coreclr_domain_id));
            return false;
        }
        coreclr_initialized = true;
        status = create_delegate(
            coreclr_host_handle,
            coreclr_domain_id,
            "MelonLoader.NativeHost",
            "MelonLoader.NativeHost.NativeEntryPoint",
            "CoreClrNativeEntry",
            &entry_pointer);
    if (status != 0 || entry_pointer == nullptr) {
        log_error("coreclr_create_delegate failed with status " + std::to_string(status));
        rollback_coreclr();
        return false;
    }

    void* bootstrap_handle = dlopen("libmain.so", RTLD_NOW | RTLD_NOLOAD);
    if (bootstrap_handle == nullptr) {
        log_error("Could not acquire the NDK bootstrap module handle");
        rollback_coreclr();
        return false;
    }
    auto entry = reinterpret_cast<native_entry_fn>(entry_pointer);
    void* start_pointer = bootstrap_handle;
    const int entry_status = entry(&start_pointer);
    if (entry_status != 0 || start_pointer == nullptr || start_pointer == bootstrap_handle) {
        log_error("Managed NativeHost did not return a start callback");
        // Managed initialization may already have installed native callbacks.
        // Keep CoreCLR alive rather than invalidating partially published pointers.
        return false;
    }
    managed_start = reinterpret_cast<managed_start_fn>(start_pointer);

    return true;
}

}  // namespace

bool install_symbol_redirect() {
    if (unity_handle == nullptr) {
        return false;
    }
    original_dlsym = reinterpret_cast<dlsym_fn>(dlsym(RTLD_DEFAULT, "dlsym"));
    void* unity_on_load = dlsym(unity_handle, "JNI_OnLoad");
    if (original_dlsym == nullptr || unity_on_load == nullptr) {
        log_error("Could not resolve dlsym or Unity JNI_OnLoad for PLT redirection");
        return false;
    }

    plthook_t* handle = nullptr;
    int status = plthook_open_by_address(&handle, unity_on_load);
    if (status != 0) {
        status = plthook_open_by_handle(&handle, unity_handle);
    }
    if (status != 0 || handle == nullptr) {
        log_error(std::string("plthook_open failed: ") + plthook_error());
        return false;
    }
    status = plthook_replace(
        handle,
        "dlsym",
        reinterpret_cast<void*>(&dlsym_detour),
        nullptr);
    plthook_close(handle);
    if (status != 0) {
        log_error(std::string("plthook_replace(dlsym) failed: ") + plthook_error());
        return false;
    }
    return true;
}

bool initialize_managed_runtime() {
    bool initialized = false;
    std::call_once(managed_initialize_once, [&initialized]() {
        initialized = initialize_managed_runtime_impl();
    });
    return managed_start != nullptr || initialized;
}

void start_managed_runtime() {
    if (managed_start == nullptr || managed_start_invoked.exchange(true)) {
        return;
    }
    const int status = managed_start();
    if (status != 0) {
        log_error("Managed MelonLoader start failed with status " + std::to_string(status));
        return;
    }
    managed_started.store(true, std::memory_order_release);
}

}  // namespace lemon::bootstrap

using namespace lemon::bootstrap;

extern "C" LEMON_EXPORT void LogManagedException(
    const char* message,
    int32_t message_length) {
    if (message == nullptr || message_length <= 0) {
        return;
    }
    log_error(std::string(message, static_cast<size_t>(message_length)));
}

extern "C" LEMON_EXPORT void NativeHookAttach(void** target, void* detour) {
    if (target == nullptr || *target == nullptr || detour == nullptr) {
        return;
    }
    // Keep the near-relay allocator alive for the lifetime of all installed hooks.
    static std::once_flag near_branch_trampoline_once;
    std::call_once(near_branch_trampoline_once, []() {
        dobby_set_near_trampoline_required(true);
    });
    void* const hook_target = *target;
    void* original = nullptr;
    const int status = DobbyHook(hook_target, detour, &original);
    if (status == 0) {
        *target = original;
    } else {
        log_error("DobbyHook failed with status " + std::to_string(status));
        *target = nullptr;
    }
}

extern "C" LEMON_EXPORT void NativeHookDetach(void** target, void*) {
    if (target != nullptr && *target != nullptr) {
        const int status = DobbyDestroy(*target);
        if (status != 0) {
            log_error("DobbyDestroy failed with status " + std::to_string(status));
        }
    }
}

extern "C" LEMON_EXPORT void* CreateArm64ValueReturnAdapter(void* target, uint32_t value_size) {
    if (target == nullptr) {
        return nullptr;
    }

    const unsigned char* begin = nullptr;
    const unsigned char* end = nullptr;
    const unsigned char* target_slot = nullptr;
    switch (value_size) {
        case 1:
        case 2:
        case 3:
        case 4:
        case 5:
        case 6:
        case 7:
        case 8:
            begin = lemon_arm64_return_8;
            end = lemon_arm64_return_8_end;
            target_slot = lemon_arm64_return_8_target;
            break;
        case 9:
        case 10:
        case 11:
        case 12:
        case 13:
        case 14:
        case 15:
        case 16:
            begin = lemon_arm64_return_16;
            end = lemon_arm64_return_16_end;
            target_slot = lemon_arm64_return_16_target;
            break;
        default:
            return nullptr;
    }

    const size_t code_size = static_cast<size_t>(end - begin);
    const size_t target_offset = static_cast<size_t>(target_slot - begin);
    const long page_size_value = sysconf(_SC_PAGESIZE);
    if (page_size_value <= 0 || target_offset + sizeof(target) > code_size) {
        return nullptr;
    }
    const size_t page_size = static_cast<size_t>(page_size_value);
    const size_t allocation_size = (code_size + page_size - 1) & ~(page_size - 1);
    void* adapter = mmap(
        nullptr,
        allocation_size,
        PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS,
        -1,
        0);
    if (adapter == MAP_FAILED) {
        return nullptr;
    }

    std::memcpy(adapter, begin, code_size);
    std::memcpy(static_cast<unsigned char*>(adapter) + target_offset, &target, sizeof(target));
    __builtin___clear_cache(
        static_cast<char*>(adapter),
        static_cast<char*>(adapter) + code_size);
    if (mprotect(adapter, allocation_size, PROT_READ | PROT_EXEC) != 0) {
        munmap(adapter, allocation_size);
        return nullptr;
    }
    return adapter;
}

extern "C" LEMON_EXPORT void DestroyArm64ValueReturnAdapter(void* adapter) {
    if (adapter == nullptr) {
        return;
    }
    const long page_size_value = sysconf(_SC_PAGESIZE);
    if (page_size_value > 0) {
        munmap(adapter, static_cast<size_t>(page_size_value));
    }
}
