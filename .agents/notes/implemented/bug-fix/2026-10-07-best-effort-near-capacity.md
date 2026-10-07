# Agent Note: Treat early near capacity as preparation

Status: implemented

## Problem

IL2CPP initialization and later CoreCLR/Mod allocations can fill an ARM64 target's
branch window. Early near storage improves availability, but a boolean reservation
does not prove that another target will be reachable or that capacity will remain.
Using it to stop all managed startup rejects configurations whose actual hooks
could still succeed.

## Decision

The bootstrap asks Dobby for shared near capacity around the original il2cpp_init
export before invoking the game's initialization. The pointer comes from Unity's
existing symbol redirection, without loading another IL2CPP instance. Failure of
this best-effort request preserves the game's return and permits managed startup.
Actual failed hooks still report failure and never publish a trampoline.

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
- Zero scans or larger absolute patches can preserve more successful installs,
  but cannot prove ownership or sufficient instruction extent for short functions.

## Consequences

Storage remains process-scoped and shared. Large modules, exhaustion and concurrent
mutation are not covered by a single request. A completed GC worker does not prove
that hooks or Mods initialized successfully. The bootstrap fixture checks call
ordering, the original domain return and runtime preparation after reservation
failure; Dobby owns the capacity, permissions and native hook regressions.

## Prior-note audit

This fully absorbs 2026-10-06-reserve-il2cpp-near-storage, preserving its timing and
ownership rationale while withdrawing its managed-startup gate. The
[CoreCLR detour note](2026-10-06-arm64-coreclr-detours.md) continues to own managed
JIT publication and is not superseded. Emulator signal diagnostics remain local
investigation material, not a Loader startup requirement or maintained test surface.
