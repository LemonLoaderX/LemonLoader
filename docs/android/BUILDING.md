# Building Android LemonLoader

Unless a block says otherwise, run commands from the Loader repository root.

## Requirements

| Input | Requirement |
| --- | --- |
| PowerShell | 7 or later |
| Product .NET SDK | Exact version in `global.json` (currently 10.0.204) |
| Android SDK | CMake 3.22.1 or later and Ninja |
| Android NDK | r27d (`27.3.13750724`) |
| Target | Android API 24+, `arm64-v8a` |

Exact product dependency versions and source revisions are defined in
`eng/AndroidDependencies.props`. Scripts read that file; revision hashes are not
duplicated in command defaults. Runtime selection lives in
`eng/runtime-profiles.json`: product SDK, Loader TFM (`net6.0`) and embedded
runtime (.NET 11) are different inputs, not conflicting version requirements.

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

Active builds consume a local pack matching the selected runtime profile. They
do not automatically download a pack or fall back to .NET 10. CI downloads the
versioned assets before building; local contributors can do the same:

```powershell
. ./scripts/common/RuntimeProfiles.ps1
$profile = Get-RuntimeProfile -Name android # or bionic
$tag = "coreclr-$($profile.version)-$($profile.revision.Substring(0, 12))"
$asset = "dotnet-runtime-$($profile.version)-$($profile.rid).zip"
$download = Join-Path $PWD "Output/RuntimeDownloads/$tag/$($profile.rid)"
gh release download $tag --repo LemonLoaderX/runtime `
    --pattern $asset --pattern "$asset.sha256" --dir $download
if ($LASTEXITCODE -ne 0) { throw 'Runtime download failed.' }
$archive = Join-Path $download $asset
$expected = ((Get-Content "$archive.sha256" -Raw).Trim() -split '\s+')[0]
if ($expected -notmatch '^[0-9a-f]{64}$' -or
    (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected) {
    throw 'Runtime archive SHA-256 mismatch.'
}
$pack = Join-Path $PWD "Output/RuntimePacks/$($profile.revision)/$($profile.rid)"
Expand-Archive -LiteralPath $archive -DestinationPath $pack
Test-RuntimeProfilePack -Root $pack -Profile $profile
```

Use a new destination, not `-Force`, when retrying an incomplete extraction.
Existing valid packs can be reused. The archive checksum detects corruption; it
is not an independent source signature.

Use `-CoreClrRuntimePackRoot <directory>` for a reviewed local/offline pack. A
runtime pack contains:

```text
managed/
native/
runtime-provenance.json
pack-files.json
LICENSE.TXT
THIRD-PARTY-NOTICES.TXT
licenses/OpenSSL/LICENSE.txt  # Bionic only
```

Rebuilding CoreCLR is a separate maintainer action in the contributor workspace:

```powershell
# Run from the workspace root, not the Loader repository.
pwsh -NoProfile -File scripts/setup-runtime.ps1
pwsh -NoProfile -File scripts/build-runtime.ps1 -RuntimeProfile all
```

The active builder uses WSL, one source checkout and separate per-RID outputs on
the workspace drive. Prepare/import each resulting pack before building Loader.
The old `build-android-managed-runtime.ps1 -Legacy` is for frozen .NET 10 recovery
only. See the workspace `docs/RUNTIME-DEVELOPMENT.md` for source iteration.

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
Output/Releases/LemonLoader-runtime-android-arm64.zip
Output/Releases/LemonLoader-runtime-bionic-arm64.zip
Output/Releases/LemonLoader-Android-arm64.zip
```

Select `-RuntimeProfile android` (default) or `-RuntimeProfile bionic`. Each build
produces only its selected variant; the default also refreshes the alias.
The historical staging folder name does not identify the runtime RID. Build
variants sequentially because they share staging.

For local dependency edits, `-AllowDirtyDependencies` isolates packages under
`Output/DevelopmentReleases`. It relaxes source selection, not content or ABI
validation; those outputs must not be uploaded as formal release assets.

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

For a compile-only desktop check, omit the bootstrap's automatic NativeAOT
publish step:

```powershell
dotnet build MelonLoader.sln --configuration Release -p:Platform=x64 -p:SkipPublishAfterBuild=true
```

Use this narrower check when automatic publication fails with `Cross-OS native
compilation is not supported`. It validates desktop compilation, not a published
desktop bootstrap; report that limitation separately from Android verification.

Hosted CI should consume published dependency and runtime artifacts. Source
runtime builds remain a dedicated fork-maintenance workflow rather than part of
every product build.
