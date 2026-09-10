#include "deployment_file.hpp"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>

namespace {
enum class Fault { none, read_interrupt, short_read, read_failure, early_eof,
                   write_interrupt, short_write, write_failure, zero_write, close_failure };
Fault fault = Fault::none;
int read_calls = 0;
int write_calls = 0;
int output_fd = -1;
}

extern "C" ssize_t __real_read(int, void*, size_t);
extern "C" ssize_t __real_write(int, const void*, size_t);
extern "C" int __real_close(int);

extern "C" ssize_t __wrap_read(int fd, void* data, size_t size) {
    ++read_calls;
    if (fault == Fault::read_interrupt && read_calls == 1) {
        errno = EINTR;
        return -1;
    }
    if (fault == Fault::read_failure && read_calls > 1) {
        errno = EIO;
        return -1;
    }
    if (fault == Fault::early_eof && read_calls > 1) return 0;
    if (fault == Fault::short_read && size > 1021) size = 1021;
    return __real_read(fd, data, size);
}

extern "C" ssize_t __wrap_write(int fd, const void* data, size_t size) {
    output_fd = fd;
    ++write_calls;
    if (fault == Fault::write_interrupt && write_calls == 1) {
        errno = EINTR;
        return -1;
    }
    if (fault == Fault::write_failure) {
        if (write_calls > 1) {
            errno = ENOSPC;
            return -1;
        }
        if (size > 7) size = 7;
    }
    if (fault == Fault::zero_write) return 0;
    if (fault == Fault::short_write && size > 4093) size = 4093;
    return __real_write(fd, data, size);
}

extern "C" int __wrap_close(int fd) {
    int result = __real_close(fd);
    if (fault == Fault::close_failure && fd == output_fd) {
        output_fd = -1;
        errno = EIO;
        return -1;
    }
    return result;
}

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    const std::filesystem::path root(argv[1]);
    int failures = 0;
    const auto check = [&](const char* name, bool success) {
        std::cout << (success ? "PASS " : "FAIL ") << name << '\n';
        if (!success) ++failures;
    };
    const auto write = [](const std::filesystem::path& path, const char* contents) {
        std::ofstream output(path, std::ios::binary);
        output << contents;
    };
    const auto read = [](const std::filesystem::path& path) {
        std::ifstream input(path, std::ios::binary);
        return std::string(std::istreambuf_iterator<char>(input), {});
    };
    const auto source = root / "source.dll";
    const auto destination = root / "Mods" / "Mod.dll";
    write(source, "packaged contents");
    std::string failure;
    check("initial install", lemon::bootstrap::deployment::publish_file(source, destination, failure));
    check("installed contents", read(destination) == "packaged contents" && failure.empty());
    write(source, "updated contents");
    check("replacement", lemon::bootstrap::deployment::publish_file(source, destination, failure));
    check("replaced contents", read(destination) == "updated contents");

    const auto expect_failure = [&](const char* operation,
                                    const std::filesystem::path& from,
                                    const std::filesystem::path& to) {
        failure.clear();
        check("operation fails", !lemon::bootstrap::deployment::publish_file(from, to, failure));
        check(operation, failure.find(operation) != std::string::npos);
        check("includes system error code", failure.find("errno=") != std::string::npos);
        check("does not lose original error during cleanup",
              failure.find("errno=0,") == std::string::npos && !failure.empty());
        std::cout << "Diagnostic: " << failure << '\n';
    };
    expect_failure("create destination directory", source, source / "child.dll");

    const auto temporary = std::filesystem::path(destination.string() + ".lemon-deploy.tmp");
    std::filesystem::create_directory(temporary);
    write(temporary / "keep", "temporary obstruction");
    expect_failure("remove temporary file", source, destination);
    check("temporary obstruction preserved", read(temporary / "keep") == "temporary obstruction");
    // Only remove this test's known obstruction; never operate on application data.
    std::filesystem::remove(temporary / "keep");
    std::filesystem::remove(temporary);

    expect_failure("copy file", root / "missing.dll", destination);
    check("failed copy preserves destination", read(destination) == "updated contents");
    const auto directory_destination = root / "directory.dll";
    std::filesystem::create_directory(directory_destination);
    write(directory_destination / "keep", "destination obstruction");
    expect_failure("rename temporary file", source, directory_destination);
    check("failed rename preserves destination", read(directory_destination / "keep") == "destination obstruction");
    check("failed rename removes temporary file", !std::filesystem::exists(directory_destination.string() + ".lemon-deploy.tmp"));
    check("retry succeeds", lemon::bootstrap::deployment::publish_file(source, destination, failure) && failure.empty());

    // More than one buffer, with binary zeros, exercises EOF and full-content preservation.
    std::string contents(128 * 1024 + 19, '\0');
    for (size_t index = 0; index < contents.size(); ++index)
        contents[index] = static_cast<char>(index % 251);
    std::ofstream(source, std::ios::binary).write(contents.data(), contents.size());
    for (Fault mode : {Fault::read_interrupt, Fault::short_read,
                       Fault::write_interrupt, Fault::short_write}) {
        fault = mode;
        read_calls = write_calls = 0;
        bool success = lemon::bootstrap::deployment::publish_file(source, destination, failure);
        fault = Fault::none;
        check("interrupted/short I/O publishes all bytes", success && read(destination) == contents);
    }
    for (Fault mode : {Fault::read_failure, Fault::early_eof, Fault::write_failure,
                       Fault::zero_write, Fault::close_failure}) {
        write(destination, "previous contents");
        fault = mode;
        read_calls = write_calls = 0;
        output_fd = -1;
        bool success = lemon::bootstrap::deployment::publish_file(source, destination, failure);
        fault = Fault::none;
        check("I/O failure does not publish partial file", !success && read(destination) == "previous contents");
        check("I/O failure cleans temporary file", !std::filesystem::exists(temporary));
        check("I/O failure retains cause", failure.find("copy file (") != std::string::npos &&
              failure.find("errno=0,") == std::string::npos);
    }
    write(source, "");
    check("empty file publishes", lemon::bootstrap::deployment::publish_file(source, destination, failure) &&
          read(destination).empty());
    return failures == 0 ? 0 : 1;
}
