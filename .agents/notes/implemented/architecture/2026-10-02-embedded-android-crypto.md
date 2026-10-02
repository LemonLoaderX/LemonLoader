# Agent Note: Embedded Android crypto helpers

Status: implemented

## Problem

Android CoreCLR requires Java crypto helper classes. Promoting a helper DEX to
classesN.dex couples the Patcher to application DEX layout. An earlier isolated
ClassLoader experiment loaded two crypto native modules; CoreCLR used the copy
without JNI state. See [porting notes](../../../../docs/android/PORTING.md).

## Decision

The bootstrap embeds the selected, validated runtime pack's complete helper DEX
in libmain.so at build time. Active Android and Bionic products require API 26; frozen legacy
retains its existing behavior. Android uses InMemoryDexClassLoader with no DEX
file extraction. The crypto runtime exposes explicit host initialization with
JavaVM and ClassLoader, and CoreCLR resolves P/Invoke through that exact module.
Byte storage and retained JNI references have process lifetime.

New Release, runtime identity and payload metadata declare embedded mode.
Payload verification checks the bootstrap digest. Legacy Releases remain
supported by Patcher's existing promotion path. Layout v8 remains valid because
old Patchers reject the missing required helper input, rather than publishing
a silently broken APK. Runtime packs still carry DEX as a verified build input;
public Loader archives do not carry a standalone helper in embedded mode.

## Alternatives considered

- Top-level classesN.dex is already verified and uses the app ClassLoader, but
  keeps the application DEX coupling the maintainer wants to remove.
- Merging helper classes into game DEX avoids another entry but rewrites game
  code and adds method-limit and collision handling.
- File-based DexClassLoader preserves API 24/25 but adds extraction and writable
  code lifecycle. The maintainer explicitly drops pre-26 product support.
- Bionic/OpenSSL avoids Java helpers entirely but changes trust semantics and
  adds private OpenSSL maintenance; Android retains platform crypto.

## Verification

- Patcher's 19 regressions pass, including new Android APKs adding no DEX entries,
  decoded directory mode, independent APK verification and old DEX promotion.
- Missing/mixed modes, wrong bootstrap hashes and insufficient API declarations
  are rejected. Existing ZIP, ABI and runtime integrity checks remain.
- Native host initializes the same crypto module used for P/Invoke, using a
  retained in-memory ClassLoader, without System.load or ART private APIs.
- Build-time embedding uses a validated matching runtime pack and rejects old
  crypto shims without the explicit initialization export.
- Bootstrap and runtime host regressions pass. ARM64 API 26 NDK compilation
  passes for the bootstrap and the complete Android crypto shim, including the
  explicit export. The compiled bootstrap contains the exact verified DEX bytes.
  Runtime profile tests and workspace PowerShell/Bash script checks pass.
- Device crypto/TLS and namespace acceptance remains a separate, non-installing
  gate. The full runtime pack and product release have not been rebuilt.

## Consequences

The explicit host API requires rebuilding the runtime source fork. Source pins
cannot be updated to uncommitted revisions; local validation uses development
packs, and publication requires reviewed commits and rebuilt pinned artifacts.
No claim of startup speedup or broad device qualification is made.
The existing pinned Android pack now fails closed at the product build gate
because it lacks the new export. Bionic remains independent of Java helpers.
Legacy package staging does not require the new local bootstrap identity file.
The current rebuild/recovery workflow remains in the parent
docs/RUNTIME-DEVELOPMENT.md until its scripts and documentation are migrated.
The [modernization roadmap](../../../../docs/maintenance/modernization.md)
tracks that ownership migration and publication/device gates.

## Self-review

Review covers byte/ClassLoader process lifetime, boot-loader isolation of helper
classes, explicit native initialization/export, JNI reference/error paths,
exact module reuse for P/Invoke, matching-pack input checks, legacy promotion,
bootstrap digest and API declarations. Constructor lookup failure previously
escaped local-ref cleanup through required_method's C++ exception. The loader
now checks that lookup directly, clears the pending Java exception and releases
the local class reference; the host regression verifies no buffer or module is
created on this failure. The Android overview API table is corrected to API 26.

Remaining limitations: ART loading and real TLS are unqualified; native runtime
initialization still inherits upstream fatal checks for incompatible Java method
signatures; the host serializes initialization rather than providing a general
concurrent initialization interface. Private symbol retention/crash recording
belongs to a separate stage, not a promise of this change.

## Prior-note Audit

No earlier active crypto, DEX or ClassLoader notes existed when this decision
was introduced. PORTING.md records the previous native-instance failure and
remains relevant. The root GAME_INTEROP_DLL_FREE_PLAN.md proposal is unchanged.
This note moves from the local parent to Loader without changing its decision;
the [modernization proposal](../../proposed/process/2026-10-02-project-modernization.md)
is partially overlapping and governs further repository ownership changes.
