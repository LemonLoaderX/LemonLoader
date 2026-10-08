# APK tooling interface

LemonLoader does not own APK mutation, signing, alignment, or installation.
LemonLoader.Patcher consumes the artifact tree produced by this repository and
updates APK ZIP entries without a case-insensitive unpack/repack cycle.

## Release inputs and APK layout

The tree below combines Release inputs and the final APK layout. The Release
has no game Interop assemblies: a matching generated DLL set supplies `runtime/interop` content.
`tools` and root license files are Release-side inputs, not copied APK assets.
The Android profile is shown; Bionic differences follow below.

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
    dotnet/
      shared/Microsoft.NETCore.App/<version>/
        libSystem.Security.Cryptography.Native.Android.so
  deployment/
    Mods/
    Plugins/
    UserLibs/
    UserData/

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
assembles these with the selected .NET 11 runtime pack under:

```text
Output/<Configuration>/linux-bionic-arm64/package/
Output/Releases/LemonLoader-Android-arm64.zip
Output/Releases/LemonLoader-runtime-android-arm64.zip
Output/Releases/LemonLoader-runtime-bionic-arm64.zip
```

The package includes `lemonloader-release.json`. Current producers emit Release
manifest format 3 with these fields:

| Field | Purpose |
| --- | --- |
| `formatVersion` | Release manifest contract; currently `3` |
| `runtimeRid` | Select Android or Bionic runtime; must match `payload.json` |
| `managedRuntimeVersion` | Locate the shared CoreCLR runtime directory |
| `managedRuntimeSourceRevision` | Identify the runtime source used for the pack |
| `minimumAndroidApi` | Record the bootstrap's minimum Android API, at least 26 |
| `developmentBuild` | Keep development outputs out of formal release archives |
| `files` | Exact payload inventory with normalized `path`, `size` and `sha256`; excludes this manifest |

The engine hash appears once, in its `files` entry. Staging checks it against the
verified runtime pack before publication. `payload.json` owns asset layout 9;
that layout requires the NDK ARM64 bootstrap and CoreCLR, with embedded JNI crypto
for Android or private OpenSSL for Bionic. Redundant ABI/profile/backend labels,
build configuration/channel, engine filename/hash and game-assembly flags are not
emitted. Release validation checks the actual files and rejects game-specific
Interop or deployment inputs. Installers merge those separately.

Format 3 requires a Patcher supporting that Release format; Patcher 2.0.0 only
accepts format 2. Current Patcher source accepts both 2 and 3, retaining format-2
consistency checks for already published archives. The installed layout remains 9,
so this change does not require a native host update or metadata migration on device.
Build commands and full `runtime-provenance.json` remain in dependency build output;
active runtime assets contain no `runtime-identity.json`.
Desktop Mono/NetStandard patch directories are excluded, and Release staging
removes managed PDBs and CoreCLR diagnostic DAC/DBI libraries to avoid paying APK
and first-extraction cost for files the Android IL2CPP runtime cannot use.

Staging consumes source-built HarmonyX, MonoMod, and Il2CppInterop assemblies.
The hashes in `lemonloader-release.json` describe those final Android
assemblies, not unrelated NuGet cache files.

## Packaging invariants

- The ABI directory is `arm64-v8a`; 32-bit libraries are unsupported.
- The bootstrap is built with the Android NDK.
- `libmain.so` must not contain `DT_NEEDED libc++_shared.so`; the C++ runtime is
  linked statically so the game's public C++ runtime remains untouched.
- Every shipped `.so`, including managed runtime dependencies, must support 16 KiB
  pages. Checking only `libmain.so` is insufficient.
- Active producers emit layout 9 without domain hashes, deployment revision,
  declared file digests or audit JSON. Only layout 9 is supported by current
  Loader/Patcher. Older Patchers must reject layout-9 Releases;
  use a Patcher build supporting layout 9. `lemonloader-release.json` continues
  validating individual Release files. All extraction uses Android's package update time
  and local markers. Cached startup checks marker/directory existence without
  hashing installed runtime files. Deployment reads actual assets and optional
  policies; see [DEPLOYMENT.md](DEPLOYMENT.md).
- Android Release assembly omits desktop `runtime/loader/Documentation` and
  Release-mode DAC/DBI diagnostics at the staging source. Patcher and runtime
  consumers do not maintain path blacklists or delete historical copies merely
  to enforce that packaging policy.
- Release assembly does not emit build-only provenance or build commands;
  Release tooling validates audit identity in its Release manifest and tolerates
  additive metadata. The native host does not require identity JSON.
- The deployment tree mirrors the runtime MelonLoader base directory. Files in
  `Mods`, `Plugins`, `UserLibs`, and `UserData` keep their relative paths. The
  default development profile preserves existing files; production profiles can
  upgrade, refresh, or enforce managed files. Unknown files are never removed.
- Active Android Releases contain the Android crypto SO and embed the complete
  verified helper DEX in `libmain.so`; they contain no standalone helper DEX.
  Release format 3 derives the crypto contract from `runtimeRid`; format 2 declares
  `coreClrCryptoDexMode: embedded`. Both record `minimumAndroidApi` of at least 26,
  and the file inventory verifies `libmain.so`. These Release fields are not
  copied into layout-9 APK configuration.
  Patcher adds no DEX entries. Layout 8, external-DEX and MonoVM Releases are
  unsupported; use the corresponding historical tool checkout for old inputs.
- A Bionic-profile Release has no JNI crypto library or helper DEX. Its shared
  runtime contains `libSystem.Security.Cryptography.Native.OpenSsl.so`,
  `libssl.so` and `libcrypto.so`; the archive includes OpenSSL attribution under
  `licenses/OpenSSL/LICENSE.txt`. Patcher injects no DEX for this profile.
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

## Minimal Installed Configuration

The current host needs the file layout above, not Patcher's digest-generation
recipe. Android accepts absent/empty `payload.json` or `{}`. Bionic selects:

```json
{"runtimeRid":"linux-bionic-arm64"}
```

`deploymentFiles` is an optional path/policy list. If `formatVersion` is explicitly
present it must be `9`; unknown fields are tolerated. A malformed JSON document or
unsupported RID/layout is still an error. No `runtime-identity.json` or
`interop-manifest.json` is required by native/managed loading. Game-specific
Interop DLLs remain necessary for Mods using their generated surface.
Active Release configuration contains `formatVersion: 9` and `runtimeRid`.
Patcher adds only non-seed path/policy overrides; it reads deployment paths
without reopening their bytes to compute hashes or revisions.
It omits `deploymentFiles` entirely when no overrides are needed. Present known
fields must have the expected JSON types; null or mistyped values are not defaults.
Invalid runtime options reject loading; invalid optional deployment policies disable
Loader before hooks or Mods run, while leaving the original game available.

The existing extraction marker filenames ending in `-hash` now store the APK
update token. Historical digest values trigger one replacement extraction. Every
APK update replaces loader, dependency, Interop and private dotnet trees, even if
only deployment changed. Missing update time retries extraction. Unchanged-package
launches retain local runtime edits and do not scan for individual missing files;
loading errors report such failures normally.

Release/download validation remains the installer's responsibility. For manual
APK editing without Patcher, see [USAGE.md](USAGE.md#manual-injection).
