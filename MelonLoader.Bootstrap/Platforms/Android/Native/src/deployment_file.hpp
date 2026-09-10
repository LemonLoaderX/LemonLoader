#pragma once

#include <array>
#include <cerrno>
#include <cstdint>
#include <fcntl.h>
#include <filesystem>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <utility>

namespace lemon::bootstrap::deployment {

namespace detail {

class FileDescriptor {
public:
    explicit FileDescriptor(int value) : value_(value) {}
    ~FileDescriptor() {
        if (value_ >= 0) {
            ::close(value_);
        }
    }
    FileDescriptor(const FileDescriptor&) = delete;
    FileDescriptor& operator=(const FileDescriptor&) = delete;
    int get() const { return value_; }
    int close() { return ::close(std::exchange(value_, -1)); }

private:
    int value_;
};

// libc++ uses sendfile for copy_file, which some Android external-storage
// implementations reject with EINVAL. Copy bytes without requiring that syscall.
inline bool copy_contents(
    const std::filesystem::path& source,
    const std::filesystem::path& destination,
    std::error_code& error,
    const char*& operation) {
    const auto fail = [&]() {
        error = std::error_code(errno, std::generic_category());
        return false;
    };
    operation = "open source file";
    FileDescriptor input(::open(source.c_str(), O_RDONLY | O_CLOEXEC));
    if (input.get() < 0) return fail();

    operation = "inspect source file";
    struct stat status{};
    if (::fstat(input.get(), &status) != 0) return fail();
    if (!S_ISREG(status.st_mode) || status.st_size < 0) {
        error = std::make_error_code(std::errc::invalid_argument);
        return false;
    }

    operation = "create temporary file";
    FileDescriptor output(::open(destination.c_str(),
        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, status.st_mode & 0777));
    if (output.get() < 0) return fail();

    std::array<char, 64 * 1024> buffer;
    std::uintmax_t copied = 0;
    for (;;) {
        operation = "read source file";
        ssize_t count;
        do {
            count = ::read(input.get(), buffer.data(), buffer.size());
        } while (count < 0 && errno == EINTR);
        if (count < 0) return fail();
        if (count == 0) break;

        operation = "write temporary file";
        ssize_t offset = 0;
        while (offset < count) {
            ssize_t written = ::write(output.get(), buffer.data() + offset,
                                     static_cast<size_t>(count - offset));
            if (written < 0 && errno == EINTR) continue;
            if (written < 0) return fail();
            if (written == 0) {
                error = std::make_error_code(std::errc::io_error);
                return false;
            }
            offset += written;
        }
        copied += static_cast<std::uintmax_t>(count);
    }
    if (copied != static_cast<std::uintmax_t>(status.st_size)) {
        error = std::make_error_code(std::errc::io_error);
        return false;
    }
    operation = "close temporary file";
    // Do not retry close after EINTR: Linux may already have released the fd.
    if (output.close() != 0) return fail();
    error.clear();
    return true;
}

}  // namespace detail

// Publish through a sibling temporary file so a failed copy preserves the destination.
inline bool publish_file(
    const std::filesystem::path& source,
    const std::filesystem::path& destination,
    std::string& failure) {
    failure.clear();
    std::error_code error;
    std::filesystem::path temporary = destination;
    temporary += ".lemon-deploy.tmp";
    const auto fail = [&](const char* operation,
                          const std::filesystem::path& path,
                          bool cleanup = false) {
        // Capture the original failure before cleanup changes any error state.
        failure = std::string(operation) + " '" + path.string() + "': " +
            error.message() + " (errno=" + std::to_string(error.value()) +
            ", category=" + error.category().name() + ")";
        if (cleanup) {
            std::error_code cleanup_error;
            std::filesystem::remove(temporary, cleanup_error);
            if (cleanup_error) {
                failure += "; temporary file cleanup also failed: " +
                    cleanup_error.message() + " (errno=" +
                    std::to_string(cleanup_error.value()) + ")";
            }
        }
        return false;
    };
    std::filesystem::create_directories(destination.parent_path(), error);
    if (error) {
        return fail("create destination directory", destination.parent_path());
    }
    std::filesystem::remove(temporary, error);
    if (error) {
        return fail("remove temporary file", temporary);
    }
    const char* copy_operation = nullptr;
    if (!detail::copy_contents(source, temporary, error, copy_operation)) {
        const std::string step = std::string("copy file (") + copy_operation + ")";
        return fail(step.c_str(), temporary, true);
    }
    std::filesystem::rename(temporary, destination, error);
    if (error) {
        return fail("rename temporary file", temporary, true);
    }
    return true;
}

}  // namespace lemon::bootstrap::deployment
