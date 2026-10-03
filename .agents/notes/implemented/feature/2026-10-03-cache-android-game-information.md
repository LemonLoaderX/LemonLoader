# Agent Note: Cache parsed Android game information

Status: implemented

## Problem

Every Android process parses PlayerSettings from game assets and may load a class
database even though game metadata remains unchanged between APK updates. Loader
hash helpers also use managed SHA implementations and whole-file byte arrays;
this repeats managed crypto work during startup and Mod loading. Android installs
a runtime Harmony patch for a DetourContext.Dispose defect already fixed in its
pinned MonoMod source fork.

## Decision

Native bootstrap supplies its existing APK update token to managed Loader.
Android caches successfully parsed name, developer, game version and engine
version in a small bounded JSON file. Identity combines the APK token, Loader
module MVID and configured Unity version override. Unknown/malformed/oversized
cache or missing token falls back to normal asset parsing. Cache writes use
temporary-file replacement and remain optional; unsuccessful parsing is not
cached. This cache is never an integrity check or startup gate.

Asset parsing loads classdata only when the asset lacks a type tree. Android SHA
helpers stream files through platform-backed SHA256/SHA512, retaining uppercase
hex output and missing-file behavior. Desktop retains its existing hash helper
implementation. The unused SHA256 allocation in Setup is removed.

Android omits the obsolete Dispose Harmony patch because its source-pinned
MonoMod already provides the correct idempotent Dispose behavior. Desktop
continues its compatibility patch for its independently selected dependencies.
Interop preload and synchronous Mod initialization remain in place: dependency
type resolution and first-frame callbacks rely on their ordering.

## Alternatives considered

- Supplying game information from Patcher avoids initial parsing but adds installer
  metadata and couples directory/manual installs to generation. Runtime-owned
  caching works with any installer and derives information from actual assets.
- Parallelizing initialization could overlap work but breaks shared Harmony,
  resolver and Unity thread requirements. Remove repeated work first.
- Removing all wrapper preload saves some work but ClassInjector still falls back
  to loaded-assembly type lookup. Keep it until that dependency contract is revised.
- ReadyToRun can reduce JIT work substantially but needs a matching crossgen
  toolchain and hook/tiered compilation verification for custom runtime packs.
  Do not add precompiled binary rewriting to the current source-only fixes.

## Consequences

Initial/update startup still parses game assets; cached launches avoid that path.
Changing Loader or override invalidates the cache. Manually replacing game assets
outside an APK update requires deleting GameInformation.json to reread information.
No generated revisions, installed file hashes or mandatory Patcher fields are
introduced. Major remaining costs include CoreCLR/JIT, Harmony and native/managed
component injection; these changes do not promise to remove all startup overhead.

GameInformation fixtures exercise real asset parsing, cache hits without asset
access, update/override invalidation and recovery from malformed cache. Both
runtime profiles require device checks for hashes, game information and Mods.

## Prior-note Audit

[Runtime extraction without digests](../simplification/2026-10-02-runtime-extraction-without-digests.md)
partially overlaps: the same APK update token remains the extraction identity.
Its no-installed-digest rule is unchanged. Crash/previous-log notes concern
independent evidence retention and remain unchanged.
