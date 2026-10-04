# Agent Note: Standard Java.Interop API for the new Android version

Status: implemented

## Problem

The first migration replaces handwritten JNI tables but retains a parallel object,
argument and member system. It bypasses Java.Interop peer/value management and
leaves Mod authors writing signatures and managing raw results. The new product
version explicitly permits breaking the old JNI API.

## Decision

Java.Interop JavaObject/IJavaPeerable, JniPeerMembers, JniTypeSignature,
JavaException and array/value marshalers form the single Java model. The old
JNI/JObject/JClass/JValue interfaces and fake ABI fixtures are removed.
Loader owns borrowed-VM hosting, weak peer registry/finalization, application
ClassLoader selection, thread scopes and diagnostics. JavaBinding compiles/caches
typed delegates, derives descriptors and marshals through upstream value managers.
Common Android peers adapt Activity, Context, AssetManager and InputStream.
Advanced Mod bindings use Java.Interop directly within the same host.

Native environment discovery retains the application's ClassLoader before managed
initialization. JniRuntime receives that loader through CreationOptions; no reflection
mutates upstream internals. CLR-finalizer cleanup detaches its managed-owned thread
even when Java.Interop attached it before entering the value manager.

JavaCallbacks supplies disposable typed interface registrations using Java Proxy.
A small helper DEX is embedded in MelonLoader.dll and lazily loaded with
InMemoryDexClassLoader under the app loader. Its child loader and native registration
stay process-scoped, separate from CoreCLR's private crypto loader. Neither APK-level
DEX entries nor Patcher-specific actions are introduced. Delegate roots are retained
until registration disposal; callback failures become Java RuntimeException.
AndroidThread observes UI work through Tasks and supports caller cancellation.

## Alternatives considered

- Retaining the old checked facade makes old Mods easier to load, but preserves
  two Java models and conflicts with the maintainer's new-version direction.
- Importing the complete Android workload supplies platform bindings, but couples
  injected hosting to application deployment and peer generation tools.
- Building another object model repeats upstream lifetime/type machinery; the
  standard peers need only Loader hosting and caller ergonomics.
- Registering native callbacks without Java interface helpers avoids embedded DEX,
  but cannot supply Runnable/listener implementations to ordinary Android APIs.

## Consequences

Old JNI Mods require migration/rebuild; there is no legacy bridge. The historical
loader/net6 installation path and private .NET 11 runtime remain independent of
the net10 managed compiler target. Typed delegate inference uses declared Java
parameter types, so overloads do not guess runtime argument types. Calls through
six arguments marshal on the stack; larger delegates use boxed buffers.
Reflection bindings target CoreCLR, not NativeAOT. Direct upstream operations
require a synchronous thread scope; scopes cannot cross await. Synchronization
and raw local-reference lifetime remain caller responsibilities.

Callback argument peers expire with the invocation. Registrations must be disposed
after Java stops using them; abandoned queued UI work needs caller cancellation.
Cancellation does not interrupt running actions. Runnable calls after disposal
are no-ops; other interface calls fail. Proxy Object methods retain identity
semantics; unimplemented abstract methods are rejected at creation.

JniHost exercises actual peers, arrays, errors, registry/finalization, worker scopes,
large delegates and real InputStream bounded buffering/seek/release under CheckJNI.
ART probes exercise the app loader, interface callbacks/boxing/errors, UI dispatch,
real assets and a following game frame. Host evidence alone never qualifies ART.

## Prior-note audit

[The first migration](2026-10-04-java-interop-hosting.md) retains source-build and
borrowed-VM rationale; its compatibility facade and no-helper restriction are
superseded. [Embedded crypto](2026-10-02-embedded-android-crypto.md) owns its private
crypto helper and VM identity. Deployment/crash/source notes keep their contracts.
