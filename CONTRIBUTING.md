# Contributing

Read the [task index](docs/README.md) and the relevant contract before changing
code. LemonLoader keeps an Android adapter over the desktop upstream baseline.

## Changes

Preserve existing worktree edits. Fix dependency behavior in its source fork,
with a focused regression and PATCHES.md entry describing upstream base, root
cause and removal condition; consumers then update their own pins. Never repair
compatibility through post-build binary rewriting or game-specific framework
branches. Do not switch shared source checkouts.

[Testing](docs/android/TESTING.md) owns commands and coverage. Select the smallest
test that reaches the original boundary, inspect the diff, then broaden checks
for shared managed code, native hosting or public contracts. Host checks do not
qualify devices.

Record nontrivial choices in .agents/notes by topic: why, alternatives and
consequences. Update an existing note for facts; a reversed decision gets a new
note with supersession links. Fully absorbed duplicate notes may be deleted after
preserving unique rationale and fixing callers. Do not archive worthless drafts.

## Commits and releases

Use scoped imperative subjects; include root cause, behavior and verification
when the diff does not explain them. Keep dependency fixes, consumers and unrelated
work separate. [Maintenance](docs/android/MAINTENANCE.md) and
[release notes](docs/releases/README.md) own publication procedures.
Applications, generated Interop, packs, symbols, logs, private paths, signing
material and build/device progress stay outside Git and public archives.

## Cleanup

Stop builds and retain matching symbols before cleaning:

```powershell
pwsh -NoProfile -File scripts/clean.ps1 -WhatIf
pwsh -NoProfile -File scripts/clean.ps1
pwsh -NoProfile -File scripts/clean.ps1 -AllOutputs -WhatIf
```

Default cleanup owns known build trees and project bin/obj. Packs and archives
require AllOutputs. Runtime source outputs, diagnostics, unknown directories,
source caches and siblings remain untouched. Selected links reject deletion;
never clean through the runtime artifacts symlink. Each repository owns its
outputs; there is no cross-repository Deep mode.
