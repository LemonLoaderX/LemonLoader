# Agent Note: Retained Android crash evidence

Status: proposed

## Problem

Normal native logs flush, but Latest.log is truncated before managed history
configuration. A failed early session can disappear on the next launch. Signals
handled by CoreCLR/ART are not necessarily crashes; installing an outer signal
logger risks false reports, deadlocks or altered termination. Other-device users
need local evidence, not a live logcat session.

## Proposal

First preserve previous/early-session logs independently of managed startup.
Then verify the already-built .NET 11 in-process crash reporter before adding a
new native crash dependency. Configure its storage before coreclr_initialize,
with finite retention and reporting before previous-handler chaining. Use a
private writable root and copy completed evidence to the existing accessible
Loader log area on the next launch. Do not upload automatically.

Supplement with the application's own ApplicationExitInfo on API 30+. Native
tombstone streams begin at API 31, contain protobuf rather than text, and may be
absent/overwritten. Save the original stream for offline inspection; do not add
a runtime protobuf parser just to retain evidence. API 26-30 still needs an
explicit native-trace coverage decision after the runtime reporter is tested.

## Verified source boundaries

- Runtime clrfeatures.cmake enables FEATURE_INPROC_CRASHREPORT for both selected
  targets. vm/crashreportstackwalker.cpp enables services with
  DOTNET_EnableCrashReport / DOTNET_EnableCrashReportOnly and uses
  DOTNET_CrashReportRootPath / DOTNET_CrashReportMaxFileCount. These are existing
  upstream controls, not a new Loader report format.
  The rebuilt Android libcoreclr.so contains the report-root/retention controls
  and crashreport.json writer messages; this is artifact evidence, not a crash test.
- Reporter lifecycle requires an existing writable root and creates
  .dotnet/crash-reports beneath it. Startup prunes completed reports and deletes
  leftover temporary reports. Recover useful partial/previous evidence before
  starting CoreCLR rather than assuming the runtime retains every interrupted write.
- PAL exception/signal.cpp attempts managed fault handling before invoking
  previous actions. CrashReportBeforeSignalChaining is opt-in; without it a
  previous handler can terminate before the runtime emits its report.
- debug/crashreport emits managed frames and a synthesized native crash-site
  frame/context when needed. The dispatcher currently discards siginfo. Do not
  promise complete native unwinding, all registers or fault-address coverage.
- Android CoreCLR does not support out-of-process createdump in the same way as
  desktop Linux. DbgEnableMiniDump alone is not an Android solution.
- Bootstrap discovers storage only after Unity JNI_OnLoad. Failures before path
  discovery and before runtime reporter initialization remain separate gaps.
- [Android ApplicationExitInfo source](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/app/ApplicationExitInfo.java)
  documents API 31 native tombstones and the global circular-buffer limitation.

## Alternatives considered

- Crashpad offers richer process/thread snapshots and mature offline tools.
  Its [Android architecture](https://github.com/chromium/crashpad/blob/main/doc/overview_design.md)
  adds a handler process, IPC, ptrace/broker behavior and mini_chromium dependency.
  Evaluate it if existing reporting is inadequate, not as the first integration.
- [xCrash](https://github.com/iqiyi/xCrash) supplies Android-style tombstones.
  Its documented integration requires Java initialization and an AAR, and its
  README's stated qualification ends at API 30. Current Android/16 KiB and
  CoreCLR handler coexistence need qualification before adoption.
- A custom fatal handler can write minimal bytes to a preopened descriptor but
  adds signal chaining, recursion, alternate-stack and fatality classification
  obligations. Do not invent unwinding or call the ordinary logger in it.
- System exit traces alone require no custom handler, but cannot provide native
  traces on API 26-30 and may be unavailable even on newer devices.

## Acceptance criteria

- A failed early session survives the next start; rotation/storage failures do
  not erase the only prior log. Repeated launches have finite retention.
- Actual rebuilt Android/Bionic runtimes contain the reporter, and subprocess
  tests/device tests establish when reports are written, including native and
  managed fatal paths, previous-handler termination and handled faults.
- Reporting does not swallow faults, replace CoreCLR signal ownership or stop
  Android reporting. Normal startup has no per-file integrity scan.
- Another-device user can obtain retained logs/reports without live logcat;
  exact-build private symbols are available. No keys, full process memory or
  automatic uploads are part of the default design.

## Risks

The in-process reporter still runs inside a damaged process and has upstream
limitations. Native-only faults may provide only a crash-site frame. Previous
Unity handlers can have their own recoverable behavior. SIGKILL, low-memory kills,
pre-init failures and inaccessible storage cannot be turned into a guaranteed
trace. Host JNI mocks do not qualify ART, OEM traces or real crash coexistence.

## Prior-note Audit

The [modernization proposal](../process/2026-10-02-project-modernization.md)
partially overlaps and retains the overall sequence. This note owns the narrower
reporting investigation. The [embedded crypto decision](../../implemented/architecture/2026-10-02-embedded-android-crypto.md)
is unrelated to signal ownership and still applies. No other active crash notes
were found. No reporter integration is implemented by this proposal.
