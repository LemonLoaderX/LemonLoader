#include "state.hpp"
#include "deployment_policy.hpp"

#include <android/asset_manager_jni.h>
#include <dlfcn.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <limits>
#include <map>
#include <string>
#include <utility>
#include <vector>

namespace lemon::bootstrap {
namespace {

bool clear_exception(JNIEnv* env, const char* operation) {
    if (!env->ExceptionCheck()) {
        return false;
    }
    env->ExceptionDescribe();
    env->ExceptionClear();
    log_error(std::string(operation) + " raised a Java exception");
    return true;
}

std::string get_string(JNIEnv* env, jstring value) {
    if (value == nullptr) {
        return {};
    }
    const char* utf8 = env->GetStringUTFChars(value, nullptr);
    if (utf8 == nullptr) {
        clear_exception(env, "GetStringUTFChars");
        return {};
    }
    std::string result(utf8);
    env->ReleaseStringUTFChars(value, utf8);
    return result;
}

std::string get_file_path(JNIEnv* env, jobject file) {
    if (file == nullptr) {
        return {};
    }
    jclass file_class = env->GetObjectClass(file);
    jmethodID get_path = env->GetMethodID(
        file_class, "getAbsolutePath", "()Ljava/lang/String;");
    auto value = static_cast<jstring>(env->CallObjectMethod(file, get_path));
    std::string result = get_string(env, value);
    env->DeleteLocalRef(value);
    env->DeleteLocalRef(file_class);
    return result;
}

bool read_asset_text(const char* path, std::string& output) {
    AAsset* asset = AAssetManager_open(asset_manager, path, AASSET_MODE_BUFFER);
    if (asset == nullptr) {
        return false;
    }
    const auto length = static_cast<size_t>(AAsset_getLength(asset));
    output.resize(length);
    const int read = AAsset_read(asset, output.data(), length);
    AAsset_close(asset);
    if (read < 0 || static_cast<size_t>(read) != length) {
        output.clear();
        return false;
    }
    while (!output.empty() &&
           (output.back() == '\r' || output.back() == '\n' || output.back() == ' ')) {
        output.pop_back();
    }
    return !output.empty();
}

std::vector<std::string> list_asset_children(const std::string& asset_path) {
    JNIEnv* env = nullptr;
    if (java_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK ||
        env == nullptr || asset_manager_object == nullptr) {
        return {};
    }

    jclass manager_class = env->GetObjectClass(asset_manager_object);
    jmethodID list_method = env->GetMethodID(
        manager_class, "list", "(Ljava/lang/String;)[Ljava/lang/String;");
    jstring path = env->NewStringUTF(asset_path.c_str());
    auto values = static_cast<jobjectArray>(
        env->CallObjectMethod(asset_manager_object, list_method, path));
    env->DeleteLocalRef(path);
    env->DeleteLocalRef(manager_class);
    if (clear_exception(env, "AssetManager.list") || values == nullptr) {
        return {};
    }

    std::vector<std::string> result;
    const jsize count = env->GetArrayLength(values);
    result.reserve(static_cast<size_t>(count));
    for (jsize index = 0; index < count; ++index) {
        auto value = static_cast<jstring>(env->GetObjectArrayElement(values, index));
        result.push_back(get_string(env, value));
        env->DeleteLocalRef(value);
    }
    env->DeleteLocalRef(values);
    return result;
}

bool extract_asset_node(
    const std::string& asset_path,
    const std::filesystem::path& destination) {
    const std::vector<std::string> children = list_asset_children(asset_path);
    if (!children.empty()) {
        std::error_code error;
        std::filesystem::create_directories(destination, error);
        for (const std::string& child : children) {
            if (!extract_asset_node(asset_path + '/' + child, destination / child)) {
                return false;
            }
        }
        return true;
    }

    AAsset* asset = AAssetManager_open(
        asset_manager, asset_path.c_str(), AASSET_MODE_STREAMING);
    if (asset != nullptr) {
        std::error_code error;
        std::filesystem::create_directories(destination.parent_path(), error);
        std::ofstream output(destination, std::ios::binary | std::ios::trunc);
        if (!output) {
            log_error("Could not create extracted asset file '" + destination.string() + "'");
            AAsset_close(asset);
            return false;
        }

        char buffer[64 * 1024];
        int read = 0;
        while ((read = AAsset_read(asset, buffer, sizeof(buffer))) > 0) {
            output.write(buffer, read);
        }
        AAsset_close(asset);
        if (read != 0 || !output.good()) {
            log_error("Could not write extracted asset file '" + destination.string() + "'");
            return false;
        }
        return true;
    }

    log_error("APK asset path has no readable file or children: '" + asset_path + "'");
    return false;
}

bool read_file(const std::filesystem::path& path, std::string& output) {
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        return false;
    }
    output.assign(
        std::istreambuf_iterator<char>(input),
        std::istreambuf_iterator<char>());
    return true;
}

struct DeploymentFileDescriptor {
    std::string path;
    uint64_t size = 0;
    std::string hash;
    deployment::Policy policy = deployment::Policy::seed;
};

bool is_safe_relative_path(const std::string& value);
bool compute_file_sha256(const std::filesystem::path& path, std::string& output);
bool compute_text_sha256(const std::string& value, std::string& output);

bool copy_if_changed(
    const std::string& asset_path,
    const std::filesystem::path& destination,
    const std::filesystem::path& hash_path,
    const std::string& asset_hash) {
    std::error_code error;
    const std::filesystem::path parent = destination.parent_path();
    const std::filesystem::path staging =
        parent / (".lemon-staging-" + destination.filename().string());
    const std::filesystem::path previous =
        parent / (".lemon-previous-" + destination.filename().string());
    std::filesystem::create_directories(parent, error);
    if (error) {
        return false;
    }

    const bool destination_exists = std::filesystem::exists(destination, error);
    const bool previous_exists = !error && std::filesystem::exists(previous, error);
    if (error) {
        return false;
    }
    if (!destination_exists && previous_exists) {
        std::filesystem::rename(previous, destination, error);
        if (error) {
            return false;
        }
    } else if (previous_exists) {
        std::filesystem::remove_all(previous, error);
        if (error) {
            return false;
        }
    }

    // Package validation owns content integrity. The marker is the commit record
    // for this atomic directory publication, so normal startup must not rescan it.
    std::string existing_hash;
    if (read_file(hash_path, existing_hash) && existing_hash == asset_hash) {
        const std::filesystem::file_status status =
            std::filesystem::symlink_status(destination, error);
        if (!error && std::filesystem::is_directory(status)) {
            return true;
        }
    }

    error.clear();
    std::filesystem::remove_all(staging, error);
    if (error) {
        return false;
    }
    std::filesystem::create_directories(staging, error);
    if (error) {
        return false;
    }

    const std::filesystem::path staged_asset = staging / destination.filename();
    if (!extract_asset_node(asset_path, staged_asset)) {
        log_error("Failed to extract APK asset tree '" + asset_path + "'");
        std::filesystem::remove_all(staging, error);
        return false;
    }

    const bool had_destination = std::filesystem::exists(destination, error);
    if (error) {
        std::filesystem::remove_all(staging, error);
        return false;
    }
    if (had_destination) {
        std::filesystem::rename(destination, previous, error);
        if (error) {
            std::filesystem::remove_all(staging, error);
            return false;
        }
    }
    std::filesystem::rename(staged_asset, destination, error);
    if (error) {
        const std::error_code publish_error = error;
        if (had_destination) {
            std::error_code restore_error;
            std::filesystem::rename(previous, destination, restore_error);
            if (restore_error) {
                log_error("Failed to restore the previous runtime directory '" +
                          destination.string() + "': " + restore_error.message());
            }
        }
        std::error_code cleanup_error;
        std::filesystem::remove_all(staging, cleanup_error);
        log_error("Failed to publish extracted APK asset tree '" + asset_path + "': " +
                  publish_error.message());
        return false;
    }
    std::filesystem::remove_all(staging, error);
    std::filesystem::remove_all(previous, error);

    std::filesystem::create_directories(hash_path.parent_path(), error);
    if (error) {
        return false;
    }
    std::filesystem::path temporary_hash = hash_path;
    temporary_hash += ".tmp";
    {
        std::ofstream hash_output(temporary_hash, std::ios::binary | std::ios::trunc);
        hash_output << asset_hash;
        if (!hash_output.good()) {
            std::filesystem::remove(temporary_hash, error);
            return false;
        }
    }
    std::filesystem::rename(temporary_hash, hash_path, error);
    if (error) {
        std::filesystem::remove(temporary_hash, error);
        return false;
    }
    return true;
}

struct PayloadDescriptor {
    std::string loader_hash;
    std::string dotnet_hash;
    std::string interop_hash;
    std::string deployment_hash;
    std::string managed_runtime_identity_hash;
    std::string deployment_profile;
    std::string deployment_revision;
    std::vector<DeploymentFileDescriptor> deployment_files;
};

bool read_payload_descriptor(PayloadDescriptor& descriptor) {
    std::string json;
    if (!read_asset_text("LemonLoader/payload.json", json)) {
        log_error("APK asset 'LemonLoader/payload.json' is missing or empty");
        return false;
    }

    JNIEnv* env = nullptr;
    if (java_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK ||
        env == nullptr) {
        log_error("Could not access JNI while reading the Android payload manifest");
        return false;
    }

    jclass json_class = env->FindClass("org/json/JSONObject");
    const bool class_failed = clear_exception(env, "FindClass(JSONObject)");
    if (json_class == nullptr || class_failed) {
        return false;
    }
    jmethodID constructor = env->GetMethodID(
        json_class, "<init>", "(Ljava/lang/String;)V");
    jmethodID get_int = env->GetMethodID(
        json_class, "getInt", "(Ljava/lang/String;)I");
    jmethodID get_string_method = env->GetMethodID(
        json_class, "getString", "(Ljava/lang/String;)Ljava/lang/String;");
    jmethodID get_long = env->GetMethodID(
        json_class, "getLong", "(Ljava/lang/String;)J");
    jmethodID get_array = env->GetMethodID(
        json_class, "getJSONArray", "(Ljava/lang/String;)Lorg/json/JSONArray;");
    const bool method_resolution_failed = clear_exception(env, "Resolve JSONObject methods");
    if (constructor == nullptr || get_int == nullptr || get_string_method == nullptr ||
        get_long == nullptr || get_array == nullptr || method_resolution_failed) {
        env->DeleteLocalRef(json_class);
        return false;
    }

    jstring json_value = env->NewStringUTF(json.c_str());
    jobject json_object = env->NewObject(json_class, constructor, json_value);
    env->DeleteLocalRef(json_value);
    const bool parse_failed = clear_exception(env, "Parse LemonLoader payload manifest");
    if (json_object == nullptr || parse_failed) {
        env->DeleteLocalRef(json_class);
        return false;
    }

    auto read_object_string = [&](jobject object, const char* name, std::string& value) {
        jstring property_name = env->NewStringUTF(name);
        auto property_value = static_cast<jstring>(
            env->CallObjectMethod(object, get_string_method, property_name));
        env->DeleteLocalRef(property_name);
        const bool property_failed = clear_exception(env, "Read payload manifest property");
        if (property_value == nullptr || property_failed) {
            if (property_value != nullptr) {
                env->DeleteLocalRef(property_value);
            }
            return false;
        }
        value = get_string(env, property_value);
        env->DeleteLocalRef(property_value);
        return !value.empty();
    };
    auto read_property = [&](const char* name, std::string& value) {
        return read_object_string(json_object, name, value);
    };

    const auto is_sha256 = [](const std::string& value) {
        return value.size() == 64 && std::all_of(
            value.begin(), value.end(), [](unsigned char character) {
                return std::isxdigit(character) != 0;
            });
    };

    jstring version_name = env->NewStringUTF("formatVersion");
    const jint format_version = env->CallIntMethod(json_object, get_int, version_name);
    env->DeleteLocalRef(version_name);
    std::string managed_runtime_backend;
    bool valid = !clear_exception(env, "Read payload manifest version") &&
        format_version == 8 &&
        read_property("loaderSha256", descriptor.loader_hash) &&
        read_property("dotnetSha256", descriptor.dotnet_hash) &&
        read_property("interopSha256", descriptor.interop_hash) &&
        read_property("deploymentSha256", descriptor.deployment_hash) &&
        read_property("managedRuntimeBackend", managed_runtime_backend) &&
        read_property(
            "managedRuntimeIdentitySha256",
            descriptor.managed_runtime_identity_hash) &&
        read_property("deploymentProfile", descriptor.deployment_profile) &&
        read_property("deploymentRevisionSha256", descriptor.deployment_revision) &&
        is_sha256(descriptor.loader_hash) &&
        is_sha256(descriptor.dotnet_hash) &&
        is_sha256(descriptor.interop_hash) &&
        is_sha256(descriptor.deployment_hash) &&
        is_sha256(descriptor.managed_runtime_identity_hash) &&
        managed_runtime_backend == "coreclr" &&
        is_sha256(descriptor.deployment_revision) &&
        (descriptor.deployment_profile == "development" ||
         descriptor.deployment_profile == "production" ||
         descriptor.deployment_profile == "locked");

    jstring files_name = env->NewStringUTF("deploymentFiles");
    jobject files = valid
        ? env->CallObjectMethod(json_object, get_array, files_name)
        : nullptr;
    env->DeleteLocalRef(files_name);
    if (valid && (files == nullptr || clear_exception(env, "Read deployment file manifest"))) {
        valid = false;
    }
    jclass array_class = nullptr;
    jmethodID array_length = nullptr;
    jmethodID array_object = nullptr;
    if (valid) {
        array_class = env->GetObjectClass(files);
        array_length = env->GetMethodID(array_class, "length", "()I");
        array_object = env->GetMethodID(
            array_class, "getJSONObject", "(I)Lorg/json/JSONObject;");
        valid = array_length != nullptr && array_object != nullptr &&
            !clear_exception(env, "Resolve JSONArray methods");
    }
    std::map<std::string, bool> unique_paths;
    const jint file_count = valid ? env->CallIntMethod(files, array_length) : 0;
    if (valid && clear_exception(env, "Read deployment file count")) {
        valid = false;
    }
    descriptor.deployment_files.clear();
    descriptor.deployment_files.reserve(valid ? static_cast<size_t>(file_count) : 0);
    for (jint index = 0; valid && index < file_count; ++index) {
        jobject file = env->CallObjectMethod(files, array_object, index);
        if (file == nullptr || clear_exception(env, "Read deployment file entry")) {
            env->DeleteLocalRef(file);
            valid = false;
            break;
        }
        DeploymentFileDescriptor entry;
        std::string policy;
        jstring size_name = env->NewStringUTF("size");
        const jlong size = env->CallLongMethod(file, get_long, size_name);
        env->DeleteLocalRef(size_name);
        valid = !clear_exception(env, "Read deployment file size") && size >= 0 &&
            read_object_string(file, "path", entry.path) &&
            read_object_string(file, "sha256", entry.hash) &&
            read_object_string(file, "policy", policy) &&
            is_safe_relative_path(entry.path) &&
            is_sha256(entry.hash) &&
            deployment::parse(policy, entry.policy) &&
            unique_paths.emplace(entry.path, true).second;
        entry.size = size >= 0 ? static_cast<uint64_t>(size) : 0;
        env->DeleteLocalRef(file);
        if (valid) {
            descriptor.deployment_files.push_back(std::move(entry));
        }
    }
    if (array_class != nullptr) {
        env->DeleteLocalRef(array_class);
    }
    if (files != nullptr) {
        env->DeleteLocalRef(files);
    }
    if (valid) {
        std::string revision_input = "deployment-revision=1";
        for (const DeploymentFileDescriptor& file : descriptor.deployment_files) {
            size_t separator = file.path.find('/');
            while (valid && separator != std::string::npos) {
                valid = unique_paths.find(file.path.substr(0, separator)) == unique_paths.end();
                separator = file.path.find('/', separator + 1);
            }
        }
        std::sort(
            descriptor.deployment_files.begin(),
            descriptor.deployment_files.end(),
            [](const auto& left, const auto& right) { return left.path < right.path; });
        for (const DeploymentFileDescriptor& file : descriptor.deployment_files) {
            revision_input += '\n' + file.path + '|' + std::to_string(file.size) + '|' +
                file.hash + '|' + deployment::name(file.policy);
        }
        std::string actual_revision;
        valid = valid && compute_text_sha256(revision_input, actual_revision) &&
            actual_revision == descriptor.deployment_revision;
    }
    env->DeleteLocalRef(json_object);
    env->DeleteLocalRef(json_class);
    if (!valid) {
        log_error("APK payload manifest is invalid or uses an unsupported layout version");
    }
    return valid;
}

struct InstalledDeploymentFile {
    std::string hash;
    deployment::Policy policy = deployment::Policy::seed;
};

bool read_deployment_state(
    const std::filesystem::path& path,
    InstalledDeploymentFile& state) {
    std::string value;
    if (!read_file(path, value)) {
        return false;
    }
    const size_t separator = value.find('\n');
    if (separator == std::string::npos) {
        return false;
    }
    state.hash = value.substr(0, separator);
    std::string policy = value.substr(separator + 1);
    while (!policy.empty() && (policy.back() == '\r' || policy.back() == '\n')) {
        policy.pop_back();
    }
    return state.hash.size() == 64 && deployment::parse(policy, state.policy);
}

bool write_text_file(const std::filesystem::path& path, const std::string& value) {
    std::error_code error;
    std::filesystem::create_directories(path.parent_path(), error);
    if (error) {
        return false;
    }
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    output << value;
    return output.good();
}

bool reject_metadata_symlink(const std::filesystem::path& path) {
    std::error_code error;
    const std::filesystem::file_status status = std::filesystem::symlink_status(path, error);
    return !error && std::filesystem::is_symlink(status);
}

bool validate_destination_path(
    const std::filesystem::path& base,
    const std::filesystem::path& relative,
    bool& exists) {
    std::error_code error;
    exists = false;
    std::filesystem::path current = base;
    for (auto iterator = relative.begin(); iterator != relative.end(); ++iterator) {
        current /= *iterator;
        const bool final = std::next(iterator) == relative.end();
        const std::filesystem::file_status status =
            std::filesystem::symlink_status(current, error);
        if (error == std::errc::no_such_file_or_directory) {
            error.clear();
            continue;
        }
        if (error) {
            return false;
        }
        if (!std::filesystem::exists(status)) {
            if (final) {
                exists = false;
            }
            continue;
        }
        if (std::filesystem::is_symlink(status) ||
            (final && !std::filesystem::is_regular_file(status)) ||
            (!final && !std::filesystem::is_directory(status))) {
            return false;
        }
        if (final) {
            exists = true;
        }
    }
    return true;
}

bool publish_deployment_file(
    const std::filesystem::path& source,
    const std::filesystem::path& destination) {
    std::error_code error;
    std::filesystem::create_directories(destination.parent_path(), error);
    if (error) {
        return false;
    }
    std::filesystem::path temporary = destination;
    temporary += ".lemon-deploy.tmp";
    std::filesystem::remove(temporary, error);
    if (error) {
        return false;
    }
    std::filesystem::copy_file(source, temporary, std::filesystem::copy_options::none, error);
    if (error) {
        std::filesystem::remove(temporary, error);
        return false;
    }
    std::filesystem::rename(temporary, destination, error);
    if (error) {
        std::filesystem::remove(temporary, error);
        return false;
    }
    return true;
}

bool recover_deployment_state(const std::filesystem::path& base) {
    const std::filesystem::path state = base / ".lemonloader-deployment-state";
    const std::filesystem::path next = base / ".lemonloader-deployment-state.next";
    const std::filesystem::path previous = base / ".lemonloader-deployment-state.previous";
    if (reject_metadata_symlink(state) || reject_metadata_symlink(next) ||
        reject_metadata_symlink(previous) ||
        reject_metadata_symlink(base / ".lemonloader-backups")) {
        log_error("Packaged deployment metadata contains a symbolic link");
        return false;
    }

    std::error_code error;
    const bool state_exists = std::filesystem::exists(state, error);
    if (error) {
        return false;
    }
    const bool previous_exists = std::filesystem::exists(previous, error);
    if (error) {
        return false;
    }
    if (!state_exists && previous_exists) {
        std::filesystem::rename(previous, state, error);
        if (error) {
            return false;
        }
    } else if (previous_exists) {
        std::filesystem::remove_all(previous, error);
        if (error) {
            return false;
        }
    }
    std::filesystem::remove_all(next, error);
    return !error;
}

bool commit_deployment_state(const std::filesystem::path& base) {
    const std::filesystem::path state = base / ".lemonloader-deployment-state";
    const std::filesystem::path next = base / ".lemonloader-deployment-state.next";
    const std::filesystem::path previous = base / ".lemonloader-deployment-state.previous";
    std::error_code error;
    std::filesystem::remove_all(previous, error);
    if (error) {
        return false;
    }
    const bool had_state = std::filesystem::exists(state, error);
    if (error) {
        return false;
    }
    if (had_state) {
        std::filesystem::rename(state, previous, error);
        if (error) {
            return false;
        }
    }
    std::filesystem::rename(next, state, error);
    if (error) {
        if (had_state) {
            std::error_code restore_error;
            std::filesystem::rename(previous, state, restore_error);
        }
        return false;
    }
    std::filesystem::remove_all(previous, error);
    if (error) {
        log_line("[WARNING] Could not remove the previous packaged deployment state");
    }
    return true;
}

void prune_deployment_backups(const std::filesystem::path& base) {
    const std::filesystem::path root = base / ".lemonloader-backups";
    std::error_code error;
    if (!std::filesystem::is_directory(root, error)) {
        return;
    }
    std::vector<std::pair<std::filesystem::path, std::filesystem::file_time_type>> directories;
    for (std::filesystem::directory_iterator iterator(root, error), end;
         !error && iterator != end;
        iterator.increment(error)) {
        if (iterator->is_directory(error)) {
            const auto modified = std::filesystem::last_write_time(iterator->path(), error);
            if (!error) {
                directories.emplace_back(iterator->path(), modified);
            }
        }
    }
    if (error || directories.size() <= 3) {
        return;
    }
    std::sort(
        directories.begin(),
        directories.end(),
        [](const auto& left, const auto& right) {
            return left.second == right.second
                ? left.first < right.first
                : left.second < right.second;
        });
    for (size_t index = 0; index < directories.size() - 3; ++index) {
        std::filesystem::remove_all(directories[index].first, error);
        error.clear();
    }
}

struct DeploymentOperation {
    deployment::Action action = deployment::Action::preserve;
    std::filesystem::path relative;
    std::filesystem::path source;
    std::filesystem::path destination;
    std::filesystem::path backup;
    bool complete = false;
};

bool rollback_deployment(std::vector<DeploymentOperation>& operations) {
    bool success = true;
    for (auto iterator = operations.rbegin(); iterator != operations.rend(); ++iterator) {
        if (!iterator->complete) {
            continue;
        }
        std::error_code error;
        if (iterator->action == deployment::Action::install) {
            std::filesystem::remove(iterator->destination, error);
            success = success && !error;
        } else if (!publish_deployment_file(iterator->backup, iterator->destination)) {
            success = false;
        }
    }
    return success;
}

bool deploy_assets_if_changed(
    const std::filesystem::path& base,
    const PayloadDescriptor& payload) {
    const std::filesystem::path state_root = base / ".lemonloader-deployment-state";
    const std::filesystem::path next_state_root =
        base / ".lemonloader-deployment-state.next";

    std::error_code error;
    std::filesystem::create_directories(base, error);
    if (error) {
        log_error("Failed to create the MelonLoader deployment directory: " + error.message());
        return false;
    }
    if (!recover_deployment_state(base)) {
        log_error("Failed to recover packaged deployment state");
        return false;
    }

    std::string installed_revision;
    read_file(state_root / ".revision", installed_revision);
    while (!installed_revision.empty() &&
           (installed_revision.back() == '\r' || installed_revision.back() == '\n')) {
        installed_revision.pop_back();
    }
    const bool revision_changed = installed_revision != payload.deployment_revision;

    const std::string asset_path = "LemonLoader/deployment";
    const std::filesystem::path staging = base / ".packaged-deployment";
    std::filesystem::remove_all(staging, error);
    if (error) {
        log_error("Failed to clean packaged deployment staging: " + error.message());
        return false;
    }

    if (!revision_changed) {
        bool deployment_current = true;
        for (const DeploymentFileDescriptor& file : payload.deployment_files) {
            const std::filesystem::path relative(file.path);
            const std::filesystem::path destination = base / relative;
            bool exists = false;
            if (!validate_destination_path(base, relative, exists)) {
                log_error("Packaged deployment file has an unsafe destination: '" +
                          destination.string() + "'");
                return false;
            }
            if (!exists) {
                deployment_current = false;
                break;
            }
            if (deployment::requires_continuous_content_check(file.policy)) {
                std::string current_hash;
                if (!compute_file_sha256(destination, current_hash)) {
                    log_error("Failed to hash enforced deployment file '" +
                              destination.string() + "'");
                    return false;
                }
                if (current_hash != file.hash) {
                    deployment_current = false;
                    break;
                }
            }
        }
        if (deployment_current) {
            return true;
        }
    }

    const std::vector<std::string> children = list_asset_children(asset_path);
    if ((!children.empty() || !payload.deployment_files.empty()) &&
        !extract_asset_node(asset_path, staging)) {
        log_error("Failed to extract packaged deployment files");
        std::filesystem::remove_all(staging, error);
        return false;
    }

    std::map<std::string, const DeploymentFileDescriptor*> manifest_files;
    for (const DeploymentFileDescriptor& file : payload.deployment_files) {
        manifest_files.emplace(file.path, &file);
    }
    size_t staged_count = 0;
    error.clear();
    const bool staging_exists = std::filesystem::exists(staging, error);
    if (!error && staging_exists && !std::filesystem::is_directory(staging, error)) {
        log_error("Packaged deployment staging is not a directory");
        std::filesystem::remove_all(staging, error);
        return false;
    }
    if (!error && staging_exists) {
        for (std::filesystem::recursive_directory_iterator iterator(staging, error), end;
             !error && iterator != end;
             iterator.increment(error)) {
            if (!iterator->is_regular_file(error)) {
                continue;
            }
            const std::filesystem::path relative =
                std::filesystem::relative(iterator->path(), staging, error);
            if (error ||
                manifest_files.find(relative.generic_string()) == manifest_files.end()) {
                log_error("Packaged deployment contains a file not declared in payload.json");
                std::filesystem::remove_all(staging, error);
                return false;
            }
            ++staged_count;
        }
    }
    if (error || staged_count != manifest_files.size()) {
        log_error("Packaged deployment does not match its payload.json file manifest");
        std::filesystem::remove_all(staging, error);
        return false;
    }

    std::map<std::string, InstalledDeploymentFile> previous_states;
    error.clear();
    const bool state_exists = std::filesystem::exists(state_root, error);
    if (error) {
        log_error("Failed to inspect packaged deployment state: " + error.message());
        std::filesystem::remove_all(staging, error);
        return false;
    }
    if (state_exists && !std::filesystem::is_directory(state_root, error)) {
        log_error("Packaged deployment state is not a directory");
        std::filesystem::remove_all(staging, error);
        return false;
    }
    if (error) {
        log_error("Failed to inspect packaged deployment state: " + error.message());
        std::filesystem::remove_all(staging, error);
        return false;
    }
    if (state_exists) {
        for (std::filesystem::recursive_directory_iterator iterator(state_root, error), end;
             !error && iterator != end;
             iterator.increment(error)) {
            if (!iterator->is_regular_file(error)) {
                continue;
            }
            const std::filesystem::path relative =
                std::filesystem::relative(iterator->path(), state_root, error);
            if (error || relative == ".revision") {
                error.clear();
                continue;
            }
            InstalledDeploymentFile previous;
            if (is_safe_relative_path(relative.generic_string()) &&
                read_deployment_state(iterator->path(), previous)) {
                previous_states.emplace(relative.generic_string(), previous);
            }
        }
    }
    if (error) {
        log_error("Failed to read packaged deployment state: " + error.message());
        std::filesystem::remove_all(staging, error);
        return false;
    }

    std::filesystem::remove_all(next_state_root, error);
    std::filesystem::create_directories(next_state_root, error);
    if (error || !write_text_file(
            next_state_root / ".revision", payload.deployment_revision + "\n")) {
        log_error("Failed to prepare packaged deployment state");
        std::filesystem::remove_all(staging, error);
        return false;
    }

    std::vector<DeploymentOperation> operations;
    size_t preserved_count = 0;
    for (const DeploymentFileDescriptor& file : payload.deployment_files) {
        const std::filesystem::path relative(file.path);
        const std::filesystem::path staged = staging / relative;
        const std::filesystem::path destination = base / relative;
        if (std::filesystem::file_size(staged, error) != file.size || error) {
            log_error("Packaged deployment size mismatch for '" + file.path + "'");
            std::filesystem::remove_all(staging, error);
            return false;
        }
        std::string staged_hash;
        if (!compute_file_sha256(staged, staged_hash) || staged_hash != file.hash) {
            log_error("Packaged deployment SHA-256 mismatch for '" + file.path + "'");
            std::filesystem::remove_all(staging, error);
            return false;
        }

        bool exists = false;
        if (!validate_destination_path(base, relative, exists)) {
            log_error("Packaged deployment file has an unsafe destination: '" +
                      destination.string() + "'");
            std::filesystem::remove_all(staging, error);
            return false;
        }
        std::string current_hash;
        if (exists && !compute_file_sha256(destination, current_hash)) {
            log_error("Failed to hash existing deployment file '" + destination.string() + "'");
            std::filesystem::remove_all(staging, error);
            return false;
        }
        const auto previous_iterator = previous_states.find(file.path);
        const bool has_previous = previous_iterator != previous_states.end();
        const deployment::Action action = deployment::decide_current(
            file.policy,
            revision_changed,
            exists,
            exists && current_hash == file.hash,
            has_previous,
            has_previous && current_hash == previous_iterator->second.hash);
        if (action == deployment::Action::install ||
            action == deployment::Action::replace) {
            operations.push_back({action, relative, staged, destination, {}});
        } else if (exists && current_hash != file.hash) {
            ++preserved_count;
        }

        const bool managed = has_previous || action == deployment::Action::install ||
            action == deployment::Action::replace || (exists && current_hash == file.hash);
        if (managed && !write_text_file(
                next_state_root / relative,
                file.hash + "\n" + deployment::name(file.policy) + "\n")) {
            log_error("Failed to prepare deployment state for '" + file.path + "'");
            std::filesystem::remove_all(staging, error);
            return false;
        }
    }

    for (const auto& [path, previous] : previous_states) {
        if (manifest_files.find(path) != manifest_files.end()) {
            continue;
        }
        const std::filesystem::path relative(path);
        const std::filesystem::path destination = base / relative;
        bool exists = false;
        if (!validate_destination_path(base, relative, exists)) {
            log_error("Obsolete deployment file has an unsafe destination: '" +
                      destination.string() + "'");
            std::filesystem::remove_all(staging, error);
            return false;
        }
        std::string current_hash;
        if (exists && !compute_file_sha256(destination, current_hash)) {
            log_error("Failed to hash obsolete deployment file '" + destination.string() + "'");
            std::filesystem::remove_all(staging, error);
            return false;
        }
        const deployment::Action action = deployment::decide_obsolete(
            previous.policy,
            revision_changed,
            exists,
            exists && current_hash == previous.hash);
        if (action == deployment::Action::remove) {
            operations.push_back({action, relative, {}, destination, {}});
        } else if (exists) {
            ++preserved_count;
        }
    }

    const std::filesystem::path backup_root =
        base / ".lemonloader-backups" / payload.deployment_revision;
    if (reject_metadata_symlink(backup_root)) {
        log_error("Packaged deployment backup generation is a symbolic link");
        std::filesystem::remove_all(staging, error);
        return false;
    }
    const bool needs_backup = std::any_of(
        operations.begin(), operations.end(), [](const DeploymentOperation& operation) {
            return operation.action == deployment::Action::replace ||
                operation.action == deployment::Action::remove;
        });
    if (needs_backup) {
        std::filesystem::remove_all(backup_root, error);
        if (error) {
            log_error("Failed to prepare packaged deployment backup generation: " +
                      error.message());
            std::filesystem::remove_all(staging, error);
            return false;
        }
    }
    for (DeploymentOperation& operation : operations) {
        if (operation.action != deployment::Action::replace &&
            operation.action != deployment::Action::remove) {
            continue;
        }
        operation.backup = backup_root / operation.relative;
        if (!publish_deployment_file(operation.destination, operation.backup)) {
            log_error("Failed to back up deployment file '" +
                      operation.destination.string() + "'");
            std::filesystem::remove_all(staging, error);
            return false;
        }
    }

    size_t installed_count = 0;
    size_t replaced_count = 0;
    size_t removed_count = 0;
    for (DeploymentOperation& operation : operations) {
        bool applied = false;
        if (operation.action == deployment::Action::install ||
            operation.action == deployment::Action::replace) {
            applied = publish_deployment_file(operation.source, operation.destination);
        } else {
            applied = std::filesystem::remove(operation.destination, error) && !error;
        }
        if (!applied) {
            log_error("Failed to apply packaged deployment file '" +
                      operation.destination.string() + "'");
            if (!rollback_deployment(operations)) {
                log_error("Packaged deployment rollback was incomplete");
            }
            std::filesystem::remove_all(staging, error);
            return false;
        }
        operation.complete = true;
        if (operation.action == deployment::Action::install) {
            ++installed_count;
        } else if (operation.action == deployment::Action::replace) {
            ++replaced_count;
        } else {
            ++removed_count;
        }
    }

    if (!commit_deployment_state(base)) {
        log_error("Failed to commit packaged deployment state");
        if (!rollback_deployment(operations)) {
            log_error("Packaged deployment rollback was incomplete");
        }
        std::filesystem::remove_all(staging, error);
        return false;
    }

    std::filesystem::remove_all(staging, error);
    if (error) {
        log_line("[WARNING] Could not clean packaged deployment staging: " + error.message());
    }
    prune_deployment_backups(base);
    if (installed_count != 0 || replaced_count != 0 || preserved_count != 0 ||
        removed_count != 0) {
        log_line(
            "Applied packaged deployment (" + payload.deployment_profile + "): installed " +
            std::to_string(installed_count) + ", replaced " +
            std::to_string(replaced_count) + ", preserved " +
            std::to_string(preserved_count) + ", removed " +
            std::to_string(removed_count) + " file(s)");
    }
    return true;
}

bool is_safe_relative_path(const std::string& value) {
    if (value.empty() || value.front() == '/' || value.back() == '/' ||
        value.find('\\') != std::string::npos || value.find('|') != std::string::npos ||
        std::any_of(value.begin(), value.end(), [](unsigned char character) {
            return character < 0x20 || character == 0x7f;
        })) {
        return false;
    }
    const size_t first_separator = value.find('/');
    const std::string top_level = value.substr(0, first_separator);
    if (top_level == "MelonLoader" || top_level == ".packaged-deployment" ||
        top_level.rfind(".lemonloader-", 0) == 0 ||
        top_level.rfind(".lemon-staging-", 0) == 0) {
        return false;
    }
    size_t start = 0;
    while (start < value.size()) {
        const size_t end = value.find('/', start);
        const std::string segment = value.substr(start, end - start);
        if (segment.empty() || segment == "." || segment == "..") {
            return false;
        }
        if (end == std::string::npos) {
            break;
        }
        start = end + 1;
    }
    return true;
}

bool compute_file_sha256(const std::filesystem::path& path, std::string& output) {
    JNIEnv* env = nullptr;
    if (java_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK ||
        env == nullptr) {
        return false;
    }

    jclass digest_class = env->FindClass("java/security/MessageDigest");
    if (digest_class == nullptr || clear_exception(env, "FindClass(MessageDigest)")) {
        return false;
    }
    jmethodID get_instance = env->GetStaticMethodID(
        digest_class,
        "getInstance",
        "(Ljava/lang/String;)Ljava/security/MessageDigest;");
    jmethodID update = env->GetMethodID(digest_class, "update", "([BII)V");
    jmethodID digest_method = env->GetMethodID(digest_class, "digest", "()[B");
    if (get_instance == nullptr || update == nullptr || digest_method == nullptr ||
        clear_exception(env, "Resolve MessageDigest methods")) {
        env->DeleteLocalRef(digest_class);
        return false;
    }

    jstring algorithm = env->NewStringUTF("SHA-256");
    jobject digest = env->CallStaticObjectMethod(digest_class, get_instance, algorithm);
    env->DeleteLocalRef(algorithm);
    if (digest == nullptr || clear_exception(env, "Create SHA-256 MessageDigest")) {
        env->DeleteLocalRef(digest_class);
        return false;
    }

    std::ifstream input(path, std::ios::binary);
    if (!input) {
        env->DeleteLocalRef(digest);
        env->DeleteLocalRef(digest_class);
        return false;
    }
    std::array<char, 64 * 1024> buffer{};
    jbyteArray bytes = env->NewByteArray(static_cast<jsize>(buffer.size()));
    if (bytes == nullptr || clear_exception(env, "Allocate SHA-256 input buffer")) {
        if (bytes != nullptr) {
            env->DeleteLocalRef(bytes);
        }
        env->DeleteLocalRef(digest);
        env->DeleteLocalRef(digest_class);
        return false;
    }
    while (input) {
        input.read(buffer.data(), static_cast<std::streamsize>(buffer.size()));
        const std::streamsize count = input.gcount();
        if (count <= 0) {
            break;
        }
        env->SetByteArrayRegion(
            bytes,
            0,
            static_cast<jsize>(count),
            reinterpret_cast<const jbyte*>(buffer.data()));
        if (clear_exception(env, "Copy SHA-256 input buffer")) {
            env->DeleteLocalRef(bytes);
            env->DeleteLocalRef(digest);
            env->DeleteLocalRef(digest_class);
            return false;
        }
        env->CallVoidMethod(digest, update, bytes, 0, static_cast<jint>(count));
        if (clear_exception(env, "Update SHA-256 digest")) {
            env->DeleteLocalRef(bytes);
            env->DeleteLocalRef(digest);
            env->DeleteLocalRef(digest_class);
            return false;
        }
    }
    env->DeleteLocalRef(bytes);
    if (!input.eof()) {
        env->DeleteLocalRef(digest);
        env->DeleteLocalRef(digest_class);
        return false;
    }

    auto digest_bytes = static_cast<jbyteArray>(env->CallObjectMethod(digest, digest_method));
    const bool digest_failed =
        digest_bytes == nullptr || clear_exception(env, "Finish SHA-256 digest");
    const bool digest_length_invalid =
        !digest_failed && env->GetArrayLength(digest_bytes) != 32;
    if (digest_failed || digest_length_invalid) {
        if (digest_bytes != nullptr) {
            env->DeleteLocalRef(digest_bytes);
        }
        env->DeleteLocalRef(digest);
        env->DeleteLocalRef(digest_class);
        return false;
    }
    std::array<jbyte, 32> result{};
    env->GetByteArrayRegion(digest_bytes, 0, 32, result.data());
    if (clear_exception(env, "Read SHA-256 digest")) {
        env->DeleteLocalRef(digest_bytes);
        env->DeleteLocalRef(digest);
        env->DeleteLocalRef(digest_class);
        return false;
    }
    static constexpr char hex[] = "0123456789abcdef";
    output.resize(64);
    for (size_t index = 0; index < result.size(); ++index) {
        const auto value = static_cast<unsigned char>(result[index]);
        output[index * 2] = hex[value >> 4];
        output[index * 2 + 1] = hex[value & 0x0f];
    }
    env->DeleteLocalRef(digest_bytes);
    env->DeleteLocalRef(digest);
    env->DeleteLocalRef(digest_class);
    return true;
}

bool compute_text_sha256(const std::string& value, std::string& output) {
    if (value.size() > static_cast<size_t>(std::numeric_limits<jsize>::max())) {
        return false;
    }
    JNIEnv* env = nullptr;
    if (java_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK ||
        env == nullptr) {
        return false;
    }
    jclass digest_class = env->FindClass("java/security/MessageDigest");
    if (digest_class == nullptr || clear_exception(env, "FindClass(MessageDigest)")) {
        return false;
    }
    jmethodID get_instance = env->GetStaticMethodID(
        digest_class,
        "getInstance",
        "(Ljava/lang/String;)Ljava/security/MessageDigest;");
    jmethodID digest_method = env->GetMethodID(digest_class, "digest", "([B)[B");
    if (get_instance == nullptr || digest_method == nullptr ||
        clear_exception(env, "Resolve MessageDigest methods")) {
        env->DeleteLocalRef(digest_class);
        return false;
    }
    jstring algorithm = env->NewStringUTF("SHA-256");
    jobject digest = env->CallStaticObjectMethod(digest_class, get_instance, algorithm);
    env->DeleteLocalRef(algorithm);
    if (digest == nullptr || clear_exception(env, "Create SHA-256 MessageDigest")) {
        env->DeleteLocalRef(digest_class);
        return false;
    }
    jbyteArray input = env->NewByteArray(static_cast<jsize>(value.size()));
    if (input != nullptr && !value.empty()) {
        env->SetByteArrayRegion(
            input,
            0,
            static_cast<jsize>(value.size()),
            reinterpret_cast<const jbyte*>(value.data()));
    }
    if (input == nullptr || clear_exception(env, "Create deployment revision input")) {
        if (input != nullptr) {
            env->DeleteLocalRef(input);
        }
        env->DeleteLocalRef(digest);
        env->DeleteLocalRef(digest_class);
        return false;
    }
    auto digest_bytes = static_cast<jbyteArray>(
        env->CallObjectMethod(digest, digest_method, input));
    env->DeleteLocalRef(input);
    const bool digest_failed =
        digest_bytes == nullptr || clear_exception(env, "Hash deployment revision");
    const bool digest_length_invalid =
        !digest_failed && env->GetArrayLength(digest_bytes) != 32;
    if (digest_failed || digest_length_invalid) {
        if (digest_bytes != nullptr) {
            env->DeleteLocalRef(digest_bytes);
        }
        env->DeleteLocalRef(digest);
        env->DeleteLocalRef(digest_class);
        return false;
    }
    std::array<jbyte, 32> result{};
    env->GetByteArrayRegion(digest_bytes, 0, 32, result.data());
    if (clear_exception(env, "Read deployment revision hash")) {
        env->DeleteLocalRef(digest_bytes);
        env->DeleteLocalRef(digest);
        env->DeleteLocalRef(digest_class);
        return false;
    }
    static constexpr char hex[] = "0123456789abcdef";
    output.resize(64);
    for (size_t index = 0; index < result.size(); ++index) {
        const auto byte = static_cast<unsigned char>(result[index]);
        output[index * 2] = hex[byte >> 4];
        output[index * 2 + 1] = hex[byte & 0x0f];
    }
    env->DeleteLocalRef(digest_bytes);
    env->DeleteLocalRef(digest);
    env->DeleteLocalRef(digest_class);
    return true;
}

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
            log_error("Could not configure Android system certificate directory");
            return;
        }

        return;
    }

    log_error("Android system certificate directory was not found");
}

}  // namespace

