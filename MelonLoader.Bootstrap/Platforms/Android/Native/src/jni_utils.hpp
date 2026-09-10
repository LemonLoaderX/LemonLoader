#pragma once
#include <jni.h>
#include <limits>
#include "utf.hpp"
#include "native_errors.hpp"

namespace lemon::bootstrap {

inline bool clear_java_exception(JNIEnv* env, const char* context) {
    if (!env->ExceptionCheck()) return false;
    jthrowable exception = env->ExceptionOccurred();
    // Describe the original pending exception before clearing it: toString()
    // below supplies Latest.log context, but cannot replace the Java stack in logcat.
    env->ExceptionDescribe();
    env->ExceptionClear();
    jclass type = exception ? env->GetObjectClass(exception) : nullptr;
    jmethodID to_string = nullptr;
    if (!env->ExceptionCheck() && type)
        to_string = env->GetMethodID(type, "toString", "()Ljava/lang/String;");
    jstring text = nullptr;
    if (!env->ExceptionCheck() && to_string)
        text = static_cast<jstring>(env->CallObjectMethod(exception, to_string));
    std::string detail;
    if (!env->ExceptionCheck() && text) {
        const jsize length = env->GetStringLength(text);
        const jchar* chars = env->GetStringChars(text, nullptr);
        if (chars) {
            try { detail = utf16_to_utf8(chars, length); }
            catch (...) { env->ReleaseStringChars(text, chars); throw; }
            env->ReleaseStringChars(text, chars);
        }
    }
    // Reporting a Throwable must not leave a secondary Java exception pending.
    if (env->ExceptionCheck()) env->ExceptionClear();
    if (text) env->DeleteLocalRef(text);
    if (type) env->DeleteLocalRef(type);
    if (exception) env->DeleteLocalRef(exception);
    log_error(std::string("JNI failure during ") + context +
              (detail.empty() ? " (Java exception details unavailable)" : ": " + detail));
    return true;
}

inline std::string java_string(JNIEnv* env, jstring value) {
    if (!value) return {};
    const jsize length = env->GetStringLength(value);
    const jchar* chars = env->GetStringChars(value, nullptr);
    if (!chars) {
        clear_java_exception(env, "reading Java string");
        throw std::runtime_error("Could not read Java string");
    }
    std::string result;
    try { result = utf16_to_utf8(chars, length); }
    catch (...) { env->ReleaseStringChars(value, chars); throw; }
    env->ReleaseStringChars(value, chars);
    return result;
}

inline jstring new_java_string(JNIEnv* env, const std::string& value) {
    const auto text = utf8_to_utf16(value);
    if (text.size() > static_cast<size_t>(std::numeric_limits<jsize>::max()))
        throw std::length_error("Java string exceeds JNI length limit");
    auto result = env->NewString(reinterpret_cast<const jchar*>(text.data()), static_cast<jsize>(text.size()));
    if (clear_java_exception(env, "creating Java string") || !result)
        throw std::runtime_error("Could not create Java string");
    return result;
}

inline jmethodID required_method(JNIEnv* env, jclass type, const char* name, const char* signature) {
    if (clear_java_exception(env, name) || !type)
        throw std::runtime_error("Cannot resolve a method on a null Java class");
    auto method = env->GetMethodID(type, name, signature);
    if (clear_java_exception(env, name) || !method)
        throw std::runtime_error(std::string("Required Java method is unavailable: ") + name + signature);
    return method;
}

inline jmethodID required_static_method(JNIEnv* env, jclass type, const char* name, const char* signature) {
    if (clear_java_exception(env, name) || !type)
        throw std::runtime_error("Cannot resolve a static method on a null Java class");
    auto method = env->GetStaticMethodID(type, name, signature);
    if (clear_java_exception(env, name) || !method)
        throw std::runtime_error(std::string("Required Java static method is unavailable: ") + name + signature);
    return method;
}

template<typename... Args>
jobject checked_object_call(JNIEnv* env, jobject object, jmethodID method, Args... args) {
    if (!object || !method) throw std::runtime_error("Invalid Java object method receiver or ID");
    auto value = env->CallObjectMethod(object, method, args...);
    if (clear_java_exception(env, "calling Java object method"))
        throw std::runtime_error("Java object method failed");
    return value;
}

template<typename... Args>
jobject checked_static_object_call(JNIEnv* env, jclass type, jmethodID method, Args... args) {
    if (!type || !method) throw std::runtime_error("Invalid Java static method receiver or ID");
    auto value = env->CallStaticObjectMethod(type, method, args...);
    if (clear_java_exception(env, "calling Java static method"))
        throw std::runtime_error("Java static method failed");
    return value;
}
}  // namespace lemon::bootstrap
