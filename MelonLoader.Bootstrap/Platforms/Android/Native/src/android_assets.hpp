#pragma once
#include <filesystem>
#include <string>
#include <vector>

namespace lemon::bootstrap {
bool read_optional_asset_text(const char* path, std::string& output);
std::vector<std::string> list_asset_children(const std::string& asset_path);
bool extract_asset_node(const std::string& asset_path, const std::filesystem::path& destination);
bool read_file(const std::filesystem::path& path, std::string& output);
bool compute_file_sha256(const std::filesystem::path& path, std::string& output);
bool copy_if_changed(const std::string& asset_path, const std::filesystem::path& destination,
                     const std::filesystem::path& marker_path, const std::string& update_stamp);
}  // namespace lemon::bootstrap
