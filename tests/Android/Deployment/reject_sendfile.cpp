#include <cerrno>
#include <sys/sendfile.h>

// Model external storage that rejects the kernel-assisted copy used by libc++.
extern "C" ssize_t sendfile(int, int, off_t*, size_t) noexcept {
    errno = EINVAL;
    return -1;
}

extern "C" ssize_t sendfile64(int, int, off64_t*, size_t) noexcept {
    errno = EINVAL;
    return -1;
}
