# Agent Note: Minimal produced installation configuration

Status: implemented

## Problem

Native loading no longer needs domain hashes, deployment revision, identity JSON
or an Interop generation manifest. Producers still build, copy and validate them
for every new APK. That retains the old coupling and duplicate reads after the
consumer requirements have been removed.

## Decision

The [reader retirement](2026-10-03-retire-layout8-readers.md) supersedes this note's
layout-8/external-DEX/MonoVM compatibility decision below; current readers use 9.

The [CoreCLR 10 retirement](2026-10-03-retire-coreclr10-workflows.md) supersedes
frozen layout-8 staging below; Loader now produces only layout 9.

Active products produce asset layout 9. Its payload.json contains formatVersion,
runtimeRid and optional path/policy deploymentFiles overrides. Seed is the native
default, so Patcher emits only non-seed overrides. Profiles remain packaging
choices; no profile label, declared file size/hash or revision is installed.
New APKs include actual game Interop DLLs without their generation manifest.
Active staging does not emit runtime-identity.json: the Release manifest already
records runtime source, engine identity, profile and cryptography information.

Release file sizes/hashes, download verification, runtime-pack checks, ABI/path/
duplicate/native-collision checks and crypto completeness remain. New layout 9
requires active CoreCLR/API26 inputs: embedded JNI helpers on Android or private
OpenSSL on Bionic. The initial transition retained layout-8 generation/readers,
external DEX and historical MonoVM to recover existing Releases. Those choices
are historical and superseded by the retirement decisions above.

The version change is required because old native/Patcher consumers require the
deleted fields. They must reject the new format clearly rather than interpret a
layout-8 declaration with missing requirements. Manual native configuration may
still omit its format and retain the existing file-layout defaults.

## Alternatives considered

- Removing fields under layout 8 minimizes version changes, but old consumers
  cannot safely interpret the result. Declare 9; the transition initially retained
  the old reader path before its separate retirement.
- Adding a capability flag while keeping every old digest preserves compatibility
  but does not remove producer coupling or the expensive APK tree rereads.
- A shared manifest generator centralizes the old recipe but preserves metadata
  that loading does not use. Remove that recipe from active production instead.
- Removing all legacy handling simplifies the implementation further but breaks
  existing external-DEX Release inputs. The original transition isolated it to
  layout 8; the later reader retirement accepts that compatibility cost.

## Test Coverage

- Active Releases/APKs contain no removed digest/revision fields or audit JSON.
- APK and directory injection work with plain Interop DLL inputs and preserve
  all four policy behaviors through non-default overrides.
- Historical layout-8 acceptance tests are replaced by rejection under the reader
  retirement. Release corruption, collisions and malformed input remain covered.
- Actual archive validation exercises both profiles; native tests cover minimal
  layout-9 extraction without startup scans.
- Device smoke consumes loaded maps/exports and lifecycle/JNI markers; it no longer
  reads or hashes runtime-identity.json, which current producers do not install.

## Consequences

Layout-9 Releases need a Patcher that supports layout 9; no release publication is
implied. Standalone APK layout verification can check structure/policies but
cannot invent removed colocated digests. Release integrity is checked before
injection. Host tests do not replace device acceptance.

## Prior-note Audit

The [runtime-extraction decision](2026-10-02-runtime-extraction-without-digests.md)
and [editable deployment](2026-10-02-editable-deployment.md) own cache/policies.
This note owns producer subtraction and the original transition rationale.
[Source ownership](../process/2026-10-02-independent-source-resolution.md) retains
independent products; crypto/crash choices remain separate.
