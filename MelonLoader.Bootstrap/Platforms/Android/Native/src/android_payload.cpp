#include "state.hpp"
#include "android_payload.hpp"
#include "android_assets.hpp"
#include "jni_utils.hpp"

#include <cstdlib>
#include <map>

namespace lemon::bootstrap {
namespace {
jobject read_json_option(JNIEnv* env, jclass json_class, jobject json, const char* key, const char* type) {
    const auto has = required_method(env, json_class, "has", "(Ljava/lang/String;)Z");
    const auto get = required_method(env, json_class, "get", "(Ljava/lang/String;)Ljava/lang/Object;");
    auto name = new_java_string(env, key);
    const bool present = env->CallBooleanMethod(json, has, name);
    if (clear_java_exception(env, "Check payload option")) {
        env->DeleteLocalRef(name);
        throw std::runtime_error("Cannot check payload option");
    }
    if (!present) { env->DeleteLocalRef(name); return nullptr; }
    auto value = checked_object_call(env, json, get, name);
    env->DeleteLocalRef(name);
    auto expected = env->FindClass(type);
    const bool failed = clear_java_exception(env, "Resolve payload option type");
    const bool valid = !failed && expected && value && env->IsInstanceOf(value, expected);
    if (expected) env->DeleteLocalRef(expected);
    if (!valid) {
        if (value) env->DeleteLocalRef(value);
        throw std::runtime_error(std::string("Invalid payload option type: ") + key);
    }
    return value;
}
}  // namespace

bool read_deployment_options(JNIEnv* env, jclass json_class, jobject json, PayloadDescriptor& descriptor) {
    const auto read_string = [&](jobject object, const char* key, const char* fallback) {
        auto value = static_cast<jstring>(read_json_option(env, json_class, object, key, "java/lang/String"));
        const auto text = value ? java_string(env, value) : fallback;
        if (value) env->DeleteLocalRef(value);
        return text;
    };
    auto files = read_json_option(env, json_class, json, "deploymentFiles", "org/json/JSONArray");
    descriptor.deployment_files.clear();
    if (!files) return true;
    auto array_class = env->GetObjectClass(files);
    const auto length = required_method(env, array_class, "length", "()I");
    const auto get = required_method(env, array_class, "getJSONObject", "(I)Lorg/json/JSONObject;");
    const auto count = env->CallIntMethod(files, length);
    if (clear_java_exception(env, "Read deployment policy count") || count < 0) return false;
    std::map<std::string, bool> paths;
    for (jint index = 0; index < count; ++index) {
        auto file = checked_object_call(env, files, get, index);
        DeploymentEntry entry;
        entry.path = read_string(file, "path", "");
        const auto policy = read_string(file, "policy", "seed");
        env->DeleteLocalRef(file);
        if (!is_safe_relative_path(entry.path) || !deployment::parse(policy, entry.policy) ||
            !paths.emplace(entry.path, true).second) return false;
        descriptor.deployment_files.push_back(std::move(entry));
    }
    for (const auto& file : descriptor.deployment_files) {
        for (auto separator = file.path.find('/'); separator != std::string::npos;
             separator = file.path.find('/', separator + 1)) {
            if (paths.count(file.path.substr(0, separator))) return false;
        }
    }
    env->DeleteLocalRef(array_class);
    env->DeleteLocalRef(files);
    return true;
}

bool read_payload_descriptor(PayloadDescriptor& descriptor) {
    descriptor = PayloadDescriptor{};
    std::string json;
    if (!read_optional_asset_text("LemonLoader/payload.json", json)) {
        log_error("Could not read APK payload options");
        return false;
    }
    if (json.empty()) return true;

    JNIEnv* env = nullptr;
    if (java_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK ||
        env == nullptr) {
        log_error("Could not access JNI while reading the Android payload manifest");
        return false;
    }

    jclass json_class = env->FindClass("org/json/JSONObject");
    const bool class_failed = clear_java_exception(env, "FindClass(JSONObject)");
    if (json_class == nullptr || class_failed) {
        return false;
    }
    jmethodID constructor = required_method(env,
        json_class, "<init>", "(Ljava/lang/String;)V");
    const bool method_resolution_failed = clear_java_exception(env, "Resolve JSONObject methods");
    if (constructor == nullptr ||
        method_resolution_failed) {
        env->DeleteLocalRef(json_class);
        return false;
    }

    jstring json_value = new_java_string(env, json.c_str());
    jobject json_object = env->NewObject(json_class, constructor, json_value);
    env->DeleteLocalRef(json_value);
    const bool parse_failed = clear_java_exception(env, "Parse LemonLoader payload manifest");
    if (json_object == nullptr || parse_failed) {
        env->DeleteLocalRef(json_class);
        return false;
    }

    bool valid = false;
    try {
        auto rid = static_cast<jstring>(read_json_option(env, json_class, json_object, "runtimeRid", "java/lang/String"));
        if (rid) { descriptor.runtime_rid = java_string(env, rid); env->DeleteLocalRef(rid); }
        auto version = read_json_option(env, json_class, json_object, "formatVersion", "java/lang/Number");
        jdouble format_version = 9;
        if (version) {
            auto number = env->GetObjectClass(version);
            const auto double_value = required_method(env, number, "doubleValue", "()D");
            format_version = env->CallDoubleMethod(version, double_value);
            env->DeleteLocalRef(number);
            env->DeleteLocalRef(version);
        }
        valid = !clear_java_exception(env, "Read payload manifest version") && format_version == 9 &&
            (descriptor.runtime_rid == "android-arm64" || descriptor.runtime_rid == "linux-bionic-arm64");
    } catch (const std::exception& error) {
        if (env->ExceptionCheck()) env->ExceptionClear();
        log_error(error.what());
    }
    if (valid) {
        if (env->PushLocalFrame(32) != JNI_OK) {
            clear_java_exception(env, "Prepare optional deployment policy frame");
            descriptor.deployment_valid = false;
        } else {
            try { descriptor.deployment_valid = read_deployment_options(env, json_class, json_object, descriptor); }
            catch (...) {
                if (env->ExceptionCheck()) env->ExceptionClear();
                descriptor.deployment_valid = false;
            }
            env->PopLocalFrame(nullptr);
        }
    }
    env->DeleteLocalRef(json_object);
    env->DeleteLocalRef(json_class);
    if (!valid) {
        log_error("APK payload manifest is invalid or uses an unsupported layout version");
    }
    return valid;
}

std::string apk_update_stamp() {
    JNIEnv* env = nullptr;
    if (!java_vm || java_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK || !env)
        return {};
    if (env->PushLocalFrame(16) != JNI_OK) {
        clear_java_exception(env, "Prepare package update lookup");
        return {};
    }
    std::string stamp;
    try {
        auto player = env->FindClass("com/unity3d/player/UnityPlayer");
        if (clear_java_exception(env, "Find Unity activity for package update") || !player)
            throw std::runtime_error("Cannot find Unity activity");
        auto field = env->GetStaticFieldID(player, "currentActivity", "Landroid/app/Activity;");
        if (clear_java_exception(env, "Resolve Unity activity for package update") || !field)
            throw std::runtime_error("Cannot resolve Unity activity");
        auto activity = env->GetStaticObjectField(player, field);
        if (clear_java_exception(env, "Read Unity activity for package update") || !activity)
            throw std::runtime_error("Cannot read Unity activity");
        auto context = env->FindClass("android/content/Context");
        auto get_manager = required_method(env, context, "getPackageManager", "()Landroid/content/pm/PackageManager;");
        auto manager = checked_object_call(env, activity, get_manager);
        auto manager_class = env->FindClass("android/content/pm/PackageManager");
        auto get_info = required_method(env, manager_class, "getPackageInfo", "(Ljava/lang/String;I)Landroid/content/pm/PackageInfo;");
        auto package = new_java_string(env, runtime_paths.package_name);
        auto info = checked_object_call(env, manager, get_info, package, 0);
        auto info_class = env->FindClass("android/content/pm/PackageInfo");
        if (clear_java_exception(env, "Find PackageInfo for package update") || !info_class || !info)
            throw std::runtime_error("Cannot read package information");
        auto update_field = env->GetFieldID(info_class, "lastUpdateTime", "J");
        if (clear_java_exception(env, "Resolve package lastUpdateTime") || !update_field || !info)
            throw std::runtime_error("Cannot resolve package update time");
        const auto updated = env->GetLongField(info, update_field);
        if (clear_java_exception(env, "Read package lastUpdateTime")) throw std::runtime_error("Cannot read package update time");
        if (updated > 0) stamp = "apk-" + std::to_string(updated);
    } catch (...) {
        if (env->ExceptionCheck()) env->ExceptionClear();
        log_line("[WARNING] Could not read APK update time; packaged deployment will be retried");
    }
    env->PopLocalFrame(nullptr);
    return stamp;
}

bool extract_runtime_assets() {
    PayloadDescriptor payload;
    if (!read_payload_descriptor(payload)) {
        return false;
    }
    runtime_paths.runtime_rid = payload.runtime_rid;
    payload.deployment_stamp = apk_update_stamp();
    if (setenv("MELONLOADER_APK_UPDATE_TOKEN", payload.deployment_stamp.c_str(), 1) != 0) {
        unsetenv("MELONLOADER_APK_UPDATE_TOKEN");
        log_line("[WARNING] Could not supply APK update time for game-information caching");
    }

    const std::filesystem::path base(runtime_paths.base_directory);
    const std::filesystem::path internal(runtime_paths.internal_data_directory);
    const std::filesystem::path loader = base / "MelonLoader";
    const bool runtime_extracted = copy_if_changed(
               "LemonLoader/runtime/loader/net6",
               loader / "net6",
               base / ".lemonloader-loader-net6-hash",
               payload.deployment_stamp) &&
           copy_if_changed(
               "LemonLoader/runtime/loader/Dependencies",
               loader / "Dependencies",
               base / ".lemonloader-loader-dependencies-hash",
               payload.deployment_stamp) &&
           copy_if_changed(
               "LemonLoader/runtime/interop",
               loader / "Il2CppAssemblies",
               base / ".lemonloader-interop-hash",
               payload.deployment_stamp) &&
           copy_if_changed(
               "LemonLoader/runtime/dotnet",
               internal / "dotnet",
               std::filesystem::path(runtime_paths.dotnet_directory) /
                   ".lemonloader-dotnet-hash",
               payload.deployment_stamp);
    if (!runtime_extracted) {
        return false;
    }

    bool deployed = false;
    if (payload.deployment_valid) {
        try { deployed = deploy_assets_if_changed(base, payload); }
        catch (const std::exception& error) {
            log_error(std::string("Packaged deployment failed: ") + error.what());
        } catch (...) { log_error("Packaged deployment failed"); }
    } else {
        log_error("Packaged deployment policy options are invalid");
    }
    if (!deployed) runtime_paths.loader_disabled = true;
    return true;
}
}  // namespace lemon::bootstrap
