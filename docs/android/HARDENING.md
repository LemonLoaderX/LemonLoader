# Android failure contracts

These constraints complement [startup architecture](ARCHITECTURE.md).
Commands and test coverage live in [Testing](TESTING.md).

## Native ownership and failures

- ARM64 resolvers inspect complete aligned instructions inside readable ELF code
  ranges and reject ambiguous candidates. Exclude the known MethodInfo overload
  before selecting three-argument Unity wrappers; nearby known callers are not
  independent candidates. Bounded scans do not prove every target is correct.
- Use Unity's initialized IL2CPP handle for P/Invoke, injection and scans. Loading
  the same filename in another linker namespace can create an uninitialized
  instance and crash. Borrow the captured handle; do not close or reopen it.
- Native callbacks contain C++ exceptions and retain operation context. Logging
  failures fall back to liblog. This does not catch signals, memory corruption or
  managed fail-fast.
- Failed Unity loading releases retained assets, calls JNI_OnUnload only after a
  successful JNI_OnLoad, and closes the module even when unloading throws.
  Successful loads remain pinned; a failed first load is not retried in-process.
- Missing crypto/host exports and ambiguous runtime version directories fail
  with library/path context. A private process lock protects runtime extraction;
  kernel lock release on exit makes deleting the lock file unnecessary.
- Retain an existing SSL_CERT_DIR value. Process-wide defaults and Bionic's
  private crypto preload are distinct behaviors; other native TLS consumers may
  depend on the environment.

## JNI and managed boundaries

- Describe the original Java exception before clearing it. Latest.log includes
  operation context and a throwable summary; a summary failure must not replace
  the original Java stack.
- Use UTF-16 JNI strings and dispose local references on their creating thread.
  CLR finalizers cannot delete local refs. Use global refs across threads;
  abandoned locals on permanently attached threads still require explicit cleanup.
- APK streams reuse bounded byte buffers and reset only for backward seeks.
  Close failures release JNI references. Java available() retains its integer
  length limit; this is not a general transport for assets above 2 GiB.
- Keep AssetsTools streams alive through deferred PlayerSettings reads. Unload
  asset readers/bundles before disposing their streams, including failure paths.
- Malformed configuration remains available for repair. Missing scene callbacks
  and stripped build-index getters report capability loss; available indices are
  preserved.

## Hook removal

NativeHookDetach(void**, void*) returns void and preserves the caller's pointer.
Optional TryNativeHookDetach returns a 32-bit 1/0 result, also preserving it.
When the checked export is present, removal failure retains the trampoline root,
hook state and stack-walk registration. Older-bootstrap fallback cannot report
that failure. Current Android binding requires GetIl2CppLibraryHandle.

Dobby failures identify operation, status, target and detour; they do not expose
every allocator/relocation failure stage. Native-bridge allocator changes require
both native ARM64 and supported translated-code tests in the Dobby fork.

## Storage limits

Asset extraction checks expected length, buffered flush and close. Deployment
publication uses checked bounded POSIX I/O rather than libc++ sendfile.
[Deployment](DEPLOYMENT.md) owns policy and rollback behavior. A process kill
between file publication and state commit can leave mixed files: in-process
rollback is not a durable multi-file journal. Preserve state, staging and
.lemonloader-backups before recovery; do not clear app data or blindly delete them.

[Crash evidence](TROUBLESHOOTING.md#native-crash-evidence) has separate signal,
storage and OEM coverage limits. An NDK build or host fixture is not device
qualification.
