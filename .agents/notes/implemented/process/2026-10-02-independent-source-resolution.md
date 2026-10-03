# Agent Note: Independent source resolution for each product

Status: implemented

Source synchronization and product adoption are separate operations. A maintained
fork may track a newer upstream API/runtime family while a product still pins its
compatible revision in a private source cache. MonoMod master remains the legacy
22-series maintenance line; reorganize is a separate API migration. Current
runtime main branding and latest Harmony source do not implicitly change the
product's .NET 11 / Harmony 2.10 / MonoMod 22 support contract.

## Problem

An unpublished parent lock and command wrappers duplicate product ownership.
Loader and Patcher pin different Interop revisions; switching a shared sibling
to satisfy one product disrupts another product or local work.

## Decision

Each product owns pins, SDK policy, setup/build/tests/cleanup/publication scripts
and documentation. A matching sibling HEAD is reused; another pin resolves to
.dependencies/name/revision. Explicit roots retain revision/cleanliness checks
and development overrides. Resolution/build is read-only: no fetch, reset or
branch switch. Setup creates a missing exact clone atomically; existing sources
are verified without mutation. Matching nested sources must be initialized.

New Windows clones enable long paths and use short .staging-GUID names; revision
basenames can still exceed Git's path limit. HTTPS clones may filter blobs;
local fixtures do not establish filtered remotes to partial source checkouts.
Generic setup rejects untracked files. Runtime setup checks tracked edits because
its build lock and artifacts link are expected untracked outputs.

Loader owns runtime setup/build and per-RID outputs under Output/RuntimeDevelopment.
The source lock serializes both profiles; explicit OutputRoot preserves historical
trees. External artifact restores require the source NuGet.config; Windows-volume
inspection prefers git.exe through WSL. The [restore-config note](../bug-fix/2026-10-02-runtime-restore-config.md)
and [source-Git note](2026-10-02-runtime-source-git.md) retain those failure causes.

Product cleanup selects named generated trees, preserves unknown evidence and
never cleans sibling sources/caches. Validate all selected paths first; reject
links and skip nested repositories. Runtime cleanup is scoped to the real output,
never its source symlink. Publication scans the product HEAD and explicit
producing sources/final archives; initialized nested repositories use their own
HEAD. Runtime scanning requires an ancestor base and audits base..HEAD only.
Private refs and ignored/untracked files are outside Git-history certification.

## Documentation ownership

[Loader's task index](../../../../docs/README.md) is the primary entry. Build,
test and release commands have one topic owner; script catalogs name entries and
internal backends without duplicating procedures. Native README describes module
ownership and links to those guides. Patcher retains local CLI, Interop and
contribution guides so it can be maintained without a Loader checkout.
The old runtime-parity log matcher is retired: string blacklists for removed
instrumentation are not a useful product contract. Actual logging/preferences
regressions and same-session device evidence remain the validation boundary.
The orphan build/android RuntimePack restore project is removed: it still reads
the retired CoreCLR10 property and has no build/CI callers. Current pack download,
preparation and import remain in their owning workflow.

Parent status/operations/scanner/submodule entries are retired. An optional local
README links to the products; legal files and historical Git metadata are recovery
material, not another authority. Unrelated private proposals stay outside active
product docs. Completed broad planning is reduced to remaining qualification gates.

Current facts replace stale overview paragraphs. Scoped decisions preserve useful
rejected alternatives; overlapping proposals are removed only after their unique
rationale/limits are absorbed into implemented notes and remaining gates. Private
chronology, jobs, artifact hashes and device progress never enter these guides.

## Moving sources

Preserve whole checkouts, refs/config/edits and ignored inputs. Nested .git files
must resolve internally with relative pointers. Stop builds, verify absolute
targets and snapshot identities before a move. Close a WSL lock-check handle
before Windows rename: that child handle can itself prevent the move. Editor Git
watchers may also hold .git directories; release handles without force-closing
processes. After a partial move, verify completed identities and move only what
remains. Do not copy/delete around blocked renames. Inspect WSL link targets
through WSL and rebuild into fresh roots rather than reuse absolute-path caches.

## Alternatives considered

- A parent lock coordinates one snapshot, but hides ownership and prevents
  independent pins. Matching optional siblings and private caches suffice.
- Switching shared sources saves disk but risks local work. New exact caches cost
  space while preserving independently maintained histories.
- A shared resolver package removes small helper duplication but adds another
  synchronized dependency. Keep the narrow product helpers.
- Parent cleanup/audit/delegates provide convenience but introduce cross-owner
  mutation and another catalog. Named product targets and explicit audit inputs
  follow actual releases.
- One combined document avoids links but mixes installation, build, contracts and
  diagnosis. A small task index with topic owners keeps reading selective.
- Retain every historical draft/runner for reproduction: preserves convenient
  history but presents old paths/toolchains as maintained. Preserve unique evidence
  privately and stable causes in their owner; delete redundant instructions.
- Major combined restructuring is easy to schedule but hard to review/rollback.
  Changes and commits remain scoped to each owner and behavioral boundary.

## Consequences

Standalone products need no parent metadata, pins or commands. New clones need
network; prepared builds are offline. Different pins can consume more disk.
Loader retains its exact SDK pin; Patcher retains its stable feature-band policy.
CoreCLR source compilation, native host suites and device checks are explicit
boundaries, not implicit meaning of product verification.

Source/setup fixtures cover matching/conflicting pins, explicit edits and failure
preservation. Cleanup/publication/orchestration fixtures cover containment, links,
nested repos, ranges, omitted boundaries and deterministic repacking. Actual
products validate real artifacts. Host results do not qualify ART/TLS/devices.

## Prior-note Audit

The broad modernization proposal is fully absorbed: ownership, incremental changes,
editable installation and no new scanning framework remain here, in the
[payload decision](../simplification/2026-10-02-minimal-produced-payload.md), crash
notes and [remaining gates](../../../../docs/maintenance/modernization.md).
The old ownership inventory and porting overview duplicate topic guides and are
removed. The runtime-artifact ADR's costly-source-build/versioned-pack reasoning
lives in [Runtime](../../../../docs/android/RUNTIME.md); runtime-specific bug notes
retain independent value. [CoreCLR 10](../simplification/2026-10-03-retire-coreclr10-workflows.md)
and [reader retirement](../simplification/2026-10-03-retire-layout8-readers.md) preserve
the reversals of former compatibility decisions. Crash investigation alternatives
belong to the existing reporter note; pending device coverage remains explicit.
