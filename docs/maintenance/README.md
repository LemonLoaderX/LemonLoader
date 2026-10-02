# Maintenance work

Read only the document needed for the current task:

- [Modernization roadmap](modernization.md): active goals, stage order, acceptance
  gates, commit policy and resumption checklist.
- [Ownership inventory](ownership.md): current producers, paths and planned owners.
- [Embedded crypto acceptance](embedded-crypto-acceptance.md): maintainer's later
  device matrix and evidence, without installation/signing changes.
- [Crash evidence investigation](../../.agents/notes/proposed/feature/2026-10-02-native-crash-evidence.md):
  runtime reporting, supplemental traces and Android coverage boundaries.
- [Android status](../android/STATUS.md): current implemented/qualified behavior.
- [Build guide](../android/BUILDING.md): current supported product commands.
- [Testing](../android/TESTING.md): automated and device validation ownership.
  Loader scripts/verify.ps1 and Patcher scripts/test.ps1 are independent; native
  host suites, runtime compilation and device checks remain explicit workflows.
- [Publication audit](../android/MAINTENANCE.md#publication-audit): explicit source
  histories and final archives, without parent gitlink discovery.
- [Runtime troubleshooting](../android/RUNTIME-TROUBLESHOOTING.md): retained
  build, Bionic feature, crypto and source-adaptation lessons, without local timelines.
- [Payload contract](../android/ARTIFACTS.md) and
  [deployment](../android/DEPLOYMENT.md): current installation/update rules.
- [Maintenance](../android/MAINTENANCE.md): current dependency/release practices.
- [Proposed modernization decision](../../.agents/notes/proposed/process/2026-10-02-project-modernization.md):
  rationale and alternatives. Proposed documents do not change runtime contracts.

This directory belongs to LemonLoader, not the parent workspace. During
migration, existing commands still use the parent workspace where documented;
the roadmap tracks their relocation rather than presenting future paths as
working commands. Keep private inputs, build logs and device evidence outside Git.
Local build status, artifact hashes and acceptance progress also stay in ignored
records, not this index, the roadmap or design notes.
