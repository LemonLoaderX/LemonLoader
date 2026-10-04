#include "state.hpp"
#include "android_payload.hpp"
#include "android_assets.hpp"
#include "asset_file.hpp"
#include "deployment_file.hpp"

#include <algorithm>
#include <fstream>
#include <iterator>
#include <map>
#include <vector>

namespace lemon::bootstrap {

namespace {
struct StagedDeploymentFile {
    std::string path;
    std::string hash;
    deployment::Policy policy = deployment::Policy::seed;
};

struct InstalledDeploymentFile {
    std::string hash;
    deployment::Policy policy = deployment::Policy::seed;
};

bool read_deployment_state(
    const std::filesystem::path& path,
    InstalledDeploymentFile& state) {
    std::string value;
    if (!read_file(path, value)) {
        return false;
    }
    const size_t separator = value.find('\n');
    if (separator == std::string::npos) {
        return false;
    }
    state.hash = value.substr(0, separator);
    std::string policy = value.substr(separator + 1);
    while (!policy.empty() && (policy.back() == '\r' || policy.back() == '\n')) {
        policy.pop_back();
    }
    return state.hash.size() == 64 && deployment::parse(policy, state.policy);
}

bool write_text_file(const std::filesystem::path& path, const std::string& value) {
    std::error_code error;
    std::filesystem::create_directories(path.parent_path(), error);
    if (error) {
        return false;
    }
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    output << value;
    if (!finish_output(output, error)) {
        log_error("Could not write/close state file '" + path.string() + "': " + error.message());
        return false;
    }
    return true;
}

bool reject_metadata_symlink(const std::filesystem::path& path) {
    std::error_code error;
    const std::filesystem::file_status status = std::filesystem::symlink_status(path, error);
    return !error && std::filesystem::is_symlink(status);
}

bool validate_destination_path(
    const std::filesystem::path& base,
    const std::filesystem::path& relative,
    bool& exists) {
    std::error_code error;
    exists = false;
    std::filesystem::path current = base;
    for (auto iterator = relative.begin(); iterator != relative.end(); ++iterator) {
        current /= *iterator;
        const bool final = std::next(iterator) == relative.end();
        const std::filesystem::file_status status =
            std::filesystem::symlink_status(current, error);
        if (error == std::errc::no_such_file_or_directory) {
            error.clear();
            continue;
        }
        if (error) {
            return false;
        }
        if (!std::filesystem::exists(status)) {
            if (final) {
                exists = false;
            }
            continue;
        }
        if (std::filesystem::is_symlink(status) ||
            (final && !std::filesystem::is_regular_file(status)) ||
            (!final && !std::filesystem::is_directory(status))) {
            return false;
        }
        if (final) {
            exists = true;
        }
    }
    return true;
}

bool publish_deployment_file(
    const std::filesystem::path& source,
    const std::filesystem::path& destination) {
    std::string failure;
    if (!deployment::publish_file(source, destination, failure)) {
        log_error("Failed to publish deployment file from '" + source.string() +
                  "' to '" + destination.string() + "': " + failure);
        return false;
    }
    return true;
}

bool recover_deployment_state(const std::filesystem::path& base) {
    const std::filesystem::path state = base / ".lemonloader-deployment-state";
    const std::filesystem::path next = base / ".lemonloader-deployment-state.next";
    const std::filesystem::path previous = base / ".lemonloader-deployment-state.previous";
    if (reject_metadata_symlink(state) || reject_metadata_symlink(next) ||
        reject_metadata_symlink(previous) ||
        reject_metadata_symlink(base / ".lemonloader-backups")) {
        log_error("Packaged deployment metadata contains a symbolic link");
        return false;
    }

    std::error_code error;
    const bool state_exists = std::filesystem::exists(state, error);
    if (error) {
        return false;
    }
    const bool previous_exists = std::filesystem::exists(previous, error);
    if (error) {
        return false;
    }
    if (!state_exists && previous_exists) {
        std::filesystem::rename(previous, state, error);
        if (error) {
            return false;
        }
    } else if (previous_exists) {
        std::filesystem::remove_all(previous, error);
        if (error) {
            return false;
        }
    }
    std::filesystem::remove_all(next, error);
    return !error;
}

bool commit_deployment_state(const std::filesystem::path& base) {
    const std::filesystem::path state = base / ".lemonloader-deployment-state";
    const std::filesystem::path next = base / ".lemonloader-deployment-state.next";
    const std::filesystem::path previous = base / ".lemonloader-deployment-state.previous";
    std::error_code error;
    std::filesystem::remove_all(previous, error);
    if (error) {
        return false;
    }
    const bool had_state = std::filesystem::exists(state, error);
    if (error) {
        return false;
    }
    if (had_state) {
        std::filesystem::rename(state, previous, error);
        if (error) {
            return false;
        }
    }
    std::filesystem::rename(next, state, error);
    if (error) {
        if (had_state) {
            std::error_code restore_error;
            std::filesystem::rename(previous, state, restore_error);
        }
        return false;
    }
    std::filesystem::remove_all(previous, error);
    if (error) {
        log_line("[WARNING] Could not remove the previous packaged deployment state");
    }
    return true;
}

void prune_deployment_backups(const std::filesystem::path& base) {
    const std::filesystem::path root = base / ".lemonloader-backups";
    std::error_code error;
    if (!std::filesystem::is_directory(root, error)) {
        return;
    }
    std::vector<std::pair<std::filesystem::path, std::filesystem::file_time_type>> directories;
    for (std::filesystem::directory_iterator iterator(root, error), end;
         !error && iterator != end;
        iterator.increment(error)) {
        if (iterator->is_directory(error)) {
            const auto modified = std::filesystem::last_write_time(iterator->path(), error);
            if (!error) {
                directories.emplace_back(iterator->path(), modified);
            }
        }
    }
    if (error || directories.size() <= 3) {
        return;
    }
    std::sort(
        directories.begin(),
        directories.end(),
        [](const auto& left, const auto& right) {
            return left.second == right.second
                ? left.first < right.first
                : left.second < right.second;
        });
    for (size_t index = 0; index < directories.size() - 3; ++index) {
        std::filesystem::remove_all(directories[index].first, error);
        error.clear();
    }
}

struct DeploymentOperation {
    deployment::Action action = deployment::Action::preserve;
    std::filesystem::path relative;
    std::filesystem::path source;
    std::filesystem::path destination;
    std::filesystem::path backup;
    bool complete = false;
};

bool rollback_deployment(std::vector<DeploymentOperation>& operations) {
    bool success = true;
    for (auto iterator = operations.rbegin(); iterator != operations.rend(); ++iterator) {
        if (!iterator->complete) {
            continue;
        }
        std::error_code error;
        if (iterator->action == deployment::Action::install) {
            std::filesystem::remove(iterator->destination, error);
            success = success && !error;
        } else if (!publish_deployment_file(iterator->backup, iterator->destination)) {
            success = false;
        }
    }
    return success;
}

}  // namespace

bool deploy_assets_if_changed(
    const std::filesystem::path& base,
    const PayloadDescriptor& payload) {
    const std::filesystem::path state_root = base / ".lemonloader-deployment-state";
    const std::filesystem::path next_state_root =
        base / ".lemonloader-deployment-state.next";

    std::error_code error;
    std::filesystem::create_directories(base, error);
    if (error) {
        log_error("Failed to create the MelonLoader deployment directory: " + error.message());
        return false;
    }
    if (!recover_deployment_state(base)) {
        log_error("Failed to recover packaged deployment state");
        return false;
    }

    std::string installed_stamp;
    read_file(state_root / ".revision", installed_stamp);
    while (!installed_stamp.empty() &&
           (installed_stamp.back() == '\r' || installed_stamp.back() == '\n')) {
        installed_stamp.pop_back();
    }
    const bool update_changed = payload.deployment_stamp.empty() || installed_stamp != payload.deployment_stamp;

    const std::string asset_path = "LemonLoader/deployment";
    if (!update_changed) {
        bool deployment_current = true;
        for (const DeploymentEntry& file : payload.deployment_files) {
            if (!deployment::requires_continuous_content_check(file.policy)) continue;
            const std::filesystem::path relative(file.path);
            const std::filesystem::path destination = base / relative;
            InstalledDeploymentFile prior;
            if (!read_deployment_state(state_root / relative, prior)) continue;
            bool exists = false;
            if (!validate_destination_path(base, relative, exists)) {
                log_error("Packaged deployment file has an unsafe destination: '" +
                          destination.string() + "'");
                return false;
            }
            if (!exists) {
                deployment_current = false;
                break;
            }
            if (deployment::requires_continuous_content_check(file.policy)) {
                std::string current_hash;
                if (!compute_file_sha256(destination, current_hash)) {
                    log_error("Failed to hash enforced deployment file '" +
                              destination.string() + "'");
                    return false;
                }
                if (current_hash != prior.hash) {
                    deployment_current = false;
                    break;
                }
            }
        }
        if (deployment_current) {
            return true;
        }
    }

    const std::filesystem::path staging = base / ".packaged-deployment";
    std::filesystem::remove_all(staging, error);
    if (error) {
        log_error("Failed to clean packaged deployment staging: " + error.message());
        return false;
    }
    const std::vector<std::string> children = list_asset_children(asset_path);
    if (!children.empty() &&
        !extract_asset_node(asset_path, staging)) {
        log_error("Failed to extract packaged deployment files");
        std::filesystem::remove_all(staging, error);
        return false;
    }

    std::map<std::string, deployment::Policy> policies;
    for (const DeploymentEntry& file : payload.deployment_files) {
        policies.emplace(file.path, file.policy);
    }
    std::vector<StagedDeploymentFile> deployment_files;
    error.clear();
    const bool staging_exists = std::filesystem::exists(staging, error);
    if (!error && staging_exists && !std::filesystem::is_directory(staging, error)) {
        log_error("Packaged deployment staging is not a directory");
        std::filesystem::remove_all(staging, error);
        return false;
    }
    if (!error && staging_exists) {
        for (std::filesystem::recursive_directory_iterator iterator(staging, error), end;
             !error && iterator != end;
             iterator.increment(error)) {
            const bool regular = iterator->is_regular_file(error);
            if (error) break;
            if (!regular) continue;
            const std::filesystem::path relative =
                std::filesystem::relative(iterator->path(), staging, error);
            StagedDeploymentFile file;
            file.path = relative.generic_string();
            if (error || !is_safe_relative_path(file.path)) {
                log_error("Packaged deployment contains an unsafe file path");
                std::filesystem::remove_all(staging, error);
                return false;
            }
            if (!compute_file_sha256(iterator->path(), file.hash)) {
                log_error("Could not read packaged deployment file '" + file.path + "'");
                std::filesystem::remove_all(staging, error);
                return false;
            }
            const auto policy = policies.find(file.path);
            if (policy != policies.end()) file.policy = policy->second;
            deployment_files.push_back(std::move(file));
        }
    }
    if (error) {
        log_error("Could not enumerate packaged deployment assets: " + error.message());
        std::filesystem::remove_all(staging, error);
        return false;
    }
    std::map<std::string, const StagedDeploymentFile*> staged_files;
    for (const auto& file : deployment_files) staged_files.emplace(file.path, &file);

    std::map<std::string, InstalledDeploymentFile> previous_states;
    error.clear();
    const bool state_exists = std::filesystem::exists(state_root, error);
    if (error) {
        log_error("Failed to inspect packaged deployment state: " + error.message());
        std::filesystem::remove_all(staging, error);
        return false;
    }
    if (state_exists && !std::filesystem::is_directory(state_root, error)) {
        log_error("Packaged deployment state is not a directory");
        std::filesystem::remove_all(staging, error);
        return false;
    }
    if (error) {
        log_error("Failed to inspect packaged deployment state: " + error.message());
        std::filesystem::remove_all(staging, error);
        return false;
    }
    if (state_exists) {
        for (std::filesystem::recursive_directory_iterator iterator(state_root, error), end;
             !error && iterator != end;
             iterator.increment(error)) {
            const bool regular = iterator->is_regular_file(error);
            if (error) break;
            if (!regular) continue;
            const std::filesystem::path relative =
                std::filesystem::relative(iterator->path(), state_root, error);
            if (error) break;
            if (relative == ".revision") continue;
            InstalledDeploymentFile previous;
            if (is_safe_relative_path(relative.generic_string()) &&
                read_deployment_state(iterator->path(), previous)) {
                previous_states.emplace(relative.generic_string(), previous);
            }
        }
    }
    if (error) {
        log_error("Failed to read packaged deployment state: " + error.message());
        std::filesystem::remove_all(staging, error);
        return false;
    }

    std::filesystem::remove_all(next_state_root, error);
    if (!error) std::filesystem::create_directories(next_state_root, error);
    if (error || !write_text_file(
            next_state_root / ".revision", payload.deployment_stamp + "\n")) {
        log_error("Failed to prepare packaged deployment state");
        std::filesystem::remove_all(staging, error);
        return false;
    }

    std::vector<DeploymentOperation> operations;
    size_t preserved_count = 0;
    for (const StagedDeploymentFile& file : deployment_files) {
        const std::filesystem::path relative(file.path);
        if (!update_changed && !deployment::requires_continuous_content_check(file.policy)) {
            const auto prior = previous_states.find(file.path);
            if (prior != previous_states.end() && !write_text_file(
                    next_state_root / relative,
                    prior->second.hash + "\n" + deployment::name(prior->second.policy) + "\n")) {
                log_error("Failed to retain deployment state for '" + file.path + "'");
                std::filesystem::remove_all(staging, error);
                return false;
            }
            continue;
        }
        const std::filesystem::path staged = staging / relative;
        const std::filesystem::path destination = base / relative;
        bool exists = false;
        if (!validate_destination_path(base, relative, exists)) {
            log_error("Packaged deployment file has an unsafe destination: '" +
                      destination.string() + "'");
            std::filesystem::remove_all(staging, error);
            return false;
        }
        std::string current_hash;
        if (exists && !compute_file_sha256(destination, current_hash)) {
            log_error("Failed to hash existing deployment file '" + destination.string() + "'");
            std::filesystem::remove_all(staging, error);
            return false;
        }
        const auto previous_iterator = previous_states.find(file.path);
        const bool has_previous = previous_iterator != previous_states.end();
        const deployment::Action action = deployment::decide_current(
            file.policy,
            update_changed,
            exists,
            exists && current_hash == file.hash,
            has_previous,
            has_previous && current_hash == previous_iterator->second.hash);
        if (action == deployment::Action::install ||
            action == deployment::Action::replace) {
            operations.push_back({action, relative, staged, destination, {}});
        } else if (exists && current_hash != file.hash) {
            ++preserved_count;
        }

        const bool managed = has_previous || action == deployment::Action::install ||
            action == deployment::Action::replace || (exists && current_hash == file.hash);
        if (managed && !write_text_file(
                next_state_root / relative,
                file.hash + "\n" + deployment::name(file.policy) + "\n")) {
            log_error("Failed to prepare deployment state for '" + file.path + "'");
            std::filesystem::remove_all(staging, error);
            return false;
        }
    }

    for (const auto& [path, previous] : previous_states) {
        if (staged_files.find(path) != staged_files.end()) {
            continue;
        }
        const std::filesystem::path relative(path);
        const std::filesystem::path destination = base / relative;
        bool exists = false;
        if (!validate_destination_path(base, relative, exists)) {
            log_error("Obsolete deployment file has an unsafe destination: '" +
                      destination.string() + "'");
            std::filesystem::remove_all(staging, error);
            return false;
        }
        std::string current_hash;
        if (exists && !compute_file_sha256(destination, current_hash)) {
            log_error("Failed to hash obsolete deployment file '" + destination.string() + "'");
            std::filesystem::remove_all(staging, error);
            return false;
        }
        const deployment::Action action = deployment::decide_obsolete(
            previous.policy,
            update_changed,
            exists,
            exists && current_hash == previous.hash);
        if (action == deployment::Action::remove) {
            operations.push_back({action, relative, {}, destination, {}});
        } else if (exists) {
            ++preserved_count;
        }
    }

    const std::filesystem::path backup_root =
        base / ".lemonloader-backups" / (payload.deployment_stamp.empty() ? "unknown-update" : payload.deployment_stamp);
    if (reject_metadata_symlink(backup_root)) {
        log_error("Packaged deployment backup generation is a symbolic link");
        std::filesystem::remove_all(staging, error);
        return false;
    }
    const bool needs_backup = std::any_of(
        operations.begin(), operations.end(), [](const DeploymentOperation& operation) {
            return operation.action == deployment::Action::replace ||
                operation.action == deployment::Action::remove;
        });
    if (needs_backup) {
        std::filesystem::remove_all(backup_root, error);
        if (error) {
            log_error("Failed to prepare packaged deployment backup generation: " +
                      error.message());
            std::filesystem::remove_all(staging, error);
            return false;
        }
    }
    for (DeploymentOperation& operation : operations) {
        if (operation.action != deployment::Action::replace &&
            operation.action != deployment::Action::remove) {
            continue;
        }
        operation.backup = backup_root / operation.relative;
        if (!publish_deployment_file(operation.destination, operation.backup)) {
            log_error("Failed to back up deployment file '" +
                      operation.destination.string() + "'");
            std::filesystem::remove_all(staging, error);
            return false;
        }
    }

    size_t installed_count = 0;
    size_t replaced_count = 0;
    size_t removed_count = 0;
    for (DeploymentOperation& operation : operations) {
        bool applied = false;
        if (operation.action == deployment::Action::install ||
            operation.action == deployment::Action::replace) {
            applied = publish_deployment_file(operation.source, operation.destination);
        } else {
            applied = std::filesystem::remove(operation.destination, error) && !error;
        }
        if (!applied) {
            const char* action = operation.action == deployment::Action::install
                ? "install"
                : operation.action == deployment::Action::replace ? "replace" : "remove";
            std::string detail = std::string(" (action=") + action + ")";
            if (operation.action == deployment::Action::remove) {
                detail += error
                    ? ": " + error.message() + " (errno=" +
                        std::to_string(error.value()) + ")"
                    : ": destination no longer exists";
            }
            log_error("Failed to apply packaged deployment file '" +
                      operation.destination.string() + "'" + detail);
            if (!rollback_deployment(operations)) {
                log_error("Packaged deployment rollback was incomplete");
            }
            std::filesystem::remove_all(staging, error);
            return false;
        }
        operation.complete = true;
        if (operation.action == deployment::Action::install) {
            ++installed_count;
        } else if (operation.action == deployment::Action::replace) {
            ++replaced_count;
        } else {
            ++removed_count;
        }
    }

    if (!commit_deployment_state(base)) {
        log_error("Failed to commit packaged deployment state");
        if (!rollback_deployment(operations)) {
            log_error("Packaged deployment rollback was incomplete");
        }
        std::filesystem::remove_all(staging, error);
        return false;
    }

    std::filesystem::remove_all(staging, error);
    if (error) {
        log_line("[WARNING] Could not clean packaged deployment staging: " + error.message());
    }
    prune_deployment_backups(base);
    if (installed_count != 0 || replaced_count != 0 || preserved_count != 0 ||
        removed_count != 0) {
        log_line(
            "Applied packaged deployment: installed " +
            std::to_string(installed_count) + ", replaced " +
            std::to_string(replaced_count) + ", preserved " +
            std::to_string(preserved_count) + ", removed " +
            std::to_string(removed_count) + " file(s)");
    }
    return true;
}

bool is_safe_relative_path(const std::string& value) {
    if (value.empty() || value.front() == '/' || value.back() == '/' ||
        value.find('\\') != std::string::npos || value.find('|') != std::string::npos ||
        std::any_of(value.begin(), value.end(), [](unsigned char character) {
            return character < 0x20 || character == 0x7f;
        })) {
        return false;
    }
    const size_t first_separator = value.find('/');
    const std::string top_level = value.substr(0, first_separator);
    if (top_level == "MelonLoader" || top_level == ".packaged-deployment" ||
        top_level.rfind(".lemonloader-", 0) == 0 ||
        top_level.rfind(".lemon-staging-", 0) == 0) {
        return false;
    }
    size_t start = 0;
    while (start < value.size()) {
        const size_t end = value.find('/', start);
        const std::string segment = value.substr(start, end - start);
        if (segment.empty() || segment == "." || segment == "..") {
            return false;
        }
        if (end == std::string::npos) {
            break;
        }
        start = end + 1;
    }
    return true;
}
}  // namespace lemon::bootstrap
