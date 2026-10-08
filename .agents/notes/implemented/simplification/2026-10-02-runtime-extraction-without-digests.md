# Agent Note: Runtime extraction without generated digest gates

Status: implemented

## Problem

Loader requires installer-generated mixed hashes for runtime extraction and checks
the hash of runtime-identity.json on every launch. That JSON is not consumed by
the host; actual compatibility is checked through CoreCLR exports and crypto
initialization. Colocated editable digests do not establish trust, but force a
manual installer to reproduce Patcher's metadata recipe.

## Decision

All APK runtime trees use PackageInfo.lastUpdateTime as their local extraction
token, shared with [editable deployment](2026-10-02-editable-deployment.md).
Each tree retains atomic staging/publication and its existing marker filename.
Old digest markers trigger one extraction; missing package time always retries.
Normal cached startup checks the marker and directory without scanning or hashing
installed files. Every APK update replaces the runtime trees, including Interop,
so removed assemblies do not survive a package update.

payload.json is optional configuration. Android is the default RID; Bionic
selects runtimeRid: linux-bionic-arm64. Optional deploymentFiles supplies policies.
Known fields distinguish absence from an invalid type. Explicit null, strings in
place of a numeric layout, and non-array policies cannot silently select defaults.
Invalid runtime options fail parsing; invalid optional deployment disables Loader
before hooks and Mods. Unknown additive fields remain tolerated.
An explicitly unsupported formatVersion or RID is rejected. Declared mixed hashes,
managedRuntimeIdentitySha256 and backend labels are not admission requirements.
runtime-identity.json and interop-manifest.json are audit/build artifacts, not
runtime requirements. The host still loads a real CoreCLR engine with the required
exports and initializes the matching crypto library. Required extraction or
loading failures retain ordinary error logs; no new file inventory or diagnosis
mechanism is introduced.

The [producer decision](2026-10-02-minimal-produced-payload.md) owns layout-9
production and layout-8 compatibility. Download, Release, runtime-pack, APK structural and ABI checks
remain at their existing tooling boundaries. This consumer subtraction does not
turn off release hash/signature validation.
Android environment discovery is separate from android_assets read/extraction,
android_payload configuration/orchestration and android_deployment policy/state
transactions. Payload policy entries carry no computed content digest; only staged
and installed deployment state owns the hashes needed by upgrade/enforce.

## Alternatives considered

- Keeping mixed hashes as optional extraction hints avoids copying .NET when
  only Mods change, but stale hints still hide manual runtime edits. Use platform
  installation freshness consistently instead.
- Hashing actual APK trees in Loader removes Patcher's formula dependency, but
  adds the scanning and hashing the maintainer explicitly rejects.
- Deleting all extraction state removes markers, but recopies the complete
  private runtime on every launch. Retain existing transaction/cache state.
- Replacing identity JSON with another required compatibility manifest preserves
  a generated installation gate. Reuse real library loading and export checks.

## Consequences

An installer copies the release's runtime trees and game-specific Interop DLLs
without recalculating digests. Android needs no payload configuration; Bionic needs
only its RID selection. Local runtime edits survive unchanged-package launches,
then are replaced by the next APK update. An unrelated APK update now also incurs
runtime extraction cost. A missing runtime tree still fails extraction; this
change does not promise to run Mods on incomplete inputs or remove Android signing
and private-storage requirements.

Host extraction regressions cover absent/minimal configuration, stale metadata,
unsupported layouts/RIDs, no identity or Interop manifest, cached starts, actual
asset updates/deletions and unavailable update tokens. They do not qualify ART or
real-device startup.

## Prior-note Audit

The editable-deployment note partially overlaps in freshness and owns policy and
Loader-disable behavior. The [source-ownership decision](../process/2026-10-02-independent-source-resolution.md)
retains repository migration. Embedded crypto and crash
evidence decisions remain unchanged.
