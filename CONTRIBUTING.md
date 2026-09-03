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

## Validation

Run the narrowest relevant test first. Cross-platform managed changes also need
a desktop build. Android bootstrap, runtime, or packaging changes require the
corresponding ARM64 build and artifact verification.

```powershell
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
