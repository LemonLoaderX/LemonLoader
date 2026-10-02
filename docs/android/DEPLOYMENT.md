# Packaged deployment

Packaged files below `assets/LemonLoader/deployment` are installed into the
runtime MelonLoader base directory. Actual APK files are the input; a generated
file inventory, mixed hash or deployment revision is not an installation gate.

## Editable Inputs

Files can be added, edited or removed from that tree with another installer or
APK editor. Reinstall the edited APK as an Android update with the same package
and signing identity. No deployment hash/revision regeneration is required.
Local destinations retain their policy's user-edit behavior.

`payload.json` may contain a `deploymentFiles` array with optional per-path
policies. Only `path` and `policy` are consumed; `policy` defaults to `seed`.
Files absent from the array also use `seed`. Old entries for removed assets do
not make those assets required. Declared `size`, `sha256`, `deploymentSha256`,
`deploymentRevisionSha256` and `deploymentProfile` are ignored by this consumer.
Unsafe/duplicate paths, file/directory conflicts and unknown policies are errors.
Bootstrap-reserved paths and symbolic-link destinations remain prohibited.

For layout 9 Patcher emits only non-seed policy overrides. For older layout-8
Release inputs it preserves the historical metadata recipe. Its packaging
profiles resolve concrete policies:

| Profile | Mods, Plugins, UserLibs | UserData | Other directories |
| --- | --- | --- | --- |
| `development` | `seed` | `seed` | `seed` |
| `production` | `refresh` | `upgrade` | `seed` |
| `locked` | `enforce` | `upgrade` | `seed` |

These profiles are independent of Android/Bionic runtime selection and the
development-source build switch. Enforce is an update policy, not anti-tamper
protection against an APK editor. Release/download consistency checks remain
separate from editable installed deployment.

## Updates And Policies

Android's `PackageInfo.lastUpdateTime` invalidates the private deployment cache.
The first launch of a new APK processes its assets. Ordinary unchanged-package
startup does not traverse the deployment tree or hash files. Explicit `enforce`
overrides retain continuous checks using locally saved packaged hashes.

- `seed`: install a missing file when processing an APK update, otherwise preserve.
- `upgrade`: replace only if the destination still matches the previous packaged
  hash. Preserve user modifications.
- `refresh`: replace on each APK update, then preserve user changes until the next
  update. An update unrelated to Mods still starts a new refresh rollout.
- `enforce`: restore packaged bytes when missing or different; continuously checked
  against prior locally recorded packaged content.

A locally deleted seed/refresh file is not reseeded on every unchanged launch.
Reinstall/update the APK to process packaged inputs again. When update time is
unavailable, Loader retries the transaction instead of trusting a stale cache.

When a previously managed file disappears from the APK, seed preserves it,
upgrade removes it only if unchanged, and refresh/enforce removes it on the next
APK update. Files never managed by Loader are never removed.

## Ownership And Transactions

`.lemonloader-deployment-state` stores prior packaged hashes and policies only
for owned files. Its `.revision` filename is retained for local-state migration,
but now contains the APK update token, not a declared deployment digest. Old
digest state triggers one normal update transaction; it is not an admission check.

A file becomes owned when installed/replaced or when a preexisting file equals
the actual packaged bytes. Merely observing a different user-owned file does
not claim it. Local hashes support upgrade/ownership decisions, not routine
integrity scans or per-file corruption diagnostics.

1. Recover prior state, then extract actual APK deployment assets into owned staging.
2. Validate relative/reserved paths and destination shapes; read staged bytes for
   the existing update-policy comparisons.
3. Read prior ownership, plan changes and back up replacements/removals.
4. Apply changes with sibling temporary files and POSIX rename.
5. Atomically publish the next ownership state, clean staging and prune backups.

An apply or state-commit failure rolls back completed operations in reverse order.
Old state remains authoritative. If deployment parsing/extraction/publication
fails, Loader is disabled before installing symbol redirects or starting managed
code; Unity remains loaded and the original game can start. Mods do not execute
against a possibly incomplete deployment. Errors remain in retained logs.

This document covers deployment only. Required runtime extraction and optional
runtime configuration have their contract in [ARTIFACTS.md](ARTIFACTS.md).
