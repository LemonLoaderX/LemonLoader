# Android port status

## Current architecture

LemonLoader develops an Android API 26+ ARM64 adapter for Unity IL2CPP games on
the MelonLoader 0.7 baseline. A C++17 NDK `libmain.so` hosts a private .NET 11
CoreCLR runtime and transfers control to the managed loader. CoreCLR is the only
supported Android managed backend.

The active profiles are android (default) and bionic, selected in
`eng/runtime-profiles.json`. They share one source revision. CoreCLR 10 recovery
is retired. Preview 5 distributes both profiles and requires Patcher
1.1.0 or later; it does not imply broad game or device qualification.

The game-independent LemonLoader Release is consumed by LemonLoader.Patcher,
which owns game input extraction, Interop generation, APK mutation, alignment,
and signing. Modified Dobby, Il2CppInterop, HarmonyX, MonoMod, MonoMod.Common,
and CoreCLR sources remain independent, reviewable forks.

## Verified capabilities

- Active bootstrap builds target `arm64-v8a`, API 26+ and 16 KiB-compatible ELF
  load segments.
- CoreCLR is hosted directly, with JNI cryptography for Android or OpenSSL for Bionic.
- Runtime extraction and deployment updates use APK update time and transactional
  publication, not mixed installed-content hashes or declared revisions.
- IL2CPP calls and injection scans reuse Unity's initialized library handle;
  host regressions cover duplicate-loading failures and JNI ownership.
- Android crypto helpers are embedded in libmain.so and loaded in memory;
  historical external-DEX inputs retain a separate compatibility path.
- Previous-session logs, bounded CoreCLR reports and API-gated Android exit traces
  are retained; exact-build native symbols stay private for offline diagnostics.
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
| Android API | 26 or later |
| Unity backend | IL2CPP |
| Managed runtime | .NET 11 Android/Bionic CoreCLR |
| Bootstrap | Android NDK r27d |

Android Mono games, 32-bit ABIs, and physical 16 KiB-page hardware have not been
qualified. Automated startup does not replace manual application acceptance.

## Open qualification work

- qualify embedded DEX loading, TLS and native handler coexistence on devices;
- broaden private Unity version and application coverage;
- validate physical 16 KiB-page devices;
- expand deployment rollback and recovery fault injection;
- verify reproducibility when changing source roots, build flags or toolchains;
- upstream loader-neutral dependency fixes where maintainers accept them;
- validate a second loader adapter before extracting generic APK tooling APIs.

Exact dependency versions live in `eng/AndroidDependencies.props`; runtime
profiles live in `eng/runtime-profiles.json`. Build
hashes, private application identities, and device evidence remain generated
artifacts outside Git.
