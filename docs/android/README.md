# Android port

LemonLoader adds an Android ARM64 platform adapter to the MelonLoader 0.7
desktop baseline. The target is Unity IL2CPP on Android API 24 or later, hosted
by private .NET 11 CoreCLR. Android is the default runtime profile; Bionic is
selectable. Both are preview distributions, not broad compatibility certification.

## Documentation map

- [Current status](STATUS.md): verified capabilities and remaining qualification.
- [Architecture](ARCHITECTURE.md): startup sequence, module ownership, and hard
  invariants.
- [Building](BUILDING.md): prerequisites, dependency inputs, and outputs.
- [Runtime](RUNTIME.md): CoreCLR hosting, Android cryptography, and managed
  compatibility.
- [Porting notes](PORTING.md): migration decisions and reusable lessons.
- [Il2CppInterop](INTEROP.md): generation and Android ABI behavior.
- [Payload contract](ARTIFACTS.md): the interface consumed by APK tooling.
- [Deployment](DEPLOYMENT.md): packaged files, ownership policies, and recovery.
- [Testing](TESTING.md): regression levels and success criteria.
- [Maintenance](MAINTENANCE.md): upstream synchronization and dependency policy.
- [Usage](USAGE.md): integrating and operating the payload.
- [Troubleshooting](TROUBLESHOOTING.md): observable failures and evidence.

## Repository model

`upstream/master` tracks LavaGang/MelonLoader. Android work is maintained as a
small patch stack on the default branch; upstream desktop updates are merged with
their ancestry intact. Modified third-party projects are separate source forks
under the LemonLoaderX organization.

The loader repository produces a game-independent archive for each profile. It does not
accept a target APK, generated Interop assemblies, Mods, signing material, or
device configuration. LemonLoader.Patcher combines those inputs later.

## Supported target

| Property | Value |
| --- | --- |
| ABI | `arm64-v8a` |
| Android API | 24 or later |
| Unity scripting backend | IL2CPP |
| Managed runtime | .NET 11 CoreCLR: Android (default) or Bionic |
| Native bootstrap | C++17, Android NDK r27d |
| ELF load alignment | at least `0x4000` |

MonoVM, Android Mono games, and 32-bit ABIs are outside the supported target.

## Build outline

First obtain the matching runtime pack as described in [Building](BUILDING.md).
Source dependency setup alone does not download active runtime packs.

```powershell
$env:ANDROID_SDK_ROOT = "<android-sdk>"
$env:ANDROID_NDK_ROOT = "<android-ndk-r27d>"
pwsh -NoProfile -File scripts/setup-android-dependencies.ps1
pwsh -NoProfile -File scripts/build/build-android.ps1 -Configuration Release
```

The build produces the NDK bootstrap, managed host, Il2Cpp support module, and a
verified payload under `Output/Release/linux-bionic-arm64`. It publishes
`Output/Releases/LemonLoader-runtime-android-arm64.zip` and the default alias
`LemonLoader-Android-arm64.zip` without modifying an APK. Select
`-RuntimeProfile bionic` for the separate Bionic archive; builds share staging
and must run sequentially.

Dependency versions and source revisions have one maintained source in
`eng/AndroidDependencies.props` and runtime profiles in `eng/runtime-profiles.json`.
Generated manifests record the exact runtime
artifact identity and content hashes for each build.

## Hard rules

- Android startup failures return to Java; they do not terminate the process.
- Runtime code executes only from application-owned storage.
- APK contents are never round-tripped through a case-insensitive extracted tree.
- Game-specific inputs and device evidence stay outside Git.
- Modified dependencies are built from their retained source forks.
- Manifest readers validate required semantics and tolerate additive metadata.
