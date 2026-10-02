# Agent Note: Retire CoreCLR 10 maintenance workflows

Status: implemented

## Problem

Keeping a frozen CoreCLR 10 profile still requires a second set of pins, download,
build, staging and probe workflows. The maintainer no longer uses that runtime
and requests removal of obsolete schemes rather than indefinite recovery support.
The optional parent also accumulates old reference checkouts and device work.

## Decision

Loader maintains only the .NET 11 Android and Bionic profiles, both API 26+.
CoreCLR 10 profile/pins, recovery builder/publisher/downloader and the old
staged-layout shell CoreClrProbe are removed. Staging produces only layout 9;
the legacy tree-digest and runtime-identity generation recipe is removed.
Runtime source setup/build and prepare/import/package remain the supported pack
workflow. Product SDK 10 and Patcher's SDK/runtime requirements are unrelated to
the retired game-host CoreCLR 10 backend and remain unchanged.

Device replacement scripts keep backups under Loader Output/DeviceBackups, not
a mandatory parent work directory. Existing unique logs, source histories, game
inputs, signing material and matching symbols remain private. Old reference
checkouts and investigations are consolidated into one ignored history tree;
re-creatable obsolete outputs can be deleted without following artifact links.
Active packs, acceptance archives and current runtime output targets are retained.

This decision does not remove the desktop upstream baseline or the currently
separate Patcher/native historical input readers. Those readers need their own
contract and safety-test retirement, not a blanket deletion of every occurrence
of the word legacy. Unity data formats and required dependency adaptation remain.

## Alternatives considered

- Keep the frozen profile for rollback: useful when qualifying a replacement,
  but it imposes permanent maintenance on an unused runtime. Git history and
  private recovery inputs preserve history without a supported build entry.
- Delete all old work and reference repositories: saves more disk space, but
  discards unique traces, local Git histories and device rollback files. Archive
  those once and remove proven generated duplicates instead.
- Keep parent backup paths for convenience: avoids changing caller expectations,
  but recreates the retired umbrella dependency. Product-owned ignored output is
  the supported default; explicit Interop backup paths remain available.

## Consequences

Legacy profile requests fail before a build. CoreCLR 10 artifacts cannot be
staged through current Loader scripts. Users needing historical recovery use
the corresponding historical checkout, not undocumented compatibility switches.
Pack hash/ZIP path/duplicate checks, RID/crypto completeness, release audit hashes
and API gates remain. Tests reject legacy selection and exercise both maintained
pack profiles and release/development verification selection.
Source compilation and host tests cannot qualify ART, TLS or device behavior.

## Prior-note Audit

- [Independent sources](../process/2026-10-02-independent-source-resolution.md):
  partially superseded only for frozen selection and retained shell probe; source
  isolation, non-mutating setup, link protection and product ownership remain.
- [Embedded crypto](../architecture/2026-10-02-embedded-android-crypto.md): partially
  superseded for frozen pre-26 recovery; embedded ClassLoader/module lifetime and
  Bionic separation remain.
- [Minimal production](2026-10-02-minimal-produced-payload.md): partially superseded
  for frozen layout-8 staging; historical consumer handling is a separate boundary.
- [Editable deployment](2026-10-02-editable-deployment.md) and
  [runtime extraction](2026-10-02-runtime-extraction-without-digests.md): related,
  but their update/ownership policies are unchanged.
- [Modernization proposal](../../proposed/process/2026-10-02-project-modernization.md):
  partially overlapping maintenance scope; retains independent products and later
  device qualification. Crash notes and the separate Interop proposal are unrelated.
