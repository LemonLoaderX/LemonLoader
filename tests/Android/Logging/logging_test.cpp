#include "lemon_bootstrap.h"
#include "state.hpp"
#include <android/log.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <vector>

namespace lemon::bootstrap {
RuntimePaths runtime_paths;
JavaVM* java_vm = nullptr;
}

struct Record { int priority; std::string text; };
std::vector<Record> records;
extern "C" int __android_log_write(int priority, const char*, const char* text) {
    records.push_back({priority, text});
    return 0;
}
extern "C" int DobbyHook(void*, void*, void**) { return -1; }

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    lemon::bootstrap::runtime_paths.base_directory = argv[1];
    lemon::bootstrap::reset_latest_log();
    lemon::bootstrap::log_line("bootstrap startup");
    lemon::bootstrap::configure_logging(10, false);
    int failures = 0;
    const auto check = [&](const char* name, bool success) {
        std::cout << (success ? "PASS " : "FAIL ") << name << '\n';
        if (!success) ++failures;
    };
    const auto ptr = [](const char16_t* value) { return reinterpret_cast<const uint16_t*>(value); };
    const std::u16string colored = u"\x1b[31mhello\x1b[0m";
    LogMsg(nullptr, ptr(colored.c_str()), colored.size(), nullptr, ptr(u"Mod"), 3, ptr(u"hello"), 5);
    check("logcat receives stripped message", records.back().text == "[Mod] hello");
    LogMsg(nullptr, ptr(u"fallback"), 8, nullptr, nullptr, 0, nullptr, 0);
    check("null stripped message preserves original", records.back().text == "fallback");
    LogMsg(nullptr, ptr(colored.c_str()), colored.size(), nullptr, nullptr, 0, ptr(u""), 0);
    check("empty stripped message remains empty", records.back().text.empty());
    LogError(ptr(u"warning"), 7, ptr(u"Mod"), 3, 1);
    check("warning priority and section", records.back().priority == ANDROID_LOG_WARN && records.back().text == "[WARNING] [Mod] warning");
    LogError(ptr(u"error"), 5, nullptr, 0, 0);
    check("error priority", records.back().priority == ANDROID_LOG_ERROR);
    auto before = records.size();
    lemon::bootstrap::log_error("native error");
    check("native error emitted exactly once at ERROR", records.size() == before + 1 && records.back().priority == ANDROID_LOG_ERROR);
    const auto read = [](const std::filesystem::path& path) {
        std::ifstream input(path, std::ios::binary);
        return std::string(std::istreambuf_iterator<char>(input), {});
    };
    const auto root = std::filesystem::path(argv[1]) / "MelonLoader";
    const auto latest = read(root / "Latest.log");
    check("file contains clean text and severities", latest.find('\x1b') == std::string::npos && latest.find("[Mod] hello") != std::string::npos && latest.find("[WARNING] [Mod] warning") != std::string::npos && latest.find("[ERROR] error") != std::string::npos);
    for (const auto& file : std::filesystem::directory_iterator(root / "Logs"))
        check("history matches latest", read(file.path()) == latest);
    return failures == 0 ? 0 : 1;
}
