# Agent Note: Reuse CoreCLR crash report storage

Status: implemented

## Problem

Ordinary Loader logging cannot record a terminal native fault. The selected .NET
11 source already contains an in-process reporter integrated with PAL fault
handling, but its file output requires host configuration. An additional outer
signal handler would duplicate runtime machinery and risk misclassifying CLR
handled faults.

## Decision

Before CoreCLR initialization, the Android bootstrap configures report-only
output through existing DOTNET controls. Defaults enable EnableCrashReportOnly,
retain eight completed reports and report before previous-handler chaining.
CrashReportRootPath points to the existing Loader log directory; the runtime
writes .dotnet/crash-reports beneath it. This applies to Android and Bionic.
Before runtime cleanup, the newest nonempty interrupted default-root report is
renamed to PreviousCrashReport.partial.json outside the runtime report directory.
One partial is retained without JSON parsing; completed report retention remains
the runtime's responsibility. Custom roots retain their owner's recovery policy.

Explicit DOTNET or COMPlus configuration, including opt-out and alternate report
roots, takes precedence. Storage/environment failures warn but do not stop game
startup. The bootstrap installs no signal handler and never calls its ordinary
logger from the fault path. Reports use the upstream JSON format, not a new Loader
manifest. No automatic upload, full-memory dump or installed-payload scan is added.

## Alternatives considered

- Private report storage with next-launch copying can survive removable external
  storage loss, but adds export, duplicate retention and partial-copy handling.
  The established Loader log directory avoids that machinery and exposes reports
  alongside the files users already collect. If Android returns no external
  directory, the existing internal log fallback still applies.
- Leaving reporting opt-in avoids initialization overhead, but preserves the
  silent-crash experience. Respect explicit settings while enabling local reports
  by default.
- A new crash library can supply richer native unwinding, but adds dependencies
  and handler-coexistence obligations. Reuse the existing reporter first; the
  [broader evidence proposal](../../proposed/feature/2026-10-02-native-crash-evidence.md)
  owns supplemental system tombstones and remaining coverage.

## Consequences

PAL reports only after declining runtime fault handling. Reporting before a
previous handler prevents that handler's termination from losing the runtime
report; it does not prevent Android/Unity handling. Runtime watchdog, stack walk
and retention services have their existing startup/resource costs.

Native-only faults may supply only the interrupted crash-site frame and context;
this is not complete native unwinding. Faults before runtime initialization,
SIGKILL/OOM, unavailable storage or corrupted process state can still lack reports.
Upstream startup removes incomplete .tmp reports; the single retained partial
preserves available bytes when stack walking fails. P/Invoke faults may leave an
empty temporary report, in which case this reporter supplies no usable trace.
It may be invalid JSON and is not a complete trace. File count, not aggregate byte
size, is bounded. Reports can reveal module/thread/type names; review before sharing.

## Test Coverage

Native logging tests exercise defaults, DOTNET/COMPlus overrides, explicit opt-out
and inaccessible storage. test-crash-reporting.sh launches independent .NET 11
host processes to exercise a handled null access, FailFast, a native memory fault,
JSON/thread context, retention and opt-out. Linux host tests validate the reporter
contract, including current-process identity and a terminating previous handler
with reporting before/after chaining. They do not qualify Android ART/OEM signal
coexistence or the ARM64 runtime binaries.
The P/Invoke probe checks the current-process reporting attempt, explicitly
labels empty/incomplete reports as a coverage limitation and checks next-start
recovery only when partial bytes exist. It is not a successful-trace assertion.

## Prior-note Audit

The broader evidence proposal partially overlaps; system exit information and
native tombstones remain its scope. The [previous-log decision](../../implemented/bug-fix/2026-10-02-preserve-previous-log.md)
is complementary and independent of runtime initialization. Embedded crypto is
unrelated to signal reporting.
