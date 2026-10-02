# Agent Note: Independent products and maintainable installation

Status: proposed

## Problem

The local parent repo coordinates independent product/dependency repos, owns
critical build documentation and pins, and is not published as the project entry
point. Installation metadata couples optional deployment edits to startup, while
normal logs alone do not reliably retain native crash evidence on other devices.

## Proposal

Execute the maintainer's five goals in the staged
[roadmap](../../../../docs/maintenance/modernization.md). Primary maintenance
documentation and the public installation interface belong to Loader. Patcher
is an APK adapter with its own dependency pins. Dependencies remain independent
sibling repos; the parent folder is not a required version authority.

Review and rebuild embedded crypto first, then independently qualify crash
evidence, deployment/install semantics and repository migration. The maintainer
authorizes scoped local commits, not pushing, release publication or device
installation. Concrete crash-library and wire-format choices remain proposed
until evaluated; the roadmap does not implicitly disable integrity checks.

Deployment revision is only an update/cache hint. Its self-consistency check is
not an authenticity guarantee because the content and manifest are editable
together. Missing/stale declared revision must not become a game-startup gate.
Evaluate removing the global revision, keeping only local/per-file state needed
for rollout, user edits, obsolete files and rollback. Do not require a new locked
mode solely to preserve the present validation design. Build/download checks and
actual runtime compatibility remain separate concerns.

Reassess the entire installed-payload design: domain mixed hashes, identity
digests, manifests, extraction markers and deployment policy state. Prefer
removal and ordinary Loader installation/loading over new validation tooling.
Do not add per-file diagnostics, expected-file inventories or startup scans.
Release/download checks and structural safety are separate from installed-payload
admission. Old-format migration still requires testing before changing behavior.

## Alternatives considered

- Retaining the parent Git lock gives one coordinated snapshot, but requires an
  unpublished extra repo and hides product build ownership.
- Removing every hash/state field would simplify manual edits, but also removes
  useful evidence of whether a destination still matches its previous package.
  Keep that information only when an update policy needs it. Colocated hashes
  are consistency metadata, not proof of trust or a reason to reject startup.
- Keeping global revision validation catches mismatched generated metadata, but
  provides no anti-tamper guarantee and makes ordinary APK editing depend on
  Patcher's recipe. Prefer local update decisions and optional legacy rollout hints.
- A reusable metadata generator reduces duplication but may preserve a recipe
  users do not need. Simplify to file layout/update behavior first; add tooling
  only for demonstrated irreducible requirements.
- Per-file diagnostics locate corruption but add generation, scanning and
  maintenance costs. The maintainer rejects this direction; use loading errors
  and retained logs instead.
- A fatal signal handler that calls the normal logger is small, but may deadlock,
  allocate or interfere with CoreCLR's recoverable signals. Evaluate established
  crash tooling and async-signal-safe evidence collection before choosing.
- One giant restructure commit is easy to schedule but difficult to verify or
  roll back. Split source behavior, contract changes and physical moves.

## Acceptance criteria

Each roadmap stage has an explicit exit. Both products build independently from
documented inputs; ordinary editable deployment revisions cannot prevent the
game from starting; protected inputs retain validation; native crashes yield
bounded accessible evidence within documented coverage; runtime artifacts match
reviewed source. All supported workflows have a concise indexed owner.

## Risks

Android signals and ClassLoader/native namespaces are not proven by host mocks.
Fail-open deployment needs a safe startup state, not continuation after partial
hook/runtime initialization. Moving submodule checkouts can invalidate Git and
artifact links. Private diagnostic exports may contain sensitive data. Schema
and runtime choices require consumer/version compatibility checks.

## Prior-note Audit

The [embedded-crypto implementation note](../../implemented/architecture/2026-10-02-embedded-android-crypto.md)
remains relevant to P1 and is migrated into Loader with its rationale intact.
No other active crash/deployment/repository-migration notes were found. The
unrelated root GAME_INTEROP_DLL_FREE_PLAN.md is preserved and is outside this
roadmap; Interop-free architecture is not assumed by installation simplification.
