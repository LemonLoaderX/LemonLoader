# Android CoreCLR runtime

Android LemonLoader uses one managed backend: ARM64 CoreCLR from .NET 11,
with Android (default) and Linux Bionic profiles. MelonLoader remains targeted at
`net6.0`; its runtimeconfig requests `LatestMajor` roll-forward into the private
runtime.

The maintained version and source revision are defined once in
`eng/runtime-profiles.json`. CoreCLR 10 recovery is retired.
Release manifests record the artifact identity
and hashes produced by that dependency, not a second set of hand-maintained
revision constants.

Select `build-android.ps1 -RuntimeProfile android|bionic`. Both
profiles use the same upstream source revision. Android uses JNI crypto and
retains official synchronous HTTP rejection. Bionic uses a private OpenSSL pair
and system CA directory; its current verification is not production security
qualification. Runtime packs are prepared with prepare-runtime-pack.ps1 and
validated before staging.

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
verified build input. The active Android bootstrap embeds these bytes at compile
time and creates an `InMemoryDexClassLoader` on API 26+. No DEX file is extracted
or added to the application's top-level DEX entries.

The native shim exports `AndroidCryptoNative_InitWithClassLoader(JavaVM*, jobject)`.
The host calls it once, on an attached thread, before any crypto operation. Startup
is serialized by the host. Helper classes are resolved through the supplied
loader; platform classes still use JNI `FindClass`. The retained loader and ELF
byte storage have process lifetime. The host uses `dlopen`, not Java `System.load`,
and supplies the exact initialized module for every crypto P/Invoke.

This avoids a second namespace-local copy with missing JNI state. This path
applies to the Android profile only.

Historical Android Releases used the application ClassLoader and
top-level helper DEX. That input path is retired. Old
runtime packs without the explicit host export cannot build embedded Android
products: rebuild the runtime fork rather than substituting a legacy shim.

Bionic instead uses `libSystem.Security.Cryptography.Native.OpenSsl.so` and
private `libssl.so`/`libcrypto.so`. It uses the Android system CA directory and
does not inject Java crypto helpers. Never mix the two profiles' crypto inputs.

## Runtime fork

The source repository is maintained at `LemonLoaderX/runtime`. Both active
profiles use one pinned official-main revision on `main`. The old
CPU discovery, affinity and NULL-handle fixes are already upstream and are not
reapplied. Optional PAL/host diagnostics from the retired .NET 10 patch stack
are not required startup markers. Source setup/build, toolchain and publication commands are in
[runtime source development](RUNTIME-DEVELOPMENT.md).

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

Active layout-9 Releases record engine/source/profile audit identity in
`lemonloader-release.json`, whose file inventory verifies runtime bytes before
injection. They do not copy identity JSON into the APK. Layout-8 input support is
retired. Native startup checks
actual CoreCLR exports and crypto initialization rather than colocated digests.

## Failure handling

Initialization failures return an error to the Java caller. Inspect bootstrap
logcat and the runtime's error output; do not require legacy-only diagnostic
markers on the active profiles. A partially initialized CoreCLR
instance is not retried in the same process because native callbacks may already
have escaped.
