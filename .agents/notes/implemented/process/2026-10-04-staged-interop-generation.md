# Agent Note: Publish standalone generation after successful tools

Status: implemented

## Problem

The standalone generation script deletes prior output before validating its tool
project, and an overlapping output can delete its own game inputs or references.
Its optional Unity restore invocation also uses a retired CLI option.

## Decision

The script validates source and output ownership before work. Output stays below
the repository Output directory and cannot overlap inputs/tools or traverse links.
Each run stages Cpp2IL, restored references and generated DLLs privately. Successful
generation replaces the output directory, with rename rollback on publication
failure. Cleanup after publication warns rather than reversing completed output.
The optional Patcher invocation passes Unity version positionally.

Generation records retain lightweight version/source information, not content
hashes or private source paths. Installed Loader does not consume those records.

## Alternatives considered

- Validate overlap but continue deleting output first: prevents input loss but
  still discards a valid earlier generation when tools fail.
- Route every run through Patcher: centralizes orchestration but makes the optional
  standalone workflow depend on Patcher. Keep its explicit tool-project path.

## Consequences

Staging temporarily retains both prior and new DLLs; generation failure preserves
prior output. The script fixture covers overlap, missing generator, failed tools,
successful replacement and the actual positional restore arguments. Existing
Interop runtime ABI guidance remains in docs/android/INTEROP.md.
