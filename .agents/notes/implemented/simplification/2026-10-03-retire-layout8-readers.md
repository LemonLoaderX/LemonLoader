# Agent Note: Retire layout 8 and external DEX readers

Status: implemented

## Problem

After current products adopt layout 9 and embedded Android crypto, supporting
old releases still retains the entire mixed-tree hash, deployment revision,
runtime-identity, MonoVM and DEX-promotion recipe. These unused branches add
maintenance work and obscure the actual manual installation contract.

## Decision

Current Loader and Patcher support layout 9, API 26+ CoreCLR with Android embedded
JNI helpers or Bionic OpenSSL. Explicit layout 8 is rejected. Native manual
installation may still omit payload.json or its format field: layout 9 defaults
apply. Unknown additive JSON fields remain tolerated. The public version stays 9
because current consumers already interpret its semantics correctly.

Patcher removes legacy tree/revision hashes, identity/Interop-manifest copying,
MonoVM acceptance, external-DEX injection and game DEX/smali enumeration. Directory
injection does not need a primary DEX. Existing game code remains unchanged.
Android native hosting removes Java System.load/application-ClassLoader fallback;
an Android request on a bootstrap without embedded helpers fails with a rebuild
diagnostic. Bionic builds still omit embedded bytes and preload private OpenSSL.
Pack preparation converts the upstream helper JAR directly at min API 26;
the unused Java System.load bridge and its compilation step are removed.

Download/Release file hashes, unsafe paths, duplicate entries, ABI validation,
native-name collisions and runtime completeness remain functional checks. Release
and explicit APK verification require CoreLib/JIT and the selected crypto inputs;
mixed Android/Bionic crypto is rejected. This is pre-install validation, not
installed-file scanning. Deployment policies and APK-update freshness are unchanged.
Old-payload detection still rejects patching an already modified game. Desktop
compatibility exports, Unity data-format support and required fork adaptations
are not removed merely because their names contain legacy.

## Alternatives considered

- Keep layout 8 isolated for old public releases: preserves convenient recovery,
  but the maintainer requests retirement of unused compatibility. Historical
  versions remain recoverable with their corresponding historical checkout.
- Reinterpret layout 8 as layout 9: simplifies entry checks but hides incompatible
  runtime/crypto assumptions. Explicit rejection gives a useful migration error.
- Remove format defaults for manual installation: creates a stricter contract,
  but makes the minimal injection workflow depend on unnecessary metadata. Keep
  current defaults and reject only explicitly unsupported declarations.

## Consequences

New tools cannot patch historical layout-8/MonoVM/external-DEX releases. Updating
an old installation needs a current complete Release and an original game input.
No schema bump or new integrity framework is introduced. Runtime packs still
carry helper DEX as a validated build input; only injection stops handling DEX.
Regressions cover unsupported input without APK/directory mutation, DEX/smali
preservation, both maintained profiles, policies, malformed/incomplete/mixed
inputs and native startup failure handling. Host checks do not qualify ART/TLS
or Android linker namespaces on a device.

## Prior-note Audit

- [Minimal production](2026-10-02-minimal-produced-payload.md): partially superseded
  for historical readers; minimal configuration and Release integrity remain.
- [Embedded crypto](../architecture/2026-10-02-embedded-android-crypto.md): partially
  superseded for old promotion/fallback; ClassLoader lifetime and exact native
  module reuse remain.
- [CoreCLR 10 retirement](2026-10-03-retire-coreclr10-workflows.md): partially
  overlapping, owns retired build workflows and private history; this note closes
  its separate historical-reader boundary.
- [Editable deployment](2026-10-02-editable-deployment.md) and
  [runtime extraction](2026-10-02-runtime-extraction-without-digests.md): related,
  preserve policy transactions/freshness and no regular startup scans.
- [Independent sources](../process/2026-10-02-independent-source-resolution.md):
  related maintenance scope; source ownership and development rules are unchanged.
  Crash decisions and the separate Interop proposal are unrelated.
