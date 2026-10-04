# Agent Note: Isolated JNI library evaluation

Status: implemented

## Problem

Loader's managed JNI surface owns unsafe reference, exception and thread behavior.
Replacing it with a maintained implementation can reduce maintenance, but normal
.NET Android application integration does not establish compatibility with a CLR
injected into an existing Unity/ART process. A larger object model can also add
initialization and allocation costs to startup-sensitive code.

## Decision

Evaluate Java.Interop and Rxmxnx.JNetInterface through opt-in host and Mod harnesses
in tests/Android/JniLibraries. Both borrow the externally owned JavaVM. Production
JNI and product dependencies remain unchanged until a separate migration decision.
Keep source identities, local timings and acceptance evidence in ignored output.

Use Java.Interop from dotnet/android's source and its own JNI generator, selecting
direct managed function-table calls. Basic JNI disables managed-peer registration
before initialization and supplies the app ClassLoader. Its host adapter converts
Throwables after the library clears the Java exception; this avoids requiring Java
peer helper classes for raw JNI. CLR thread scopes must refresh JNIEnv after detach.

Use JNetInterface's independent package and ordinary high-level methods. The Mobile
package is for Java.Interop-hosted applications and is not an independent replacement.
Treat additional app-ClassLoader bridging and object-model costs as evaluation
criteria rather than assuming Android support removes either concern.

## Alternatives considered

- Replacing production JNI immediately exercises real callers, but obscures whether
  failures come from the candidate, public API adaptation or game initialization.
  Borrowed-VM probes establish the integration boundary before changing callers.
- Fake JNI tables isolate ownership errors but cannot qualify ART, ClassLoader or
  actual asset-stream behavior. A real host JVM plus device probes covers those
  boundaries without intentional native crash injection.
- Java.Interop's Android workload provides complete Java peer infrastructure,
  but adding that hosting model is unnecessary for Loader's basic JNI operations.
  The experiment uses explicit runtime managers instead.

## Consequences

The harness is not a production compatibility layer or a promised startup speedup.
Its per-operation timing includes the candidate API actually used; a high-level
library may exchange performance for ownership and type checks. Record that tradeoff
without presenting raw JNI and rich wrappers as equivalent abstractions.

The device runner preserves installed APK/signing identity and original Mod files.
Changing APK profiles still advances Android's package update token and can trigger
deployment refresh; consume extraction before isolating Mods and capture regenerated
inputs rather than destroying original files. Host CheckJNI diagnostics and device
frame checks remain separate from whole-game and minimum-platform acceptance.

## Prior-note audit

[Embedded crypto helpers](../architecture/2026-10-02-embedded-android-crypto.md)
partially overlaps the VM/ClassLoader boundary. Its crypto module identity and
in-memory DEX ownership stay unchanged; this experiment does not replace runtime
crypto JNI. Layout, extraction, source ownership and crash notes are unrelated.
