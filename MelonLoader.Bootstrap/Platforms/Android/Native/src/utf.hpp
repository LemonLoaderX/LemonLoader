#pragma once

#include <cstdint>
#include <string>
#include <stdexcept>

namespace lemon::bootstrap {

inline std::string utf16_to_utf8(const uint16_t* value, int length) {
    std::string output;
    if (value == nullptr || length <= 0) return output;
    output.reserve(static_cast<size_t>(length));
    for (int index = 0; index < length; ++index) {
        uint32_t code = value[index];
        if (code >= 0xd800 && code <= 0xdbff) {
            if (index + 1 < length && value[index + 1] >= 0xdc00 && value[index + 1] <= 0xdfff) {
                code = 0x10000 + ((code - 0xd800) << 10) + (value[++index] - 0xdc00);
            } else {
                code = 0xfffd;
            }
        } else if (code >= 0xdc00 && code <= 0xdfff) {
            code = 0xfffd;
        }
        if (code <= 0x7f) output.push_back(static_cast<char>(code));
        else if (code <= 0x7ff) {
            output.push_back(static_cast<char>(0xc0 | (code >> 6)));
            output.push_back(static_cast<char>(0x80 | (code & 0x3f)));
        } else if (code <= 0xffff) {
            output.push_back(static_cast<char>(0xe0 | (code >> 12)));
            output.push_back(static_cast<char>(0x80 | ((code >> 6) & 0x3f)));
            output.push_back(static_cast<char>(0x80 | (code & 0x3f)));
        } else {
            output.push_back(static_cast<char>(0xf0 | (code >> 18)));
            output.push_back(static_cast<char>(0x80 | ((code >> 12) & 0x3f)));
            output.push_back(static_cast<char>(0x80 | ((code >> 6) & 0x3f)));
            output.push_back(static_cast<char>(0x80 | (code & 0x3f)));
        }
    }
    return output;
}

inline std::u16string utf8_to_utf16(const std::string& value) {
    std::u16string result;
    for (size_t index = 0; index < value.size();) {
        auto first = static_cast<unsigned char>(value[index++]);
        uint32_t code;
        size_t following;
        uint32_t minimum;
        if (first < 0x80) { code = first; following = 0; minimum = 0; }
        else if ((first & 0xe0) == 0xc0) { code = first & 0x1f; following = 1; minimum = 0x80; }
        else if ((first & 0xf0) == 0xe0) { code = first & 0x0f; following = 2; minimum = 0x800; }
        else if ((first & 0xf8) == 0xf0) { code = first & 7; following = 3; minimum = 0x10000; }
        else throw std::invalid_argument("Invalid UTF-8 leading byte");
        if (following > value.size() - index) throw std::invalid_argument("Truncated UTF-8 sequence");
        for (size_t offset = 0; offset < following; ++offset) {
            auto next = static_cast<unsigned char>(value[index++]);
            if ((next & 0xc0) != 0x80) throw std::invalid_argument("Invalid UTF-8 continuation byte");
            code = (code << 6) | (next & 0x3f);
        }
        if (code < minimum || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff))
            throw std::invalid_argument("Invalid UTF-8 code point");
        if (code <= 0xffff) result.push_back(static_cast<char16_t>(code));
        else {
            code -= 0x10000;
            result.push_back(static_cast<char16_t>(0xd800 + (code >> 10)));
            result.push_back(static_cast<char16_t>(0xdc00 + (code & 0x3ff)));
        }
    }
    return result;
}

// Payload v8 uses StringComparer.Ordinal in its C# producer (UTF-16 code units).
inline bool utf16_ordinal_less(const std::string& left, const std::string& right) {
    return utf8_to_utf16(left) < utf8_to_utf16(right);
}

}  // namespace lemon::bootstrap
