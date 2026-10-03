# Project modernization

This document defines goals and execution order, not local build status.
Build jobs, artifact hashes, test-run results and acceptance progress belong in
ignored local records; keep only stable decisions and commands in repository docs.

## Goals

1. Finish rebuilding the embedded-DEX Android runtime and matching Loader/Patcher
   artifacts, independently review the changes, and prepare outputs for the
   maintainer's later device acceptance. Supported products require API 26+;
   CoreCLR 10 recovery is retired.
2. Retain useful native crash evidence on the device without requiring a user
   to run logcat. Preserve previous-session logs and provide an accessible,
   bounded diagnostic export with offline symbolization inputs.
3. Simplify the whole installation/update contract, not only deployment revision.
   Remove unnecessary generated metadata and hash admission gates so manual
   installation/MT Manager edits do not depend on Patcher. Reuse ordinary loading
   errors/logs; do not add per-file diagnostics or routine startup scans.
4. Remove the parent repository as a required version lock and build coordinator.
   LemonLoader and Patcher independently own their dependencies and workflows.
5. Reduce maintenance and onboarding cost: concise indexed documentation, a small
   set of supported scripts, and explicit ownership instead of duplicate rules.
6. Remove obsolete runtime schemes and redundant compatibility after caller/test
   inspection. Consolidate old references and unique investigation evidence into
   ignored history; delete re-creatable stale work without following links.

## Confirmed scope and guardrails

- The maintainer authorizes incremental local commits. Do not push, publish,
  install APKs, change signing state, uninstall or clear application data.
- Preserve unrelated worktree edits, independent Git histories, unique private
  evidence, current runtime packs, acceptance symbols, signing material and
  application data. Obsolete generated work may be removed; unique old evidence
  and unused reference checkouts are consolidated, not kept as active inputs.
- Keep unsafe ZIP paths, duplicate entries, ABI errors, native-name collisions,
  existing download/release hash or signature validation, and actionable runtime
  compatibility/missing-input errors. This does not require preserving every
  installed-payload hash/revision gate or replacing it with another framework.
- Deployment revision is an update/cache hint, not an authenticity guarantee or
  permission to start the game. A hash stored beside mutable content does not
  establish trust. Distinguish download/build consistency checks, authenticated
  inputs (where actually supported), per-file ownership and runtime compatibility.
- Device qualification is the maintainer's later gate; host tests and NDK builds
  do not prove ART, TLS, crash unwinding or all target applications.
- New work is owned by the relevant repository. The parent folder ultimately
  becomes an optional local container, not a required repository or pin source.
- Existing unsupported or legacy paths are inventoried before removal. Remove
  obsolete scripts only after caller/workflow checks and a replacement or an
  explicit retirement decision; do not delete private evidence as cleanup.

## Current facts

- Crypto helpers are loaded from the bootstrap with InMemoryDexClassLoader and
  an explicit runtime initialization export; earlier runtime packs lack it.
- Identity generation is not entirely in Patcher: Loader staging produces
  runtime/payload identities; Patcher finishes game-specific deployment and
  Interop identities. The native host reads actual deployment assets and optional
  policies without declared revision/hash checks. Runtime extraction also uses
  package update time; actual library loading retains compatibility checks.
- Native logging flushes normal writes, but resetting Latest.log and configuring
  history are separate startup stages. A flush alone is not a crash recorder.
- Product repos already have dependency manifests. Parent scripts/gitlinks and
  sibling source assumptions still impose additional coordination.

## Target ownership

```text
LemonLoader-Project/           optional local parent; no required root Git lock
  LemonLoader/                product, installation contract, primary docs
  LemonLoader.Patcher/        APK adapter, CLI/GUI, its own dependency pins
  Dobby/
  dotnet-runtime/
  HarmonyX/
  Il2CppInterop/
  MonoMod/                    retain its own nested dependencies where applicable
```

Each repo is independently cloneable/buildable. Product manifests pin exact
reviewed revisions or versioned artifacts. A sibling checkout is a convenience,
not automatically modified to satisfy a conflicting product pin. Define a
source-root override and clear mismatch errors, with an isolated fetch/cache
path when two products require different revisions. Do not introduce a new
mandatory umbrella repo under another name.

## Stages and exits

### Cleanup boundary

