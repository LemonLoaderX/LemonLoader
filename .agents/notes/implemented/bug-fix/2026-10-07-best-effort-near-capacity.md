# Agent Note: Treat early near capacity as preparation

Status: implemented

## Problem

IL2CPP initialization and later CoreCLR/Mod allocations can fill an ARM64 target's
branch window. Early near storage improves availability, but a boolean reservation
does not prove that another target will be reachable or that capacity will remain.
Using it to stop all managed startup rejects configurations whose actual hooks
could still succeed.

A large image can place late scene methods outside the reach of a page acquired
near init. Once initialization fills the late target's branch window, that page
cannot supply a relay even though the early request succeeded.

## Decision

The bootstrap asks Dobby for shared near capacity around the original il2cpp_init
export and both ends of each readable executable range before invoking the game's
initialization. It reuses the ARM64 resolver's ELF inspection of Unity's borrowed
handle, without loading another instance or freezing the later resolver cache.
The original export remains an anchor when range discovery fails. Failure of these
best-effort requests preserves the game's return and permits managed startup.
Actual failed hooks still report failure and never publish a trampoline.

Range anchors are the first and last complete four-byte-aligned instructions;
partial bytes at ELF boundaries are excluded. Ranges with no complete aligned
instruction are skipped. An unaligned search boundary can advance Dobby's existing
page cursor off-alignment and invalidate subsequent ARM64 relays.

Dobby owns allocation, nearest placement and capacity accounting. Its reservation
leaves a relay available rather than consuming and discarding it. Loader does not
scan mapped zeros, take over foreign reservations or relax short-function safety.
No payload format, runtime pack or public Mod API changes are needed.

## Alternatives considered

- A startup gate gives an early error, but the result describes only one anchor
  at one instant. It is neither necessary nor sufficient for later hook success.
- Dropping preparation is simpler, but unnecessarily loses the opportunity to
  acquire owned gaps before IL2CPP itself fills them. Waiting until CoreCLR starts
  can already be too late.
- Address-order placement can reserve a page far from clustered targets. Dobby
  selects the nearest gap while retaining owned pages as its first source.
- A single init anchor minimizes requests, but its nearest page can be beyond the
  branch range of late methods. Per-method reservations would target exact hooks,
  but require metadata that is unavailable before initialization. ELF range ends
  extend early preparation without a game-specific method list or new allocator API.
- Zero scans or larger absolute patches can preserve more successful installs,
  but cannot prove ownership or sufficient instruction extent for short functions.

## Consequences

Storage remains process-scoped and shared. Extra range requests may retain additional
pages. Interior targets of very large ranges, exhaustion and concurrent mutation
still have no coverage guarantee. A completed GC worker does not prove
that hooks or Mods initialized successfully. The bootstrap fixture checks call
ordering, the original domain return and runtime preparation after reservation
failure; Dobby owns the capacity, permissions and native hook regressions.
The standalone ARM64 bootstrap fixture models a large image, fills unreserved gaps
during the original initialization, then checks a late target's actual hook,
original invocation and undo. Unaligned starts, ends and short ranges check that
every request remains instruction-aligned and incomplete instructions are skipped.
The namespace fixture checks range ownership even
when every reservation fails. Neither fixture qualifies all game layouts.

## Prior-note audit

This fully absorbs 2026-10-06-reserve-il2cpp-near-storage, preserving its timing and
ownership rationale while withdrawing its managed-startup gate. The
[CoreCLR detour note](2026-10-06-arm64-coreclr-detours.md) continues to own managed
JIT publication and is not superseded. Emulator signal diagnostics remain local
investigation material, not a Loader startup requirement or maintained test surface.
