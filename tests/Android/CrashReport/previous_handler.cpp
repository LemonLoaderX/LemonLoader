#include <signal.h>
#include <pthread.h>
#include <cstdlib>
#include <unistd.h>

static void terminate_in_previous_handler(int) { _exit(73); }

__attribute__((constructor)) static void install_previous_handler() {
    if (std::getenv("LEMON_TEST_PREVIOUS_HANDLER") == nullptr) return;
    struct sigaction action{};
    action.sa_handler = terminate_in_previous_handler;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGSEGV, &action, nullptr) != 0) _exit(74);
}

static void* native_fault(void*) {
    *static_cast<volatile int*>(nullptr) = 1;
    return nullptr;
}

extern "C" void crash_native_thread() {
    pthread_t thread;
    if (pthread_create(&thread, nullptr, native_fault, nullptr) != 0) _exit(75);
    pthread_join(thread, nullptr);
}
