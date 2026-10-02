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

## Alternatives considered

- Retaining the parent Git lock gives one coordinated snapshot, but requires an
  unpublished extra repo and hides product build ownership.
- Removing all hashes would simplify manual edits, but loses protected-runtime
  integrity and transactional-update guarantees. Separate editable user content
  from protected content instead.
- Maintaining separate copies of metadata generators in both products allows
  local builds, but perpetuates drift. Loader should own a reusable installation
  interface/tool, with Patcher consuming a reviewed version.
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

The parent embedded-crypto implementation note remains relevant to P1; migrate
it into Loader with its rationale intact when committing that implementation.
No other active crash/deployment/repository-migration notes were found. The
unrelated root GAME_INTEROP_DLL_FREE_PLAN.md is preserved and is outside this
roadmap; Interop-free architecture is not assumed by installation simplification.
