#include "lemon_bootstrap.h"
#include "state.hpp"

#include <dlfcn.h>
#include <link.h>

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace lemon::bootstrap {
namespace {

enum class injection_target : uint32_t {
    generic_method_get_method_three_argument = 1,
    metadata_get_type_info_from_type_definition_index = 2,
    class_from_il2cpp_type = 3,
    class_from_name = 4,
    class_get_default_field_value = 5,
    class_init = 6,
    generic_method_get_method_legacy = 7,
};

enum class generic_method_abi {
    legacy,
    three_argument,
};

struct executable_range {
    uintptr_t begin = 0;
    uintptr_t end = 0;
};

struct module_code {
    void* handle = nullptr;
    std::vector<executable_range> ranges;
};

struct scan_result {
    std::vector<uintptr_t> calls;
    std::vector<uintptr_t> transfers;
};

struct unity_version {
    uint32_t major;
    uint32_t minor;
    uint32_t build;
};

constexpr size_t instruction_size = sizeof(uint32_t);
constexpr size_t max_function_scan = 4096;
constexpr intptr_t local_branch_limit = 256;
constexpr uint32_t arm64_ret = 0xd65f03c0U;
constexpr uint32_t arm64_branch_mask = 0xfc000000U;
constexpr uint32_t arm64_branch = 0x14000000U;
constexpr uint32_t arm64_branch_link = 0x94000000U;

std::once_flag module_once;
bool module_ready = false;
std::array<std::once_flag, 8> target_once{};
module_code il2cpp_code;
std::array<void*, 8> resolved_targets{};

intptr_t sign_extend_28(uint32_t value) {
    return static_cast<intptr_t>(static_cast<int32_t>(value << 4) >> 4);
}

bool decode_direct_branch(uintptr_t address, uint32_t instruction, uintptr_t& target, bool& link) {
    const uint32_t opcode = instruction & arm64_branch_mask;
    if (opcode != arm64_branch && opcode != arm64_branch_link) {
        return false;
    }

    const uint32_t encoded_offset = (instruction & 0x03ffffffU) << 2;
    target = static_cast<uintptr_t>(static_cast<intptr_t>(address) + sign_extend_28(encoded_offset));
    link = opcode == arm64_branch_link;
    return true;
}

bool is_executable(uintptr_t address) {
    for (const auto& range : il2cpp_code.ranges) {
        if (address >= range.begin && address < range.end) {
            return true;
        }
    }
    return false;
}

int collect_il2cpp_segments(dl_phdr_info* info, size_t, void*) {
    if (info == nullptr || info->dlpi_name == nullptr ||
        std::strstr(info->dlpi_name, "libil2cpp.so") == nullptr) {
        return 0;
    }

    for (ElfW(Half) index = 0; index < info->dlpi_phnum; ++index) {
        const ElfW(Phdr)& header = info->dlpi_phdr[index];
        if (header.p_type != PT_LOAD || (header.p_flags & PF_X) == 0) {
            continue;
        }
        const uintptr_t begin = static_cast<uintptr_t>(info->dlpi_addr + header.p_vaddr);
        il2cpp_code.ranges.push_back({begin, begin + static_cast<uintptr_t>(header.p_memsz)});
    }
    return il2cpp_code.ranges.empty() ? 0 : 1;
}

bool initialize_module() {
    il2cpp_code.handle = dlopen("libil2cpp.so", RTLD_NOW | RTLD_NOLOAD);
    if (il2cpp_code.handle == nullptr) {
        il2cpp_code.handle = dlopen("libil2cpp.so", RTLD_NOW | RTLD_LOCAL);
    }
    if (il2cpp_code.handle == nullptr) {
        log_error("ARM64 IL2CPP resolver could not acquire libil2cpp.so");
        return false;
    }
    dl_iterate_phdr(&collect_il2cpp_segments, nullptr);
    if (il2cpp_code.ranges.empty()) {
        log_error("ARM64 IL2CPP resolver could not find an executable libil2cpp segment");
        return false;
    }
    return true;
}

uintptr_t get_export(const char* name) {
    void* address = dlsym(il2cpp_code.handle, name);
    const uintptr_t result = reinterpret_cast<uintptr_t>(address);
    return is_executable(result) ? result : 0;
}

scan_result scan_function(
    uintptr_t start,
    bool ignore_return = false,
    size_t transfer_limit = 0) {
    scan_result result;
    if (!is_executable(start)) {
        return result;
    }

    for (size_t offset = 0; offset < max_function_scan; offset += instruction_size) {
        const uintptr_t address = start + offset;
        if (!is_executable(address)) {
            break;
        }

        uint32_t instruction = 0;
        std::memcpy(&instruction, reinterpret_cast<const void*>(address), sizeof(instruction));
        if (instruction == arm64_ret && !ignore_return) {
            break;
        }

        uintptr_t target = 0;
        bool link = false;
        if (!decode_direct_branch(address, instruction, target, link) || !is_executable(target)) {
            continue;
        }

        result.transfers.push_back(target);
        if (link) {
            result.calls.push_back(target);
        }
        if (transfer_limit != 0 && result.transfers.size() >= transfer_limit) {
            break;
        }
        if (link) {
            continue;
        }

        const intptr_t distance = static_cast<intptr_t>(target) - static_cast<intptr_t>(address);
        if (distance < -local_branch_limit || distance > local_branch_limit) {
            break;
        }
    }
    return result;
}

uintptr_t first_branch_target(uintptr_t start, size_t instruction_limit = 4) {
    for (size_t index = 0; index < instruction_limit; ++index) {
        const uintptr_t address = start + index * instruction_size;
        if (!is_executable(address)) {
            return 0;
        }
        uint32_t instruction = 0;
        std::memcpy(&instruction, reinterpret_cast<const void*>(address), sizeof(instruction));
        uintptr_t target = 0;
        bool link = false;
        if (decode_direct_branch(address, instruction, target, link) && !link && is_executable(target)) {
            return target;
        }
        if (instruction == arm64_ret) {
            return 0;
        }
    }
    return 0;
}

uintptr_t resolve_export_body(const char* export_name) {
    const uintptr_t api = get_export(export_name);
    return api == 0 ? 0 : first_branch_target(api);
}

uintptr_t find_three_argument_wrapper(uintptr_t core) {
    if (core < 8 || !is_executable(core - instruction_size)) {
        return 0;
    }

    uint32_t instruction = 0;
    std::memcpy(&instruction, reinterpret_cast<const void*>(core - instruction_size), sizeof(instruction));
    if (instruction != arm64_ret) {
        return 0;
    }

    for (size_t distance = 8; distance <= 128; distance += instruction_size) {
        const uintptr_t boundary = core - distance;
        std::memcpy(&instruction, reinterpret_cast<const void*>(boundary), sizeof(instruction));
        if (instruction != arm64_ret) {
            continue;
        }

        const uintptr_t candidate = boundary + instruction_size;
        const scan_result scan = scan_function(candidate);
        if (scan.calls.size() == 1 && scan.calls.front() == core && candidate < core) {
            return candidate;
        }
    }
    return 0;
}

bool has_legacy_generic_method_shim(const unity_version& version) {
    return version.major > 2020 ||
        (version.major == 2020 &&
            (version.minor > 3 || (version.minor == 3 && version.build >= 41)));
}

uintptr_t resolve_generic_method_get_method(
    generic_method_abi abi,
    const unity_version& version) {
    const uintptr_t body = resolve_export_body("il2cpp_object_get_virtual_method");
    if (body == 0) {
        return 0;
    }

    scan_result virtual_method = scan_function(body);
    if (virtual_method.transfers.empty() && abi == generic_method_abi::legacy) {
        virtual_method = scan_function(body, true);
    }
    if (virtual_method.transfers.empty()) {
        return 0;
    }

    const uintptr_t candidate = virtual_method.transfers.back();
    const scan_result candidate_scan = scan_function(candidate);
    if (abi == generic_method_abi::legacy) {
        if (!has_legacy_generic_method_shim(version)) {
            return candidate;
        }

        scan_result shim_scan = candidate_scan;
        if (version.major == 2020 && shim_scan.transfers.size() == 1) {
            shim_scan = scan_function(candidate, true, 2);
        }
        if (shim_scan.transfers.empty()) {
            return 0;
        }
        return shim_scan.transfers[shim_scan.transfers.size() > 1 ? 1 : 0];
    }
    return candidate_scan.calls.size() == 1
        ? find_three_argument_wrapper(candidate_scan.calls.front())
        : 0;
}

uintptr_t resolve_metadata_get_type_info() {
    const uintptr_t image_get_type = resolve_export_body("il2cpp_image_get_class");
    if (image_get_type == 0) {
        return 0;
    }
    const scan_result image_scan = scan_function(image_get_type);
    if (image_scan.transfers.empty()) {
        return 0;
    }

    uintptr_t candidate = image_scan.transfers.back();
    for (size_t depth = 0; depth < 8; ++depth) {
        const scan_result scan = scan_function(candidate);
        if (scan.transfers.size() != 1) {
            return candidate;
        }
        candidate = scan.transfers.front();
    }
    return 0;
}

uintptr_t resolve_get_default_field_value() {
    const uintptr_t field_get_value_object = resolve_export_body("il2cpp_field_get_value_object");
    if (field_get_value_object == 0) {
        return 0;
    }

    const scan_result outer = scan_function(field_get_value_object);
    for (const uintptr_t helper : outer.calls) {
        const scan_result helper_scan = scan_function(helper);
        if (helper_scan.calls.size() != 2) {
            continue;
        }
        const uintptr_t getter_thunk = helper_scan.calls.front();
        if (first_branch_target(getter_thunk, 1) != 0) {
            return getter_thunk;
        }
    }
    return 0;
}

uintptr_t resolve_class_init() {
    const uintptr_t array_new_specific = resolve_export_body("il2cpp_array_new_specific");
    if (array_new_specific == 0) {
        return 0;
    }

    const scan_result scan = scan_function(array_new_specific);
    return scan.calls.empty() ? 0 : scan.calls.front();
}

uintptr_t resolve_target(injection_target target, const unity_version& version) {
    switch (target) {
        case injection_target::generic_method_get_method_three_argument:
            return resolve_generic_method_get_method(generic_method_abi::three_argument, version);
        case injection_target::metadata_get_type_info_from_type_definition_index:
            return resolve_metadata_get_type_info();
        case injection_target::class_from_il2cpp_type:
            return resolve_export_body("il2cpp_class_from_il2cpp_type");
        case injection_target::class_from_name:
            return resolve_export_body("il2cpp_class_from_name");
        case injection_target::class_get_default_field_value:
            return resolve_get_default_field_value();
        case injection_target::class_init:
            return resolve_class_init();
        case injection_target::generic_method_get_method_legacy:
            return resolve_generic_method_get_method(generic_method_abi::legacy, version);
    }
    return 0;
}

const char* target_name(injection_target target) {
    switch (target) {
        case injection_target::generic_method_get_method_three_argument:
            return "GenericMethod::GetMethod(three-argument)";
        case injection_target::metadata_get_type_info_from_type_definition_index:
            return "MetadataCache::GetTypeInfoFromTypeDefinitionIndex";
        case injection_target::class_from_il2cpp_type:
            return "Class::FromIl2CppType";
        case injection_target::class_from_name:
            return "Class::FromName";
        case injection_target::class_get_default_field_value:
            return "Class::GetDefaultFieldValue";
        case injection_target::class_init:
            return "Class::Init";
        case injection_target::generic_method_get_method_legacy:
            return "GenericMethod::GetMethod(legacy)";
    }
    return "unknown";
}

bool ensure_module_initialized() {
    std::call_once(module_once, []() {
        module_ready = initialize_module();
    });
    return module_ready;
}

void initialize_target(uint32_t value, const unity_version& version) {
    if (!ensure_module_initialized()) {
        return;
    }

    const auto target = static_cast<injection_target>(value);
    const uintptr_t address = resolve_target(target, version);
    resolved_targets[value] = reinterpret_cast<void*>(address);
    if (address == 0) {
        log_error(std::string("ARM64 IL2CPP resolver could not resolve ") + target_name(target));
    }
}

}  // namespace
}  // namespace lemon::bootstrap

extern "C" LEMON_EXPORT void* ResolveArm64Il2CppInjectionTarget(
    uint32_t target,
    uint32_t unity_major,
    uint32_t unity_minor,
    uint32_t unity_build) {
    using namespace lemon::bootstrap;
    if (target == 0 || target >= resolved_targets.size()) {
        return nullptr;
    }
    const unity_version version{unity_major, unity_minor, unity_build};
    std::call_once(target_once[target], [target, version]() {
        initialize_target(target, version);
    });
    return resolved_targets[target];
}
