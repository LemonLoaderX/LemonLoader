#include <cassert>
#include <cstdarg>
#include <deque>
#include <iostream>
#include <memory>
#include <set>
#include "android_environment.cpp"

namespace {
struct Node {
    std::u16string text;
    std::map<std::string, std::string> fields;
    std::vector<Node*> children;
    std::vector<jbyte> bytes;
    std::string digest_input;
};
std::vector<std::unique_ptr<Node>> nodes;
Node* root;
Node* options;
std::map<std::string, std::string> assets;
std::string asset_bytes, error;
size_t asset_position;
int asset_reads = 0, asset_lists = 0, hashes = 0, frames = 0;
bool pending = false, missing_update = false, failed_list = false, short_read = false;
jlong update_time = 1234;
JNIEnv* current_env;
AAsset asset;
AAssetManager manager;
Node* make() { nodes.push_back(std::make_unique<Node>()); return nodes.back().get(); }
Node* node(jobject value) { return reinterpret_cast<Node*>(value); }
jobject object(Node* value) { return reinterpret_cast<jobject>(value); }
jstring text(const std::string& value) {
    auto n = make(); n->text.assign(value.begin(), value.end()); return reinterpret_cast<jstring>(n);
}
std::string string(jstring value) { return lemon::bootstrap::utf16_to_utf8(reinterpret_cast<const uint16_t*>(node(value)->text.data()), node(value)->text.size()); }
const char* method(jmethodID value) { return reinterpret_cast<const char*>(value); }
jboolean check(JNIEnv*) { return pending; }
jthrowable occurred(JNIEnv*) { return nullptr; }
void clear(JNIEnv*) { pending = false; }
void describe(JNIEnv*) {}
jint push(JNIEnv*, jint) { ++frames; return JNI_OK; }
jobject pop(JNIEnv*, jobject) { --frames; return nullptr; }
void delete_ref(JNIEnv*, jobject) {}
jclass find_class(JNIEnv*, const char* name) { return reinterpret_cast<jclass>(const_cast<char*>(name)); }
jclass object_class(JNIEnv*, jobject) { return find_class(nullptr, "object"); }
jmethodID get_method(JNIEnv*, jclass, const char* name, const char*) { return reinterpret_cast<jmethodID>(const_cast<char*>(name)); }
jobject new_object(JNIEnv*, jclass, jmethodID, va_list) { return object(root); }
jfieldID get_field(JNIEnv*, jclass, const char*, const char*) { return reinterpret_cast<jfieldID>(1); }
jobject static_field(JNIEnv*, jclass, jfieldID) { return object(root); }
jlong long_field(JNIEnv*, jobject, jfieldID) { if (missing_update) pending = true; return update_time; }
jint get_env(JavaVM*, void** value, jint) { *value = current_env; return JNI_OK; }
jsize length(JNIEnv*, jstring value) { return node(value)->text.size(); }
const jchar* chars(JNIEnv*, jstring value, jboolean*) { return reinterpret_cast<const jchar*>(node(value)->text.data()); }
void release_chars(JNIEnv*, jstring, const jchar*) {}
jstring new_string(JNIEnv*, const jchar* value, jsize count) {
    auto n = make(); n->text.assign(reinterpret_cast<const char16_t*>(value), count); return reinterpret_cast<jstring>(n);
}
jobject object_call(JNIEnv*, jobject receiver, jmethodID id, va_list args) {
    const std::string name = method(id);
    if (name == "optString" || name == "getString") {
        const auto key = string(va_arg(args, jstring));
        const auto found = node(receiver)->fields.find(key);
        if (name == "optString") {
            const auto fallback = va_arg(args, jstring);
            return found == node(receiver)->fields.end() ? fallback : text(found->second);
        }
        if (found == node(receiver)->fields.end()) { pending = true; return nullptr; }
        return text(found->second);
    }
    if (name == "optJSONArray") { (void)va_arg(args, jstring); return object(options); }
    if (name == "getJSONObject") return object(node(receiver)->children.at(va_arg(args, jint)));
    if (name == "getPackageManager" || name == "getPackageInfo") return object(root);
    if (name == "list") {
        ++asset_lists;
        if (failed_list) return nullptr;
        const auto prefix = string(va_arg(args, jstring)) + '/';
        std::set<std::string> names;
        for (const auto& [path, value] : assets) {
            if (path.rfind(prefix, 0) == 0) {
                const auto remainder = path.substr(prefix.size());
                names.insert(remainder.substr(0, remainder.find('/')));
            }
        }
        auto list = make();
        for (const auto& entry : names) list->children.push_back(node(text(entry)));
        return object(list);
    }
    if (name == "digest") {
        auto result = make(); result->bytes.resize(32);
        // A stable fixture digest tests ownership comparisons, not SHA-256 itself.
        const auto value = std::hash<std::string>{}(node(receiver)->digest_input);
        for (size_t index = 0; index < 32; ++index) result->bytes[index] = static_cast<jbyte>(value >> ((index % 8) * 8));
        return object(result);
    }
    assert(false); return nullptr;
}
jobject static_call(JNIEnv*, jclass, jmethodID id, va_list) {
    assert(std::strcmp(method(id), "getInstance") == 0); ++hashes; return object(make());
}
jint int_call(JNIEnv*, jobject receiver, jmethodID id, va_list args) {
    if (std::strcmp(method(id), "length") == 0) return node(receiver)->children.size();
    assert(std::strcmp(method(id), "optInt") == 0);
    const auto key = string(va_arg(args, jstring)); const auto fallback = va_arg(args, jint);
    const auto found = node(receiver)->fields.find(key);
    return found == node(receiver)->fields.end() ? fallback : std::stoi(found->second);
}
void void_call(JNIEnv*, jobject receiver, jmethodID id, va_list args) {
    assert(std::strcmp(method(id), "update") == 0);
    auto value = node(va_arg(args, jbyteArray)); const auto start = va_arg(args, jint); const auto count = va_arg(args, jint);
    node(receiver)->digest_input.append(reinterpret_cast<const char*>(value->bytes.data()) + start, count);
}
jbyteArray new_bytes(JNIEnv*, jsize count) { auto n = make(); n->bytes.resize(count); return reinterpret_cast<jbyteArray>(n); }
void set_bytes(JNIEnv*, jbyteArray array, jsize start, jsize count, const jbyte* values) { std::copy(values, values + count, node(array)->bytes.begin() + start); }
void get_bytes(JNIEnv*, jbyteArray array, jsize start, jsize count, jbyte* values) { std::copy_n(node(array)->bytes.begin() + start, count, values); }
jsize array_length(JNIEnv*, jarray array) { return node(array)->bytes.empty() ? node(array)->children.size() : node(array)->bytes.size(); }
jobject array_element(JNIEnv*, jobjectArray array, jsize index) { return object(node(array)->children.at(index)); }
void policy(const std::string& path, const std::string& value) {
    if (!options) options = make();
    auto entry = make(); entry->fields = {{"path", path}, {"policy", value}, {"sha256", "stale"}, {"size", "-1"}};
    options->children.push_back(entry);
}
std::string read(const std::filesystem::path& path) { std::ifstream input(path, std::ios::binary); return {std::istreambuf_iterator<char>(input), {}}; }
void write(const std::filesystem::path& path, const std::string& value) { std::filesystem::create_directories(path.parent_path()); std::ofstream(path) << value; }
}
AAsset* AAssetManager_open(AAssetManager*, const char* path, int) {
    const auto found = assets.find(path); if (found == assets.end()) return nullptr;
    ++asset_reads; asset_bytes = found->second; asset_position = 0; return &asset;
}
int64_t AAsset_getLength(AAsset*) { return asset_bytes.size(); }
int64_t AAsset_getLength64(AAsset*) { return asset_bytes.size(); }
int AAsset_read(AAsset*, void* destination, size_t count) {
    const auto size = std::min(count, asset_bytes.size() - asset_position) - (short_read && count > 0 ? 1 : 0);
    std::memcpy(destination, asset_bytes.data() + asset_position, size); asset_position += size; return size;
}
void AAsset_close(AAsset*) {}
AAssetManager* AAssetManager_fromJava(JNIEnv*, jobject) { return &manager; }
namespace lemon::bootstrap {
RuntimePaths runtime_paths;
JavaVM* java_vm;
AAssetManager* asset_manager = &manager;
jobject asset_manager_object;
void log_line(const std::string&) {}
void log_error(const std::string& value) { error = value; }
void configure_crash_reporting() {}
}

