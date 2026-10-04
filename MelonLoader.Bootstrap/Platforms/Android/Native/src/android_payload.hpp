#pragma once
#include "deployment_policy.hpp"
#include <filesystem>
#include <string>
#include <vector>

namespace lemon::bootstrap {
struct DeploymentEntry {
    std::string path;
    deployment::Policy policy = deployment::Policy::seed;
};
struct PayloadDescriptor {
    std::string runtime_rid = "android-arm64";
    std::string deployment_stamp;
    std::vector<DeploymentEntry> deployment_files;
    bool deployment_valid = true;
};
bool is_safe_relative_path(const std::string& value);
bool deploy_assets_if_changed(const std::filesystem::path& base, const PayloadDescriptor& payload);
std::string apk_update_stamp();
}  // namespace lemon::bootstrap
