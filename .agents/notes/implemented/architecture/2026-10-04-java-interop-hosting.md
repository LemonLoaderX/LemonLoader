# Agent Note: Java.Interop hosting and checked Mod interface

Status: implemented

## Problem

Handwritten JNI bindings duplicate function tables and expose unclear ownership,
pending exceptions and attachment. A replacement must fit a CLR injected into an
existing ART process without importing an Android application hosting framework.

## Decision

Compile pinned dotnet/android Java.Interop files with their upstream JNI generator.
Use direct function-table calls, borrow the existing VM, and disable managed-peer
registration before initialization. This dependency introduces no helper JAR/DEX
or native shim. Product dependencies never rewrite upstream source or binaries.
Java.Interop is supplied once with the Loader assemblies; support-module builds
exclude its transitive copy. Its source documentation stays outside runtime inputs.

MelonLoader.Java remains the Mod interface. Ordinary errors immediately throw
JThrowableException after clearing Java state. Its class, summary and Android
stack text retain Java diagnostics; a recursion guard contains conversion failure.
Member caches separate static/instance kind, name and signature; invalid descriptors,
access/return modes and managed buffer lengths are rejected before native calls.

Ordinary object results own global references. FindClass returns locals backed by a
process-owned class cache and shared member IDs. Borrow/Adopt, Transfer, local-return
calls and local/thread scopes make lifetime explicit. Ended frames/attachments and
disposed wrappers cannot be reused. Local finalizers never delete from another
thread; global finalizers use scoped attachment. Thread scopes cannot cross await.

Retain the app ClassLoader obtained during AssetManager initialization separately.
FindClass uses Class.forName without initialization through this loader, so CLR
workers do not depend on native FindClass context. Crypto runtime hosting keeps
its independent helper/module identity.

Android managed Loader/support targets net10.0 for current Java.Interop APIs.
CoreCLR remains .NET 11; desktop targets stay unchanged. The loader/net6 folder
remains an existing installation contract, distinct from TFM and runtime version.
New Android Mods target net10.0; compiled net6 Mods need compatibility qualification.

## Alternatives considered

- JNetInterface offers richer type/ownership interfaces and scoped threads, but its
  ordinary high-level calls add initialization/allocation work and need additional
  application-class loading integration. Java.Interop's direct layer fits this host.
- Keeping handwritten bindings minimizes dependency size but retains repetitive
  unsafe ABI, ownership and exception maintenance.
- The Android workload includes a complete peer system; its application hosting and
  helpers are unnecessary for basic borrowed-VM JNI.
- A net6 source fork preserves the compilation target but adds upstream backport
  maintenance. The existing product runtime already supports net10.
- Exposing Java.Interop directly avoids wrapping but makes Mods manage host settings,
  raw pointers and copyable reference structs. Keep the checked Loader interface.

## Consequences

Asset streams adapt Java file/IO errors to .NET semantics. Pending-exception escape
hatches remain explicit. Raw class definition, reflected-member conversion, native
registration, direct buffers, unimplemented facilities and product function-table
structs are outside this checked facade. Mods using those APIs must migrate and
rebuild. Spans avoid extra argument/buffer copies;
primitive region reads avoid retained Java pins. This promises no whole-game speedup.
Raw jvalue cannot infer all argument types; borrowed lifetimes and synchronized
concurrent disposal remain caller responsibilities.

## Prior-note audit

The borrowed-VM evaluation rationale is absorbed here. Comparison prototypes are
replaced by JniHost regressions; timings and device evidence stay ignored.
[Embedded crypto](2026-10-02-embedded-android-crypto.md) partially overlaps VM ownership
but keeps its own helpers and runtime. Deployment, source and crash contracts remain.
