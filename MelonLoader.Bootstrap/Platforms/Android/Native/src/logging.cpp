#include "lemon_bootstrap.h"
#include "state.hpp"

#include <android/log.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <mutex>
#include <sstream>
#include <vector>

extern "C" int DobbyHook(void* target, void* replacement, void** original);

namespace lemon::bootstrap {
namespace {

std::mutex log_mutex;
std::ofstream latest_log;
std::ofstream historical_log;
std::atomic<bool> capture_player_logs{false};
std::once_flag player_log_hook_once;
uint32_t player_log_hook_count = 0;
thread_local bool forwarding_player_log = false;

using AndroidLogWriteFn = int (*)(int, const char*, const char*);
using AndroidLogVPrintFn = int (*)(int, const char*, const char*, va_list);
using AndroidLogPrintFn = int (*)(int, const char*, const char*, ...);

AndroidLogWriteFn original_log_write = nullptr;
AndroidLogVPrintFn original_log_vprint = nullptr;
AndroidLogPrintFn original_log_print = nullptr;

void append_utf8(std::string& output, uint32_t code_point) {
    if (code_point <= 0x7f) {
        output.push_back(static_cast<char>(code_point));
    } else if (code_point <= 0x7ff) {
        output.push_back(static_cast<char>(0xc0 | (code_point >> 6)));
        output.push_back(static_cast<char>(0x80 | (code_point & 0x3f)));
    } else if (code_point <= 0xffff) {
        output.push_back(static_cast<char>(0xe0 | (code_point >> 12)));
        output.push_back(static_cast<char>(0x80 | ((code_point >> 6) & 0x3f)));
        output.push_back(static_cast<char>(0x80 | (code_point & 0x3f)));
    } else {
        output.push_back(static_cast<char>(0xf0 | (code_point >> 18)));
        output.push_back(static_cast<char>(0x80 | ((code_point >> 12) & 0x3f)));
        output.push_back(static_cast<char>(0x80 | ((code_point >> 6) & 0x3f)));
        output.push_back(static_cast<char>(0x80 | (code_point & 0x3f)));
    }
}

std::string timestamp() {
    const auto now = std::chrono::system_clock::now();
    const std::time_t value = std::chrono::system_clock::to_time_t(now);
    std::tm local{};
    localtime_r(&value, &local);
    std::ostringstream output;
    output << '[' << std::put_time(&local, "%H:%M:%S") << "] ";
    return output.str();
}

std::string historical_log_name() {
    const auto now = std::chrono::system_clock::now();
    const std::time_t value = std::chrono::system_clock::to_time_t(now);
    std::tm local{};
    localtime_r(&value, &local);
    std::ostringstream output;
    output << std::put_time(&local, "%y-%m-%d_%H-%M-%S") << ".log";
    return output.str();
}

std::filesystem::path melonloader_directory() {
    return std::filesystem::path(runtime_paths.base_directory) / "MelonLoader";
}

void capture_unity_log(const char* tag, const char* message) {
    if (!capture_player_logs.load(std::memory_order_relaxed) ||
        tag == nullptr || message == nullptr || std::strcmp(tag, "Unity") != 0) {
        return;
    }

    std::string text(message);
    while (!text.empty() && (text.back() == '\r' || text.back() == '\n')) {
        text.pop_back();
    }
    if (text.empty()) {
        return;
    }
    log_line("[UNITY] " + text);
}

int hook_log_write(int priority, const char* tag, const char* text) {
    const bool outermost = !forwarding_player_log;
    if (outermost) {
        forwarding_player_log = true;
        capture_unity_log(tag, text);
    }
    const int result = original_log_write == nullptr
        ? 0
        : original_log_write(priority, tag, text);
    if (outermost) {
        forwarding_player_log = false;
    }
    return result;
}

void capture_formatted_unity_log(const char* tag, const char* format, va_list args) {
    if (!capture_player_logs.load(std::memory_order_relaxed) ||
        tag == nullptr || format == nullptr || std::strcmp(tag, "Unity") != 0) {
        return;
    }
    va_list copy;
    va_copy(copy, args);
    const int length = std::vsnprintf(nullptr, 0, format, copy);
    va_end(copy);
    if (length < 0) {
        return;
    }
    std::vector<char> buffer(static_cast<size_t>(length) + 1);
    va_copy(copy, args);
    std::vsnprintf(buffer.data(), buffer.size(), format, copy);
    va_end(copy);
    capture_unity_log(tag, buffer.data());
}

int hook_log_vprint(int priority, const char* tag, const char* format, va_list args) {
    const bool outermost = !forwarding_player_log;
    if (outermost) {
        forwarding_player_log = true;
        capture_formatted_unity_log(tag, format, args);
    }
    const int result = original_log_vprint == nullptr
        ? 0
        : original_log_vprint(priority, tag, format, args);
    if (outermost) {
        forwarding_player_log = false;
    }
    return result;
}

int hook_log_print(int priority, const char* tag, const char* format, ...) {
    va_list args;
    va_start(args, format);
    const bool outermost = !forwarding_player_log;
    if (outermost) {
        forwarding_player_log = true;
        capture_formatted_unity_log(tag, format, args);
    }
    const int result = original_log_vprint == nullptr
        ? 0
        : original_log_vprint(priority, tag, format, args);
    if (outermost) {
        forwarding_player_log = false;
    }
    va_end(args);
    return result;
}

bool install_log_hook(void* target, void* replacement, void** original) {
    if (target == nullptr) {
        return false;
    }
    *original = nullptr;
    return DobbyHook(target, replacement, original) == 0 && *original != nullptr;
}

uint32_t install_player_log_hooks() {
    std::call_once(player_log_hook_once, []() {
        void* write = dlsym(RTLD_DEFAULT, "__android_log_write");
        void* vprint = dlsym(RTLD_DEFAULT, "__android_log_vprint");
        void* print = dlsym(RTLD_DEFAULT, "__android_log_print");
        if (install_log_hook(
                write,
                reinterpret_cast<void*>(&hook_log_write),
                reinterpret_cast<void**>(&original_log_write))) {
            ++player_log_hook_count;
        }
        if (install_log_hook(
                vprint,
                reinterpret_cast<void*>(&hook_log_vprint),
                reinterpret_cast<void**>(&original_log_vprint))) {
            ++player_log_hook_count;
        }
        if (print != nullptr && original_log_vprint != nullptr) {
            if (install_log_hook(
                    print,
                    reinterpret_cast<void*>(&hook_log_print),
                    reinterpret_cast<void**>(&original_log_print))) {
                ++player_log_hook_count;
            }
        }
    });
    return player_log_hook_count;
}

}  // namespace

std::string utf16_to_utf8(const uint16_t* value, int length) {
    if (value == nullptr || length <= 0) {
        return {};
    }

    std::string output;
    output.reserve(static_cast<size_t>(length));
    for (int index = 0; index < length; ++index) {
        uint32_t code_point = value[index];
        if (code_point >= 0xd800 && code_point <= 0xdbff && index + 1 < length) {
            const uint32_t low = value[index + 1];
            if (low >= 0xdc00 && low <= 0xdfff) {
                code_point = 0x10000 + ((code_point - 0xd800) << 10) + (low - 0xdc00);
                ++index;
            }
        }
        append_utf8(output, code_point);
    }
    return output;
}

static void log_line(const std::string& message, int priority) {
    std::lock_guard<std::mutex> lock(log_mutex);
    __android_log_write(priority, "LemonLoader", message.c_str());

    if (runtime_paths.base_directory.empty()) {
        return;
    }

    const std::filesystem::path log_directory = melonloader_directory();
    std::error_code error;
    if (!latest_log.is_open()) {
        std::filesystem::create_directories(log_directory, error);
        latest_log.open(log_directory / "Latest.log", std::ios::app | std::ios::binary);
    }
    const std::string line = timestamp() + message + '\n';
    if (latest_log) {
        latest_log << line;
        latest_log.flush();
    }
    if (historical_log) {
        historical_log << line;
        historical_log.flush();
    }
}

void log_line(const std::string& message) {
    log_line(message, ANDROID_LOG_INFO);
}

void log_error(const std::string& message) {
    log_line("[ERROR] " + message, ANDROID_LOG_ERROR);
}

void reset_latest_log() {
    if (runtime_paths.base_directory.empty()) {
        return;
    }
    std::lock_guard<std::mutex> lock(log_mutex);
    latest_log.close();
    historical_log.close();
    const std::filesystem::path log_path = melonloader_directory() / "Latest.log";
    std::error_code error;
    std::filesystem::create_directories(log_path.parent_path(), error);
    latest_log.open(log_path, std::ios::binary | std::ios::trunc);
}

void configure_logging(uint32_t max_logs, bool should_capture_player_logs) {
    capture_player_logs.store(false, std::memory_order_relaxed);
    std::string history_warning;
    bool history_directory_ready = true;
    {
        std::lock_guard<std::mutex> lock(log_mutex);
        historical_log.close();
        if (runtime_paths.base_directory.empty()) {
            return;
        }

        const std::filesystem::path loader_directory = melonloader_directory();
        const std::filesystem::path logs_directory = loader_directory / "Logs";
        std::error_code error;
        std::filesystem::create_directories(logs_directory, error);
        if (error) {
            history_directory_ready = false;
            history_warning =
                "Could not create historical log directory: " + error.message();
        }

        if (history_directory_ready && max_logs > 0) {
            std::vector<std::filesystem::directory_entry> logs;
            for (std::filesystem::directory_iterator iterator(logs_directory, error), end;
                 !error && iterator != end;
                 iterator.increment(error)) {
                std::error_code file_error;
                if (iterator->is_regular_file(file_error) &&
                    iterator->path().extension() == ".log") {
                    logs.push_back(*iterator);
                }
            }
            if (error) {
                history_warning =
                    "Could not enumerate historical logs: " + error.message();
            }
            std::sort(logs.begin(), logs.end(), [](const auto& left, const auto& right) {
                std::error_code left_error;
                std::error_code right_error;
                const auto left_time = left.last_write_time(left_error);
                const auto right_time = right.last_write_time(right_error);
                if (left_error || right_error) {
                    return left.path().filename() < right.path().filename();
                }
                return left_time < right_time;
            });
            while (logs.size() >= max_logs) {
                std::error_code remove_error;
                std::filesystem::remove(logs.front().path(), remove_error);
                if (remove_error && history_warning.empty()) {
                    history_warning =
                        "Could not remove old historical log " +
                        logs.front().path().filename().string() + ": " +
                        remove_error.message();
                }
                logs.erase(logs.begin());
            }
        }

        if (history_directory_ready) {
            const std::string base_name = historical_log_name();
            std::filesystem::path historical_path = logs_directory / base_name;
            for (uint32_t suffix = 1; std::filesystem::exists(historical_path, error); ++suffix) {
                const std::filesystem::path stem(base_name);
                historical_path = logs_directory /
                    (stem.stem().string() + '-' + std::to_string(suffix) + ".log");
            }
            historical_log.open(historical_path, std::ios::binary | std::ios::trunc);
            if (!historical_log) {
                history_warning = "Could not create the historical log file";
            }

            if (historical_log) {
                latest_log.flush();
                std::ifstream latest(loader_directory / "Latest.log", std::ios::binary);
                if (latest) {
                    historical_log << latest.rdbuf();
                    historical_log.flush();
                }
            }
        }
    }
    if (!history_warning.empty()) {
        log_line("[WARNING] " + history_warning);
    }
    if (should_capture_player_logs) {
        const uint32_t hook_count = install_player_log_hooks();
        capture_player_logs.store(hook_count > 0, std::memory_order_relaxed);
        if (hook_count == 0) {
            log_line("[WARNING] Could not install Android Unity player log hooks");
        } else {
            log_line(
                "Unity player log capture enabled with " +
                std::to_string(hook_count) + " Android liblog hook(s)");
        }
    }
}

}  // namespace lemon::bootstrap

