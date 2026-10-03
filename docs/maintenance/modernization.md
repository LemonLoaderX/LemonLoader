# Modernization gates

The maintained design is documented in the topic guides and implemented notes.
This file retains the goals and remaining acceptance boundaries; local progress,
jobs, hashes and device results stay in ignored output.

## Goals and owners

| Goal | Authority |
| --- | --- |
| Embedded Android crypto; separate Bionic profile | [Runtime](../android/RUNTIME.md), [crypto decision](../../.agents/notes/implemented/architecture/2026-10-02-embedded-android-crypto.md) |
| Useful crash evidence without live logcat | [Troubleshooting](../android/TROUBLESHOOTING.md#native-crash-evidence), [CoreCLR reports](../../.agents/notes/implemented/feature/2026-10-02-runtime-crash-reports.md), [system traces](../../.agents/notes/implemented/feature/2026-10-02-system-exit-evidence.md) |
| Editable manual installation without generated hash/revision gates | [Artifacts](../android/ARTIFACTS.md), [deployment](../android/DEPLOYMENT.md) |
| Independent products, pins and sibling sources | [Maintenance](../android/MAINTENANCE.md), [source ownership](../../.agents/notes/implemented/process/2026-10-02-independent-source-resolution.md) |
| Retire unused runtimes and compatibility | [CoreCLR 10 retirement](../../.agents/notes/implemented/simplification/2026-10-03-retire-coreclr10-workflows.md), [reader retirement](../../.agents/notes/implemented/simplification/2026-10-03-retire-layout8-readers.md) |

## Acceptance boundaries

1. Review the runtime source fork, then rebuild/prepare both RIDs from one source
   revision. Preserve independent outputs and matching private symbols. Build
   Loader and Patcher from documented inputs; validate actual archives and
   reproducible repacking. Development outputs never become formal packs by
   changing labels.
2. Run the [device matrix](embedded-crypto-acceptance.md) for ART, TLS and native
   namespace behavior. Qualify cold start, Activity recreation, managed/IL2CPP
   lifecycle and a longer Mod session. Host mocks cannot establish those results.
3. Qualify runtime crash reporting alongside CoreCLR/Unity/Android handlers.
   Check handled faults, native and managed fatal paths, interrupted reports and
   next-launch recovery. API 26-29 has no historical system-exit API; API 30 has no
   native tombstone stream. Pre-init faults, SIGKILL/OOM and damaged reporters may
   provide no trace. Richer crash tooling is justified only by demonstrated gaps.
4. Keep source histories, toolchains and output identities available for review.
   Publish reviewed runtime artifacts before consuming product tags; verify that
   independent checkouts can obtain the pinned inputs. Physical 16 KiB-page
   hardware, additional Unity versions and OpenSSL security review are separate
   qualification gates.

## Resuming work

Read the [task index](../README.md) and the target repository's AGENTS.md, inspect
its worktree and active jobs, then select one affected boundary and its smallest
test. Keep commits scoped to the owner and purpose. Record local progress and the
next command outside Git. Preserve unrelated edits and unique private evidence.

Routine work never authorizes pushing, publishing, APK installation, signing
changes, uninstallation or app-data clearing. Do not add installed-file
inventories or corruption scans to replace removed metadata. Historical desktop
code, Unity file-format support and required fork adaptations are not blanket
cleanup targets.
