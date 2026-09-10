#pragma once
#include <cerrno>
#include <fstream>
#include <system_error>

namespace lemon::bootstrap {
inline std::error_code file_io_error() {
    return std::error_code(errno ? errno : EIO, std::generic_category());
}

inline bool finish_output(std::ofstream& output, std::error_code& error) {
    error.clear();
    if (!output) error = file_io_error();
    if (output.is_open()) {
        errno = 0;
        output.flush();
        if (!output && !error) error = file_io_error();
        errno = 0;
        output.close();
        if (!output && !error) error = file_io_error();
    } else if (!error) error = std::make_error_code(std::errc::io_error);
    return !error;
}
}  // namespace lemon::bootstrap
