# Android porting notes

This document records the reusable engineering conclusions behind the Android
port. It deliberately excludes test-game identities, device identifiers, local
paths, build hashes, and one-off diagnostic evidence.

## Platform strategy

The port is an Android adapter over the desktop MelonLoader implementation, not
a separate loader implementation. Shared managed behavior stays upstream-shaped;
Android-specific path discovery, startup, native loading, and lifecycle behavior
live behind the Android build target.

The first NativeAOT bootstrap was retired. A small C++17 NDK `libmain.so` matches
Unity's Java/native startup model more directly, has no glibc dependency, and can
host the private runtime without changing the desktop bootstrap.

## CoreCLR hosting

Android uses the CoreCLR host interface directly:

1. extract a verified private runtime into application storage;
2. initialize the selected cryptography backend;
3. load and identity-check `libcoreclr.so`;
4. build the trusted-platform-assembly and native-search paths;
5. call `coreclr_initialize` and `coreclr_create_delegate`;
6. transfer control to `MelonLoader.NativeHost`.

The old hostfxr-based MonoVM backend is retired. Current Android and Linux Bionic
profiles both host CoreCLR directly from the same .NET 11 source revision.
Android uses a JNI crypto bridge; Bionic uses private OpenSSL libraries.
Neither profile falls back to MonoVM or silently switches to the other runtime.

## Android cryptography

The source-built Android runtime expects Java helper classes and a native
cryptography library initialized through `JNI_OnLoad`. Loading that library from
an isolated class loader created two native-library identities, leaving the copy
used by CoreCLR without its Java VM state.

The accepted design promotes one deterministic helper DEX into the application
class loader and supplies a CoreCLR P/Invoke override so managed cryptography
reuses that initialized native module. Runtime build provenance remains an
internal build artifact; releases carry only the identity and hashes needed by
their consumers.

## Unity and IL2CPP

`JNI_OnLoad` only registers Unity's native loader methods. Managed startup begins
after Unity has loaded and `il2cpp_init` is intercepted. The bootstrap is
process-scoped because Android may destroy and recreate an Activity without
terminating the process; a completed runtime is reused, while partial runtime
initialization is not retried in the same process.

Android ARM64 requires AAPCS64-aware handling for value arguments, returns,
homogeneous floating-point aggregates, and indirect results. Stripped Unity
versions also require version-aware generic-method resolution. These fixes live
in the Il2CppInterop fork and the native resolver, not in game-specific Mods.

## Dependency ownership

Modified Dobby, Il2CppInterop, HarmonyX, MonoMod, MonoMod.Common, and CoreCLR
sources are retained as independent forks. Fixes are built from those sources;
post-build IL or byte patching is not a maintained compatibility mechanism.

The normal LemonLoader build consumes a versioned CoreCLR runtime artifact.
Building the full runtime source is a separate workflow because it is expensive
and has a different maintenance lifecycle. Source-integrated native libraries
such as Dobby and plthook are built directly by CMake.

## Product separation

LemonLoader produces a game-independent payload. The Patcher owns APK ZIP
handling, Unity input extraction, Interop generation, DEX insertion, deployment
content, alignment, and signing. This keeps game material out of loader releases
and lets CLI and GUI share one typed patch pipeline.

## Validation lessons

- A successful build or surviving process is not runtime success.
- Runtime identity, loaded mappings, managed callbacks, and visible application
  progress must agree.
- Failed native hooks must leave original code unchanged.
- APK entries must be handled case-sensitively without a Windows extract/repack
  round trip.
- Manifest consumers validate fields they use and tolerate additive metadata.
- Build commands and machine paths belong in private provenance, not releases.