bool initialize_android_environment(JNIEnv* env) {
    jclass unity_player = env->FindClass("com/unity3d/player/UnityPlayer");
    if (unity_player == nullptr || clear_exception(env, "FindClass(UnityPlayer)")) {
        return false;
    }
    jfieldID activity_field = env->GetStaticFieldID(
        unity_player, "currentActivity", "Landroid/app/Activity;");
    jobject activity = env->GetStaticObjectField(unity_player, activity_field);
    if (activity == nullptr || clear_exception(env, "UnityPlayer.currentActivity")) {
        env->DeleteLocalRef(unity_player);
        return false;
    }

    jclass activity_class = env->GetObjectClass(activity);
    jmethodID get_package_name = env->GetMethodID(
        activity_class, "getPackageName", "()Ljava/lang/String;");
    jmethodID get_files_dir = env->GetMethodID(
        activity_class, "getFilesDir", "()Ljava/io/File;");
    jmethodID get_external_files_dir = env->GetMethodID(
        activity_class, "getExternalFilesDir", "(Ljava/lang/String;)Ljava/io/File;");
    jmethodID get_assets = env->GetMethodID(
        activity_class, "getAssets", "()Landroid/content/res/AssetManager;");

    auto package_value = static_cast<jstring>(
        env->CallObjectMethod(activity, get_package_name));
    jobject files_directory = env->CallObjectMethod(activity, get_files_dir);
    jobject external_directory = env->CallObjectMethod(
        activity, get_external_files_dir, nullptr);
    jobject assets = env->CallObjectMethod(activity, get_assets);
    if (clear_exception(env, "Activity path discovery")) {
        return false;
    }

    runtime_paths.package_name = get_string(env, package_value);
    const std::filesystem::path files_path = get_file_path(env, files_directory);
    const std::filesystem::path external_path = get_file_path(env, external_directory);
    runtime_paths.internal_data_directory = files_path.parent_path().string();
    runtime_paths.dotnet_directory =
        (files_path.parent_path() / "dotnet").string();
    runtime_paths.base_directory = external_path.empty()
        ? (files_path / "MelonLoader").string()
        : (external_path / "MelonLoader").string();
    asset_manager = AAssetManager_fromJava(env, assets);
    asset_manager_object = env->NewGlobalRef(assets);

    env->DeleteLocalRef(assets);
    if (external_directory != nullptr) {
        env->DeleteLocalRef(external_directory);
    }
    env->DeleteLocalRef(files_directory);
    env->DeleteLocalRef(package_value);
    env->DeleteLocalRef(activity_class);
    env->DeleteLocalRef(activity);
    env->DeleteLocalRef(unity_player);

    if (asset_manager == nullptr || asset_manager_object == nullptr ||
        runtime_paths.base_directory.empty() ||
        runtime_paths.dotnet_directory.empty()) {
        log_error("Android runtime path or AssetManager discovery failed");
        return false;
    }
    return true;
}