The [CoreCLR 10 retirement decision](../../.agents/notes/implemented/simplification/2026-10-03-retire-coreclr10-workflows.md)
supersedes the former frozen recovery rule. Current builds support only .NET 11
Android/Bionic and API 26+. The [reader retirement](../../.agents/notes/implemented/simplification/2026-10-03-retire-layout8-readers.md)
removes layout 8, external DEX and historical MonoVM inputs while retaining active
safety/policy tests and explicit unsupported-input errors. Desktop upstream
code, Unity file-format support and required fork adaptations are not blanket
cleanup targets. Local cleanup inventories/results belong outside Git.

### P0: Durable plan and baseline

- Persist goals, constraints, sequence and acceptance gates in Loader.
- Inspect ownership and existing decisions; preserve unrelated proposal.
- Commit the plan separately from implementation.
- Record initial [ownership inventory](ownership.md); exhaustive caller and
  Git-metadata checks remain mandatory before P4 physical moves/deletions.

Exit: a resumable plan exists in the primary product without requiring chat
history; runtime behavior has not been changed by planning.

### P1: Review and rebuild embedded crypto

- Review native initialization, JNI references, ClassLoader parent, buffer
  lifetime, exception paths, P/Invoke handle reuse and compiler/linker exports.
- Review build/staging identity, API declarations, legacy compatibility and
  new-mode APK verification. Fix defects with focused regressions.
- Commit runtime changes in their source fork; use that real source identity
  for rebuilds. Do not update pins to a fictitious/uncommitted revision.
- Rebuild Android and Bionic from the reviewed common runtime source; preserve
  separate outputs and old packs. Normalize/import/package validated packs.
- Update consuming pins, build matching Loader/Patcher development artifacts, check no new
  top-level DEX and retain hashes/symbols/logs privately.
- Commit Loader and Patcher changes separately after their automated gates.
- Produce a [device-acceptance checklist](embedded-crypto-acceptance.md); maintainer performs installation and
  crypto/TLS/lifecycle/namespace tests later.

Exit: matching, locally verified development artifacts and exact commands are available.
Do not label them device-qualified or publish them before device acceptance.
Publish reviewed runtime inputs before consuming product releases.
Do not relabel existing development packs as formal packs.

### P2: Native crash evidence

- Inventory CoreCLR/Unity handlers, existing logs, Android exit information
  and storage accessibility; distinguish faults from SIGKILL/OOM/ANR.
- Evaluate a maintained Android crash library against a minimal recorder;
  select based on handler coexistence, APK/bootstrap integration, reliability
  and maintenance cost, not the attractiveness of a full dump alone.
  Existing .NET 11 in-process reporting is a third candidate; see the
  [scoped investigation](../../.agents/notes/proposed/feature/2026-10-02-native-crash-evidence.md).
- Preserve last-session logs before truncation, including early-startup
  failures. Prepare bounded report storage before a fault can occur.
- Persist crash/session identity, signal/code/fault address, register context,
  module identity/load bias and available trace. Preserve unstripped symbols
  outside public releases for offline symbolization.
- Do not allocate, lock normal log mutexes, call JNI/.NET or perform complex
  unwinding in a fatal signal handler. Do not treat CoreCLR's internally handled
  signals as fatal crashes, swallow original faults or suppress Android reports.
- Recover/export evidence on the next launch through app-accessible storage;
  evaluate API 30+ ApplicationExitInfo as supplemental evidence, not API 26
  coverage. Bound retention and redact sensitive data by default.
- Test faults in subprocesses, handler chaining, early crashes, recursive
  faults, low storage, truncated reports, report rotation and symbol matching.

Exit: another-device user can provide retained evidence without live logcat;
coverage limits (pre-init faults, SIGKILL, OOM, corrupted process state) are explicit.

### P3: Installation/deployment contract owned by Loader

- Reassess all manifests, identity digests, mixed domain hashes, extraction
  markers and deployment policy state from actual installation/update needs.
  Prefer deleting unnecessary requirements, not rebuilding the same machinery.
- Compare with upstream MelonLoader's directory installation/loading. Keep
  demonstrated Android requirements: APK asset extraction, private runtime files
  and process-safe publication. Do not add per-file corruption diagnostics,
  expected-file inventories or routine startup scans; reuse existing error logs.
- Remove deployment revision self-consistency as a startup prerequisite. Treat
  legacy revision as an optional rollout hint or retire it when equivalent update
  decisions are derived locally. Missing/stale declared revision must not prevent
  the game from starting or require a manual installer to recalculate it.
