# Agent Note: Retain Android system exit evidence

Status: implemented

## Problem

CoreCLR in-process reporting can fail inside a damaged process. Android stores
historical process exits independently, and API 31 adds native tombstone streams
that can contain registers, modules and native backtraces even when Loader could
not finish its own report.

## Decision

After storage discovery and log rotation, before runtime extraction, the bootstrap
queries ActivityManager on API 30+. It requests at most eight recent exits for
its own package and filters by the current process name obtained from public
Application.getProcessName (API 28+), not hidden process APIs. Each launch recovers at
most the latest relevant abnormal exit: signalled, low memory, Java/native crash,
ANR or initialization failure. Normal/user-requested exits are not crash reports.

SystemExit/<timestamp>-<pid>/exit.txt stores numeric exit metadata. API 31+ native
crashes attempt trace.pb; ANRs attempt trace.txt. Streams are closed on success
and failure, limited to 8 MiB and published by same-directory rename only after
a complete nonempty read. No protobuf parsing, Java helper, new DEX, signal
handler, upload or process-memory dump is added. Missing system traces leave the
summary intact and can be retried on a later launch.

Keep eight event directories. Cleanup removes only the fixed owned filenames
inside numeric event directories, never follows symlinks or recursively removes
unrecognized content. Existing traces are reused instead of reread. Failures
clear JNI exceptions, release local frames and report context without preventing
startup. This is ordinary next-launch recovery, not signal-handler code.

## Alternatives considered

- Native unwinding in a custom signal handler can cover older APIs but introduces
  fault-state execution and handler-coexistence risks. System tombstones reuse
  Android's independent reporter and do not change fault handling.
- Parsing tombstones into another Loader format makes them easier to display but
  adds a schema/parser dependency and loses original evidence. Preserve raw bytes
  for offline analysis.
- Recovering every historical exit maximizes history but increases startup I/O,
  binder calls and repetitive exports. Recover one relevant exit per launch and
  use a small retained set.

## Consequences

The [native build-ID decision](../bug-fix/2026-10-02-preserve-native-build-id.md)
keeps published bootstrap IDs matched to private symbols for offline trace lookup.

System reports supplement [CoreCLR reports](2026-10-02-runtime-crash-reports.md)
and [previous logs](../bug-fix/2026-10-02-preserve-previous-log.md). They can identify
low-memory/signalled exits without claiming those are native crashes. API 26-29
has no ApplicationExitInfo, and API 30 has no native tombstone stream. Android's
global circular trace storage can return null, overwrite evidence or deny access.
Recovery needs another successful launch and system-service reads can add latency.
The byte limit bounds storage/read volume, not binder or stream response time.
Reports may contain sensitive diagnostic data; review before sharing.

## Test Coverage

Host fake-JNI tests exercise API gating, own-process filtering, record identity,
summary retention, stream bytes/close, unavailable traces, read failures, byte
limits, retry, exception cleanup and bounded cleanup. Android public SDK
descriptors are the JNI signature authority; NDK builds check the native JNI
surface and linking, not OEM trace availability or real-device permission.

## Prior-note Audit

The [CoreCLR report decision](2026-10-02-runtime-crash-reports.md)
retains reporting alternatives and API coverage limitations. Runtime report
configuration and previous-session rotation remain independent decisions.
