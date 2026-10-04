#include "state.hpp"
#include "android_assets.hpp"
#include "jni_utils.hpp"
#include "asset_file.hpp"

#include <array>
#include <fstream>
#include <iterator>
#include <vector>

namespace lemon::bootstrap {
bool read_optional_asset_text(const char* path, std::string& output) {
    AAsset* asset = AAssetManager_open(asset_manager, path, AASSET_MODE_BUFFER);
    if (asset == nullptr) {
        output.clear();
        return true;
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
    return true;
}

std::vector<std::string> list_asset_children(const std::string& asset_path) {
    JNIEnv* env = nullptr;
    if (java_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK ||
        env == nullptr || asset_manager_object == nullptr) {
        throw std::runtime_error("Could not access APK assets while listing a directory");
    }

    jclass manager_class = env->GetObjectClass(asset_manager_object);
    jmethodID list_method = required_method(env,
        manager_class, "list", "(Ljava/lang/String;)[Ljava/lang/String;");
    jstring path = new_java_string(env, asset_path.c_str());
    auto values = static_cast<jobjectArray>(
        checked_object_call(env, asset_manager_object, list_method, path));
    env->DeleteLocalRef(path);
    env->DeleteLocalRef(manager_class);
    if (clear_java_exception(env, "AssetManager.list") || values == nullptr) {
        throw std::runtime_error("Could not list APK asset directory '" + asset_path + "'");
    }

    std::vector<std::string> result;
    const jsize count = env->GetArrayLength(values);
    result.reserve(static_cast<size_t>(count));
    for (jsize index = 0; index < count; ++index) {
        auto value = static_cast<jstring>(env->GetObjectArrayElement(values, index));
        result.push_back(java_string(env, value));
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
        if (error) {
            log_error("Could not create extracted asset directory '" + destination.string() + "': " + error.message());
            return false;
        }
        for (const std::string& child : children) {
            if (child.empty() || child == "." || child == ".." ||
                child.find('/') != std::string::npos || child.find('\\') != std::string::npos) {
                log_error("APK asset contains an unsafe child name");
                return false;
            }
            if (!extract_asset_node(asset_path + '/' + child, destination / child)) {
                return false;
            }
        }
        return true;
    }

    std::string failure;
    if (extract_asset_file(asset_manager, asset_path, destination, failure)) return true;
    log_error("Could not extract APK asset '" + asset_path + "' to '" +
              destination.string() + "': " + failure);
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
    return !input.bad();
}

bool copy_if_changed(
    const std::string& asset_path,
    const std::filesystem::path& destination,
    const std::filesystem::path& marker_path,
    const std::string& update_stamp) {
    std::error_code error;
    const std::filesystem::path parent = destination.parent_path();
    const std::filesystem::path staging =
        parent / (".lemon-staging-" + destination.filename().string());
    const std::filesystem::path previous =
        parent / (".lemon-previous-" + destination.filename().string());
    const auto fail = [&](const char* operation) {
        log_error(std::string(operation) + " for runtime tree '" + destination.string() +
                  "': " + error.message() + " (errno=" + std::to_string(error.value()) + ")");
        return false;
    };
    std::filesystem::create_directories(parent, error);
    if (error) {
        return fail("Create parent directory");
    }

    const bool destination_exists = std::filesystem::exists(destination, error);
    const bool previous_exists = !error && std::filesystem::exists(previous, error);
    if (error) {
        return fail("Inspect current/previous extraction");
    }
    if (!destination_exists && previous_exists) {
        std::filesystem::rename(previous, destination, error);
        if (error) {
            return fail("Recover previous extraction");
        }
    } else if (previous_exists) {
        std::filesystem::remove_all(previous, error);
        if (error) {
            return fail("Remove previous extraction");
        }
    }

    // APK installation invalidates extraction without an installer-generated digest.
    std::string existing_stamp;
    if (!update_stamp.empty() && read_file(marker_path, existing_stamp) && existing_stamp == update_stamp) {
        const std::filesystem::file_status status =
            std::filesystem::symlink_status(destination, error);
        if (!error && std::filesystem::is_directory(status)) {
            return true;
        }
    }

    error.clear();
    std::filesystem::remove_all(staging, error);
    if (error) {
        return fail("Clean extraction staging");
    }
    std::filesystem::create_directories(staging, error);
    if (error) {
        return fail("Create extraction staging");
    }

    const std::filesystem::path staged_asset = staging / destination.filename();
    if (!extract_asset_node(asset_path, staged_asset)) {
        log_error("Failed to extract APK asset tree '" + asset_path + "'");
        std::filesystem::remove_all(staging, error);
        return false;
    }

    const bool had_destination = std::filesystem::exists(destination, error);
    if (error) {
        fail("Inspect extraction destination");
        std::filesystem::remove_all(staging, error);
        return false;
    }
    if (had_destination) {
        std::filesystem::rename(destination, previous, error);
        if (error) {
            fail("Back up previous extraction");
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
    if (error) fail("Clean published extraction staging");

    std::filesystem::create_directories(marker_path.parent_path(), error);
    if (error) {
        return fail("Create extraction marker directory");
    }
    std::filesystem::path temporary_marker = marker_path;
    temporary_marker += ".tmp";
    {
        std::ofstream marker_output(temporary_marker, std::ios::binary | std::ios::trunc);
        marker_output << update_stamp;
        if (!finish_output(marker_output, error)) {
            log_error("Failed to write extraction marker '" + temporary_marker.string() + "': " + error.message());
            std::filesystem::remove(temporary_marker, error);
            return false;
        }
    }
    std::filesystem::rename(temporary_marker, marker_path, error);
    if (error) {
        fail("Publish extraction marker");
        std::filesystem::remove(temporary_marker, error);
        return false;
    }
    std::filesystem::remove_all(previous, error);
    if (error) fail("Clean committed previous extraction");
    return true;
}

bool compute_file_sha256(const std::filesystem::path& path, std::string& output) {
    JNIEnv* env = nullptr;
    if (java_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK ||
        env == nullptr) {
        return false;
    }

    jclass digest_class = env->FindClass("java/security/MessageDigest");
    if (clear_java_exception(env, "FindClass(MessageDigest)") || digest_class == nullptr) {
        return false;
    }
    jmethodID get_instance = required_static_method(env,
        digest_class,
        "getInstance",
        "(Ljava/lang/String;)Ljava/security/MessageDigest;");
    jmethodID update = required_method(env, digest_class, "update", "([BII)V");
    jmethodID digest_method = required_method(env, digest_class, "digest", "()[B");
    if (get_instance == nullptr || update == nullptr || digest_method == nullptr ||
        clear_java_exception(env, "Resolve MessageDigest methods")) {
        env->DeleteLocalRef(digest_class);
        return false;
    }

    jstring algorithm = new_java_string(env, "SHA-256");
    jobject digest = checked_static_object_call(env, digest_class, get_instance, algorithm);
    env->DeleteLocalRef(algorithm);
    if (clear_java_exception(env, "Create SHA-256 MessageDigest") || digest == nullptr) {
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
    if (clear_java_exception(env, "Allocate SHA-256 input buffer") || bytes == nullptr) {
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
        if (clear_java_exception(env, "Copy SHA-256 input buffer")) {
            env->DeleteLocalRef(bytes);
            env->DeleteLocalRef(digest);
            env->DeleteLocalRef(digest_class);
            return false;
        }
        env->CallVoidMethod(digest, update, bytes, 0, static_cast<jint>(count));
        if (clear_java_exception(env, "Update SHA-256 digest")) {
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

    auto digest_bytes = static_cast<jbyteArray>(checked_object_call(env, digest, digest_method));
    const bool digest_failed =
        clear_java_exception(env, "Finish SHA-256 digest") || digest_bytes == nullptr;
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
    if (clear_java_exception(env, "Read SHA-256 digest")) {
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
}  // namespace lemon::bootstrap
