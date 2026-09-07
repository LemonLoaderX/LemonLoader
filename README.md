# LemonLoader

LemonLoader is an Android ARM64 port of
[MelonLoader](https://github.com/LavaGang/MelonLoader) for Unity IL2CPP games.
It keeps the MelonLoader 0.7 desktop code as its upstream baseline and contains
the Android platform adapter, native bootstrap, managed host, and release
assembly workflow.

The project is maintained by the
[LemonLoaderX](https://github.com/LemonLoaderX) organization and is not affiliated
with LavaGang, Unity Technologies, or a particular game.

## Supported target

| Area | Support |
| --- | --- |
| Android | API 24 or later (development profiles) |
| ABI | `arm64-v8a` |
| Unity backend | IL2CPP |
| Managed runtime | .NET 11 CoreCLR, Android default / Bionic selectable |
| Bootstrap | C++17 built with Android NDK r27d |
| ELF alignment | 16 KiB-compatible load segments |

MonoVM, Mono games, 32-bit ABIs, and automatic APK installation are not part of
the supported Android target.

## Repository responsibilities

This repository builds a game-independent Android payload. It does not decode,
modify, align, sign, or install APKs. Those operations belong to
[LemonLoader.Patcher](https://github.com/LemonLoaderX/LemonLoader.Patcher), which
also generates the game-specific Il2CppInterop assemblies.

Modified upstream dependencies remain in reviewable source forks:

- [Dobby](https://github.com/LemonLoaderX/Dobby)
- [Il2CppInterop](https://github.com/LemonLoaderX/Il2CppInterop)
- [HarmonyX](https://github.com/LemonLoaderX/HarmonyX)
- [MonoMod](https://github.com/LemonLoaderX/MonoMod) and
  [MonoMod.Common](https://github.com/LemonLoaderX/MonoMod.Common)
- [runtime](https://github.com/LemonLoaderX/runtime)

The normal build selects `eng/runtime-profiles.json` and consumes a validated
local runtime pack. .NET 10 is frozen legacy and must be selected explicitly.
Preview 5 distributes both profiles and requires Patcher 1.1.0 or later.
Rebuilding the runtime source is a separate maintainer workflow.

## Build

Requirements:

- PowerShell 7
- .NET SDK 10.0.204 (selected by `global.json`)
- Android SDK with CMake and Ninja
- Android NDK r27d
- the source dependencies recorded in `eng/AndroidDependencies.props`

From this repository, after obtaining the matching pack using
[Building](docs/android/BUILDING.md#runtime-artifact):

```powershell
$env:ANDROID_SDK_ROOT = "<android-sdk>"
$env:ANDROID_NDK_ROOT = "<android-ndk-r27d>"
pwsh -NoProfile -File scripts/setup-android-dependencies.ps1
pwsh -NoProfile -File scripts/build/build-android.ps1 -Configuration Release
```

The release archive is written to:

```text
Output/Releases/LemonLoader-Android-arm64.zip
Output/Releases/LemonLoader-runtime-android-arm64.zip
```

Use `-RuntimeProfile bionic` for `LemonLoader-runtime-bionic-arm64.zip`.
The unqualified archive name is an alias for Android only. These scripts create
local packages; GitHub publication is owned by the version-tag workflow.

Build scripts validate dependency identity, architecture, Android imports,
required exports, 16 KiB ELF alignment, and release manifests before publishing
the archive. Source forks are checked out at their manifest revisions below the
ignored `.dependencies/` directory; CoreCLR remains a versioned release artifact
unless runtime development is explicitly requested.

## Documentation

- [Android overview](docs/android/README.md)
- [Current status](docs/android/STATUS.md)
- [Architecture](docs/android/ARCHITECTURE.md)
- [Building](docs/android/BUILDING.md)
- [Runtime](docs/android/RUNTIME.md)
- [Il2CppInterop integration](docs/android/INTEROP.md)
- [Payload contract](docs/android/ARTIFACTS.md)
- [Testing](docs/android/TESTING.md)
- [Maintenance](docs/android/MAINTENANCE.md)
- [Troubleshooting](docs/android/TROUBLESHOOTING.md)
- [Porting notes](docs/android/PORTING.md)

## Contributing

Keep platform behavior in Android-specific files and preserve the desktop
upstream implementation. Fix dependency problems in the dependency fork that
owns them rather than rewriting built assemblies in this repository. Every
behavioral change should include the narrowest regression that reproduces it.

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md) before
opening an issue or pull request.

## License

LemonLoader retains MelonLoader's Apache License 2.0 license. See
[LICENSE.md](LICENSE.md). Third-party code and generated release inputs retain
their own licenses and notices.
