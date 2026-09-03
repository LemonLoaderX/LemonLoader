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
CoreCLR build is expensive. Start from an identified `release/10.0` upstream
commit, replay only the documented Android CoreCLR patches, and build one ARM64
runtime pack.

Validate architecture, Bionic imports, host exports, cryptography files, helper
DEX, 16 KiB ELF alignment, and the standalone embedding probe. Publish the pack
with its SHA-256 and source revision, then update LemonLoader's dependency
manifest. Normal loader builds consume that artifact and do not rebuild CoreCLR.

## Native dependency checks

For every shipped `.so` or linked `.a`:

- retain its source revision and license;
- build for Android ARM64 rather than generic Linux ARM64;
- use `--no-undefined` where supported;
- reject glibc-versioned imports;
- require ELF `LOAD` alignment of at least `0x4000`;
- test failure behavior as well as the successful link.

## Release checklist

- build from a clean, reachable source revision;
- run dependency, managed, desktop, bootstrap, and payload tests appropriate to
  the changes;
- verify the runtime artifact and release manifests;
- confirm the release contains no game assets, Mods, Interop output, logs,
  credentials, local paths, or full build provenance;
- patch a private test input through the released Patcher;
- use replacement installation only for device regression;
- distinguish automated startup evidence from manual application acceptance;
- inspect all Git refs and release archives with a secret scanner.

Physical 16 KiB-page hardware, additional Unity revisions, complex hook layouts,
and deployment fault injection remain continuing qualification work. Do not
turn one successful device run into a broader support claim.