bool extract_runtime_assets() {
    PayloadDescriptor payload;
    if (!read_payload_descriptor(payload)) {
        return false;
    }

    const std::filesystem::path base(runtime_paths.base_directory);
    const std::filesystem::path internal(runtime_paths.internal_data_directory);
    const std::filesystem::path loader = base / "MelonLoader";
    const bool runtime_extracted = copy_if_changed(
               "LemonLoader/runtime/loader/net6",
               loader / "net6",
               base / ".lemonloader-loader-net6-hash",
               payload.loader_hash) &&
           copy_if_changed(
               "LemonLoader/runtime/loader/Dependencies",
               loader / "Dependencies",
               base / ".lemonloader-loader-dependencies-hash",
               payload.loader_hash) &&
           copy_if_changed(
               "LemonLoader/runtime/interop",
               loader / "Il2CppAssemblies",
               base / ".lemonloader-interop-hash",
               payload.interop_hash) &&
           copy_if_changed(
               "LemonLoader/runtime/dotnet",
               internal / "dotnet",
               std::filesystem::path(runtime_paths.dotnet_directory) /
                   ".lemonloader-dotnet-hash",
               payload.dotnet_hash);
    if (!runtime_extracted) {
        return false;
    }

    const std::filesystem::path runtime_identity =
        std::filesystem::path(runtime_paths.dotnet_directory) / "runtime-identity.json";
    std::string runtime_identity_hash;
    if (!compute_file_sha256(runtime_identity, runtime_identity_hash) ||
        runtime_identity_hash != payload.managed_runtime_identity_hash) {
        log_error("The extracted managed runtime identity does not match payload.json");
        return false;
    }
    // Deployment mirrors the MelonLoader base directory. The APK manifest
    // assigns each file an explicit ownership and replacement policy.
    return deploy_assets_if_changed(base, payload);
}

