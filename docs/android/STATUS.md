# Android port status

## Current architecture

LemonLoader provides an Android API 23+ ARM64 adapter for Unity IL2CPP games on
the MelonLoader 0.7 baseline. A C++17 NDK `libmain.so` hosts a private .NET 10
CoreCLR runtime and transfers control to the managed loader. CoreCLR is the only
supported Android managed backend.

The game-independent LemonLoader Release is consumed by LemonLoader.Patcher,
which owns game input extraction, Interop generation, APK mutation, alignment,
and signing. Modified Dobby, Il2CppInterop, HarmonyX, MonoMod, MonoMod.Common,
and CoreCLR sources remain independent, reviewable forks.

## Verified capabilities

- Android bootstrap builds for `arm64-v8a` with API 23 and 16 KiB-compatible ELF
  load segments.
- CoreCLR is hosted directly and uses the source-built Android cryptography path.
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
| Android API | 23 or later |
| Unity backend | IL2CPP |
| Managed runtime | .NET 10 Android CoreCLR |
| Bootstrap | Android NDK r27d |

Android Mono games, 32-bit ABIs, and physical 16 KiB-page hardware have not been
qualified. Automated startup does not replace manual application acceptance.

## Open qualification work

- broaden private Unity version and application coverage;
- validate physical 16 KiB-page devices;
- expand deployment rollback and recovery fault injection;
- upstream loader-neutral dependency fixes where maintainers accept them;
- validate a second loader adapter before extracting generic APK tooling APIs.

Exact versions and revisions live in `eng/AndroidDependencies.props`. Build
hashes, private application identities, and device evidence remain generated
artifacts outside Git.
