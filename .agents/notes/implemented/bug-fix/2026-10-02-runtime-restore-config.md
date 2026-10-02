# Agent Note: Explicit NuGet config for external runtime artifacts

Status: implemented

## Problem

The runtime artifacts link points outside the source tree. Arcade toolset
projects are physically restored under that output tree, where implicit NuGet
config discovery finds nuget.org instead of the repository's official feeds.
Rebuilding fails NU1102 for Microsoft.Net.Compilers.Toolset
5.12.0-1.26431.109 even though the source NuGet.config declares dotnet feeds.

## Decision

The runtime build backend passes RestoreConfigFile with the absolute source
NuGet.config path. This is an existing supported Arcade extension, applies to
tool and project restores, and preserves reviewed tool versions and source feed
configuration. No package version downgrade or machine-level config change is
used. The script remains in the parent until the
[ownership migration](../../../../docs/maintenance/modernization.md).

## Alternatives considered

- Copying config files beside generated projects can work but spreads source
  configuration through disposable output and risks stale copies.
- Falling back to a stable compiler available on nuget.org bypasses the pinned
  runtime toolset and does not validate the intended source build.
- Changing user NuGet configuration introduces machine-specific hidden state.

## Verification

The original runtime build fails during toolset restore with only nuget.org in
the error. Replaying the restore entry point with explicit RestoreConfigFile
restores the Arcade toolset and proceeds to the runtime project restore.

## Consequences

Output isolation no longer changes feed discovery. Official feeds and the
pinned SDK/toolset must remain available. Large first-time restores still cost
time and network bandwidth; explicit config is not a cache bypass.
