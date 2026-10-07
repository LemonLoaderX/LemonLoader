# Agent Note: Withdraw the incomplete macOS ARM64 JIT-copy adapter

Status: implemented

## Problem

The Loader adapter wraps a bare ARM instruction encoder whose memory allocation
uses malloc and whose permission methods do nothing. The native JIT-copy bridge
only toggles pthread JIT write protection and flushes caches. It neither creates
MAP_JIT allocations nor makes arbitrary malloc or read-only text pages executable
or writable. Reporting permission success through these methods is unsound.

## Decision

The Mono macOS ARM64 override uses MonoMod's existing MonoPosix permission wrapper
around its ARM encoder. Permission requests execute mprotect and failures remain
errors. The Loader-specific adapter, native copy bridge and export/linker entries
are removed. The independent dlsym interpose and other upstream changes remain.

This restores a checked permission path; it does not implement or qualify hardened
macOS ARM64 W^X/MAP_JIT support. A future complete executable-memory backend belongs
in the MonoMod fork, with only necessary host bridges in Loader.

## Alternatives considered

- Adding MAP_JIT allocation alone fixes fresh pages but leaves arbitrary text,
  data vtables, permission transitions and restoration unresolved.
- Building a complete backend is the route to broader support, but needs macOS
  ARM64 execution tests and entitlement validation before being selected.
- Retaining the copy-only bridge avoids some Mono JIT write faults, but makes
  success claims for mappings whose permissions it does not establish.

## Consequences

Hosts that reject MonoPosix permission changes now fail through that error path.
The Core registration branch is guarded by !NET6_0_OR_GREATER and applies to Mono;
CoreCLR JIT warmup is not evidence that this Loader override executes there.
Compilation and removal checks cannot qualify Mac behavior. Revisit the override
only with allocation, patch/call/undo, arbitrary RX text and JIT-write tests on the
supported macOS runtime and hardware.

## Prior-note audit

No active note owns this adapter or JIT-copy export. The Android CoreCLR detour and
near-capacity notes cover different runtime/platform boundaries and remain intact.
