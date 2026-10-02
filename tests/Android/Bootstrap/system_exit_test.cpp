#include <cassert>
#include <cstdarg>
#include <cstring>
#include <deque>
#include <iostream>
#include "system_exit.cpp"

namespace {
struct Exit { std::string process = "game"; jint reason = 5, pid = 42; jlong time = 2000; };
std::vector<Exit> exits;
std::deque<std::u16string> strings;
std::string trace, failure, last_error;
jint sdk = 31;
bool pending = false, trace_available = true;
int frames = 0, popped = 0, closes = 0, requests = 0, reads = 0;
size_t offset = 0, chunk_start = 0;
constexpr uintptr_t list_id = 10, stream_id = 11, array_id = 12, first_record = 100;
jobject object(uintptr_t id) { return reinterpret_cast<jobject>(id); }
Exit& record(jobject value) { return exits.at(reinterpret_cast<uintptr_t>(value) - first_record); }
jstring text(const std::string& value) {
    strings.emplace_back(value.begin(), value.end());
    return reinterpret_cast<jstring>(&strings.back());
}
const char* method_name(jmethodID method) { return reinterpret_cast<const char*>(method); }
jint push(JNIEnv*, jint count) {
    assert(count == 64);
    if (failure == "frame") { pending = true; return JNI_ERR; }
    ++frames;
    return JNI_OK;
}
jobject pop(JNIEnv*, jobject) { ++popped; return nullptr; }
jboolean exception_check(JNIEnv*) { return pending; }
jthrowable exception_occurred(JNIEnv*) { return nullptr; }
void exception_clear(JNIEnv*) { pending = false; }
void exception_describe(JNIEnv*) {}
void delete_local(JNIEnv*, jobject) {}
jclass find_class(JNIEnv*, const char* name) {
    if (failure == name) { pending = true; return nullptr; }
    if (sdk < 30) assert(std::strcmp(name, "android/os/Build$VERSION") == 0);
    return reinterpret_cast<jclass>(const_cast<char*>(name));
}
jmethodID method(JNIEnv*, jclass, const char* name, const char* signature) {
    if (failure == name) { pending = true; return nullptr; }
    if (!std::strcmp(name, "getHistoricalProcessExitReasons")) assert(!std::strcmp(signature, "(Ljava/lang/String;II)Ljava/util/List;"));
    if (!std::strcmp(name, "getTraceInputStream")) assert(!std::strcmp(signature, "()Ljava/io/InputStream;"));
    if (!std::strcmp(name, "read")) assert(!std::strcmp(signature, "([B)I"));
    return reinterpret_cast<jmethodID>(const_cast<char*>(name));
}
jfieldID field(JNIEnv*, jclass, const char* name, const char*) { return reinterpret_cast<jfieldID>(const_cast<char*>(name)); }
jint static_int(JNIEnv*, jclass, jfieldID) { return sdk; }
jobject static_object(JNIEnv*, jclass, jfieldID) { return object(1); }
jobject static_call(JNIEnv*, jclass, jmethodID method, va_list) {
    assert(!std::strcmp(method_name(method), "getProcessName"));
    return text("game");
}
jobject object_call(JNIEnv*, jobject receiver, jmethodID method, va_list args) {
    const std::string name = method_name(method);
    if (failure == "history" && name == "getHistoricalProcessExitReasons") { pending = true; return nullptr; }
    if (name == "getSystemService") return object(2);
    if (name == "getHistoricalProcessExitReasons") {
        const auto package = va_arg(args, jstring);
        assert(*reinterpret_cast<std::u16string*>(package) == u"game");
        assert(va_arg(args, jint) == 0 && va_arg(args, jint) == 8);
        ++requests;
        return object(list_id);
    }
    if (name == "get") return object(first_record + va_arg(args, jint));
    if (name == "getProcessName") return text(record(receiver).process);
    if (name == "getTraceInputStream") {
        if (failure == "trace-exception") { pending = true; return nullptr; }
        if (!trace_available) return nullptr;
        offset = 0;
        return object(stream_id);
    }
    assert(false);
    return nullptr;
}
jint int_call(JNIEnv*, jobject receiver, jmethodID method, va_list) {
    const std::string name = method_name(method);
    if (name == "size") return static_cast<jint>(exits.size());
    if (name == "getReason") return record(receiver).reason;
    if (name == "getPid") return record(receiver).pid;
    if (name == "getStatus") return 11;
    assert(name == "read" && receiver == object(stream_id));
    ++reads;
    if (failure == "read-exception" && reads > 1) { pending = true; return -1; }
    if (failure == "zero-read") return 0;
    if (failure == "oversized-read") return 4097;
    if (offset == trace.size()) return -1;
    chunk_start = offset;
    const auto count = std::min(size_t{4096}, trace.size() - offset);
    offset += count;
    return static_cast<jint>(count);
}
jlong long_call(JNIEnv*, jobject receiver, jmethodID method, va_list) {
    assert(!std::strcmp(method_name(method), "getTimestamp"));
    return record(receiver).time;
}
void void_call(JNIEnv*, jobject receiver, jmethodID method, va_list) {
    assert(receiver == object(stream_id) && !std::strcmp(method_name(method), "close"));
    ++closes;
    if (failure == "close-exception") pending = true;
}
jbyteArray new_array(JNIEnv*, jsize size) {
    assert(size == 4096);
    if (failure == "buffer") { pending = true; return nullptr; }
    return reinterpret_cast<jbyteArray>(array_id);
}
void region(JNIEnv*, jbyteArray, jsize start, jsize count, jbyte* destination) {
    assert(start == 0);
    std::memcpy(destination, trace.data() + chunk_start, count);
}
jstring new_string(JNIEnv*, const jchar* value, jsize length) {
    strings.emplace_back(reinterpret_cast<const char16_t*>(value), length);
    return reinterpret_cast<jstring>(&strings.back());
}
jsize string_length(JNIEnv*, jstring value) { return reinterpret_cast<std::u16string*>(value)->size(); }
const jchar* string_chars(JNIEnv*, jstring value, jboolean*) { return reinterpret_cast<const jchar*>(reinterpret_cast<std::u16string*>(value)->data()); }
void release_chars(JNIEnv*, jstring, const jchar*) {}
std::string read_file(const std::filesystem::path& path) {
    std::ifstream input(path, std::ios::binary);
    return {std::istreambuf_iterator<char>(input), {}};
}
void reset() {
    sdk = 31;
    exits = {Exit{}};
    trace = std::string("\0\1protobuf\xff", 11);
    failure.clear(); last_error.clear(); strings.clear();
    pending = false; trace_available = true;
    frames = popped = closes = requests = reads = 0;
}
}
namespace lemon::bootstrap {
RuntimePaths runtime_paths;
void log_error(const std::string& value) { last_error = value; }
}

