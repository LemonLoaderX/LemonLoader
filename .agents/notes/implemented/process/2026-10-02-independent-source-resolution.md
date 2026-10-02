# Agent Note: Independent source resolution for each product

Status: implemented

## Problem

The parent workspace overrides Loader dependency paths and checks parent gitlinks.
Patcher publishing defaults to a parent dependencies directory. Products already
pin different Il2CppInterop revisions, so automatically checking out a shared
sibling to satisfy one product can disrupt the other product or local work.

## Decision

The [CoreCLR 10 retirement](../simplification/2026-10-03-retire-coreclr10-workflows.md)
supersedes this note's frozen-profile selection and retained shell-probe decision.
The independent source/build ownership below remains in force.

Each product reads only its own dependency manifest. Default builds use a sibling
checkout only when its HEAD matches that product's pin, otherwise a private
.dependencies/name/revision checkout in that product. Explicit source roots keep
the existing strict revision/cleanliness checks and development overrides.
Resolution is read-only; builds never fetch or change source checkouts.

Setup creates missing pinned checkouts in temporary sibling staging and publishes
them only after checkout/submodule setup succeeds. An existing checkout is verified
and never switched, fetched or reset; missing revisions use separate cache paths.
Matching shared siblings are verified without submodule mutation. Local edits,
wrong HEADs and uninitialized nested dependencies receive actionable errors.
Patcher owns its generator URL and revision; Loader does not supply them.
New clones enable long paths locally; temporary checkout names omit the revision
basename because Git's Windows directory changes can still hit MAX_PATH despite
core.longpaths. Blob filtering applies to HTTPS clones;
local offline fixture/source clones do not create a filtered remote pointing at
another checkout, which can trigger recursive lazy fetching from partial sources.

Loader's scripts/build.ps1 is the public product entry for profile selection and
existing native/managed/staging orchestration. It does not inspect the parent
gitlinks or require a Patcher checkout. Runtime setup/build also belongs to Loader:
eng/runtime-profiles.json supplies the fork URL and active pins; setup uses the same
sibling/cache rule without selecting branches or fetching upstream substitutes.
The WSL backend keeps its source lock and per-RID isolation. Default output belongs
to Loader Output/RuntimeDevelopment; an explicit output root preserves existing
build trees. Historical output roots require an explicit OutputRoot; there is no
parent wrapper supplying paths or SDK/cache policy.
Runtime setup checks tracked changes, matching the builder: its artifacts symlink
and build lock are untracked source-side outputs. They and other untracked local
files remain untouched. Generic dependency setup still rejects untracked files.

Each product owns scripts/clean.ps1 and its cleanup fixtures. Cleanup selects known
generated build trees, never sibling source repositories or .dependencies caches.
Routine cleanup preserves packs, published/development archives, runtime source
outputs, symbols, diagnostic evidence and unknown Output directories. AllOutputs
adds only explicitly named pack/download/archive directories, not a wildcard
purge. Runtime source cleanup is manual and scoped to its actual output target;
the old cross-repository Deep switch is not retained. Stop builds before cleaning.
All selected trees are validated before deletion; links at/above a target and
nested links reject cleanup. Traversal skips nested Git repositories and links.
Per-product AGENTS.md retains maintenance rules without requiring parent docs.
Each product also owns script syntax/helper checks and publication scanning.
Publication scanning always includes its own HEAD; additional source checkouts
and final archives are explicit inputs rather than discovered through parent
gitlinks. Initialized nested dependencies of those selected sources are scanned
at their own HEAD; missing/mismatched nested checkouts reject the operation.
The scanner checks clean tracked sources and validates Git roots. Untracked and
ignored source files are outside HEAD history scanning, not certified clean.
Runtime history scanning requires an explicit full upstream commit and ancestor
validation, and scans only that base..HEAD patch range. Backup refs are excluded.
Loader owns the reviewed upstream false-positive fingerprints; Patcher starts
with no exceptions. These checks audit publication inputs, not installed files.
Loader's scripts/verify.ps1 owns its host/script and Interop
source regressions, optional desktop build, and selected Android build/repack
check. It uses the same source-root/development selection as product builds,
without requiring Patcher or mutating process-wide caches. Patcher retains its
own scripts/test.ps1. SkipDesktop/SkipAndroid explicitly narrow verification;
completion reports the omitted boundaries rather than claiming full coverage.
The release reproducibility check selects profile/development output from the
staged manifest and repacks that same tree, including frozen legacy selection.
Parent setup/build/verify/test/cleanup/publication delegates are retired after
caller inspection; product entries are the only supported commands. Setup
requires an independently cloned product, never umbrella gitlink initialization.
Loader owns its exact SDK policy; Patcher owns a stable .NET 10 latest-feature-band
policy matching its CI, so neither needs a parent global.json.
Actual runtime pack reproducibility, checksum-sidecar and round-trip checks live
in the existing Loader profile test with explicit pack/profile/development inputs
and isolated Output/Tests outputs. No new wrapper or actual-pack startup scan is
introduced. Parent status/audit and the shared environment-cache override are retired;
ordinary git status and existing source/setup/build checks replace them.
Stable historical runtime causes and recovery steps belong to Loader's
RUNTIME-TROUBLESHOOTING.md. Chronological build/device/publication states stay in
private retained evidence, not tracked history documents. The old dual-checkout
raw-nupkg verifier, fixed-revision shell runner, unauthenticated fixed-version
OpenSSL downloader are retired after caller inspection.
Current pack preparation/staging own structural/native gates. CoreClrProbe source
remains available for explicit investigations, and Java/application/device
qualification remains separate from shell execution. No diagnostic assets are
deleted as part of retirement.
The all-SO raw-nupkg inspector retains a distinct glibc/native diagnostic boundary
and lives under Loader scripts/test without the parent unzip cache assumption.
Dependency source checkouts may live as independent siblings of both products.
Physical relocation preserves the whole checkout, its refs/config/status and
ignored outputs; it is not a reset, checkout or cleanup. Only checkouts with
self-contained Git directories are moved directly. Nested submodule metadata
must remain internal and use valid relative paths. Stop builds and validate every
absolute source/destination first. Check the runtime source lock while builds stay
stopped, then close the check's WSL handle before a Windows rename; the open child
lock file can itself prevent directory relocation. Keep builds stopped throughout
this maintenance window. Editor Git watchers may also hold nested .git directories
without a terminal there; release those handles without force-closing processes.
After a partial move, compare already-moved identities to the original snapshot
and move only remaining sources. Do not copy/delete around blocked renames.
WSL reparse points are inspected through WSL because Windows APIs may not expose
their targets. Preserve relative links and external artifact targets without
following them. Old absolute-path CMake/runtime intermediates are evidence, not
portable caches: select fresh output roots for rebuilds after relocation.
Physical dependency relocation is governed by the
[modernization proposal](../../proposed/process/2026-10-02-project-modernization.md).

