# Project documentation

The repository contains the MelonLoader 0.7.3 desktop baseline and a maintained
Android adapter. Upstream desktop behavior is documented in the root
`README.md`; the documents below describe the Android fork and the rules for
keeping it mergeable with desktop upstream.

## Android documentation

| Document | Audience | Purpose |
| --- | --- | --- |
| [Project overview](../README.md) | Everyone | Supported target, repository responsibilities, and build entry point |
| [Contributing](../CONTRIBUTING.md) | Contributors | Change ownership, validation, and commit expectations |
| [Android overview](android/README.md) | Everyone | Scope, support matrix, repository model, and documentation map |
| [Architecture](android/ARCHITECTURE.md) | Runtime developers | Startup sequence, runtime layout, and hard invariants |
| [Building](android/BUILDING.md) | Builders and CI maintainers | Prerequisites, commands, outputs, and reproducible inputs |
| [Testing](android/TESTING.md) | Contributors and release engineers | Static, build, compatibility, and device test expectations |
| [Usage](android/USAGE.md) | APK tooling authors and Mod users | Payload integration, runtime directories, updates, and configuration |
| [Maintenance](android/MAINTENANCE.md) | Long-term maintainers | Upstream synchronization, dependency policy, releases, and supply chain |
| [Runtime](android/RUNTIME.md) | Runtime maintainers | CoreCLR, NDK bootstrap, Android cryptography, Harmony, and lifecycle compatibility |
| [Il2CppInterop](android/INTEROP.md) | Tooling authors | Preparing and generating game-specific Interop assemblies |
| [APK artifact interface](android/ARTIFACTS.md) | APK tooling authors | Exact unpacked payload contract and packaging invariants |
| [Troubleshooting](android/TROUBLESHOOTING.md) | Developers and users | Failure signatures, likely causes, and diagnostic artifacts |

## Documentation rules

- Treat commands in `BUILDING.md` and `TESTING.md` as maintained interfaces.
- Record design rationale in `ARCHITECTURE.md` or `RUNTIME.md`, not only in commit
  messages.
- Keep device evidence outside Git and update support claims only after the
  corresponding regression has been reviewed.
- Treat generated `payload.json`, `lemonloader-release.json`, and
  `interop-manifest.json` as the source of truth for current versions and hashes.
  Do not copy ordinary local-build hashes into maintained documentation.
- Keep commands parameterized and free of machine-specific paths. Small
  implementation changes do not require synchronized edits to every overview
  document.
- Keep APK-tool-specific steps out of runtime scripts. Document their required
  input and output through `ARTIFACTS.md`.
- Never include keystores, passwords, decoded games, generated Interop
  assemblies, APKs, device logs, or build output in the repository.

## Repository guides

- [Script catalog](../scripts/README.md)
- The managed compatibility patcher is maintained in the adjacent
  `LemonLoader.Patcher` repository.
- [Test projects](../tests/README.md)
- [Android build support](../build/android/README.md)
