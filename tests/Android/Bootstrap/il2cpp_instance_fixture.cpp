#include <cstdint>

static unsigned char storage[512];
static void* initialized_class = nullptr;

extern "C" __attribute__((aligned(16))) void* il2cpp_init(const char*) {
    initialized_class = storage;
    return initialized_class;
}

extern "C" __attribute__((aligned(16))) void* il2cpp_domain_get() {
    // An uninitialized duplicate reproduces Class::Init's null + field offset.
    volatile unsigned char flags = *reinterpret_cast<volatile unsigned char*>(
        reinterpret_cast<uintptr_t>(initialized_class) + 0x135);
    (void)flags;
    return initialized_class;
}
