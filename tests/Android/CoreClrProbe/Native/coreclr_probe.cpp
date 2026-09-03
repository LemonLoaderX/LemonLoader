#include <dlfcn.h>
#include <unistd.h>

#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <filesystem>
#include <iterator>
#include <map>
#include <string>
#include <vector>

namespace {

using coreclr_initialize_fn = int (*)(
    const char*, const char*, int, const char**, const char**, void**, unsigned int*);
using coreclr_create_delegate_fn = int (*)(
    void*, unsigned int, const char*, const char*, const char*, void**);
using coreclr_shutdown_fn = int (*)(void*, unsigned int);
using managed_probe_fn = int (*)(void*);

void fail(const std::string& message) {
    std::fprintf(stderr, "CORECLR_NATIVE_HOST_FAIL %s\n", message.c_str());
}

std::string join_paths(const std::vector<std::string>& paths) {
    std::string result;
    for (const std::string& path : paths) {
        if (!result.empty()) {
            result.push_back(':');
        }
        result += path;
    }
    return result;
}

std::string build_tpa_list(
    const std::filesystem::path& runtime_directory,
    const std::filesystem::path& probe_directory) {
    std::map<std::string, std::string> assemblies;
    for (const std::filesystem::path& directory : {runtime_directory, probe_directory}) {
        std::error_code error;
        for (const auto& entry : std::filesystem::directory_iterator(directory, error)) {
            if (error || !entry.is_regular_file() || entry.path().extension() != ".dll") {
                continue;
            }
            assemblies.try_emplace(entry.path().filename().string(), entry.path().string());
        }
        if (error) {
            return {};
        }
    }

    std::vector<std::string> paths;
    paths.reserve(assemblies.size());
    for (const auto& [name, path] : assemblies) {
        static_cast<void>(name);
        paths.push_back(path);
    }
    return join_paths(paths);
}

}  // namespace

int main(int argc, char** argv) {
    if (argc != 4) {
        fail("usage: coreclr_probe <dotnet-root> <probe-directory> <runtime-version>");
        return 2;
    }

    const std::string dotnet_root = argv[1];
    const std::string probe_directory = argv[2];
    const std::string runtime_version = argv[3];
    const std::string runtime_directory =
        dotnet_root + "/shared/Microsoft.NETCore.App/" + runtime_version;
    const std::string coreclr_path = runtime_directory + "/libcoreclr.so";
    const std::string assembly_path =
        probe_directory + "/LemonLoader.CoreClrProbe.dll";
    const std::string tpa_list = build_tpa_list(runtime_directory, probe_directory);
    const std::string native_search = runtime_directory + ":" + probe_directory;
    if (tpa_list.empty()) {
        fail("could not build the trusted platform assembly list");
        return 1;
    }

    setenv("DOTNET_ROOT", dotnet_root.c_str(), 1);
    setenv("DOTNET_MULTILEVEL_LOOKUP", "0", 1);
    using mallopt_fn = int (*)(int, int);
    auto mallopt_value = reinterpret_cast<mallopt_fn>(dlsym(RTLD_DEFAULT, "mallopt"));
    if (mallopt_value != nullptr) {
        mallopt_value(-204, 0);
    }

    void* coreclr = dlopen(coreclr_path.c_str(), RTLD_NOW | RTLD_LOCAL);
    if (coreclr == nullptr) {
        fail(std::string("dlopen coreclr: ") + dlerror());
        return 1;
    }
    std::fprintf(stderr, "CORECLR_NATIVE_STAGE coreclr-loaded\n");
    auto initialize = reinterpret_cast<coreclr_initialize_fn>(
        dlsym(coreclr, "coreclr_initialize"));
    auto create_delegate = reinterpret_cast<coreclr_create_delegate_fn>(
        dlsym(coreclr, "coreclr_create_delegate"));
    auto shutdown = reinterpret_cast<coreclr_shutdown_fn>(
        dlsym(coreclr, "coreclr_shutdown"));
    if (initialize == nullptr || create_delegate == nullptr || shutdown == nullptr) {
        fail("CoreCLR hosting exports are missing");
        return 1;
    }

    const char* property_keys[] = {
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
    };
    const char* property_values[] = {
        tpa_list.c_str(),
        probe_directory.c_str(),
        probe_directory.c_str(),
        native_search.c_str(),
        runtime_directory.c_str(),
        probe_directory.c_str(),
        "android-arm64",
        "true",
        "true",
        "false",
    };
    void* host_handle = nullptr;
    unsigned int domain_id = 0;
    int status = initialize(
        assembly_path.c_str(),
        "LemonLoader.CoreClrProbe",
        static_cast<int>(std::size(property_keys)),
        property_keys,
        property_values,
        &host_handle,
        &domain_id);
    if (status < 0 || host_handle == nullptr || domain_id == 0) {
        fail("coreclr initialization status " + std::to_string(status));
        return 1;
    }
    std::fprintf(stderr, "CORECLR_NATIVE_STAGE runtime-initialized\n");

    void* entry_pointer = nullptr;
    status = create_delegate(
        host_handle,
        domain_id,
        "LemonLoader.CoreClrProbe",
        "LemonLoader.CoreClrProbe.EntryPoint",
        "RunDirect",
        &entry_pointer);
    if (status != 0 || entry_pointer == nullptr) {
        shutdown(host_handle, domain_id);
        fail("coreclr delegate status " + std::to_string(status));
        return 1;
    }
    std::fprintf(stderr, "CORECLR_NATIVE_STAGE entry-loaded=%p\n", entry_pointer);

    int native_marker = 42;
    const int probe_status = reinterpret_cast<managed_probe_fn>(entry_pointer)(&native_marker);
    shutdown(host_handle, domain_id);
    return probe_status;
}
