#pragma once
#include <android/log.h>
#include <cstdio>
#include <exception>
#include <string>
#include <utility>

namespace lemon::bootstrap {
void log_error(const std::string& message);

inline void report_native_exception(const char* context, const char* detail) noexcept {
    char message[1536]{};
    std::snprintf(message, sizeof(message), "%s: %s", context, detail ? detail : "unknown native exception");
    try { log_error(message); }
    catch (...) { __android_log_write(ANDROID_LOG_ERROR, "LemonLoader", message); }
}

template<typename Result, typename Action>
Result native_boundary(const char* context, Result failure, Action&& action) noexcept {
    try { return std::forward<Action>(action)(); }
    catch (const std::exception& exception) { report_native_exception(context, exception.what()); }
    catch (...) { report_native_exception(context, nullptr); }
    return failure;
}
template<typename Action>
void native_boundary(const char* context, Action&& action) noexcept {
    native_boundary(context, false, [&]() { std::forward<Action>(action)(); return true; });
}
}  // namespace lemon::bootstrap
