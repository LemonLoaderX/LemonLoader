#include <sys/mman.h>
#include <unistd.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "runtime.cpp"
#include "arm64_il2cpp_resolver.cpp"

namespace lemon::bootstrap {
RuntimePaths runtime_paths;
JavaVM* java_vm = nullptr;
void* unity_handle = nullptr;
bool prepare_android_runtime() { return false; }
bool initialize_android_crypto(const std::string&) { return false; }
void log_line(const std::string& message) { std::puts(message.c_str()); }
void log_error(const std::string& message) { std::fprintf(stderr, "%s\n", message.c_str()); }
}

static uint8_t* image;
static size_t page_size;
static void* init_address;
static constexpr size_t mib = 1024 * 1024;
static constexpr size_t image_size = 225 * mib;
static void* image_handle = reinterpret_cast<void*>(0x1234);
static uintptr_t incomplete_code_page;

static void require(bool success, const char* message) {
    if (!success) { std::fprintf(stderr, "FAIL %s\n", message); std::exit(1); }
}

extern "C" int __real_dobby_reserve_near_trampoline(void*);
extern "C" int __wrap_dobby_reserve_near_trampoline(void* target) {
    const auto address = reinterpret_cast<uintptr_t>(target);
    require(address % 4 == 0, "near anchor must be ARM64 instruction aligned");
    require(address < incomplete_code_page || address >= incomplete_code_page + page_size,
        "range without a complete aligned instruction must not reserve capacity");
    return __real_dobby_reserve_near_trampoline(target);
}

extern "C" void* __real_dlsym(void*, const char*);
extern "C" void* __wrap_dlsym(void* handle, const char* name) {
    if (handle == image_handle)
        return std::strcmp(name, "il2cpp_init") == 0 ? init_address : nullptr;
    return __real_dlsym(handle, name);
}

extern "C" int __real_dladdr(const void*, Dl_info*);
extern "C" int __wrap_dladdr(const void* address, Dl_info* info) {
    if (address == init_address) {
        *info = {};
        info->dli_fbase = image;
        return 1;
    }
    return __real_dladdr(address, info);
}

static void* initialize_fixture(const char*) {
    // Model later runtime allocations. Exact-address allocation never replaces a
    // page already acquired by Dobby during the production pre-init callback.
    for (auto* gap : {image - page_size, image + image_size}) {
        void* result = mmap(gap, page_size, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        require(result != MAP_FAILED, "fill unreserved gap");
        if (result != gap) munmap(result, page_size);
    }
    return reinterpret_cast<void*>(0x5678);
}

static int replacement() { return 42; }

int main(int argc, char** argv) {
    using namespace lemon::bootstrap;
    const bool unaligned_begin = argc == 2 && std::strcmp(argv[1], "unaligned-begin") == 0;
    const bool unaligned_end = argc == 2 && std::strcmp(argv[1], "unaligned-end") == 0;
    require(argc == 1 || unaligned_begin || unaligned_end, "unknown fixture case");
    page_size = static_cast<size_t>(sysconf(_SC_PAGESIZE));
    // Reserve address space, not physical backing, around a large ELF image.
    // Its two free neighbor pages are the only near-relay candidates. Both the
    // init and late-target branch windows stay inside these owned guards.
    auto* region = static_cast<uint8_t*>(mmap(nullptr, 512 * mib, PROT_NONE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0));
    require(region != MAP_FAILED, "reserve fixture address space");
    image = region + 128 * mib;
    require(mprotect(image, page_size, PROT_READ | PROT_WRITE) == 0, "ELF header access");
    auto* elf = reinterpret_cast<ElfW(Ehdr)*>(image);
    std::memcpy(elf->e_ident, ELFMAG, SELFMAG);
    elf->e_ident[EI_CLASS] = ELFCLASS64;
    elf->e_phoff = sizeof(*elf);
    elf->e_phentsize = sizeof(ElfW(Phdr));
    elf->e_phnum = 2;
    auto* segment = reinterpret_cast<ElfW(Phdr)*>(image + elf->e_phoff);
    segment->p_type = PT_LOAD;
    segment->p_flags = PF_R | PF_X;
    const size_t code_size = unaligned_end ? 42 * mib - page_size + 5 : 122 * mib;
    segment->p_vaddr = 86 * mib + (unaligned_begin ? 1 : 0);
    segment->p_memsz = code_size - (unaligned_begin ? 1 : 0);
    // Four bytes starting off-alignment contain no complete ARM64 instruction.
    segment[1].p_type = PT_LOAD;
    segment[1].p_flags = PF_R | PF_X;
    segment[1].p_vaddr = mib + 1;
    segment[1].p_memsz = 4;
    incomplete_code_page = reinterpret_cast<uintptr_t>(image + mib);
    require(mprotect(image + mib, page_size, PROT_READ | PROT_EXEC) == 0, "short segment access");
    auto* code = image + 86 * mib;
    require(mprotect(code, code_size, PROT_READ | PROT_WRITE) == 0, "code preparation");
    init_address = image + 95 * mib;
    const uint32_t init_code[] = {0x58000050u, 0xd61f0200u}; // ldr x16, #8; br x16
    std::memcpy(init_address, init_code, sizeof(init_code));
    auto init_callback = &initialize_fixture;
    std::memcpy(static_cast<uint8_t*>(init_address) + 8, &init_callback, sizeof(init_callback));
    auto* target = image + (unaligned_end ? 100 : 204) * mib;
    const uint32_t target_code[] = {0x528000e0u, 0xd65f03c0u}; // mov w0, #7; ret
    std::memcpy(target, target_code, sizeof(target_code));
    __builtin___clear_cache(static_cast<char*>(init_address), static_cast<char*>(init_address) + 16);
    __builtin___clear_cache(reinterpret_cast<char*>(target), reinterpret_cast<char*>(target) + 8);
    require(mprotect(code, code_size, PROT_READ | PROT_EXEC) == 0, "code publication");
    require(munmap(image - page_size, page_size) == 0 && munmap(image + image_size, page_size) == 0,
        "make two owned gaps available");
    original_dlsym = &__wrap_dlsym;
    auto initialize = reinterpret_cast<il2cpp_init_fn>(dlsym_detour(image_handle, "il2cpp_init"));
    require(initialize("fixture") == reinterpret_cast<void*>(0x5678), "preserve original initialization");
    require(std::llabs(reinterpret_cast<intptr_t>(&replacement) - reinterpret_cast<intptr_t>(target)) > 128 * mib,
        "replacement must require a near relay");
    void* original = target;
    NativeHookAttach(&original, reinterpret_cast<void*>(&replacement));
    require(original != nullptr, "late IL2CPP target: DobbyHook -1 after early init-only reservation");
    auto target_function = reinterpret_cast<int (*)()>(target);
    require(target_function() == 42 && reinterpret_cast<int (*)()>(original)() == 7, "hook and original calls");
    void* detach_target = target;
    require(TryNativeHookDetach(&detach_target, reinterpret_cast<void*>(&replacement)) == 1 && target_function() == 7,
        "hook restoration");
    std::puts("PASS large IL2CPP near capacity, initialization, hook, original and undo");
    munmap(region, 512 * mib);
}
