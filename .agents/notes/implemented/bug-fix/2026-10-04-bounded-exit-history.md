# Agent Note: Recover bounded system exit history

Status: implemented

## Problem

Selecting only the first abnormal exit repeatedly selects an already retained
low-memory record and hides an older native tombstone. One failing record also
prevents recovering other available evidence.

## Decision

Recovery processes the existing maximum of eight records, filtered to the current
process and abnormal reasons. Each event owns a local JNI frame and failure boundary.
Existing complete traces are reused; missing traces remain retryable. Cleanup runs
after the bounded batch and keeps the existing eight-event and fixed-name rules.

This partially supersedes the one-event-per-launch choice in
[system exit evidence](../feature/2026-10-02-system-exit-evidence.md). Its raw trace,
API, byte-limit, ownership and startup failure contracts remain authoritative.

## Alternatives considered

- Retain one record per launch: limits I/O but cannot advance past a saved newest
  event and loses available crash evidence.
- Add a persistent recovery cursor: skips repeats but introduces another state
  format and can suppress retries for temporarily unavailable traces.

## Consequences

A first recovery can read several traces, each limited to 8 MiB; the bound does
not limit binder latency. Later launches reuse saved bytes. Host fixtures cover a
newer low-memory event preceding a native crash and per-event storage failure.
ART/OEM trace availability remains a device qualification boundary.
