#include "state.hpp"
#include "jni_utils.hpp"

#include <algorithm>
#include <array>
#include <filesystem>
#include <fstream>
#include <vector>

namespace lemon::bootstrap {
namespace {

constexpr size_t trace_limit = 8 * 1024 * 1024;
constexpr size_t retained_exits = 8;

void checked(JNIEnv* env, const char* operation) {
    if (clear_java_exception(env, operation)) throw std::runtime_error(operation);
}

struct LocalFrame {
    JNIEnv* env;
    explicit LocalFrame(JNIEnv* value) : env(value) {
        const auto status = env->PushLocalFrame(64);
        checked(env, "prepare system exit JNI frame");
        if (status != JNI_OK) throw std::runtime_error("Cannot prepare system exit JNI frame");
    }
    ~LocalFrame() { env->PopLocalFrame(nullptr); }
};

struct TraceStream {
    JNIEnv* env;
    jobject stream;
    jmethodID close;
    ~TraceStream() noexcept {
        env->CallVoidMethod(stream, close);
        try { clear_java_exception(env, "close system exit trace"); }
        catch (...) { if (env->ExceptionCheck()) env->ExceptionClear(); }
    }
};

bool event_name(const std::string& name) {
    const auto dash = name.find('-');
    return dash != std::string::npos && dash > 0 && dash + 1 < name.size() &&
        name.find('-', dash + 1) == std::string::npos &&
        std::all_of(name.begin(), name.end(), [](char ch) { return ch == '-' || (ch >= '0' && ch <= '9'); });
}

void prune_exits(const std::filesystem::path& root, const std::filesystem::path& current) {
    std::vector<std::filesystem::path> events;
    for (const auto& entry : std::filesystem::directory_iterator(root)) {
        if (entry.is_symlink() || !entry.is_directory() || !event_name(entry.path().filename().string())) continue;
        bool owned = std::filesystem::is_regular_file(std::filesystem::symlink_status(entry.path() / "exit.txt"));
        for (const auto& file : std::filesystem::directory_iterator(entry.path())) {
            const auto name = file.path().filename().string();
            if (file.is_symlink() || !file.is_regular_file() ||
                (name != "exit.txt" && name != "exit.tmp" && name != "trace.pb" && name != "trace.txt" && name != "trace.tmp"))
                owned = false;
        }
        if (owned) events.push_back(entry.path());
    }
    std::sort(events.begin(), events.end());
    auto count = events.size();
    for (const auto& event : events) {
        if (count <= retained_exits) break;
        if (event == current) continue;
        for (const char* name : {"exit.txt", "exit.tmp", "trace.pb", "trace.txt", "trace.tmp"}) {
            const auto path = event / name;
            if (std::filesystem::is_regular_file(std::filesystem::symlink_status(path)))
                std::filesystem::remove(path);
        }
        std::error_code error;
        if (std::filesystem::remove(event, error)) {
            --count;
        }
    }
}

void save_trace(JNIEnv* env, jobject record, jmethodID get_trace,
                const std::filesystem::path& directory, const char* name) {
    const auto destination = directory / name;
    if (std::filesystem::is_symlink(std::filesystem::symlink_status(destination)))
        throw std::runtime_error("System exit trace destination is a symlink");
    if (std::filesystem::is_regular_file(destination) && std::filesystem::file_size(destination) > 0) return;
    const auto stream_class = env->FindClass("java/io/InputStream");
    checked(env, "find system exit InputStream");
    const auto close = required_method(env, stream_class, "close", "()V");
    const auto read = required_method(env, stream_class, "read", "([B)I");
    auto stream = checked_object_call(env, record, get_trace);
    if (!stream) return;
    TraceStream guard{env, stream, close};
    auto bytes = env->NewByteArray(4096);
    checked(env, "allocate system exit trace buffer");
    if (!bytes) throw std::runtime_error("Cannot allocate system exit trace buffer");
    const auto temporary = directory / "trace.tmp";
    if (std::filesystem::is_symlink(std::filesystem::symlink_status(temporary)))
        throw std::runtime_error("System exit trace temporary path is a symlink");
    try {
        std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
        if (!output) throw std::runtime_error("Cannot open system exit trace output");
        std::array<jbyte, 4096> buffer{};
        size_t total = 0;
        for (;;) {
            const auto count = env->CallIntMethod(stream, read, bytes);
            checked(env, "read system exit trace");
            if (count == -1) break;
            if (count <= 0 || count > static_cast<jint>(buffer.size()))
                throw std::runtime_error("Invalid system exit trace read length");
            if (static_cast<size_t>(count) > trace_limit - total)
                throw std::runtime_error("System exit trace exceeds the 8 MiB limit");
            env->GetByteArrayRegion(bytes, 0, count, buffer.data());
            checked(env, "copy system exit trace bytes");
            output.write(reinterpret_cast<const char*>(buffer.data()), count);
            if (!output) throw std::runtime_error("Cannot write system exit trace");
            total += count;
        }
        output.close();
        if (!output) throw std::runtime_error("Cannot finish system exit trace");
        if (total == 0) std::filesystem::remove(temporary);
        else std::filesystem::rename(temporary, destination);
    } catch (...) {
        std::error_code ignored;
        std::filesystem::remove(temporary, ignored);
        throw;
    }
}

void recover(JNIEnv* env) {
    LocalFrame frame(env);
    auto version = env->FindClass("android/os/Build$VERSION");
    checked(env, "find Android version for exit recovery");
    auto sdk_field = env->GetStaticFieldID(version, "SDK_INT", "I");
    checked(env, "resolve Android version for exit recovery");
    if (!sdk_field) throw std::runtime_error("Cannot resolve Android API level");
    const auto sdk = env->GetStaticIntField(version, sdk_field);
    checked(env, "read Android version for exit recovery");
    if (sdk < 30) return;

    auto process_class = env->FindClass("android/app/Application");
    checked(env, "find Android Application");
    auto process_method = required_static_method(env, process_class, "getProcessName", "()Ljava/lang/String;");
    auto process_value = static_cast<jstring>(checked_static_object_call(env, process_class, process_method));
    const auto process_name = java_string(env, process_value);
    if (process_name.empty()) return;

    auto player = env->FindClass("com/unity3d/player/UnityPlayer");
    checked(env, "find Unity activity for exit recovery");
    auto activity_field = env->GetStaticFieldID(player, "currentActivity", "Landroid/app/Activity;");
    checked(env, "resolve Unity activity for exit recovery");
    if (!activity_field) throw std::runtime_error("Cannot resolve Unity activity");
    auto activity = env->GetStaticObjectField(player, activity_field);
    checked(env, "read Unity activity for exit recovery");
    if (!activity) return;
    auto context = env->FindClass("android/content/Context");
    checked(env, "find Android Context");
    auto service_method = required_method(env, context, "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;");
    auto service_name = new_java_string(env, "activity");
    auto manager = checked_object_call(env, activity, service_method, service_name);
    if (!manager) return;
    auto manager_class = env->FindClass("android/app/ActivityManager");
    checked(env, "find Android ActivityManager");
    auto history_method = required_method(env, manager_class, "getHistoricalProcessExitReasons", "(Ljava/lang/String;II)Ljava/util/List;");
    auto package = new_java_string(env, runtime_paths.package_name);
    auto history = checked_object_call(env, manager, history_method, package, 0, static_cast<jint>(retained_exits));
    if (!history) return;
    auto list = env->FindClass("java/util/List");
    checked(env, "find system exit List");
    auto size_method = required_method(env, list, "size", "()I");
    auto get_method = required_method(env, list, "get", "(I)Ljava/lang/Object;");
    const auto size = env->CallIntMethod(history, size_method);
    checked(env, "read system exit List size");
    auto exit_class = env->FindClass("android/app/ApplicationExitInfo");
    checked(env, "find ApplicationExitInfo");
    auto name_method = required_method(env, exit_class, "getProcessName", "()Ljava/lang/String;");
    auto reason_method = required_method(env, exit_class, "getReason", "()I");
    auto time_method = required_method(env, exit_class, "getTimestamp", "()J");
    auto pid_method = required_method(env, exit_class, "getPid", "()I");
    auto status_method = required_method(env, exit_class, "getStatus", "()I");
    auto trace_method = required_method(env, exit_class, "getTraceInputStream", "()Ljava/io/InputStream;");
    for (jint index = 0; index < std::min(size, static_cast<jint>(retained_exits)); ++index) {
        auto record = checked_object_call(env, history, get_method, index);
        if (!record) continue;
        auto name_value = static_cast<jstring>(checked_object_call(env, record, name_method));
        const auto name = java_string(env, name_value);
        env->DeleteLocalRef(name_value);
        const auto reason = env->CallIntMethod(record, reason_method);
        checked(env, "read system exit reason");
        if (name != process_name || reason < 2 || reason > 7) {
            env->DeleteLocalRef(record);
            continue;
        }
        const auto timestamp = env->CallLongMethod(record, time_method);
        checked(env, "read system exit timestamp");
        const auto pid = env->CallIntMethod(record, pid_method);
        checked(env, "read system exit PID");
        const auto status = env->CallIntMethod(record, status_method);
        checked(env, "read system exit status");
        if (timestamp <= 0 || pid <= 0) return;
        const auto root = std::filesystem::path(runtime_paths.base_directory) / "MelonLoader" / "SystemExit";
        const auto directory = root / (std::to_string(timestamp) + '-' + std::to_string(pid));
        if (std::filesystem::is_symlink(std::filesystem::symlink_status(root)) ||
            std::filesystem::is_symlink(std::filesystem::symlink_status(directory)))
            throw std::runtime_error("System exit storage is a symlink");
        std::filesystem::create_directories(directory);
        const auto summary = directory / "exit.txt";
        if (std::filesystem::is_symlink(std::filesystem::symlink_status(summary)))
            throw std::runtime_error("System exit summary is a symlink");
        if (!std::filesystem::exists(summary) || std::filesystem::file_size(summary) == 0) {
            const auto temporary = directory / "exit.tmp";
            if (std::filesystem::is_symlink(std::filesystem::symlink_status(temporary)))
                throw std::runtime_error("System exit summary temporary path is a symlink");
            try {
                std::ofstream output(temporary, std::ios::binary);
                output << "timestamp_ms=" << timestamp << "\npid=" << pid << "\nreason=" << reason << "\nstatus=" << status << '\n';
                output.close();
                if (!output) throw std::runtime_error("Cannot save system exit summary");
                std::filesystem::rename(temporary, summary);
            } catch (...) {
                std::error_code ignored;
                std::filesystem::remove(temporary, ignored);
                throw;
            }
        }
        prune_exits(root, directory);
        if (reason == 6 || (reason == 5 && sdk >= 31))
            save_trace(env, record, trace_method, directory, reason == 5 ? "trace.pb" : "trace.txt");
        return;
    }
}
}  // namespace

void recover_system_exit(JNIEnv* env) noexcept {
    try {
        if (!runtime_paths.base_directory.empty()) recover(env);
    } catch (const std::exception& error) {
        if (env->ExceptionCheck()) env->ExceptionClear();
        try { log_error(std::string("Could not retain Android system exit evidence: ") + error.what()); } catch (...) {}
    } catch (...) {
        if (env->ExceptionCheck()) env->ExceptionClear();
        try { log_error("Could not retain Android system exit evidence"); } catch (...) {}
    }
}
}  // namespace lemon::bootstrap