bool prepare_android_runtime() {
    setenv("MELONLOADER_BASE_DIR", runtime_paths.base_directory.c_str(), 1);
    setenv("MELONLOADER_DOTNET_ROOT", runtime_paths.dotnet_directory.c_str(), 1);
    setenv("MELONLOADER_ANDROID_PACKAGE", runtime_paths.package_name.c_str(), 1);
    setenv("MELONLOADER_BOOTSTRAP_KIND", "ndk", 1);
    setenv("MELONLOADER_MANAGED_RUNTIME_BACKEND", "coreclr", 1);
    setenv("DOTNET_ROOT", runtime_paths.dotnet_directory.c_str(), 1);
    configure_android_certificate_store();
    const char* existing_path = getenv("PATH");
    const std::string path = runtime_paths.dotnet_directory + ':' +
        (existing_path == nullptr ? "" : existing_path);
    setenv("PATH", path.c_str(), 1);

    using mallopt_fn = int (*)(int, int);
    auto mallopt_value = reinterpret_cast<mallopt_fn>(dlsym(RTLD_DEFAULT, "mallopt"));
    if (mallopt_value != nullptr && mallopt_value(-204, 0) == 0) {
        log_line("[WARNING] Bionic heap pointer tagging opt-out is unavailable");
    }
    return true;
}

}  // namespace lemon::bootstrap
