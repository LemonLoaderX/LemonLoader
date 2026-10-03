# Agent Note: Preserve ELF build IDs for offline crash symbols

Status: implemented

## Problem

Bootstrap linking generates an ELF build ID, but Release preparation explicitly
removes it and staging rejects it. A system tombstone therefore cannot identify
the published module using the same ID as the retained private symbol file.
Preserving symbol files alone does not provide that lookup key.

## Decision

Release stripping retains .note.gnu.build-id while removing DWARF and static
symbol tables. The build script checks that the original and stripped library
have the same SHA-1 linker build ID; standalone verification and Release staging
require it. No identifier is manufactured or rewritten after linking.

Native compilation maps source, build, Dobby and NDK prefixes to stable paths,
including dependency object files. This removes those local paths from debug
inputs hashed by the linker rather than deleting the diagnostic identifier to
hide path-dependent builds. An ELF build ID is an opaque identifier, not a machine
path, timestamp, signing identity or installed-payload admission digest.

Keep the matching unstripped bootstrap privately, indexed by its build ID and
product/runtime profile. [System-exit recovery](../feature/2026-10-02-system-exit-evidence.md)
retains Android's original trace, which can include this module identity. Public
archives still contain no debug/static symbols or local build evidence.

## Alternatives considered

- Removing build IDs produces identical stripped outputs when private debug
  paths differ, but discards Android's standard offline symbol matching key.
  Normalize compilation paths and retain the ID instead.
- Matching only filenames or a release archive hash requires the user to know
  the exact installed archive. Tombstones already carry ELF IDs when available.
- Injecting a new ID after stripping could hash only published bytes, but would
  separate the linked symbol file from its original identity and require more
  binary-rewriting and symbol-index machinery. Preserve the linker's ID.

## Consequences

Published bootstrap bytes and archive hashes change. The diagnostic identifier
adds only a small ELF note; it does not add startup scanning or fatal-signal work.
Actual unwinding and tombstone availability keep their existing Android limits.
Stable prefix mapping covers local path variation, not arbitrary compiler/linker,
SDK or source differences. Symbolization must use the matching retained binary.

Build gates validate presence and stripped/unstripped identity. Native builds
from relocated source/build roots check path-independent outputs with the same
toolchain and inputs. Release validation continues rejecting debug/static
symbols and checking ABI, alignment and cryptography inputs.

## Prior-note Audit

The [CoreCLR report decision](../feature/2026-10-02-runtime-crash-reports.md)
and system-exit note partially overlap in offline-symbol inputs and retain their
reporting/trace decisions. Runtime extraction notes concern local cache tokens,
not ELF symbol identities. The historical build-ID removal has no separate active
note; its reproducibility motivation is retained in the alternatives above.