- Evaluate whether a global deployment revision is needed at all. Preserve
  only the state needed for refresh-once, user-edit preservation, safe obsolete
  file handling and transactional recovery. Per-file previous hashes can support
  those decisions without pretending to authenticate the APK's editable content.
- Specify a minimal Loader-owned file layout and extraction/update behavior.
  Patcher is an optional adapter, not an admission authority. Do not build a
  metadata-generation framework unless necessary metadata remains after deletion.
- Make ordinary deployment explicitly editable; do not introduce a mandatory
  locked/verified path merely to keep the current manifest design. Evaluate
  optional managed/locked policies for a demonstrated distribution need.
  Filename/content edits should not require manually recomputing revision fields.
  Existing locked/enforce policies require an explicit migration decision; they
  are deployment behavior, not anti-tamper protection against an APK editor.
- Isolate optional deployment failures from base game startup. Determine safe
  Loader-disable/fallback points before installing hooks or changing startup;
  do not continue from partially initialized runtime state.
- Support a minimal third-party/manual injection workflow: documented native
  replacement, release extraction, explicit game Interop input, private runtime
  installation and local Mods path. APK signing/Android permissions still apply;
  do not promise that PC-style extraction removes these platform requirements.
- Test MT Manager-like add/edit/delete, stale metadata, unsafe paths, protected
  tampering, locked behavior, interrupted updates, rollback and old consumer
  compatibility. Change schema versions only if old consumers cannot interpret
  the new semantics safely.

Exit: a second minimal installer and ordinary local deployment edits work without
Patcher internals, manual digest regeneration or new scanning overhead. Existing
release/download verification and structural safety checks remain.
Deployment revisions are not admission checks. Document what validation detects
and its trust source; do not label colocated hashes as proof of authenticity.

### P4: Independent repositories and sibling layout

- Assign every root script/doc/config to Loader, Patcher, a dependency owner,
  or obsolete/local-only status before moving it.
- Move build/setup/audit/runtime/release workflows into their owners and update
  CI, explicit source paths, source pin validation and output roots.
- Move primary maintenance docs/agent rules to Loader; Patcher links to public
  contract docs but retains its own commands and operational responsibilities.
- Migrate dependency checkouts with verified absolute targets and repository
  identity/status checks; preserve .git metadata, dirty work and output links.
  Do not let parent submodule metadata become a hidden build dependency.
- Verify clean standalone Loader/Patcher clones with matching dependencies,
  conflicting sibling revisions, explicit overrides and local development edits.
- Retire the parent lock/build scripts only after independent workflows pass.
  Preserve the old local root/history for recovery instead of destructive reset.

Exit: neither product needs files, Git metadata or commands from the parent repo;
both independently control their dependency revisions.

### P5: Documentation/script simplification and final audit

- Provide a short primary index by task: use/install, build, troubleshoot,
  contribute/release, public contracts and active decisions.
- Keep current commands in one authoritative location; keep current status
  separate from rationale and historical/private evidence.
- Put decisions in proposed/implemented/rejected notes by topic; do not flatten
  everything into one long file or build redundant note/index hierarchies.
- Consolidate duplicate helpers, remove unreferenced obsolete scripts/docs and
  repair links. Keep stable narrow entry points and explicit output locations.
- Run complete repository-specific regression/CI-equivalent checks and a
  clean-clone onboarding walkthrough; document remaining device gates.

Exit: a newcomer can build/diagnose through the index without knowing the old
workspace layout; retired paths have no live script/CI references.

## Execution and commit policy

Work in the above dependency order. Parallel unrelated architecture changes are
not required. Every nontrivial decision gets a scoped note before implementation;
tentative design bullets are investigation tasks, not already-approved formats.

Keep commits per owner and purpose: plan, runtime fix/test, artifact pin update,
Loader behavior, Patcher adaptation, crash evidence, deployment contract, tooling
migration, then obsolete-file cleanup. Record verification and known limitations
in commit bodies. Never stage all parent or subrepo changes blindly. Do not commit
generated packs, private traces, APKs, symbols, keys or build evidence.

## Resume checklist

1. Read this plan, current status and the target repo's rules.
2. Inspect all affected worktrees and active build jobs; preserve edits.
3. Select the earliest unfinished stage and its narrowest exit condition.
4. Run the documented narrow test, inspect diff and actual artifacts.
5. Record progress, blockers and the next command in ignored local records;
   make a scoped commit for source or stable documentation changes.
