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
| Runtime source build | parent `build-runtime.ps1/.sh` | Loader runtime-build workflow |
| Runtime setup | parent `setup-runtime.ps1` | Loader dependency workflow |
| Product build coordinator | parent `build.ps1` | Loader narrow entry point |
| Source setup/audit/status | parent scripts | per-product manifest validation |
| Syntax/helper verification | parent `test-scripts.ps1` | per-product tests |
| Source/archive secret scan | parent `scan-publication.ps1` | owned release checks |
| Cleanup | parent `clean.ps1` | per-product output cleanup |
| Runtime current docs | parent `RUNTIME-DEVELOPMENT.md` | Loader runtime docs |
| Runtime historical evidence prose | parent `RUNTIME-EXPERIMENT.md` | compact Loader history/notes |
| Parent operations/status | parent docs | current facts merged into Loader docs |
| Historical device/OpenSSL probes | parent diagnostic scripts | inventory callers before retaining/retiring |

## Existing path coupling

- Loader's default source resolver uses `.dependencies/<name>`; its public setup
  already pins fork sources. Parent builds override this with `dependencies/*`.
- Patcher publishing defaults to `../dependencies/Il2CppInterop`; it independently
  verifies the pin in its own props. It needs a sibling/default-cache migration,
  not adoption of Loader's pin.
- Loader release CI operates from the Loader checkout and downloads reviewed
  runtime artifacts; it does not require the parent Git lock. Local runtime
  source build/setup/test/audit still do.
- Runtime builds use an artifacts symlink and per-RID outputs under parent temp.
  Move only after builds stop; preserve the existing target and avoid a recursive
  cleanup following a link.
- Nested dependency Git metadata must be inspected before physical moves. A
  `.git` file may point into parent submodule storage; moving only the directory
  is not sufficient to create an independent clone.

## Installation identity ownership

- Loader staging creates release file inventories, runtime identity and initial
  domain hashes. These are not Patcher-only computations.
- Patcher validates the release, adds generated Interop/deployment files and
  recomputes final domain identities and deployment revision/policies.
- The native host parses these identities, computes deployment revision and
  verifies staged content. Deployment invalidity currently shares the payload
  failure path; this needs a behavioral separation, not just a helper relocation.
  In bootstrap native_load_impl, extraction/redirect failure returns JNI_FALSE
  while the Unity rollback guard remains active. Optional deployment isolation
  must occur before hooks/runtime startup or use a separately verified fallback;
  simply changing that return to success is unsafe.
- Candidate destination: Loader-owned public contract plus a reusable metadata
  tool/interface, consumed by Patcher and a minimal second installer. The precise
  packaging and editable-deployment policy remain P3 design tasks.
- Declared deployment revision is not an authenticity boundary: an APK editor
  can change content and metadata together. Its real consumers are refresh-once,
  obsolete-file actions and the unchanged-deployment fast path. P3 evaluates
  removing global revision and deriving update decisions locally; stale revision
  validation must not gate game startup. Per-file previous hashes may still be
  useful for preserving user modifications, independently of trust.

## Crash evidence baseline

- Native normal logging writes Android logs and flushes Latest/history streams.
  Startup reset truncates Latest before history configuration; early prior-session
  evidence needs rotation independent of managed startup.
- No new crash collector is implemented by this inventory. Signal handlers must
  coexist with CoreCLR's handled faults and Android/Unity reporting. Capturing a
  signal is not by itself proof of a fatal crash.
- Candidate evidence tiers: previous-session logs; minimal bounded crash/session
  context; maintained native trace tooling; API 30+ exit traces as a supplement;
  private exact-build symbols and an accessible next-launch export.

## Retirement rule

Before deleting a script/doc, search every caller and CI reference, confirm its
replacement or intentionally unsupported workflow, move unique rationale into
its owner and run the affected entry point. Historical artifacts/private inputs
are not deletion targets. See [roadmap](modernization.md) for stage gates.
