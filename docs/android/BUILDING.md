# Building Android LemonLoader

## Requirements

| Input | Requirement |
| --- | --- |
| PowerShell | 7 or later |
| .NET SDK | 10.0.x |
| Android SDK | CMake 3.22.1 or later and Ninja |
| Android NDK | r27d (`27.3.13750724`) |
| Target | Android API 23+, `arm64-v8a` |

Exact product dependency versions and source revisions are defined in
`eng/AndroidDependencies.props`. Scripts read that file; revision hashes are not
duplicated in command defaults or documentation.

## Source dependencies

The build needs the maintained Dobby, Il2CppInterop, HarmonyX, and MonoMod source
forks. Resolve their URLs and revisions from the product manifest with:

```powershell
pwsh -NoProfile -File scripts/setup-android-dependencies.ps1
```

The script refuses to replace a checkout with local changes and places managed
sources below the ignored `.dependencies/` directory. Builds may instead pass
the corresponding `-SourceRoot` parameters for reviewed external checkouts.

MonoMod.Common is a MonoMod submodule and must be initialized at the gitlink
revision. Modified dependency binaries are never accepted without their
producing source.

## Runtime artifact

The normal build consumes the Android CoreCLR archive recorded in the dependency
manifest. The resolver uses a content-addressed ignored cache, verifies the
archive SHA-256, rejects unsafe or duplicate ZIP entries, validates runtime
provenance, and publishes the extracted pack atomically.

Use `-CoreClrRuntimePackRoot <directory>` for a reviewed local/offline pack. A
runtime pack contains:

```text
managed/
native/
runtime-provenance.json
```

Rebuilding CoreCLR is a separate maintainer action:

```powershell
pwsh -NoProfile -File scripts/setup-android-dependencies.ps1 -IncludeRuntime
pwsh -NoProfile -File scripts/build/build-android-managed-runtime.ps1 `
    -AndroidNdkRoot "<android-ndk-r27d>" `
    -SourceRoot .dependencies/runtime
```

The runtime build uses Linux directly or WSL from Windows and derives its cache
under the selected Linux user's home directory. It does not modify the system
JDK, SDK, PATH, registry, or global package sources.

## Release build

```powershell
$env:ANDROID_SDK_ROOT = "<android-sdk>"
$env:ANDROID_NDK_ROOT = "<android-ndk-r27d>"
pwsh -NoProfile -File scripts/setup-android-dependencies.ps1
pwsh -NoProfile -File scripts/build/build-android.ps1 -Configuration Release
```

Partial entries:

| Script | Output |
| --- | --- |
| `build-android-ndk-bootstrap.ps1` | verified `libmain.so` |
| `build-android-managed.ps1` | managed host and Il2Cpp support assemblies |
| `stage-android-package.ps1` | verified unpacked payload |
| `publish-android-release.ps1` | deterministic release ZIP |

The final files are:

```text
Output/Release/linux-bionic-arm64/package/
Output/Releases/LemonLoader-Android-arm64.zip
```

The release is game-independent. Interop assemblies, Mods, configuration,
alignment, signing, and APK mutation belong to LemonLoader.Patcher.

## Validation

The build rejects incorrect dependency revisions, dirty dependency source,
non-AArch64 native files, glibc imports, ELF load alignment below `0x4000`,
missing JNI or host exports, ambiguous runtime identity, incomplete Android
cryptography files, and inconsistent hashes or manifests.

Changes shared with desktop builds must also pass:

```powershell
dotnet build MelonLoader.sln --configuration Release -p:Platform=x64
```

Hosted CI should consume published dependency and runtime artifacts. Source
runtime builds remain a dedicated fork-maintenance workflow rather than part of
every product build.