## Alternatives considered

- A shared dependency lock gives one coordinated snapshot but prevents independent
  product pins and requires the unpublished umbrella repo.
- Always using siblings is convenient for development but builds the wrong source
  when products disagree. Check the pin or use explicit development roots.
- Switching shared siblings during setup saves disk space but disrupts another
  product and can overwrite local work. Use isolated revision caches instead.
- A new shared resolver package avoids a small amount of script duplication but
  adds another synchronized dependency. Each product owns its narrow helper.
- Keeping umbrella cleanup provides one command but mutates other independently
  maintained sources and treats unknown outputs as disposable. Product-owned,
  named cleanup targets keep ownership and evidence retention explicit.
- Discovering publication sources from parent gitlinks is convenient but can scan
  unrelated forks or omit the exact source used by an external build. Explicit
  source selection follows the actual release inputs without a new shared lock.
- A new per-product audit/status framework can duplicate source checks and provide
  a convenient summary, but adds another gate to maintain. Use native Git for
  worktree inspection and reuse pinned setup/build checks for compatibility.
- Moving every historical experiment script preserves reproduction convenience
  but retains obsolete paths, duplicate validation and an old OpenSSL download
  recipe without authenticated inputs. Keep useful lessons/probe source and
  privately preserve exact old scripts instead of presenting them as supported.
- Keeping parent delegates preserves old command names but keeps a second catalog
  and parent path/output defaults to maintain. Product commands and a small local
  redirect index retain discoverability without a new umbrella interface.
- Applying Loader's exact SDK pin to Patcher is reproducible but couples two
  products with different existing CI policies. Patcher follows its own stable
  .NET 10 feature-band policy; Loader retains its stricter existing pin.

## Consequences

Products build from standalone checkouts and may share correctly pinned siblings
without sharing a version authority. Cache copies consume additional disk when
pins differ. Old caches and dependency working trees are preserved. Setup requires
network access only for a new source clone; builds remain offline once inputs are
prepared. Existing runtime artifacts are not moved or deleted by script migration.
Physical relocation does not retire parent compatibility wrappers or consolidate
documentation; those have separate caller checks and retirement gates.
Release maintainers must supply every source input to scanning;
scanning the product alone does not certify a dependency or a release archive.
Product cleanup does not reclaim shared dependency build caches or
runtime source build space; those need deliberate owner-specific maintenance.

Local Git fixtures cover matching/conflicting siblings, independent cache paths,
explicit overrides, dirty/wrong checkouts and pinned setup without shared-source
mutation, including active runtime pins distinct from frozen legacy. WSL runtime
fixtures exercise real launcher/backend path conversion, per-RID output isolation,
development evidence, exclusive locking, existing-artifacts protection and failed
build propagation using a small fixture build.sh. They do not compile CoreCLR.
Product build and publish entries verify the actual manifests/inputs.
Cleanup fixtures operate only on synthetic standalone trees and exercise WhatIf,
default/archive retention, unknown diagnostics, nested Git checkout preservation,
containment and ancestor/nested-link rejection before any selected tree is removed.
Script checks exercise helper behavior without devices or the parent checkout.
Publication fixtures record exact redaction, input/deduplication and range options;
real-scanner mode additionally checks synthetic leaked histories/ZIPs, patch-range
exclusion and private-ref exclusion. Base identity is normalized before comparison
so a trailing source separator cannot silently change a runtime range into HEAD.
Verification-entry fixtures use a standalone product tree and recorded build
commands to exercise pin mismatches, explicit edited source selection, skipped
boundaries, legacy/Bionic development paths and failure/repack propagation.

## Prior-note Audit

The modernization proposal partially overlaps and owns physical moves and
documentation consolidation; it links back to this source-resolution decision.
Runtime source Git and restore-config notes retain their build-specific rationale.
Payload and crash notes do not change dependency ownership.
