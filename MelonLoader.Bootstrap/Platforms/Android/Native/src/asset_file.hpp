#pragma once
#include <android/asset_manager.h>
#include <filesystem>
#include <memory>
#include <string>
#include "file_output.hpp"

namespace lemon::bootstrap {
inline bool extract_asset_file(AAssetManager* manager, const std::string& asset_path,
                              const std::filesystem::path& destination, std::string& failure) {
    std::unique_ptr<AAsset, decltype(&AAsset_close)> asset(
        AAssetManager_open(manager, asset_path.c_str(), AASSET_MODE_STREAMING), &AAsset_close);
    if (!asset) { failure = "asset is not readable: " + asset_path; return false; }
    std::error_code error;
    std::filesystem::create_directories(destination.parent_path(), error);
    if (error) { failure = "create directory: " + error.message(); return false; }
    errno = 0;
    std::ofstream output(destination, std::ios::binary | std::ios::trunc);
    if (!output) { failure = "open file: " + file_io_error().message(); return false; }
    char buffer[64 * 1024];
    const auto expected = AAsset_getLength64(asset.get());
    int64_t copied = 0;
    int count = 0;
    while ((count = AAsset_read(asset.get(), buffer, sizeof(buffer))) > 0) {
        output.write(buffer, count);
        if (!output) break;
        copied += count;
    }
    const bool written = finish_output(output, error);
    if (count < 0) { failure = "read APK asset: " + asset_path; return false; }
    if (!written) {
        failure = "write/close file: " + error.message() + " (errno=" + std::to_string(error.value()) + ")";
        return false;
    }
    if (copied != expected) { failure = "incomplete APK asset: " + asset_path; return false; }
    return true;
}
}  // namespace lemon::bootstrap
