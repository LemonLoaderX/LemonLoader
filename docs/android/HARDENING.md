# Android bootstrap hardening

This document describes Android bootstrap failure handling, compatibility
contracts and the commands used to test them.

## Changes

- ARM64 scans check each complete aligned instruction against readable ELF code
  ranges, stop at range boundaries and reject ambiguous wrapper candidates.
  The known MethodInfo overload is excluded before judging three-argument
  candidates: Unity 6000.0.59 can place both overloads next to the shared core.
  Treating that known caller as another candidate caused startup rejection and
  is covered by the synthetic host regression.
- Native entry points and loader callbacks contain C++ exceptions and report
  context. If normal logging itself fails, reporting falls back to Android
  liblog. This does not catch memory corruption, signals or managed fail-fast.
- Failed Unity loads use scope-bound rollback. Catching JNI exceptions only at
  the exported load boundary previously skipped the explicit rollback calls.
  Both failure returns and exceptions now release retained assets, call Unity's
  `JNI_OnUnload` after a successful `JNI_OnLoad`, and close the library. An unload
  callback exception cannot prevent the remaining cleanup. Successful loads stay
  pinned for the process lifetime; failed loads still require a new process.
- JNI lookups reject missing method IDs before calling Java; exception reporting
  describes the original pending exception to logcat before clearing it, and
  includes operation context and the throwable description in Latest.log.
  A failure while obtaining that summary cannot replace the original Java stack.
- JNI strings use UTF-16, preserving supplementary characters and embedded NULs.
  Payload v8 revision ordering matches the producer's UTF-16 ordinal comparer;
  no format bump is required.
- Local JNI references are disposed on their creating thread. Their CLR
  finalizers never call `DeleteLocalRef`. Use global references across threads,
  and explicitly dispose locals before leaving their JNI frame. Abandoned locals
  on a permanently attached thread are not reclaimed by this change.
- Asset extraction checks buffered flush, close and expected length. Deployment
  copies use checked bounded POSIX I/O rather than libc++ `sendfile`.
- A lock in private application files excludes concurrent Loader processes for
  the lifetime of loaded runtime files. A lock failure reports its path and OS
  error before extraction or log reset. Lock files need not be deleted: the
  kernel releases their locks when the owning process exits.
- CoreCLR directory discovery reports filesystem errors and rejects ambiguous
  version directories. Runtime and crypto selection use the declared runtime RID.
  Linker failures identify the library and linker error; required crypto inputs
  cannot silently disappear.
- The process-wide `SSL_CERT_DIR` default is retained for both Android and Bionic,
  without overwriting an existing value. The Bionic-only crypto setup is not a
  replacement for that older process-wide behavior, including other native TLS
  consumers loaded by a game or Mod.
- Loader configuration failures report paths and exceptions; malformed files
  remain available for repair. Missing scene callbacks and stripped build-index
  getters report the lost capability. Available scene indices are preserved.
- APK asset streams reuse a bounded Java byte buffer, copy directly into the
  caller's buffer, and reset only for backward seeks. Close failures release
  retained JNI references. Native hook detach releases the captured trampoline
  root after removal. With the checked Android export, a failure retains the
  trampoline, hook state and stack-walk registration.

### Native hook compatibility

The legacy `NativeHookDetach(void**, void*)` export returns void and preserves the
caller's pointer on both success and failure, as older Android and desktop
bootstraps do.

The optional Android `TryNativeHookDetach` export returns an explicit 32-bit
1/0 result and also preserves the pointer. Managed binding resolves it separately
from required bootstrap exports. Older bootstraps still load and use their legacy
void call; they cannot report removal failure to managed callers, so the extra
failure retention guarantee only applies when the checked export is present.
Failed Dobby operations report the operation, status, target and detour addresses.
They do not identify every internal allocator/relocation failure stage.

Related source-fork changes belong to their owners: HarmonyX synchronizes delegate
IDs and its method cache; Patcher cancellation includes stdout/stderr draining
after the child process exits. Dobby provides native-bridge relay allocation.

## Regressions

From the Loader root, on Linux/WSL with a C++17 compiler and an NDK:

```bash
ANDROID_NDK_ROOT=<ndk> bash scripts/test/test-android-bootstrap.sh
bash scripts/test/test-android-logging.sh
bash scripts/test/test-android-deployment.sh
CXX=clang++ bash scripts/test/test-android-deployment.sh --libcxx
```

The bootstrap suite includes guard pages, ambiguous ARM64 wrappers, invalid
runtime directories, emergency logging, cross-process lock contention,
`/dev/full`, asset read/truncation failures, JNI lookup failures, a missing crypto
bridge, legacy/checked hook removal, and UTF conversion/ordering. JNI tests check
stack-description ordering, summary failure and pending-exception cleanup with the
NDK's interface and fake Java operations, not an Android VM. The libc++ variant
needs its host development headers and libraries.

The same script runs the production `NativeLoader.load` implementation with
wrapped linker operations and injected environment/extraction JNI failures. It
checks rollback exactly once, cleanup after a throwing Unity unload callback,
failure diagnostics, refusal to retry failed loads and successful-load pinning.

```powershell
dotnet run --project tests/Android/Managed/AndroidManaged.Tests.csproj
dotnet run --project tests/Preferences/Preferences.csproj
```

Managed tests link production sources to a fake JNI function table and small
Unity/logging hosts. They exercise reference ownership and finalizers, byte
copy/buffer reuse, seeking and close errors, malformed configuration preservation,
scene capability fallback, trampoline retention/removal, optional-export fallback
and stack-walk registration. Real Unity event delivery and actual Android JNI
thread attachment require the separate device tests.

For local source forks, run the normal Android native and managed build scripts
with explicit workspace dependency roots and `-AllowDirtyDependencies`. Shared
managed changes also need the desktop build described in [BUILDING.md](BUILDING.md).
Dependency-specific regressions are documented in each fork's `PATCHES.md`.

## Remaining limits

- An arbitrary process kill or power loss between publishing deployment files
  and committing their state can leave a mixed deployment. In-process rollback
  and metadata-directory recovery are not a durable multi-file transaction.
  Before another deployment attempt after such an interruption, preserve the
  deployment state, staging and `.lemonloader-backups` alongside affected files;
  compare them with the packaged manifest to plan recovery. Do not clear app
  data or blindly delete state/backups. Durable journaling and crash injection
  remain separate work.
- Native-bridge relay allocation must preserve translated-code compatibility.
  Allocator changes require tests on native ARM64 and native-bridge execution.
- ARM64 generic-method ABI coverage and wrapper heuristics need additional real
  Unity binaries. Bounded scans prevent a known overread, not all wrong-target
  interpretations. Physical 16 KiB-page devices remain unqualified.
- APK stream length still follows Java `available()` and its integer limit;
  this is not a new general-purpose backend for assets above 2 GiB.
