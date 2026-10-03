# Documentation

Start with the task, then follow the relevant contract. Commands run from the
owning repository root; a parent checkout is not required.

| Task | Guide |
| --- | --- |
| Install Loader, add Mods or edit an APK | [Usage](android/USAGE.md) |
| Implement an installer | [Payload layout](android/ARTIFACTS.md), [deployment policies](android/DEPLOYMENT.md) |
| Build Loader | [Building](android/BUILDING.md) |
| Build or update CoreCLR packs | [Runtime development](android/RUNTIME-DEVELOPMENT.md), [runtime troubleshooting](android/RUNTIME-TROUBLESHOOTING.md) |
| Generate game Interop | [Interop workflow](android/INTEROP.md) |
| Diagnose startup, crashes or hooks | [Troubleshooting](android/TROUBLESHOOTING.md) |
| Change native or managed hosting | [Architecture](android/ARCHITECTURE.md), [runtime](android/RUNTIME.md), [failure contracts](android/HARDENING.md) |
| Select tests | [Testing](android/TESTING.md) |
| Check support boundaries | [Status](android/STATUS.md) |
| Maintain forks or publish | [Maintenance](android/MAINTENANCE.md), [release notes](releases/README.md) |
| Qualify a runtime on a device | [Device acceptance](maintenance/embedded-crypto-acceptance.md) |
| Resume modernization work | [Remaining gates](maintenance/modernization.md) |
| Find a script | [Script catalog](../scripts/README.md) |

[Contributing](../CONTRIBUTING.md) owns change/cleanup rules; [AGENTS.md](../AGENTS.md)
owns agent constraints. Decisions and rejected alternatives live by topic in
`.agents/notes/{proposed,implemented,rejected}`; runtime source adaptations live
in each fork's PATCHES.md. Do not repeat a decision across overview documents.

Keep one authoritative command per workflow. Update its guide and callers when
changing it. Release-specific notes describe their version, not current support.
Private paths, artifact hashes, build/job status, device evidence, applications,
generated Interop, symbols and signing material stay in ignored local output.