int main(int argc, char** argv) {
    assert(argc == 2);
    using namespace lemon::bootstrap;
    JNINativeInterface table{};
    table.ExceptionCheck = check; table.ExceptionOccurred = occurred; table.ExceptionClear = clear; table.ExceptionDescribe = describe;
    table.PushLocalFrame = push; table.PopLocalFrame = pop; table.DeleteLocalRef = delete_ref;
    table.FindClass = find_class; table.GetObjectClass = object_class; table.GetMethodID = get_method; table.GetStaticMethodID = get_method;
    table.NewObjectV = new_object; table.CallObjectMethodV = object_call; table.CallStaticObjectMethodV = static_call;
    table.CallIntMethodV = int_call; table.CallVoidMethodV = void_call;
    table.GetStaticFieldID = get_field; table.GetFieldID = get_field; table.GetStaticObjectField = static_field; table.GetLongField = long_field;
    table.NewString = new_string; table.GetStringLength = length; table.GetStringChars = chars; table.ReleaseStringChars = release_chars;
    table.NewByteArray = new_bytes; table.SetByteArrayRegion = set_bytes; table.GetByteArrayRegion = get_bytes;
    table.GetArrayLength = array_length; table.GetObjectArrayElement = array_element;
    JNIEnv env{&table}; current_env = &env;
    JNIInvokeInterface vm_table{}; vm_table.GetEnv = get_env; JavaVM vm{&vm_table}; java_vm = &vm;
    root = make(); asset_manager_object = object(root);
    root->fields = {{"formatVersion", "8"}, {"loaderSha256", std::string(64,'a')}, {"dotnetSha256", std::string(64,'b')},
        {"interopSha256", std::string(64,'c')}, {"managedRuntimeIdentitySha256", std::string(64,'d')}, {"managedRuntimeBackend", "coreclr"},
        {"deploymentRevisionSha256", "stale"}, {"deploymentSha256", "stale"}, {"deploymentProfile", "unknown"}};
    assets["LemonLoader/payload.json"] = "fixture JSON supplied through fake JSONObject";
    PayloadDescriptor payload;
    assert(read_payload_descriptor(payload) && payload.deployment_valid && payload.deployment_files.empty());
    policy("Mods/refresh.dll", "refresh"); policy("UserData/config", "upgrade"); policy("Mods/enforce.dll", "enforce");
    assert(read_payload_descriptor(payload) && payload.deployment_valid && payload.deployment_files.size() == 3);
    assert(payload.deployment_files[0].hash.empty());
    std::cout << "PASS absent/stale deployment revision, hashes, sizes and profiles do not gate payload parsing\n";
    runtime_paths.package_name = "game";
    assert(deployment_update_stamp() == "apk-1234" && frames == 0);
    missing_update = true; assert(deployment_update_stamp().empty() && !pending && frames == 0); missing_update = false;
    std::cout << "PASS package update stamp and unavailable-token fallback\n";
    const std::filesystem::path base(argv[1]);
    assets["LemonLoader/deployment/Mods/new.dll"] = "seed-v1";
    assets["LemonLoader/deployment/Mods/refresh.dll"] = "refresh-v1";
    assets["LemonLoader/deployment/Mods/enforce.dll"] = "enforce-v1";
    assets["LemonLoader/deployment/UserData/config"] = "config-v1";
    payload.deployment_stamp = "apk-1234";
    assert(deploy_assets_if_changed(base, payload));
    assert(read(base / "Mods/new.dll") == "seed-v1" && read(base / "Mods/refresh.dll") == "refresh-v1");
    std::cout << "PASS actual APK files install without generated inventory and retain policy overrides\n";
    write(base / "Mods/new.dll", "user seed"); write(base / "Mods/refresh.dll", "user refresh");
    write(base / "UserData/config", "user config");
    auto lists = asset_lists; auto opens = asset_reads; auto hash_count = hashes;
    assert(deploy_assets_if_changed(base, payload));
    assert(asset_lists == lists && asset_reads == opens && hashes == hash_count + 1); // Explicit enforce only.
    write(base / "Mods/enforce.dll", "user enforce");
    assert(deploy_assets_if_changed(base, payload) && read(base / "Mods/enforce.dll") == "enforce-v1");
    std::cout << "PASS unchanged package preserves user edits without APK scans; enforce remains explicit\n";
    failed_list = true;
    payload.deployment_stamp = "apk-list-failure";
    bool list_failed = false;
    try { deploy_assets_if_changed(base, payload); }
    catch (const std::runtime_error&) { list_failed = true; }
    assert(list_failed && read(base / "Mods/refresh.dll") == "user refresh");
    assert(read(base / ".lemonloader-deployment-state/.revision") == "apk-1234\n");
    failed_list = false;
    std::cout << "PASS asset listing failure retains deployed files and the previous update token\n";
    assets.erase("LemonLoader/deployment/Mods/refresh.dll");
    assets["LemonLoader/deployment/Mods/added.dll"] = "added outside Patcher";
    assets["LemonLoader/deployment/UserData/config"] = "config-v2";
    payload.deployment_stamp = "apk-1235";
    assert(deploy_assets_if_changed(base, payload));
    assert(!std::filesystem::exists(base / "Mods/refresh.dll") && read(base / "Mods/added.dll") == "added outside Patcher");
    assert(read(base / "UserData/config") == "user config" && read(base / "Mods/new.dll") == "user seed");
    std::cout << "PASS manual asset add/delete ignores stale entries and upgrade protects user modifications\n";
    options = nullptr; assert(read_payload_descriptor(payload) && payload.deployment_valid);
    payload.deployment_stamp = "apk-1236"; assert(deploy_assets_if_changed(base, payload));
    lists = asset_lists; opens = asset_reads; hash_count = hashes;
    std::filesystem::remove(base / "Mods/new.dll");
    assert(deploy_assets_if_changed(base, payload));
    assert(asset_lists == lists && asset_reads == opens && hashes == hash_count);
    assert(!std::filesystem::exists(base / "Mods/new.dll"));
    std::cout << "PASS default seed-on-update path performs no regular content or asset scan\n";
    policy("../escape", "seed"); assert(read_payload_descriptor(payload) && !payload.deployment_valid);
    options = nullptr; policy("Mods/a", "invalid"); assert(read_payload_descriptor(payload) && !payload.deployment_valid);
    options = nullptr; policy("Mods/a", "seed"); policy("Mods/a", "seed"); assert(read_payload_descriptor(payload) && !payload.deployment_valid);
    std::cout << "PASS unsafe paths, unknown policies and duplicate overrides disable optional deployment only\n";
    options = nullptr; policy("Mods/a", "seed"); policy("Mods/a/b", "seed"); assert(read_payload_descriptor(payload) && !payload.deployment_valid);
    options = nullptr; assert(read_payload_descriptor(payload)); payload.deployment_stamp = "apk-1237";
    assets["LemonLoader/deployment/Mods/new.dll"] = "reseed";
    std::filesystem::create_directories(base / "Mods/new.dll.lemon-deploy.tmp");
    write(base / "Mods/new.dll.lemon-deploy.tmp/keep", "obstruction");
    assert(!deploy_assets_if_changed(base, payload));
    assert(read(base / ".lemonloader-deployment-state/.revision") == "apk-1236\n");
    assert(!std::filesystem::exists(base / "Mods/new.dll"));
    std::cout << "PASS failed deployment preserves prior state and does not publish incomplete files\n";
    assets["LemonLoader/runtime/loader/net6/Host.dll"] = "host";
    assets["LemonLoader/runtime/loader/Dependencies/Helper.dll"] = "dependency";
    assets["LemonLoader/runtime/interop/Game.dll"] = "interop";
    assets["LemonLoader/runtime/dotnet/runtime-identity.json"] = "runtime identity";
    runtime_paths.base_directory = (base / "integration/external").string();
    runtime_paths.internal_data_directory = (base / "integration/internal").string();
    runtime_paths.dotnet_directory = (base / "integration/internal/dotnet").string();
    options = nullptr; policy("../unsafe", "seed");
    runtime_paths.loader_disabled = false;
    hash_count = hashes;
    assert(extract_runtime_assets() && runtime_paths.loader_disabled && !pending && frames == 0);
    assert(hashes == hash_count); // No identity or runtime-tree hashing.
    assert(read(base / "integration/external/MelonLoader/net6/Host.dll") == "host");
    std::cout << "PASS full runtime extraction isolates invalid optional deployment before hooks\n";
    options = nullptr; runtime_paths.loader_disabled = false;
    std::filesystem::create_directories(base / "integration/external/Mods/new.dll.lemon-deploy.tmp");
    write(base / "integration/external/Mods/new.dll.lemon-deploy.tmp/keep", "blocked");
    assert(extract_runtime_assets() && runtime_paths.loader_disabled);
    std::cout << "PASS full runtime extraction isolates deployment transaction failure\n";
    root->fields = {{"runtimeRid", "linux-bionic-arm64"}};
    assert(read_payload_descriptor(payload) && payload.runtime_rid == "linux-bionic-arm64");
    root->fields["runtimeRid"] = "unsafe-rid"; assert(!read_payload_descriptor(payload));
    root->fields = {{"formatVersion", "7"}}; assert(!read_payload_descriptor(payload));
    root->fields.clear();
    assert(read_payload_descriptor(payload) && payload.runtime_rid == "android-arm64");
    root->fields["formatVersion"] = "9";
    assert(read_payload_descriptor(payload) && payload.runtime_rid == "android-arm64");
    root->fields.clear();
    short_read = true; assert(!read_payload_descriptor(payload)); short_read = false;
    assets.erase("LemonLoader/payload.json");
    assert(read_payload_descriptor(payload));
    std::cout << "PASS minimal/absent payload options accept no digests while rejecting unsupported layouts and RIDs\n";
    assets.erase("LemonLoader/runtime/dotnet/runtime-identity.json");
    assets["LemonLoader/runtime/dotnet/shared/Microsoft.NETCore.App/11/System.Private.CoreLib.dll"] = "runtime";
    runtime_paths.base_directory = (base / "minimal/external").string();
    runtime_paths.internal_data_directory = (base / "minimal/internal").string();
    runtime_paths.dotnet_directory = (base / "minimal/internal/dotnet").string();
    runtime_paths.loader_disabled = false;
    assert(extract_runtime_assets() && !runtime_paths.loader_disabled);
    assert(read(base / "minimal/external/MelonLoader/Il2CppAssemblies/Game.dll") == "interop");
    assert(!std::filesystem::exists(base / "minimal/internal/dotnet/runtime-identity.json"));
    lists = asset_lists; opens = asset_reads; hash_count = hashes;
    write(base / "minimal/external/MelonLoader/net6/Host.dll", "local host edit");
    assert(extract_runtime_assets() && asset_lists == lists && asset_reads == opens && hashes == hash_count);
    assert(read(base / "minimal/external/MelonLoader/net6/Host.dll") == "local host edit");
    std::cout << "PASS ordinary runtime installation needs neither payload/Interop manifests nor identity JSON and cached start performs no scans\n";
    ++update_time;
    assets["LemonLoader/runtime/loader/net6/Host.dll"] = "updated host";
    assets.erase("LemonLoader/runtime/interop/Game.dll");
    assets["LemonLoader/runtime/interop/NewGame.dll"] = "updated interop";
    assert(extract_runtime_assets());
    assert(read(base / "minimal/external/MelonLoader/net6/Host.dll") == "updated host");
    assert(!std::filesystem::exists(base / "minimal/external/MelonLoader/Il2CppAssemblies/Game.dll"));
    assert(read(base / "minimal/external/MelonLoader/Il2CppAssemblies/NewGame.dll") == "updated interop");
    std::cout << "PASS APK update replaces runtime trees and removes obsolete assemblies without regenerated metadata\n";
    missing_update = true;
    assert(extract_runtime_assets()); lists = asset_lists;
    assert(extract_runtime_assets() && asset_lists > lists);
    missing_update = false;
    std::cout << "PASS unavailable package token retries runtime extraction rather than caching an empty stamp\n";
    ++update_time;
    assets.erase("LemonLoader/runtime/loader/net6/Host.dll");
    assert(!extract_runtime_assets());
    assert(read(base / "minimal/external/MelonLoader/net6/Host.dll") == "updated host");
    std::cout << "PASS missing required runtime tree preserves the previous extraction and reports failure\n";
}
