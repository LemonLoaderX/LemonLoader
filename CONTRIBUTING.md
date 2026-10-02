# Contributing

LemonLoader is maintained as an Android platform layer over MelonLoader. Keep
changes small enough to review and place each fix in the repository that owns
the failing behavior.

## Before changing code

1. Confirm the issue against the current default branch.
2. Identify whether ownership belongs to LemonLoader, the Patcher, or a retained
   dependency fork.
3. Add a regression that reaches the original failure boundary.
4. Avoid game-specific branches in framework code. Private test games are
   integration inputs, not project dependencies.

Inspect each affected worktree with Git and preserve existing edits. Dependency
fixes come first, then each consumer updates its own pin; there is no workspace
gitlink update. Keep fork PATCHES.md entries scoped to the upstream base, root
cause, regression and removal condition. Nontrivial decisions belong in
.agents/notes, updating the existing topic before adding a new one.

## Validation

Run the narrowest relevant test first. Cross-platform managed changes also need
a desktop build. Android bootstrap, runtime, or packaging changes require the
corresponding ARM64 build and artifact verification.

```powershell
pwsh -NoProfile -File scripts/test/test-scripts.ps1
dotnet build MelonLoader.sln --configuration Release -p:Platform=x64
pwsh -NoProfile -File scripts/build/build-android-ndk-bootstrap.ps1 `
    -Configuration Release `
    -AndroidNdkRoot "<android-ndk-r27d>"
```

Do not commit APKs, generated Interop assemblies, runtime packs, logs, signing
material, local paths, or device identifiers.

## Commits

Use an imperative subject with a meaningful scope, for example
`fix(android): preserve CoreCLR startup on restricted kernels`. Explain the
problem, root cause, chosen behavior, and verification in the body when they are
not obvious from the diff. Do not mix dependency updates, generated output, and
unrelated refactoring in one commit.

## Cleanup

Stop builds first and preview from this repository root:

```powershell
pwsh -NoProfile -File scripts/clean.ps1 -WhatIf
pwsh -NoProfile -File scripts/clean.ps1
# Also remove known pack/download/archive directories:
pwsh -NoProfile -File scripts/clean.ps1 -AllOutputs -WhatIf
```

Routine cleanup removes Output/Debug, Release and Dependencies, project bin/obj
and known per-project outputs. Save exact-build symbols outside those build trees
before cleaning. Packs and formal/development archives require AllOutputs.
RuntimeDevelopment, diagnostic/test evidence, private/unknown Output directories,
source caches and sibling repositories remain untouched in both modes. Runtime
source outputs need deliberate maintenance at their real output root, not through
the source artifacts symlink. Links within a selected tree or on its path reject
cleanup before deletion. There is no cross-repository Deep mode.