extern "C" LEMON_EXPORT void ConfigureLogging(
    uint32_t max_logs,
    uint8_t capture_player_logs) {
    lemon::bootstrap::configure_logging(max_logs, capture_player_logs != 0);
}

extern "C" LEMON_EXPORT void LogMsg(
    const void*,
    const uint16_t* message,
    int message_length,
    const void*,
    const uint16_t* section,
    int section_length,
    const uint16_t* stripped_message,
    int stripped_message_length) {
    std::string text = stripped_message != nullptr
        ? lemon::bootstrap::utf16_to_utf8(stripped_message, stripped_message_length)
        : lemon::bootstrap::utf16_to_utf8(message, message_length);
    const std::string section_text =
        lemon::bootstrap::utf16_to_utf8(section, section_length);
    if (!section_text.empty()) {
        text = '[' + section_text + "] " + text;
    }
    lemon::bootstrap::log_line(text);
}

extern "C" LEMON_EXPORT void LogError(
    const uint16_t* message,
    int message_length,
    const uint16_t* section,
    int section_length,
    int warning) {
    std::string text = lemon::bootstrap::utf16_to_utf8(message, message_length);
    const std::string section_text =
        lemon::bootstrap::utf16_to_utf8(section, section_length);
    if (!section_text.empty()) {
        text = '[' + section_text + "] " + text;
    }
    lemon::bootstrap::log_line(
        std::string(warning ? "[WARNING] " : "[ERROR] ") + text,
        warning ? ANDROID_LOG_WARN : ANDROID_LOG_ERROR);
}

extern "C" LEMON_EXPORT void LogMelonInfo(
    const void*,
    const uint16_t* name,
    int name_length,
    const uint16_t* info,
    int info_length) {
    lemon::bootstrap::log_line(
        lemon::bootstrap::utf16_to_utf8(name, name_length) + ": " +
        lemon::bootstrap::utf16_to_utf8(info, info_length));
}

extern "C" LEMON_EXPORT uint8_t IsConsoleOpen() {
    return 0;
}

extern "C" LEMON_EXPORT JavaVM* GetJavaVM() {
    return lemon::bootstrap::java_vm;
}
