# Contributing to LemonLoader

LemonLoader maintains an Android adapter over the desktop upstream baseline.
This guide owns development rules; [the task index](docs/README.md) selects the
technical contract and [AGENTS.md](AGENTS.md) is the concise agent entry point.

## Repository organization

| Area | Responsibility |
| --- | --- |
| MelonLoader/ | Managed lifecycle and Mod-facing interfaces |
| MelonLoader/Android/ | Android/JNI hosting, peers, bindings, callbacks and UI dispatch |
| MelonLoader.Bootstrap/Platforms/Android/Native/ | Native bootstrap, extraction, loader/runtime initialization |
| Dependencies/SupportModules/, UnityUtilities/ | Unity-specific integration, separated from general hosting |
| Dependencies/JavaInterop/ | Integration of the pinned upstream Java.Interop source |
| eng/, global.json, Directory.Build*.props | Product-owned dependency, runtime and toolchain selection |
| scripts/ | Reusable preparation, build, validation, device and cleanup operations |
| tests/ | Regressions grouped by the behavior they exercise |
| docs/, .agents/notes/ | Stable task guides and design rationale |
| Output/, .dependencies/ | Generated evidence/artifacts and pinned source caches; not source documentation |

Keep related implementation and tests near their current owner. Add a directory
for a real responsibility, not a speculative layer or one forwarding helper.
Upstream/vendored organization is preserved; do not move it merely to match this
table. New project boundaries need independently useful responsibilities.

Dependency fixes belong in the source fork. PATCHES.md records upstream base,
root cause, validation and removal condition; the consuming product updates its
pin separately. Never switch a shared checkout or repair compatibility by rewriting
compiled dependencies. A source sync does not automatically upgrade consumers.

## Design and code style

- Prefer cohesive modules with small interfaces. Keep public surface limited to
  intended Mod/host contracts; use internal implementation types otherwise.
- Add an abstraction, option, cache, retry or compatibility layer only for a current
  use case. Explain what it simplifies, who owns it and when it can be removed.
  Shared implementation is useful; a general framework for one caller is not a goal.
- Separate policy from file/native/process operations where it makes behavior
  testable. Do not scatter the same validation or duplicate entire pipelines.
- Make ownership, disposal, thread affinity, cancellation and commit points explicit.
  Borrowed JNI/native handles remain borrowed. Unsafe code must document the ABI,
  lifetime and synchronization assumptions that cannot be inferred from its types.
- Keep Android behavior behind existing platform boundaries. Preserve desktop and
  old reference-target behavior when changing shared source; do not add game-specific
  branches or mask another runtime/emulator's incorrect contract.
- Follow .editorconfig/.gitattributes and nearby style; formatter settings own
  whitespace. Do not mass-format, sort or rename unrelated upstream code. New C#
  types/files use meaningful type names, locals name their purpose and async methods
  follow the existing Async convention. Keep language features compatible with each target.
- Prefer explicit input/result types and normal control flow. Respect nullability;
  avoid broad suppression, magic offsets and stringly typed mode switches when an
  existing type expresses the contract. Small duplication is preferable to a misleading abstraction.
- C/C++ code follows its existing platform style and uses scoped ownership for
  acquired resources. Preserve page permissions, alignment, publication and ABI rules.
- PowerShell functions use Verb-Noun names and declared parameters. Check native
  command exit codes. Bash scripts quote paths and use argument arrays; do not build
  shell commands from untrusted strings. Keep shared helper files free of startup work.
- Comments explain why, invariants and unusual constraints. Public interfaces need
  useful contract documentation, not boilerplate repeating their names. Errors and
  production logs identify an action the user can take; secrets and routine inventories stay out.

## Documentation

Public source documentation and code comments use English consistently with the
repository. Local handoff notes may use the maintainer's language. Write short,
concrete instructions with scope, prerequisites, expected behavior and limitations.

| Document | What belongs there |
| --- | --- |
| README.md | Product purpose, supported use and links to starting tasks |
| AGENTS.md | Essential constraints, source map and selected command entry points |
| CONTRIBUTING.md | Development workflow, design/style, documentation/testing and cleanup policy |
| docs/README.md | Task navigation; not a duplicate specification |
| docs/android/ | Installation, runtime/JNI/artifact contracts, build and test procedures |
| docs/maintenance/ | Durable qualification/recovery procedures and remaining platform boundaries |
| docs/releases/<tag>.md | Version-specific breaking changes, migration and known limitations |
| .agents/notes/ | Nontrivial decisions: problem, chosen approach, real alternatives and consequences |
| Output/<task>/ | Private commands, input identities, results, logs and one current checkpoint |

Each contract has one authoritative topic. Link to it from overviews instead of
copying options, versions or long procedures. Commands name their shell and working
directory; distinguish defaults from prerequisites and placeholders. Do not create
a guide, note or checklist for every small edit.

Update the existing decision topic when facts change. A reversed decision gets a
new note with explicit supersession links; retain only unique rationale needed to
avoid repeating a mistake. Remove fully absorbed duplicates and fix inbound links.
Implemented notes describe current decisions; label superseded parts clearly.
Do not add meaningless archives, empty templates or a second source-of-truth index.

