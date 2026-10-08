# Agent Note: Minimal produced installation configuration

Status: implemented

## Problem

Native loading no longer needs domain hashes, deployment revision, identity JSON
or an Interop generation manifest. Producers still build, copy and validate them
for every new APK. That retains the old coupling and duplicate reads after the
consumer requirements have been removed.

## Decision

The [reader retirement](2026-10-03-retire-layout8-readers.md) supersedes this note's
layout-8/external-DEX/MonoVM compatibility decision below; current readers use 9.

The [CoreCLR 10 retirement](2026-10-03-retire-coreclr10-workflows.md) supersedes
frozen layout-8 staging below; Loader now produces only layout 9.

Active products produce asset layout 9. Its payload.json contains formatVersion,
runtimeRid and optional path/policy deploymentFiles overrides. Seed is the native
default, so Patcher emits only non-seed overrides and omits an empty policy list. Profiles remain packaging
choices; no profile label, declared file size/hash or revision is installed.
New APKs include actual game Interop DLLs without their generation manifest.
Active staging does not emit runtime-identity.json: the Release manifest already
records runtime source and the verified file inventory.

Release manifest format 3 further removes redundant declarations: old `rid`,
`abi`, `assetLayoutVersion`, `configuration`, `bootstrapFlavor`, `runtimeProfile`,
`runtimeChannel`, `managedRuntimeBackend`, `managedRuntimeEngineFile`,
`managedRuntimeEngineSha256`, `gameAssembliesIncluded` and `coreClrCryptoDexMode`.
The remaining RID selects the packaging profile and crypto contract; payload.json
owns layout 9. File paths determine the ABI, required engine and game-independent
layout. The engine has one hash in the inventory, checked against the verified
pack at staging. Runtime version/source, minimum API and development isolation
remain useful identity, compatibility and publication inputs.

The direct development deployment script also consumes ordinary top-level DLLs,
not the host audit manifest. It backs up the old tree, verifies a separate staged
tree from actual local hashes, then replaces it with rollback covering both renames.
An ADB error does not prove the remote rename failed. Recovery checks the actual
destination before moving the previous tree; uncertain publication or failed recovery
retains the copies and reports failure instead of nesting a backup in an installed tree.
Android compilation excludes generator-specific patches and the generator package.
The managed build recreates its owned packaging input tree so removed references
cannot survive as stale DLLs from an earlier build.
Off-device generation and desktop behavior retain their existing owners. Inactive
start-screen/generator config fields are omitted on Android, and an empty private
signature-patch framework is removed rather than retained for hypothetical use.
The retired MonoVM backend selector and unused runtime channel label are no longer
produced. Shared AsmResolver and native IL2CPP binding still have runtime callers.

This changes the Release envelope, not installed layout 9. Patcher retains the
format-2 reader checks for published archives. Format 3 is explicit because old
Patchers require the removed fields; silently deleting them under format 2 would
misrepresent compatibility. Additive fields alone still do not require a bump.

Release file sizes/hashes, download verification, runtime-pack checks, ABI/path/
duplicate/native-collision checks and crypto completeness remain. New layout 9
requires active CoreCLR/API26 inputs: embedded JNI helpers on Android or private
OpenSSL on Bionic. The initial transition retained layout-8 generation/readers,
external DEX and historical MonoVM to recover existing Releases. Those choices
are historical and superseded by the retirement decisions above.

The version change is required because old native/Patcher consumers require the
deleted fields. They must reject the new format clearly rather than interpret a
layout-8 declaration with missing requirements. Manual native configuration may
still omit its format and retain the existing file-layout defaults.

## Alternatives considered

- Removing fields under layout 8 minimizes version changes, but old consumers
  cannot safely interpret the result. Declare 9; the transition initially retained
  the old reader path before its separate retirement.
- Adding a capability flag while keeping every old digest preserves compatibility
  but does not remove producer coupling or the expensive APK tree rereads.
- A shared manifest generator centralizes the old recipe but preserves metadata
  that loading does not use. Remove that recipe from active production instead.
- Removing all legacy handling simplifies the implementation further but breaks
  existing external-DEX Release inputs. The original transition isolated it to
  layout 8; the later reader retirement accepts that compatibility cost.

## Test Coverage

- Active Releases/APKs contain no removed digest/revision fields or audit JSON.
- APK and directory injection work with plain Interop DLL inputs and preserve
  all four policy behaviors through non-default overrides.
- Historical layout-8 acceptance tests are replaced by rejection under the reader
  retirement. Release corruption, collisions and malformed input remain covered.
- Actual archive validation exercises both profiles; native tests cover minimal
  layout-9 extraction without startup scans.
- Release validation covers formats 2 and 3 for both RIDs, malformed metadata,
  missing/empty runtime files, exact inventory and same-length byte corruption.
- Device smoke consumes loaded maps/exports and lifecycle/JNI markers; it no longer
  reads or hashes runtime-identity.json, which current producers do not install.

## Consequences

Layout-9 Releases need a Patcher that supports layout 9; no release publication is
implied. Standalone APK layout verification can check structure/policies but
cannot invent removed colocated digests. Release integrity is checked before
injection. Host tests do not replace device acceptance.

## Prior-note Audit

The [runtime-extraction decision](2026-10-02-runtime-extraction-without-digests.md)
and [editable deployment](2026-10-02-editable-deployment.md) own cache/policies.
This note owns producer subtraction and the original transition rationale.
[Source ownership](../process/2026-10-02-independent-source-resolution.md) retains
independent products; crypto/crash choices remain separate.
