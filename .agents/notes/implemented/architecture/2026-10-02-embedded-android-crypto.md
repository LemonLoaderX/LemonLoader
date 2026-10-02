# Agent Note: Embedded Android crypto helpers

Status: implemented

## Problem

Android CoreCLR requires Java crypto helper classes. Promoting a helper DEX to
classesN.dex couples the Patcher to application DEX layout. An earlier isolated
ClassLoader experiment loaded two crypto native modules; CoreCLR used the copy
without JNI state. See [porting notes](../../../../docs/android/PORTING.md).

## Decision

The [CoreCLR 10 retirement](../simplification/2026-10-03-retire-coreclr10-workflows.md)
supersedes the frozen pre-26 recovery described below. Embedded crypto remains
the maintained Android mechanism.

The bootstrap embeds the selected, validated runtime pack's complete helper DEX
in libmain.so at build time. Active Android and Bionic products require API 26; frozen legacy
retains its existing behavior. Android uses InMemoryDexClassLoader with no DEX
file extraction. The crypto runtime exposes explicit host initialization with
JavaVM and ClassLoader, and CoreCLR resolves P/Invoke through that exact module.
Byte storage and retained JNI references have process lifetime.

Release metadata declares embedded mode and file validation protects bootstrap
bytes. The [minimal-producer decision](../simplification/2026-10-02-minimal-produced-payload.md)
owns active layout-9 configuration and audit-field removal. Historical layout-8
embedded inputs retain their identity/bootstrap digest checks, while external-DEX
Releases remain supported by the promotion path. Runtime packs carry DEX as a verified build input;
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

## Test Coverage

- Patcher regressions cover new Android APKs adding no DEX entries,
  decoded directory mode, independent APK verification and old DEX promotion.
- Missing/mixed modes, wrong bootstrap hashes and insufficient API declarations
  are rejected. Existing ZIP, ABI and runtime integrity checks remain.
- Native host initializes the same crypto module used for P/Invoke, using a
  retained in-memory ClassLoader, without System.load or ART private APIs.
- Build-time embedding uses a validated matching runtime pack and rejects old
  crypto shims without the explicit initialization export.
- Bootstrap and runtime host regressions cover explicit/legacy initialization,
  JNI failure cleanup, process lifetime and exact crypto module reuse. Build
  checks require the explicit export and complete matching DEX bytes in the ELF.
- Patcher's test entry can additionally validate actual Release ZIPs using its
  production ReleaseValidator, without game inputs or APK installation. Runtime
  packaging accepts an explicit development pack, validates it and preserves its
  development identity in isolated output. Regressions cover locked-mode rejection,
  archive round-trip and reproducibility.

## Consequences

The explicit host API requires rebuilding the runtime source fork. Source pins
cannot be updated to uncommitted revisions; local validation uses development
packs, and publication requires reviewed commits and rebuilt pinned artifacts.
Old Android packs fail the product build gate because they lack the new export.
Publish runtime artifacts before consuming product releases. Local development
pack paths retain their development identity. Bionic remains independent of Java helpers.
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
Actual rebuilt-pack inspection also exposed an upstream raw crypto DEX copied
by the old staging extension filter. Embedded staging now publishes only native
SO inputs from that directory, rather than maintaining a historical filename
denylist; all helper DEX bytes stay build inputs, not runtime release files.

Host mocks do not prove ART loading or TLS behavior. Native runtime
initialization inherits upstream fatal checks for incompatible Java method
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