Update affected documentation in the same change as the contract. Remove stale
paths and commands. Local job status, device addresses, full build commands,
artifact hashes and private acceptance history belong in ignored output, never
tracked guides or design notes. Historical release notes describe their version.

## Verification

[Testing](docs/android/TESTING.md) owns exact commands. Before running one, identify
which behavior or boundary changed and what evidence is already available.

| Change | Smallest useful verification |
| --- | --- |
| Prose/comments only | Check facts, links, command paths and diff; no product rebuild |
| Setup/script/helper | Affected script fixture and syntax/parameter checks |
| Managed behavior | The corresponding managed regression project |
| Native/JNI/ABI | Focused host/native fixture, then target execution when the changed contract needs it |
| Payload/packaging/public interface | Producer and consumer contract checks with representative artifacts |
| Shared code or release | Broader affected targets and the maintained CI/release gates |

Tests assert observable contracts, including relevant failures, cancellation,
ownership and rollback. Prefer a reproducer that fails on the original defect.
Do not mirror private implementation steps, rely only on source-text matching or
add tests for mechanical edits. Use synthetic inputs for routine tests and mocks
for external boundaries; use real serialization/native calls where mocks cannot
prove the property. Keep tests independent and responsible for their fixtures.

Preserve ZIP paths/duplicates, release hash/signature, ABI/native-name collisions
and runtime-pack completeness checks. Do not weaken a test to accept a regression.
Installed digests are not startup admission checks. Unknown additive fields remain
tolerated; only incompatible semantics justify a format/schema version change.

Reuse passed results for unchanged source, pins, tools and fixtures. Repeat or
broaden checks for a relevant change, failure, explicit request or required CI gate,
not merely because another turn or review ended. Never claim a skipped check passed.
Keep functional validation separate from performance evidence: fix inputs and compare
output/behavior before reporting speedups. Host models do not qualify ART, physical
ARM64, 16 KiB devices, TLS endpoints or every Unity version.

## Output lifecycle

Before a large build or device experiment, choose its owned output directory,
inspect available space and identify canonical inputs and restoration needs.
Use ignored Output/<task>/ for diagnostics; normal scripts keep their established
output paths. Reuse inputs and process variants sequentially when separate copies
are unnecessary. Do not expand to another drive to avoid cleaning existing outputs.

At each completed boundary, retain current deliverables, their minimal identity,
matching private symbols and evidence for unresolved failures. Remove reproducible
intermediates, duplicate APKs/decoded games, obsolete variants and finished tool
downloads. Keep recovery backups until restoration has been verified. Do not
delete unique user inputs, keys or logs that are the only evidence of an open issue.

Stop owned jobs and preview the existing cleanup entry:

```powershell
pwsh -NoProfile -File scripts/clean.ps1 -WhatIf
pwsh -NoProfile -File scripts/clean.ps1
# Preview archive/pack removal only when those outputs are intentionally in scope:
pwsh -NoProfile -File scripts/clean.ps1 -AllOutputs -WhatIf
```

Default cleanup owns known build trees and bin/obj; AllOutputs additionally covers
known packs/archives. Diagnostics, runtime-source outputs, unknown directories,
source caches and siblings are preserved. Resolve absolute targets before recursive
operations and reject links; never clean through the runtime artifacts symlink.
Disposable Git fixtures need a specifically recorded owned root, not a blanket
exception for nested repositories. If cleanup is blocked, record the exact leftover
path/reason and stop that action; changing tools or shells is not a workaround.

## Delivery and permissions

Keep changes scoped to the owner and purpose. Preserve unrelated worktree edits;
do not reset, stash, rewrite history or switch shared branches for convenience.
Commits, pushes, tags, releases and device mutation require authorization for that
scope. Once granted, complete that scope without repeated confirmation; do not
carry a completed release's authorization into unrelated later work.

Use scoped Conventional Commit subjects and explain non-obvious cause, behavior
and validation. Mark breaking changes and provide concrete migration instructions.
Loader's base version follows the selected upstream baseline; Android releases
retain their own tag identity. Payload schema and product release versions are
separate. [Maintenance](docs/android/MAINTENANCE.md) and
[release notes](docs/releases/README.md) own publication procedures.

Reviewed dependency commits must be remotely obtainable before consumer release
tags. Use the maintained tag workflow; do not create a competing manual Release,
move a published tag, replace public binaries or relabel development artifacts.
Public archives exclude applications, generated game Interop, credentials, signing
material, private paths, logs and full build provenance. Runtime symbols remain private.

Routine tests never uninstall applications, clear app data, rename packages or
change signing identity. Authorized device work uses existing inputs, explicit
backup/restoration and verified recovery. A tool policy is enforced by the runtime,
not by this document; report denials and never bypass them.

Handoff states the change, checks and their limits, artifact locations and cleanup
status. Keep one current local checkpoint and link supporting evidence; avoid a
new report for every tool call or another full verification pass just to finish.
