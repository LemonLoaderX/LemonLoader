# LemonLoader agent instructions

LemonLoader is an Android adapter over the desktop MelonLoader baseline. It owns
the injected host, Mod/JNI interfaces, payload/runtime contracts and runtime-pack
tooling. It builds independently of a parent container or Patcher checkout.

## Read by task

Start with [Contributing](CONTRIBUTING.md) for organization, design, code style,
documentation, validation and cleanup rules. Use [docs/README.md](docs/README.md)
to select the relevant contract and [scripts/README.md](scripts/README.md) to find
its maintained command. Read nested instructions for files you touch, not every guide.

## Source map

| Location | Owner |
| --- | --- |
| MelonLoader/ | Managed host and public Mod interfaces; Android-specific code in Android/ |
| MelonLoader.Bootstrap/Platforms/Android/Native/ | Native Android loading, extraction and hosting |
| Dependencies/SupportModules/, UnityUtilities/ | Unity/IL2CPP integration; preserve upstream boundaries |
| Dependencies/JavaInterop/ | Source-built upstream Java.Interop integration |
| eng/, global.json | Product dependency/toolchain pins and runtime profile selection |
| scripts/, tests/ | Reusable operations and focused regressions |
| docs/, .agents/notes/ | Stable guides and decision rationale |
| Output/, .dependencies/ | Ignored generated output and exact source caches |

## Commands and verification

Run from this repository root. Select only rows relevant to the change; SDK/NDK
and runtime-pack prerequisites are in [Building](docs/android/BUILDING.md).

| Task | Entry |
| --- | --- |
| Prepare missing source inputs | `pwsh -NoProfile -File scripts/setup-android-dependencies.ps1` |
| Prepare only Java.Interop for JNI host tests | Add `-JavaInteropOnly` to that setup command |
| Source selection or setup change | `pwsh -NoProfile -File scripts/test/test-source-dependencies.ps1` |
| Script/helper change | `pwsh -NoProfile -File scripts/test/test-scripts.ps1` |
| Managed Android behavior | `dotnet run --project tests/Android/Managed/AndroidManaged.Tests.csproj` |
| One Android profile build | `pwsh -NoProfile -File scripts/build.ps1 -RuntimeProfile android` |
| Bionic profile build | Use the same build entry with `-RuntimeProfile bionic` |
| Broader product verification | `scripts/verify.ps1`; select scope using [Testing](docs/android/TESTING.md) |
| Cleanup preview | `pwsh -NoProfile -File scripts/clean.ps1 -WhatIf` |

Native/JNI/device and runtime-source work has separate prerequisites and test
boundaries in the task guides. Host success does not qualify ART, ARM64 or a game.
Do not repeat unchanged builds/tests just for handoff or after a documentation edit.

## Non-negotiable constraints

- Preserve unrelated edits and upstream behavior. Keep changes in their owning
  module/fork; no game-specific framework branches or post-build binary rewriting.
- Prefer a small public interface with explicit ownership. Do not add a framework,
  cache, option or retry without a present use case and a clear lifecycle.
- Follow `.editorconfig`, `.gitattributes` and existing file style. Keep production
  logs actionable; comments explain contracts and reasons rather than narrating code.
- Keep ZIP/path/duplicate, release hash/signature, ABI, native-name and runtime
  completeness checks. Installed digests are not startup admission requirements.
  Tolerate additive fields; change schemas only for incompatible semantics.
- Keep build/device status, APKs, generated Interop, packs, symbols, secrets and
  signing material outside Git/public archives. Update the owning guide and existing
  decision topic; do not duplicate rules across overview documents.
- Clean known task outputs promptly using [the output lifecycle](CONTRIBUTING.md#output-lifecycle).
  Preserve recovery inputs and exact symbols; never follow output links or clean siblings.
- Commits, pushes, tags, publication and device mutation need scoped authorization;
  do not ask again while that authorization remains applicable. Never reset user work
  or bypass a tool-policy rejection. Routine tests never uninstall, clear app data,
  rename packages or change signing identity.
