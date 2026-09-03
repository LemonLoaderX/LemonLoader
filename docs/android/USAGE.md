# Using Android LemonLoader

## What this repository produces

LemonLoader produces a verified unpacked payload for an APK tooling pipeline.
It does not modify or install an APK itself. A complete payload is under:

```text
Output/Release/linux-bionic-arm64/package
```

External tooling must place the staged `assets` and `lib` trees into a decoded
ARM64 Unity IL2CPP APK, perform the required Unity Java/manifest integration,
align the result for 16 KiB pages, and sign it. See `ARTIFACTS.md` for the exact
file interface.

## Before packaging

Confirm all of the following:

- the application is Unity IL2CPP and contains `lib/arm64-v8a/libil2cpp.so`;
- generated Interop assemblies match that exact APK's `libil2cpp.so` and
  `global-metadata.dat`;
- `lemonloader-release.json` reports `gameAssembliesIncluded: false`;
- `lemonloader-release.json` reports `bootstrapFlavor: Ndk`;
- every native library in the final APK is compatible with 16 KiB pages;
- signing material and package-specific patch files remain outside this repo.

## Runtime directories

After first launch, user-visible LemonLoader data is stored below the app's
scoped external-files directory:

```text
Android/data/<package>/files/MelonLoader/
  MelonLoader/
    Latest.log
    Logs/
  Mods/
  Plugins/
  UserData/
    Loader.cfg
```

The private .NET runtime is extracted inside application-private storage and is
not a user-managed Mod directory. Do not copy, edit, or execute it from shared
storage.

## Installing Mods

Place compatible MelonLoader Mod assemblies in `Mods`. Development devices can
use ADB to push files after the application has created the directory. Do not
pre-create `Android/data/<package>/files/MelonLoader` through `adb shell`; on
current Android versions that can give the directory the wrong owner and block
the application from writing it.

Mods must target the same MelonLoader and generated Il2CppInterop surface as the
packaged payload. Desktop-only native dependencies and x86/x64 libraries remain
unsupported. Unity coroutines hosted through `MelonCoroutines` are available on
the validated Android IL2CPP path; build Mod libraries against the target game's
generated Unity proxies rather than a desktop game's wrapper surface.

The `Mods` tree is scanned recursively. A Mod and its managed dependencies may
therefore be kept together, for example under `Mods/ExampleMod/`, without adding a
MelonLoader subfolder `manifest.json`. Only managed assemblies carrying
`MelonInfo` are loaded as Mods; other managed DLLs remain available to the
assembly resolver. Hidden, disabled, retired, and explicitly excluded directory
trees keep the standard MelonLoader exclusion behavior.

## Configuration and logs

`UserData/Loader.cfg` is created and normalized on startup. The default and a
non-default `theme` value have been validated through an on-device load/save
cycle. Preserve the file across replacement updates.

Use `MelonLoader/Latest.log` for the current run and `MelonLoader/Logs` for
retained logs. For startup failures also capture timestamped logcat, because
native loader and linker errors may occur before managed logging starts.
Set `loader.capture_player_logs = true` in `Loader.cfg` to mirror Android logcat
messages tagged `Unity` into both current and retained logs. A successful setup
records `Unity player log capture enabled` near the start of `Latest.log` and
subsequent player messages use the `[UNITY]` prefix.

## Updating a patched application

An update must preserve the package identity and signing certificate. Do not
uninstall or clear app data. External tooling should use the platform's replace
installation path and should record `firstInstallTime` before and after the
update. The value must remain unchanged.

The runtime and deployment hashes in `assets/LemonLoader/payload.json`
independently invalidate LemonLoader's extraction caches. A replacement runtime
is copied into a staging directory before replacing the prior extraction, so
files removed from the new payload do not survive indefinitely. The packaged
deployment tree mirrors the MelonLoader base directory, so an APK can preload
`Mods`, `Plugins`, `UserLibs`, or nested `UserData` files. Layout v8 additionally
records a deployment revision and a concrete policy for every packaged file.
Development packages seed only missing files; production and locked profiles can
upgrade, refresh, or enforce selected directories without requiring a declaration
for each file. Replacements and obsolete managed files are backed up, and unknown
files are never removed. See [DEPLOYMENT.md](DEPLOYMENT.md) for the complete
policy and transaction contract.

## Current limitations

- Android ARM64 and Unity IL2CPP only.
- API 23+; only 4 KiB and 16 KiB page-size devices are accepted by preflight.
- Game-specific Interop assemblies must be generated off device.
- Coroutine hosting is validated with asynchronous AssetBundle operations.
- `Update`, `FixedUpdate`, and `LateUpdate` use the normal injected
  `MonoBehaviour` phases and have deterministic smoke markers.
- IMGUI, quit, and scene-unload adapters exist but lack current device probes.
- APK patching, signing, and installation remain external responsibilities.
