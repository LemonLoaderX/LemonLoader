# Android CoreCLR runtime

Android LemonLoader uses one managed backend: the Android ARM64 CoreCLR runtime
from .NET 10. The MelonLoader assemblies remain targeted at `net6`; their
runtimeconfig requests `LatestMajor` roll-forward into the private runtime.

The maintained version and source revision are defined once in
`eng/AndroidDependencies.props`. Release manifests record the artifact identity
and hashes produced by that dependency, not a second set of hand-maintained
revision constants.

## Hosting model

The NDK bootstrap follows the upstream Android CoreCLR embedding model:

1. find the extracted `Microsoft.NETCore.App` directory;
2. initialize the Android cryptography library through the application class
   loader;
3. load and verify `libcoreclr.so`;
4. build the trusted-platform-assembly and native search paths;
5. call `coreclr_initialize`;
6. create the `MelonLoader.NativeHost` delegate with
   `coreclr_create_delegate`;
7. keep the runtime alive until process exit.

The runtime is accepted only when it exports the CoreCLR host functions and does
not expose a MonoVM identity. There is no fallback backend.

## Private layout

```text
<application-data>/dotnet/
  runtime-identity.json
  shared/Microsoft.NETCore.App/<version>/
    System.Private.CoreLib.dll
    libcoreclr.so
    libclrjit.so
    ...
```

Native runtime files stay in application-owned storage. Android versions and
device policies do not consistently permit native execution from shared storage.

## Cryptography

Android CoreCLR uses `libSystem.Security.Cryptography.Native.Android.so` and Java
helper classes. The runtime artifact contains a deterministic helper DEX as a
Patcher input. The Patcher promotes it into the application class loader; the
bootstrap then initializes the native library once and supplies a CoreCLR
P/Invoke override for that same module.

This avoids a second namespace-local copy with missing JNI state. Generic Linux
OpenSSL shims and private renamed OpenSSL libraries are not part of the supported
runtime.

## Runtime fork

The source fork is maintained at `LemonLoaderX/runtime`. Its `PATCHES.md`
describes three loader-neutral Android adaptations:

- stable CPU discovery when Android temporarily offlines processors;
- restricted-kernel affinity and thread-creation handling;
- concise PAL and CoreCLR initialization-stage diagnostics.

The normal LemonLoader build consumes a versioned runtime artifact. A full
runtime source build is an explicit maintainer workflow and publishes the same
`managed/`, `native/`, and `runtime-provenance.json` interface consumed by the
loader build.

## Managed compatibility

The Android build uses source forks rather than rewriting restored DLLs:

- MonoMod.Common recognizes the .NET 10 private `DynamicMethod._returnType`
  field.
- HarmonyX resolves the concrete runtime local-builder type and dynamic delegate
  types used by .NET 9 and later.
- HarmonyX default patcher resolvers preserve a patcher selected by an earlier
  resolver.

The build runs focused MonoMod and Harmony probes before staging these
assemblies. RuntimeDetour and Harmony patching remain enabled; unsupported
legacy JIT-specific behavior uses MonoMod's existing fallback.

## Identity and provenance

The source build output keeps full internal provenance, including the build
command and normalized content hash. Runtime publication creates a minimal
`runtime-provenance.json` containing only the version, source revision, backend,
hosting model, and engine hash. The normal build validates that identity before
staging, but does not copy it into the APK.

The published payload instead carries `runtime-identity.json` with only the
runtime version, backend, hosting model, engine filename, and engine SHA-256.
Consumers validate these required values and tolerate additional metadata.

## Failure handling

Initialization failures return an error to the Java caller. The runtime fork
forwards the first actionable PAL or host stage through CoreCLR's existing error
writer; it does not add routine success logs. A partially initialized CoreCLR
instance is not retried in the same process because native callbacks may already
have escaped.
