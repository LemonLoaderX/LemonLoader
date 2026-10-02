#include "lemon_bootstrap.h"
#include "state.hpp"
#include <android/log.h>
#include <cstdlib>
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
    lemon::bootstrap::reset_latest_log();
    check("previous session survives reset", read(root / "Previous.log") == latest);
    check("new session starts empty", read(root / "Latest.log").empty());
    lemon::bootstrap::reset_latest_log();
    check("empty session does not replace previous evidence", read(root / "Previous.log") == latest);
    lemon::bootstrap::log_error("early startup failure");
    const auto early = read(root / "Latest.log");
    lemon::bootstrap::reset_latest_log();
    check("failure before history configuration survives next start", read(root / "Previous.log") == early);
    lemon::bootstrap::log_line("next startup");
    lemon::bootstrap::configure_logging(1, false);
    check("history retention does not prune previous session", read(root / "Previous.log") == early);
    check("history retention remains bounded", std::distance(std::filesystem::directory_iterator(root / "Logs"), std::filesystem::directory_iterator{}) == 1);
    std::filesystem::remove(root / "Previous.log");
    std::filesystem::create_directory(root / "Previous.log");
    std::ofstream(root / "Previous.log" / "keep") << "unrelated entry";
    const auto before_failure = read(root / "Latest.log");
    before = records.size();
    lemon::bootstrap::reset_latest_log();
    check("rotation failure preserves latest instead of truncating", read(root / "Latest.log").find(before_failure) == 0);
    check("rotation failure emits one actionable warning", records.size() == before + 1 && records.back().priority == ANDROID_LOG_WARN && records.back().text.find("Previous.log") != std::string::npos);
    check("rotation does not remove an obstructing directory", read(root / "Previous.log" / "keep") == "unrelated entry");
    lemon::bootstrap::log_line("continued after rotation failure");
    check("logging continues in append mode after rotation failure", read(root / "Latest.log").find("continued after rotation failure") != std::string::npos);
    const auto clear_crash_environment = [] {
        for (const char* prefix : {"DOTNET_", "COMPlus_"}) {
            for (const char* name : {"EnableCrashReport", "EnableCrashReportOnly", "CrashReportRootPath", "CrashReportMaxFileCount", "CrashReportBeforeSignalChaining"}) {
                unsetenv((std::string(prefix) + name).c_str());
            }
        }
    };
    const auto environment = [](const char* name) {
        const char* value = std::getenv(name);
        return value == nullptr ? std::string{} : std::string(value);
    };
    clear_crash_environment();
    const auto reports = root / ".dotnet" / "crash-reports";
    std::filesystem::create_directories(reports);
    std::ofstream(reports / "report-100-1.crashreport.json.tmp") << "older partial";
    std::ofstream(reports / "report-200-2.crashreport.json.tmp") << "newer partial";
    std::ofstream(reports / "report-300-3.crashreport.json.tmp");
    std::ofstream(reports / "report-400-4.crashreport.json") << "completed";
    std::ofstream(reports / "unrelated.tmp") << "unrelated";
    lemon::bootstrap::configure_crash_reporting();
    check("newest nonempty interrupted crash report survives runtime cleanup", read(root / "PreviousCrashReport.partial.json") == "newer partial" && !std::filesystem::exists(reports / "report-200-2.crashreport.json.tmp"));
    check("report recovery leaves completed and unrelated files alone", read(reports / "report-400-4.crashreport.json") == "completed" && read(reports / "unrelated.tmp") == "unrelated");
    std::filesystem::remove(reports / "report-100-1.crashreport.json.tmp");
    lemon::bootstrap::configure_crash_reporting();
    check("empty interrupted report does not overwrite prior evidence", read(root / "PreviousCrashReport.partial.json") == "newer partial");
    check("runtime crash reports enabled with bounded defaults", environment("DOTNET_EnableCrashReportOnly") == "1" && environment("DOTNET_CrashReportMaxFileCount") == "8" && environment("DOTNET_CrashReportBeforeSignalChaining") == "1");
    check("runtime crash report root shares the existing log directory", environment("DOTNET_CrashReportRootPath") == root.string());
    setenv("DOTNET_EnableCrashReportOnly", "0", 1);
    setenv("DOTNET_CrashReportMaxFileCount", "3", 1);
    setenv("DOTNET_CrashReportRootPath", "/custom/report/root", 1);
    setenv("DOTNET_CrashReportBeforeSignalChaining", "0", 1);
    lemon::bootstrap::configure_crash_reporting();
    check("explicit reporter configuration and opt-out are preserved", environment("DOTNET_EnableCrashReportOnly") == "0" && environment("DOTNET_CrashReportMaxFileCount") == "3" && environment("DOTNET_CrashReportRootPath") == "/custom/report/root" && environment("DOTNET_CrashReportBeforeSignalChaining") == "0");
    clear_crash_environment();
    setenv("COMPlus_EnableCrashReport", "0", 1);
    setenv("COMPlus_CrashReportRootPath", "/legacy/report/root", 1);
    lemon::bootstrap::configure_crash_reporting();
    check("legacy configuration is not shadowed by DOTNET defaults", std::getenv("DOTNET_EnableCrashReportOnly") == nullptr && std::getenv("DOTNET_CrashReportRootPath") == nullptr);
    clear_crash_environment();
    std::ofstream(root / "blocked-storage") << "not a directory";
    lemon::bootstrap::runtime_paths.base_directory = (root / "blocked-storage").string();
    before = records.size();
    lemon::bootstrap::configure_crash_reporting();
    check("unavailable crash storage is nonfatal and emits one warning", std::getenv("DOTNET_CrashReportRootPath") == nullptr && records.size() == before + 1 && records.back().priority == ANDROID_LOG_WARN);
    clear_crash_environment();
    return failures == 0 ? 0 : 1;
}
