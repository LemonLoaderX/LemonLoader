# Ownership inventory

Status: migration inventory, not a completed move. Updated 2026-10-02.

## Current source authorities

| Concern | Current authority | Destination |
| --- | --- | --- |
| Loader fork pins | Loader `eng/AndroidDependencies.props` | Loader, retained |
| Active runtime pins/profile | Loader `eng/runtime-profiles.json` | Loader, retained |
| Patcher Interop pin | Patcher `Directory.Build.props` | Patcher, retained |
| Parent checkout lock | parent `.gitmodules` and gitlinks | retired after standalone validation |
| Loader release CI | Loader `.github/workflows/android.yml` | Loader, retained |
| Patcher release CI | Patcher workflows and scripts | Patcher, retained |
| Runtime source build | Loader `build-runtime.ps1` and WSL backend | Loader; parent wrapper retained during migration |
| Runtime setup | Loader `setup-runtime.ps1` | Loader; non-mutating pinned source setup |
| Product build entry | Loader `scripts/build.ps1`; parent wrapper retained during migration | Loader |
| Source setup/audit/status | parent scripts | per-product manifest validation |
| Syntax/helper verification | parent `test-scripts.ps1` | per-product tests |
| Source/archive secret scan | parent `scan-publication.ps1` | owned release checks |
| Cleanup | parent `clean.ps1` | per-product output cleanup |
| Runtime current docs | Loader `docs/android/RUNTIME-DEVELOPMENT.md` | Loader, retained |
| Runtime historical evidence prose | parent `RUNTIME-EXPERIMENT.md` | compact Loader history/notes |
| Parent operations/status | parent docs | current facts merged into Loader docs |
| Historical device/OpenSSL probes | parent diagnostic scripts | inventory callers before retaining/retiring |

## Existing path coupling

- Both products select a matching sibling HEAD or a private per-revision cache.
  Loader reads its props; Patcher independently reads generator URL/revision from
  its own props. Setup never switches shared or existing checkouts. Parent builds
  still override Loader paths with `dependencies/*` during physical migration.
- Loader release CI operates from the Loader checkout and downloads reviewed
  runtime artifacts; it does not require the parent Git lock. Local runtime
  source build/setup is also Loader-owned; remaining parent audit/test coordination
  still needs migration.
- Runtime builds use an artifacts symlink and per-RID outputs under Loader Output
  or an explicit output root; parent wrappers retain historical temp paths.
  Move only after builds stop; preserve the existing target and avoid a recursive
  cleanup following a link.
- Nested dependency Git metadata must be inspected before physical moves. A
  `.git` file may point into parent submodule storage; moving only the directory
  is not sufficient to create an independent clone.

## Installation identity ownership

- Loader staging creates Release file inventories and source/runtime audit
  identity. Active layout-9 payload configuration contains only format/RID;
  frozen layout-8 staging retains the historical recipe.
- Patcher validates the Release and adds Interop DLLs/deployment files. Layout 9
  emits non-seed policy overrides without generated digests, revision or copied
  Interop manifest. Its layout-8 compatibility path retains the old computations.
- The native host checks actual CoreCLR/crypto loading and reads deployment from
  actual assets and optional path policies, ignoring declared hashes/revision
  and identity digests. Package lastUpdateTime supplies all extraction freshness.
  Optional deployment errors
  disable Loader before symbol redirects; Unity remains loaded. Required runtime
  extraction and redirect failures retain their rollback path.
- Candidate destination: a minimal Loader-owned file layout/extraction/update
  contract, with optional Patcher. Remove unnecessary metadata requirements first;
  do not assume shared metadata-generation tooling is needed. No per-file
  diagnostic system or routine startup scan is requested.
- Declared deployment revision is not an authenticity boundary: an APK editor
  can change content and metadata together. The current consumer no longer uses
  it for admission or freshness. Per-file previous hashes support user-edit
  preservation only during updates or explicit enforcement.
- Normal extraction compares APK update time to its saved marker and directory
  existence; it does not recompute installed file hashes. Release validation
  separately checks individual files. Neither requires a new diagnostic framework.
- Upstream MelonAssembly loads the file and reports exceptions; it also prints a
  Mod hash without making it a manifest admission check. Reuse ordinary loading
  behavior rather than add corruption diagnosis.

## Crash evidence baseline

- Native normal logging writes Android logs and flushes Latest/history streams.
  Startup reset preserves the previous nonempty session in Previous.log before
  history configuration; failure falls back to append mode.
- Loader configures CoreCLR's existing in-process reporter and retains one
  nonempty interrupted default-root report. It installs no new signal handler.
  Reporting must coexist with CoreCLR's handled faults and Android/Unity reporting;
  capturing a signal is not by itself proof of a fatal crash.
- Candidate evidence tiers: previous-session logs; minimal bounded crash/session
  context; maintained native trace tooling; API 30+ exit info (native tombstone
  streams start at API 31) as a supplement;
  private exact-build symbols and an accessible next-launch export.
- The rebuilt .NET 11 source already enables an in-process reporter for both
  target profiles. Prefer validating this before adding signal handlers or a
  new crash library. Native-only faults may have just a synthesized crash-site
  frame, not full native unwinding. See the [scoped investigation](../../.agents/notes/proposed/feature/2026-10-02-native-crash-evidence.md).

## Retirement rule

Before deleting a script/doc, search every caller and CI reference, confirm its
replacement or intentionally unsupported workflow, move unique rationale into
its owner and run the affected entry point. Historical artifacts/private inputs
are not deletion targets. See [roadmap](modernization.md) for stage gates.
