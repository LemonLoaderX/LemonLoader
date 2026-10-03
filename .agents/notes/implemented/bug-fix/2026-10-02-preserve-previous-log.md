# Agent Note: Preserve the previous Android session log

Status: implemented

## Problem

Latest.log is reset before managed startup configures historical logs. A native
startup failure before that point has no historical copy, and another launch
used to truncate its only file evidence.

## Decision

Normal startup closes log streams and atomically renames a nonempty Latest.log
to Previous.log in the same Loader log directory before opening a new Latest.log.
Empty/missing sessions leave Previous.log intact. Previous.log holds one session,
separate from managed history retention; repeated early failures do not create
an unbounded archive. Existing Logs/ retention behavior is unchanged.

If inspection or rotation fails, Latest.log is opened in append mode and an
actionable warning reports the path/error. Never truncate evidence after a
failed rotation or delete an obstructing directory. This runs during ordinary
startup, not from a signal handler, and requires no managed initialization.

## Alternatives considered

- Rotating only when managed logging starts preserves the existing flow but
  misses precisely the early failures this fixes.
- Adding every early session to Logs/ preserves more history but needs a second
  pre-configuration retention policy to bound repeated failing launches.
- Copying before truncation keeps the old pathname but costs a full file copy
  and introduces partial-copy/low-storage handling. A same-directory rename
  provides atomic publication on Android without those costs.

## Consequences

One prior nonempty log is available alongside Latest.log even when the last
session never reached managed code. It is overwritten by a later nonempty
session, not a permanent crash archive or native stack recorder. Rotation failure
can mix sessions in Latest.log; retaining evidence takes priority over separation.
Process exclusion remains the bootstrap's responsibility. SIGKILL, power loss,
pre-path-discovery failures and storage failure can still prevent usable evidence.

## Test Coverage

The native logging host regression covers nonempty/empty session rotation,
failure before history setup, independent history retention, an obstructing
destination and continued append logging. Tests use real filesystem operations
against temporary output directories.

## Prior-note Audit

The [CoreCLR report decision](../feature/2026-10-02-runtime-crash-reports.md)
partially overlaps and owns reporter/trace integration. This decision implements
only its previous-session logging concern. The source-ownership decision retains
the broader execution order; embedded crypto is unrelated to log rotation.
