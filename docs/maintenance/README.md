# Maintenance work

Read only the document needed for the current task:

- [Modernization roadmap](modernization.md): active goals, stage order, acceptance
  gates, commit policy and resumption checklist.
- [Android status](../android/STATUS.md): current implemented/qualified behavior.
- [Build guide](../android/BUILDING.md): current supported product commands.
- [Testing](../android/TESTING.md): automated and device validation ownership.
- [Payload contract](../android/ARTIFACTS.md) and
  [deployment](../android/DEPLOYMENT.md): current installation/update rules.
- [Maintenance](../android/MAINTENANCE.md): current dependency/release practices.
- [Proposed modernization decision](../../.agents/notes/proposed/process/2026-10-02-project-modernization.md):
  rationale and alternatives. Proposed documents do not change runtime contracts.

This directory belongs to LemonLoader, not the parent workspace. During
migration, existing commands still use the parent workspace where documented;
the roadmap tracks their relocation rather than presenting future paths as
working commands. Keep private inputs, build logs and device evidence outside Git.
