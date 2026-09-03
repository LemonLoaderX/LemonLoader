# 0002: Consume versioned CoreCLR artifacts in product builds

Status: Accepted

## Context

A complete Android CoreCLR build is large, slow, and requires a Linux or WSL
toolchain. Rebuilding it during every LemonLoader build tightly couples product
development to the runtime fork and makes a clean checkout expensive.

Checking runtime binaries into a Git submodule would misuse Git for release
artifacts and would not by itself provide content validation or source
provenance.

## Decision

The runtime fork publishes a versioned Android ARM64 archive containing
`managed/`, `native/`, and `runtime-provenance.json`. Normal LemonLoader builds
resolve that archive through a content-addressed cache and verify its SHA-256,
source revision, engine hash, backend, and hosting model.

Runtime maintainers can explicitly build the same pack from the complete source
fork. A local archive or extracted pack can be supplied for offline development.

## Consequences

Ordinary product builds no longer compile CoreCLR or require its source checkout.
Updating the runtime becomes an explicit release operation: publish the fork and
artifact first, then update LemonLoader's single dependency manifest. The
artifact host must remain available, and its checksum is part of the reviewed
dependency update.
