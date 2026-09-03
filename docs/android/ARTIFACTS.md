# APK tooling interface

LemonLoader does not own APK mutation, signing, alignment, or installation.
LemonLoader.Patcher consumes the artifact tree produced by this repository and
updates APK ZIP entries without a case-insensitive unpack/repack cycle.

## Required APK inputs

```text
lib/arm64-v8a/
  libmain.so

assets/LemonLoader/
  payload.json
  runtime/
    loader/
      net6/
        MelonLoader.dll
        MelonLoader.NativeHost.dll
      Dependencies/
    interop/
      *.dll
      interop-manifest.json
    dotnet/
      shared/Microsoft.NETCore.App/<version>/
        libSystem.Security.Cryptography.Native.Android.so
  deployment/
    Mods/
    Plugins/
    UserLibs/
    UserData/

tools/android/
  lemonloader-coreclr-crypto.dex

LICENSE.md
NOTICE.txt
licenses/dotnet-runtime/
  LICENSE.TXT
  THIRD-PARTY-NOTICES.TXT
licenses/Dobby/LICENSE
licenses/Il2CppInterop/LICENSE
licenses/HarmonyX/LICENSE
licenses/HarmonyX/LICENSE.Harmony
licenses/MonoMod/LICENSE
licenses/MonoMod.Common/LICENSE
```

The supported `libmain.so` is available after
`scripts/build/build-android-ndk-bootstrap.ps1`.
`MelonLoader.dll` and `MelonLoader.NativeHost.dll` are available after
`scripts/build/build-android-managed.ps1`. `scripts/build/build-android.ps1`
assembles these with the verified .NET 10 Android runtime artifact and NDK C++
runtime under:

```text
Output/<Configuration>/linux-bionic-arm64/package/
Output/Releases/LemonLoader-Android-arm64.zip
```

The package includes `lemonloader-release.json` with a SHA-256 entry for every
payload file (the manifest excludes itself), the locked dotnet source revision,
and the exact managed runtime library SHA-256. It does not publish the build
command or full `runtime-provenance.json`; those remain in the dependency build
output. The runtime domain contains only a minimal `runtime-identity.json` with
the version, backend, hosting model, engine filename, and engine hash. Supported output uses
`bootstrapFlavor: Ndk`. It is deployable only
and always records `gameAssembliesIncluded: false`. Game-specific Interop DLLs
are generated and merged by LemonLoader.Patcher. The manifest also records the
CoreCLR backend and engine provenance.
Desktop Mono/NetStandard patch directories are excluded, and Release staging
removes managed PDBs and CoreCLR diagnostic DAC/DBI libraries to avoid paying APK
and first-extraction cost for files the Android IL2CPP runtime cannot use.

Staging consumes source-built HarmonyX, MonoMod, and Il2CppInterop assemblies.
The hashes in `lemonloader-release.json` describe those final Android
assemblies, not unrelated NuGet cache files.

## Packaging invariants

- The ABI directory is `arm64-v8a`; 32-bit libraries are unsupported.
- The selected `bootstrapFlavor` must be `Ndk`.
- `libmain.so` must not contain `DT_NEEDED libc++_shared.so`; the C++ runtime is
  linked statically so the game's public C++ runtime remains untouched.
- Every shipped `.so`, including managed runtime dependencies, must support 16 KiB
  pages. Checking only `libmain.so` is insufficient.
- Layout v8 `payload.json` records loader/dotnet/Interop domain hashes and the
  deployment content hash. `lemonloader-release.json` records size/SHA-256 for
  every Release file, and APK validation recomputes every domain hash; normal
  startup uses each domain marker plus directory existence to avoid rehashing the
  complete runtime. The payload also records a deployment
  revision containing effective policies, the selected profile, and one policy
  per packaged file. Patcher recomputes all of these after adding game Interop
  and deployment inputs.
- Android Release assembly omits desktop `runtime/loader/Documentation` and
  Release-mode DAC/DBI diagnostics at the staging source. Patcher and runtime
  consumers do not maintain path blacklists or delete historical copies merely
  to enforce that packaging policy.
- Release assembly does not emit build-only `runtime-provenance.json` or build
  command metadata; consumers validate required runtime identity fields and
  otherwise tolerate additive metadata.
- The deployment tree mirrors the runtime MelonLoader base directory. Files in
  `Mods`, `Plugins`, `UserLibs`, and `UserData` keep their relative paths. The
  default development profile preserves existing files; production profiles can
  upgrade, refresh, or enforce managed files. Unknown files are never removed.
- A CoreCLR Release must contain the Android crypto library and
  `lemonloader-coreclr-crypto.dex`, declare no private native libraries, and carry
  no generic Linux OpenSSL shim. It is
  incomplete as an APK until the Patcher copies the helper to the next free
  top-level `classesN.dex`. The helper remains a Release-side Patcher tool input,
  is not copied into `runtime/dotnet`, and APK verification requires the promoted
  entry to match the hash recorded in `payload.json`.
- `libunity.so` is always the game's Unity player library. LemonLoader loads and
  hooks that original file; the Release neither supplies nor replaces it.
- The dotnet tree is extracted to application-private storage. It must not run
  from shared external storage.
- The default Mod directory is app-scoped external storage and requires no broad
  storage permission. External tooling may expose or copy files there, but must
  not change the runtime's private dotnet directory.

The exact Java/manifest patch remains the responsibility of the APK tool. Its
observable contract is that loading the library named `main` invokes
`JNI_OnLoad`, after which LemonLoader replaces Unity `NativeLoader.load` and
continues the original `libunity.so` initialization.
