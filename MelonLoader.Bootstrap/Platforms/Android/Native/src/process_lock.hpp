#pragma once
#include <cerrno>
#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>
#include <filesystem>
#include <system_error>

namespace lemon::bootstrap {
// Hold for the lifetime of loaded runtime files, not just while extracting them.
class ProcessLock {
public:
    ProcessLock() = default;
    ProcessLock(const ProcessLock&) = delete;
    ProcessLock& operator=(const ProcessLock&) = delete;
    ~ProcessLock() { if (descriptor_ >= 0) close(descriptor_); }

    bool acquire(const std::filesystem::path& path, std::error_code& error) {
        if (descriptor_ >= 0) return true;
        int descriptor = open(path.c_str(), O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0600);
        if (descriptor < 0) { error = {errno, std::generic_category()}; return false; }
        int status;
        do { status = flock(descriptor, LOCK_EX | LOCK_NB); } while (status != 0 && errno == EINTR);
        if (status != 0) {
            error = {errno, std::generic_category()};
            close(descriptor);
            return false;
        }
        descriptor_ = descriptor;
        error.clear();
        return true;
    }
private:
    int descriptor_ = -1;
};
}  // namespace lemon::bootstrap
