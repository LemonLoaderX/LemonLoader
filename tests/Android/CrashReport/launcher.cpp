#include "state.hpp"

#include <unistd.h>

namespace lemon::bootstrap {
RuntimePaths runtime_paths;
JavaVM* java_vm = nullptr;
}

extern "C" int __android_log_write(int, const char*, const char*) { return 0; }
extern "C" int DobbyHook(void*, void*, void**) { return -1; }

int main(int argc, char** argv) {
    if (argc < 4) return 2;
    lemon::bootstrap::runtime_paths.base_directory = argv[1];
    lemon::bootstrap::configure_crash_reporting();
    execv(argv[2], argv + 2);
    return 127;
}
