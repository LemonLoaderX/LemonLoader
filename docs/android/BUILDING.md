# Building Android LemonLoader

Unless a block says otherwise, run commands from the Loader repository root.

## Requirements

| Input | Requirement |
| --- | --- |
| PowerShell | 7 or later |
| Product .NET SDK | Exact version in `global.json` (currently 10.0.204) |
| Android SDK | CMake 3.22.1 or later and Ninja |
| Android NDK | r27d (`27.3.13750724`) |
| Target | Android API 26+, `arm64-v8a` |

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

Setup/build selects a sibling `../Dobby`, `../Il2CppInterop`, `../HarmonyX` or
`../MonoMod` only when its HEAD matches this product's manifest. Otherwise setup
creates an isolated `.dependencies/<name>/<revision>` checkout. Existing sources
are verified without fetching or switching revisions; local changes are preserved.
Different product pins never switch a shared checkout. Builds do not fetch.
Use ordinary git status for worktree inspection; setup/build helpers own the
source-pin checks. No parent status/audit gate or shared environment cache is
required. Configure local NuGet/temp caches through standard environment variables
when needed; product commands do not redirect them to a parent temp directory.

Use the corresponding `-DobbySourceRoot`, `-Il2CppInteropSourceRoot`,
`-HarmonyXSourceRoot` or `-MonoModSourceRoot` for explicit external checkouts.
Setup's optional `-SourceRoot <directory>` creates/verifies named checkouts there
instead; pass those explicit paths to builds. Existing old caches are left intact.

MonoMod.Common is a MonoMod submodule and must be initialized at the gitlink
revision. Modified dependency binaries are never accepted without their
producing source.

### Relocating Existing Sources

Stop builds and release handles inside source directories before moving them.
Editor Git watchers can hold nested .git directories even without a terminal there.
Verify each checkout's absolute Git/common directory, refs, local status and links.
A standalone .git directory moves with the checkout; a .git file pointing outside
it needs separate Git-metadata migration. MonoMod's nested checkout must retain
its relative pointer into MonoMod's own .git/modules and matching gitlink.
Inspect WSL symlinks through WSL; Windows may expose a reparse point without its
target. Preserve external artifacts, SDK links and private outputs without
following or deleting them. Verify refs/config/status and link targets afterward.

An access-denied move is not permission to force-close another process, change
ACLs, copy over the destination or delete source. Resolve directory handles first
and retry the unchanged checkout. Check the runtime build lock while builds stay
stopped, then close that check's WSL handle before a Windows directory rename:
an open child lock file can itself prevent the rename. This requires a maintenance
window with no new builds, not a lock held throughout the move. After a partial
move, verify the already-moved identities and resume only the remaining sources.
Historical absolute-path CMake caches are not portable: keep them as evidence and
use fresh build/output roots after relocation.
Moving sources never changes the consuming products' independent pins.

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

Package an imported pack with `scripts/build/package-runtime.ps1`. For an explicit
local development pack:

```powershell
pwsh -NoProfile -File scripts/build/package-runtime.ps1 -RuntimeProfile android `
    -RuntimePackRoot "<development-pack>" -Development
```

This validates the pack and writes a reproducible archive plus checksum under
`Output/DevelopmentRuntimeArtifacts`, without replacing formal runtime archives.
Use one profile when specifying a pack path. Development identity is retained;
packaging does not turn an unqualified build into a published runtime.

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

Rebuilding CoreCLR is a separate maintainer action:

```powershell
pwsh -NoProfile -File scripts/setup-runtime.ps1
pwsh -NoProfile -File scripts/build-runtime.ps1 -RuntimeProfile all
```

The active builder uses WSL, one source checkout and separate per-RID outputs on
the source drive. Prepare/import each resulting pack before building Loader.
See [runtime source development](RUNTIME-DEVELOPMENT.md) for source iteration.

## Release build

```powershell
$env:ANDROID_SDK_ROOT = "<android-sdk>"
$env:ANDROID_NDK_ROOT = "<android-ndk-r27d>"
pwsh -NoProfile -File scripts/setup-android-dependencies.ps1
pwsh -NoProfile -File scripts/build.ps1 -Configuration Release
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

The product entry accepts `-RuntimeProfile android|bionic|all` without a
parent repository or Patcher checkout. Use `all` only with per-profile pack caches.
For local dependency edits, pass explicit source paths and `-Development`
(alias `-AllowDirtyDependencies`) to isolate packages under
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
