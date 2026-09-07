# Android CoreCLR runtime

Android LemonLoader uses one managed backend: ARM64 CoreCLR from .NET 11,
with Android (default) and Linux Bionic profiles. MelonLoader remains targeted at
`net6.0`; its runtimeconfig requests `LatestMajor` roll-forward into the private
runtime.

The maintained version and source revision are defined once in
`eng/runtime-profiles.json`. The .NET 10 entries in AndroidDependencies.props
are frozen legacy inputs only. Release manifests record the artifact identity
and hashes produced by that dependency, not a second set of hand-maintained
revision constants.

Select `build-android.ps1 -RuntimeProfile android|bionic|legacy`. Both active
profiles use the same upstream source revision. Android uses JNI crypto and
retains official synchronous HTTP rejection. Bionic uses a private OpenSSL pair
and system CA directory; its current verification is not production security
qualification. Runtime packs are prepared with prepare-runtime-pack.ps1 and
validated before staging. .NET 10 is retained only as an explicit legacy input.

## Hosting model

The NDK bootstrap follows the upstream Android CoreCLR embedding model:

1. find the extracted `Microsoft.NETCore.App` directory;
2. initialize the selected crypto backend (Android JNI or Bionic OpenSSL);
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

This avoids a second namespace-local copy with missing JNI state. This path
applies to the Android profile only.

Bionic instead uses `libSystem.Security.Cryptography.Native.OpenSsl.so` and
private `libssl.so`/`libcrypto.so`. It uses the Android system CA directory and
does not inject Java crypto helpers. Never mix the two profiles' crypto inputs.

## Runtime fork

The source repository is maintained at `LemonLoaderX/runtime`. Both active
profiles use one pinned official-main revision on `main`. The old
CPU discovery, affinity and NULL-handle fixes are already upstream and are not
reapplied. Optional PAL/host diagnostics from `legacy/net10` are not ported.
The legacy branch's `PATCHES.md` describes that old patch stack, not the active
runtime's behavior.

The normal LemonLoader build consumes a versioned runtime artifact. A full
runtime source build is an explicit maintainer workflow and publishes the same
`managed/`, `native/`, and `runtime-provenance.json` interface consumed by the
loader build.

## Managed compatibility

The Android build uses source forks rather than rewriting restored DLLs:

- MonoMod.Common handles the .NET 10 DynamicMethod field and .NET 11 runtime
  method-handle changes.
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
hosting model, engine hash, runtime RID and crypto backend. Staging validates
that identity but does not copy the provenance file into the APK.

The published payload instead carries `runtime-identity.json` with only the
runtime version, backend, hosting model, engine filename/hash, RID and crypto
backend.
Consumers validate these required values and tolerate additional metadata.

## Failure handling

Initialization failures return an error to the Java caller. Inspect bootstrap
logcat and the runtime's error output; do not require legacy-only diagnostic
markers on the active profiles. A partially initialized CoreCLR
instance is not retried in the same process because native callbacks may already
have escaped.
