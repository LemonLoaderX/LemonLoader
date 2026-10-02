# Agent Note: Independent source resolution for each product

Status: implemented

## Problem

The parent workspace overrides Loader dependency paths and checks parent gitlinks.
Patcher publishing defaults to a parent dependencies directory. Products already
pin different Il2CppInterop revisions, so automatically checking out a shared
sibling to satisfy one product can disrupt the other product or local work.

## Decision

Each product reads only its own dependency manifest. Default builds use a sibling
checkout only when its HEAD matches that product's pin, otherwise a private
.dependencies/name/revision checkout in that product. Explicit source roots keep
the existing strict revision/cleanliness checks and development overrides.
Resolution is read-only; builds never fetch or change source checkouts.

Setup creates missing pinned checkouts in temporary sibling staging and publishes
them only after checkout/submodule setup succeeds. An existing checkout is verified
and never switched, fetched or reset; missing revisions use separate cache paths.
Matching shared siblings are verified without submodule mutation. Local edits,
wrong HEADs and uninitialized nested dependencies receive actionable errors.
Patcher owns its generator URL and revision; Loader does not supply them.
New clones enable long paths locally, and dependency inspection passes the option
before Git's -C path handling so deep staging roots work on Windows. Blob filtering applies to HTTPS clones;
local offline fixture/source clones do not create a filtered remote pointing at
another checkout, which can trigger recursive lazy fetching from partial sources.

Loader's scripts/build.ps1 is the public product entry for profile selection and
existing native/managed/staging orchestration. It does not inspect the parent
gitlinks or require a Patcher checkout. Source runtime build migration and physical
dependency moves remain separate steps of the
[modernization proposal](../../proposed/process/2026-10-02-project-modernization.md).

## Alternatives considered

- A shared dependency lock gives one coordinated snapshot but prevents independent
  product pins and requires the unpublished umbrella repo.
- Always using siblings is convenient for development but builds the wrong source
  when products disagree. Check the pin or use explicit development roots.
- Switching shared siblings during setup saves disk space but disrupts another
  product and can overwrite local work. Use isolated revision caches instead.
- A new shared resolver package avoids a small amount of script duplication but
  adds another synchronized dependency. Each product owns its narrow helper.

## Consequences

Products build from standalone checkouts and may share correctly pinned siblings
without sharing a version authority. Cache copies consume additional disk when
pins differ. Old caches and dependency working trees are preserved. Setup requires
network access only for a new source clone; builds remain offline once inputs are
prepared. This decision does not migrate runtime artifacts or root scripts yet.

Local Git fixtures cover matching/conflicting siblings, independent cache paths,
explicit overrides, dirty/wrong checkouts and pinned setup without shared-source
mutation. Product build and publish entries verify the actual manifests/inputs.

## Prior-note Audit

The modernization proposal partially overlaps and owns physical moves and
documentation consolidation; it links back to this source-resolution decision.
Runtime source Git and restore-config notes retain their build-specific rationale.
Payload and crash notes do not change dependency ownership.
