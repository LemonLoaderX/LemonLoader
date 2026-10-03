# Agent Note: Editable deployment without generated admission metadata

Status: implemented

## Problem

Packaged deployment requires generated size/hash/revision metadata even though
APK editing can change all of it together. Stale metadata blocks native startup,
including the game. Files added with another installer cannot work without
Patcher's inventory recipe. These fields are not an authenticity boundary.

## Decision

Deployment reads actual APK assets. The optional legacy deploymentFiles array is
only a path/policy override list: missing policies default to seed, undeclared
assets use seed, deleted assets are absent regardless of stale entries. Declared
sizes, hashes, deployment mixed hash/revision and profile labels do not gate
installation. Unsafe/duplicate override paths and unknown policies still fail.

Android PackageInfo.lastUpdateTime is the private extraction freshness token.
It replaces the global deployment digest, is not a trust identity and needs no
installer calculation. Ordinary unchanged-package startup does not traverse the
deployed tree or hash files. Deployment is seeded once per APK update; a locally
deleted seed/refresh file is not automatically restored on every unchanged start.
Explicit enforce overrides retain their continuous checks against prior local
state. If the update token is unavailable, retry the transaction rather than
pretend the package is current.

Enforcement repair on an unchanged APK preserves all seed/upgrade/refresh
destinations, including missing files. Repairing one enforced Mod must not
reseed a different Mod deleted by the user. Full rollout remains APK-update work.

The existing transaction calculates hashes from staged bytes only when processing
an APK update or enforcement repair. These hashes preserve user edits under
upgrade and support ownership/rollback, not corruption diagnostics. Existing
seed/upgrade/refresh/enforce replacement and obsolete-file rules remain.

Optional deployment parse, extraction or transaction failure disables Loader
before symbol redirects/managed initialization while leaving Unity loaded. No
Mod executes after an incomplete rollback. Required runtime extraction failures
remain fatal in this step. Release/download validation is unchanged. The
[producer decision](2026-10-02-minimal-produced-payload.md) owns layout-9 metadata
subtraction and layout-8 compatibility. The [runtime-extraction decision](2026-10-02-runtime-extraction-without-digests.md)
owns removal of runtime-domain digest requirements.

## Alternatives considered

- Recalculating the old revision inside Loader removes one producer dependency
  but preserves the same generated admission recipe and still rejects ordinary
  asset edits. Ignore those fields instead.
- Removing every deployment policy/state simplifies installation further but
  loses existing user-edit-preserving upgrades and transactional updates. Keep
  only the demonstrated policy/ownership behavior during migration.
- Scanning APK assets or installed files every launch notices edits without an
  update token, but adds routine work the maintainer explicitly rejects.
- Returning success after deployment failure and starting Mods is less disruptive
  but can run on partially updated content. Disable Loader before hooks instead.

## Consequences

MT Manager add/edit/delete operations take effect when the edited APK is installed
as an update without regenerating deployment metadata. Policy overrides remain
optional and ordinary user-owned destinations are preserved. The first launch
after migrating old revision state performs a transaction. Reinstallation updates
all refresh files once, even if only another package asset changed. Enforce is an
explicit deployment policy, not protection against APK editing.

This is the deployment portion of the wider installed-contract subtraction.
Runtime extraction/configuration belongs to the linked runtime decision; game
Interop assemblies remain necessary for Mods that use their generated surface.
Package update time is platform freshness metadata, not byte integrity evidence.

## Test Coverage

Native host tests cover optional/stale fields, actual asset add/edit/delete,
policy behavior, invalid paths/policies, transactional errors and the pre-hook
Loader-disable path. Existing release and atomic file-publication tests retain
their safety boundary.

## Prior-note Audit

The [source-ownership decision](../process/2026-10-02-independent-source-resolution.md)
partially overlaps and governs the remaining runtime/layout simplification.
Crash evidence notes are unrelated. Existing DEPLOYMENT.md defines policy and
transaction mechanics, updated here for editable input semantics.
