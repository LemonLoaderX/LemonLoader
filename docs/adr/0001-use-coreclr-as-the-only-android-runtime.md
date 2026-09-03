# 0001: Use CoreCLR as the only Android managed runtime

Status: Accepted

## Context

The migration initially supported a MonoVM/SGen compatibility backend through
hostfxr and later added Android CoreCLR through its native host interface.
Maintaining both required backend identities, different layouts, a private
OpenSSL path, and signal/thread ownership coordination with Unity.

The project goal is behavioral parity with desktop MelonLoader, which uses
CoreCLR. The dual-backend machinery increased the release and test surface but
did not represent two intended products.

## Decision

Android releases use CoreCLR only. The native bootstrap calls the CoreCLR host
interface directly and never falls back to MonoVM. MonoVM build scripts, runtime
patches, payload files, and signal-ownership integration are not maintained.

Desktop MelonLoader's support for Mono games is unaffected; this decision is
limited to the Android port.

## Consequences

The Android payload and bootstrap are smaller and have one runtime identity.
Runtime qualification can focus on the same managed engine family as desktop.
Old development payloads using MonoVM are not supported by new loader builds,
although manifest consumers may continue to parse their established fields.
