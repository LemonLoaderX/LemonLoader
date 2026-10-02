# Project documentation

The repository contains the MelonLoader desktop baseline and a maintained
Android adapter. Start with the task below, then read only the relevant contract.

## By task

- Install or edit an APK: [usage and manual injection](android/USAGE.md),
  [payload layout](android/ARTIFACTS.md), [deployment policies](android/DEPLOYMENT.md).
- Build Loader: [building](android/BUILDING.md). APK generation belongs to
  [Patcher](https://github.com/LemonLoaderX/LemonLoader.Patcher).
- Develop CoreCLR: [source workflow](android/RUNTIME-DEVELOPMENT.md),
  [runtime troubleshooting](android/RUNTIME-TROUBLESHOOTING.md).
- Diagnose a failure: [troubleshooting](android/TROUBLESHOOTING.md),
  [test boundaries](android/TESTING.md).
- Maintain or release: [maintenance](android/MAINTENANCE.md),
  [release notes](releases/README.md), [modernization](maintenance/README.md).

## Android documentation

| Document | Audience | Purpose |
| --- | --- | --- |
| [Project overview](../README.md) | Everyone | Supported target, repository responsibilities, and build entry point |
| [Current status](android/STATUS.md) | Everyone | Verified capabilities, support boundary, and remaining qualification work |
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
- Product dependency manifests own source pins; Release manifests/checksums
  describe distributable inputs. Installed payload configuration is not a digest
  admission gate, and active layouts need no Interop generation manifest.
  Keep local build hashes, job status and acceptance progress outside tracked docs.
- Keep commands parameterized and free of machine-specific paths. Small
  implementation changes do not require synchronized edits to every overview
  document.
- Keep APK-tool-specific steps out of runtime scripts. Document their required
  input and output through `ARTIFACTS.md`.
- Never include keystores, passwords, decoded games, generated Interop
  assemblies, APKs, device logs, or build output in the repository.

## Repository guides

- [Script catalog](../scripts/README.md)
- The managed compatibility patcher is maintained in the separate
  `LemonLoader.Patcher` repository.
- [Test projects](../tests/README.md)
- [Android build support](../build/android/README.md)
