# Android maintenance

## Upstream synchronization

The default branch is an adapter over `upstream/master`. Preserve upstream ancestry
and keep Android behavior in platform files, build properties, native bootstrap
code, and support adapters.

1. Fetch and review the intended upstream MelonLoader changes.
2. Verify the current desktop and Android branches before merging.
3. Merge the upstream branch instead of cherry-picking its commits.
4. Resolve conflicts by preserving upstream behavior and reapplying the smallest
   Android adapter.
5. Run desktop regression and the affected Android build/test entry points.
6. Record durable architectural changes in the relevant document.

Do not mix a major upstream rebase with a runtime or payload-format migration.

## Dependency ownership

| Dependency | Maintained form |
| --- | --- |
| Android NDK | Exact r27d revision in `eng/AndroidDependencies.props` |
| Dobby | Source fork built by the bootstrap CMake graph |
| plthook | Unmodified vendored source with commit provenance |
| Il2CppInterop | Source fork; Runtime/HarmonySupport and CLI built from it |
| HarmonyX | Source fork with CoreCLR emit and resolver fixes |
| MonoMod | Source fork plus its pinned MonoMod.Common submodule |
| CoreCLR | Versioned runtime artifact built from the complete runtime fork |

Each product has one maintained dependency manifest. Build scripts read it
instead of copying revisions into parameter defaults. Generated manifests carry
the exact hashes for a particular artifact.

## Updating a source fork

1. Rebase or replay its small patch stack on the reviewed upstream base.
2. Keep each root-cause fix and its regression in one reviewable commit.
3. Update the fork's `PATCHES.md` and removal condition.
4. Build and test the fork independently.
5. Update the single dependency manifest in the consuming product.
6. Run the consumer probe and its normal release validation.

Do not compensate for a source incompatibility with a post-build IL or byte
patch in LemonLoader or the Patcher.

## Updating CoreCLR

The runtime repository has a separate lifecycle because a complete Android
CoreCLR build is expensive. Both active .NET 11 profiles use one reviewed
upstream `main` commit from `eng/runtime-profiles.json`. Build Android ARM64 and
Linux Bionic ARM64 from the same checkout with separate intermediates. The
`release/10.0` fork is a frozen legacy fallback, not the default build input.

Validate architecture, Bionic imports, host exports, cryptography files, helper
DEX, 16 KiB ELF alignment, and the standalone embedding probe. Publish the pack
with its SHA-256 and source revision, then update LemonLoader's dependency
manifest. Normal loader builds consume that artifact and do not rebuild CoreCLR.

Android uses the JNI crypto library and helper DEX; Bionic uses private OpenSSL
libraries and attribution. Loader Preview 5 requires Patcher 1.1.0 or later.
The Release `files[]` inventory protects the helper DEX at its fixed path;
Patcher writes `coreClrCryptoDexSha256` only into the final APK payload after
promoting the DEX to `classesN.dex`. Asset layout remains v8.

## Native dependency checks

For every shipped `.so` or linked `.a`:

- retain its source revision and license;
- build for Android ARM64 rather than generic Linux ARM64;
- use `--no-undefined` where supported;
- reject glibc-versioned imports;
- require ELF `LOAD` alignment of at least `0x4000`;
- test failure behavior as well as the successful link.

## Release checklist

Commit `docs/releases/<tag>.md` before tagging. The file contains the release
body, not a duplicate title. Push the reviewed commit and version tag; the tag
workflow owns draft creation, CI asset upload and publication. Do not also
create a Release manually. Published assets are not replaced on workflow retries;
use a new version for binary changes and edit notes only for prose corrections.

- build from a clean, reachable source revision;
- require path-mapped deterministic source builds and normalized release text;
- isolate dependency builds from consuming-workspace MSBuild props and suppress
  ambient CI repository metadata;
- run dependency, managed, desktop, bootstrap, and payload tests appropriate to
  the changes;
- verify the runtime artifact and release manifests;
- confirm the release contains no game assets, Mods, Interop output, logs,
  credentials, local paths, or full build provenance;
- confirm the Release bootstrap has no DWARF, static symbol-table, or
  machine-dependent build-ID sections and source-built managed assemblies contain
  no embedded or path-bearing debug data;
- patch a private test input through the released Patcher;
- use replacement installation only for device regression;
- distinguish automated startup evidence from manual application acceptance;
- scan the selected publication histories and final release archives for secrets;
  private backup refs are not publication inputs.

Physical 16 KiB-page hardware, additional Unity revisions, complex hook layouts,
and deployment fault injection remain continuing qualification work. Do not
turn one successful device run into a broader support claim.
