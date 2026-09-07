# Android port status

## Current architecture

LemonLoader develops an Android API 24+ ARM64 adapter for Unity IL2CPP games on
the MelonLoader 0.7 baseline. A C++17 NDK `libmain.so` hosts a private .NET 11
CoreCLR runtime and transfers control to the managed loader. CoreCLR is the only
supported Android managed backend.

The active profiles are android (default) and bionic, selected in
`eng/runtime-profiles.json`. They share one source revision. .NET 10 is frozen
legacy, not the default. Preview 5 distributes both profiles and requires Patcher
1.1.0 or later; it does not imply broad game or device qualification.

The game-independent LemonLoader Release is consumed by LemonLoader.Patcher,
which owns game input extraction, Interop generation, APK mutation, alignment,
and signing. Modified Dobby, Il2CppInterop, HarmonyX, MonoMod, MonoMod.Common,
and CoreCLR sources remain independent, reviewable forks.

## Verified capabilities

- Active bootstrap builds target `arm64-v8a`, API 24+ and 16 KiB-compatible ELF
  load segments.
- CoreCLR is hosted directly, with JNI cryptography for Android or OpenSSL for Bionic.
- Runtime, loader, Interop, and deployment content have separate identities and
  transactional update behavior.
- Il2CppInterop covers Android ARM64 aggregate ABI and multiple generic-method
  lookup forms.
- Failed short-function hooks leave original instructions unchanged.
- Normal builds consume a versioned CoreCLR artifact rather than rebuilding the
  runtime source.
- Automated device smoke coverage exercises CoreCLR identity, JNI worker-thread
  attachment, scene callbacks, and the main Unity update phases.

## Supported boundary

| Area | Supported |
| --- | --- |
| ABI | `arm64-v8a` |
| Android API | 24 or later for development profiles |
| Unity backend | IL2CPP |
| Managed runtime | .NET 11 Android/Bionic CoreCLR |
| Bootstrap | Android NDK r27d |

Android Mono games, 32-bit ABIs, and physical 16 KiB-page hardware have not been
qualified. Automated startup does not replace manual application acceptance.

## Open qualification work

- broaden private Unity version and application coverage;
- validate physical 16 KiB-page devices;
- expand deployment rollback and recovery fault injection;
- remove checkout-path and line-ending dependence from compiled artifact hashes;
- upstream loader-neutral dependency fixes where maintainers accept them;
- validate a second loader adapter before extracting generic APK tooling APIs.

Exact dependency versions live in `eng/AndroidDependencies.props`; runtime
profiles live in `eng/runtime-profiles.json`. Build
hashes, private application identities, and device evidence remain generated
artifacts outside Git.
