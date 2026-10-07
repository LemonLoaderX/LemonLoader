#include <sys/resource.h>
#include <dlfcn.h>
#include <string.h>

extern "C"
{
    void Init();
    int SetRlimitHook(int resource, rlimit* rlp);
    void MLRegisterDlsymHook(void* detour);
    void* MLRealDlsym(void* handle, const char* symbol);
    void* DlsymHook(void* handle, const char* symbol);
}

#define DYLD_INTERPOSE(_replacement,_replacee) \
       __attribute__((used)) static struct{ const void* replacement; const void* replacee; } _interpose_##_replacee \
       __attribute__ ((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_replacee };

int SetRlimitHook(int resource, rlimit* rlp)
{
    int result = setrlimit(resource, rlp);
    Init();
    return result;
}

DYLD_INTERPOSE(SetRlimitHook, setrlimit)

// Detour registered by the managed bootstrap (ModuleSymbolRedirect.Attach).
// Receives the symbol AND its already-resolved real address, and returns either
// MelonLoader's hook (for the runtime entry points) or the real address.
typedef void* (*DlsymDetourFn)(void* handle, const char* symbol, void* real);
static DlsymDetourFn g_dlsymDetour = nullptr;

void MLRegisterDlsymHook(void* detour)
{
    g_dlsymDetour = (DlsymDetourFn)detour;
}

// The real dlsym, exposed to managed code. dyld does not interpose the image
// that declares the interpose, so this call resolves the genuine export. The
// managed side MUST use this (not its own dlsym P/Invoke, whose GOT slot IS
// interposed) so MelonLoader resolves the real mono/il2cpp exports rather than
// its own detours -- otherwise the detours call themselves and recurse.
void* MLRealDlsym(void* handle, const char* symbol)
{
    return dlsym(handle, symbol);
}

// The game's engine (UnityPlayer.dylib) resolves the mono/il2cpp entry points
// via dlsym, so we interpose dlsym to return MelonLoader's detours for them.
// plthook cannot patch UnityPlayer.dylib's GOT on modern macOS
// (LC_DYLD_CHAINED_FIXUPS); DYLD interpose is the mechanism that reliably works
// here (it is what triggers Init via setrlimit). Only runtime-entry symbols
// (mono_/il2cpp_) are handed to managed code -- routing every dlsym in the
// process (e.g. AppKit's during startup) through a managed callback is needless
// and unsafe.
void* DlsymHook(void* handle, const char* symbol)
{
    void* real = dlsym(handle, symbol);
    if (g_dlsymDetour != nullptr && symbol != nullptr &&
        (strncmp(symbol, "mono_", 5) == 0 || strncmp(symbol, "il2cpp_", 7) == 0))
        return g_dlsymDetour(handle, symbol, real);
    return real;
}

DYLD_INTERPOSE(DlsymHook, dlsym)
