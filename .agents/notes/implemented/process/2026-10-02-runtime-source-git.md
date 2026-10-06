# Agent Note: Native Git for runtime sources on Windows volumes

Status: implemented

## Problem

The WSL runtime builder stores source on a Windows volume. Linux Git uses
different stat/index metadata and scans this large tree through DrvFS; the
rebuild spent over nine minutes in git status before compilation began.
Windows Git reads the same checkout promptly. This is a preflight bottleneck,
not evidence that the compiler or crypto generator is slow.

## Decision

The existing runtime build backend selects git.exe when available and uses an
explicit Windows-converted source path for revision, status and diff. Otherwise
it retains Linux Git. It strips the single trailing CR from rev-parse output
before identity comparison. Clean-source and locked-revision checks remain;
binary diff evidence is retained without content rewriting. Build isolation,
the source lock and the Linux toolchain remain unchanged.

The backend also passes the verified checkout HEAD as SourceRevisionId to the
upstream build. Linux Git cannot reliably interpret Windows worktree metadata;
implicit upstream revision discovery may otherwise identify a parent repository.
Development builds use their actual checkout HEAD, not the product's locked pin.

The backend is Loader's scripts/build/build-runtime.sh; see
[runtime source development](../../../../docs/android/RUNTIME-DEVELOPMENT.md).

## Alternatives considered

- Skipping source-status validation is faster but defeats source identity gates.
- Moving all source into the WSL filesystem avoids DrvFS but changes the user's
  requested sibling layout and requires another checkout/cache policy.
- Letting Linux Git finish preserves behavior but adds repeated avoidable scans
  before each RID build.
- Leaving upstream source identity discovery implicit avoids another argument but
  can embed an unrelated parent commit in native version and crash-report identity.

## Consequences

No mandatory machine-specific Git path is recorded. Windows Git and the source
checkout must be accessible through WSL interop; when unavailable Linux Git may
still be slow. This does not address compiler filesystem I/O or relax build
validation. Verify locked/development plan modes and script syntax before use.
The launcher fixture checks explicit source identity for both profiles and for a
development checkout whose HEAD differs from the product pin.