int main(int argc, char** argv) {
    assert(argc == 2);
    const auto root = std::filesystem::path(argv[1]);
    JNINativeInterface table{};
    table.PushLocalFrame = push; table.PopLocalFrame = pop;
    table.ExceptionCheck = exception_check; table.ExceptionOccurred = exception_occurred;
    table.ExceptionClear = exception_clear; table.ExceptionDescribe = exception_describe;
    table.FindClass = find_class; table.GetMethodID = method; table.GetStaticMethodID = method;
    table.GetStaticFieldID = field; table.GetStaticIntField = static_int; table.GetStaticObjectField = static_object;
    table.CallStaticObjectMethodV = static_call; table.CallObjectMethodV = object_call;
    table.CallIntMethodV = int_call; table.CallLongMethodV = long_call; table.CallVoidMethodV = void_call;
    table.NewByteArray = new_array; table.GetByteArrayRegion = region;
    table.NewString = new_string; table.GetStringLength = string_length;
    table.GetStringChars = string_chars; table.ReleaseStringChars = release_chars; table.DeleteLocalRef = delete_local;
    JNIEnv env{&table};
    using namespace lemon::bootstrap;
    runtime_paths.package_name = "game";
    runtime_paths.base_directory = (root / "native").string();
    const auto reports = std::filesystem::path(runtime_paths.base_directory) / "MelonLoader/SystemExit";
    reset(); sdk = 26; recover_system_exit(&env);
    assert(requests == 0 && frames == popped && last_error.empty());
    std::cout << "PASS pre-API30 gating without newer class lookup\n";
    reset(); exits = {{"game:service"}, {"game", 10}, Exit{}};
    recover_system_exit(&env);
    assert(read_file(reports / "2000-42/trace.pb") == trace && closes == 1 && frames == popped && last_error.empty());
    assert(read_file(reports / "2000-42/exit.txt").find("reason=5\nstatus=11") != std::string::npos);
    recover_system_exit(&env);
    assert(closes == 1 && frames == popped);
    std::cout << "PASS own-process abnormal exit, exact binary trace, close and repeat reuse\n";
    reset(); sdk = 30; runtime_paths.base_directory = (root / "api30").string();
    recover_system_exit(&env);
    assert(closes == 0 && std::filesystem::exists(root / "api30/MelonLoader/SystemExit/2000-42/exit.txt"));
    std::cout << "PASS API30 native reason without tombstone access\n";
    reset(); exits[0].reason = 6; runtime_paths.base_directory = (root / "anr").string();
    recover_system_exit(&env);
    assert(read_file(root / "anr/MelonLoader/SystemExit/2000-42/trace.txt") == trace);
    std::cout << "PASS ANR trace stored separately from native protobuf\n";
    reset(); runtime_paths.base_directory = (root / "retry").string(); trace_available = false;
    recover_system_exit(&env);
    assert(std::filesystem::exists(root / "retry/MelonLoader/SystemExit/2000-42/exit.txt") && closes == 0);
    trace_available = true; recover_system_exit(&env);
    assert(read_file(root / "retry/MelonLoader/SystemExit/2000-42/trace.pb") == trace);
    std::cout << "PASS unavailable system trace retains summary and retries\n";
    for (const auto* mode : {"frame", "history", "getReason", "trace-exception", "buffer", "read-exception", "zero-read", "oversized-read"}) {
        reset(); failure = mode; trace.assign(5000, 'x'); runtime_paths.base_directory = (root / mode).string();
        recover_system_exit(&env);
        assert(!pending && !last_error.empty() && frames == popped);
        assert(!std::filesystem::exists(root / mode / "MelonLoader/SystemExit/2000-42/trace.pb"));
        assert(!std::filesystem::exists(root / mode / "MelonLoader/SystemExit/2000-42/trace.tmp"));
        if (failure == "buffer" || failure == "read-exception" || failure == "zero-read" || failure == "oversized-read") assert(closes == 1);
    }
    std::cout << "PASS JNI/read failures are nonfatal, clean pending exceptions, frames and partial output\n";
    reset(); trace.assign(trace_limit + 1, 'x'); runtime_paths.base_directory = (root / "large").string();
    recover_system_exit(&env);
    assert(closes == 1 && !pending && last_error.find("8 MiB") != std::string::npos);
    assert(!std::filesystem::exists(root / "large/MelonLoader/SystemExit/2000-42/trace.pb"));
    std::cout << "PASS oversized traces rejected without publishing truncated protobuf\n";
    reset(); trace.clear(); runtime_paths.base_directory = (root / "empty-trace").string();
    recover_system_exit(&env);
    assert(closes == 1 && last_error.empty() && !std::filesystem::exists(root / "empty-trace/MelonLoader/SystemExit/2000-42/trace.pb"));
    std::cout << "PASS empty stream closed without publishing an empty trace\n";
    reset(); failure = "close-exception"; runtime_paths.base_directory = (root / "close-failure").string();
    recover_system_exit(&env);
    assert(closes == 1 && !pending && frames == popped && !last_error.empty());
    assert(read_file(root / "close-failure/MelonLoader/SystemExit/2000-42/trace.pb") == trace);
    std::cout << "PASS trace close exception cleared without losing completed bytes\n";
    reset(); runtime_paths.base_directory = (root / "retention").string();
    const auto retention = root / "retention/MelonLoader/SystemExit";
    for (int index = 1000; index < 1010; ++index) {
        const auto directory = retention / (std::to_string(index) + "-1");
        std::filesystem::create_directories(directory);
        std::ofstream(directory / "exit.txt") << "prior";
        std::ofstream(directory / "trace.pb") << "prior";
    }
    recover_system_exit(&env);
    assert(std::distance(std::filesystem::directory_iterator(retention), std::filesystem::directory_iterator{}) == 8);
    assert(std::filesystem::exists(retention / "2000-42/trace.pb"));
    std::cout << "PASS report directories retained with an eight-event limit\n";
    std::filesystem::create_directories(retention / "0500-1");
    std::ofstream(retention / "0500-1/exit.txt") << "unrecognized event";
    std::ofstream(retention / "0500-1/user-file") << "preserve";
    std::filesystem::create_directory_symlink(root / "retry", retention / "0400-1");
    recover_system_exit(&env);
    assert(read_file(retention / "0500-1/user-file") == "preserve" && read_file(retention / "0500-1/exit.txt") == "unrecognized event");
    assert(std::filesystem::is_symlink(retention / "0400-1"));
    std::cout << "PASS retention leaves unrecognized content and directory symlinks untouched\n";
    reset(); runtime_paths.base_directory = (root / "symlink").string();
    std::filesystem::create_directories(root / "symlink/MelonLoader");
    std::filesystem::create_directory_symlink(retention, root / "symlink/MelonLoader/SystemExit");
    recover_system_exit(&env);
    assert(!last_error.empty() && frames == popped);
    std::cout << "PASS report storage symlink rejected\n";
    reset(); runtime_paths.base_directory = (root / "blocked").string();
    std::filesystem::create_directories(root / "blocked/MelonLoader");
    std::ofstream(root / "blocked/MelonLoader/SystemExit") << "preserve obstruction";
    recover_system_exit(&env);
    assert(!last_error.empty() && frames == popped && read_file(root / "blocked/MelonLoader/SystemExit") == "preserve obstruction");
    std::cout << "PASS inaccessible storage reports error without replacing unrelated content\n";
}
