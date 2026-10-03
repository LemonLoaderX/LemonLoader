# Using Android LemonLoader

## What this repository produces

LemonLoader produces a verified unpacked payload for an APK tooling pipeline.
It does not modify or install an APK itself. A complete payload is under:

```text
Output/Release/linux-bionic-arm64/package
```

LemonLoader.Patcher is optional for an original ARM64 Unity IL2CPP APK. It exposes
generate-interop, inject with existing DLLs, and process-apk, or combines them with
patch. Its [workflow guide](https://github.com/LemonLoaderX/LemonLoader.Patcher/blob/main/docs/WORKFLOW.md)
includes equivalent script commands; manual injection is described below. It edits
ZIP entries directly. Android Releases
embed crypto helpers in libmain.so, so injection adds no DEX. Alignment and
signing are explicit options.
Do not extract/repack a complete APK on a case-insensitive filesystem.
See [ARTIFACTS.md](ARTIFACTS.md) for the payload interface.

Select `--runtime android` (default) or `--runtime bionic` in Patcher. Android's
upstream synchronous HTTP rejection is unchanged. Use asynchronous HTTP on that
profile; evaluate Bionic separately when a Mod requires synchronous requests.

## Manual Injection

MT Manager or another ZIP-entry editor can install the same Loader without
Patcher's metadata recipe. Use the matching current Loader Release and already
generated ARM64 Interop DLLs for the exact game's IL2CPP library/metadata.

1. Check the Release against its published checksum and retain an original APK.
   Use a standard Unity layout with `lib/arm64-v8a/libmain.so`, `libunity.so` and
   `libil2cpp.so`, where Unity loads the library named `main`. Check that runtime
   private native names do not collide with game libraries; do not overwrite
   unrelated native libraries or merge an existing Loader installation.
2. Replace only `lib/arm64-v8a/libmain.so` with the Release bootstrap, and copy the
   Release `assets/LemonLoader/runtime` tree into the same APK asset path.
   Preserve the game's `libunity.so`, `libil2cpp.so` and game assets.
3. Add the matching Interop DLLs under `assets/LemonLoader/runtime/interop`.
   Generation manifests are not needed by loading. Optional packaged Mods/config
   go under `assets/LemonLoader/deployment` with their destination-relative paths.
4. Copy Release `payload.json` as-is, or use the minimal configuration from
   [ARTIFACTS.md](ARTIFACTS.md#minimal-installed-configuration). Android needs no
   configuration file; Bionic needs its RID selection. No digest/revision is
   recalculated. Active Releases need no additional `classesN.dex`.
5. Preserve case-sensitive, unique, safe ZIP paths and ARM64/16 KiB compatibility.
   Align and sign the finished APK using the existing package/signing identity,
   then use Android's replacement update path. APK updates invalidate extraction;
   copying files into the installed APK without an Android update does not.

Root release manifests, licenses and `tools` are Release-side material, not APK
asset destinations. Loader extracts dotnet into private storage on launch; the
editor does not need access to that private directory. Current tooling rejects
old layout-8 and external-DEX Releases.

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

Use `MelonLoader/Latest.log` for the current run, `MelonLoader/Previous.log` for
the previous nonempty session and `MelonLoader/Logs` for managed history.
Previous.log is preserved before managed startup, including early failures;
rotation failure keeps Latest.log in append mode instead of erasing it.
For failures before storage discovery also capture timestamped logcat.
CoreCLR crash reports are saved under `MelonLoader/.dotnet/crash-reports`, with
eight completed reports retained by default. Reporting can be disabled with
`DOTNET_EnableCrashReportOnly=0` before runtime startup; existing `DOTNET_` and
`COMPlus_` reporter settings take precedence. Reports contain diagnostic names
and paths; review them before sharing. Native-only reports need not include a
complete native stack, and SIGKILL or faults before runtime startup may leave none.
`MelonLoader/PreviousCrashReport.partial.json` retains the most recent nonempty
interrupted default-root report before runtime cleanup. It may contain truncated
JSON; preserve its original bytes rather than treating it as a complete report.
Some P/Invoke faults can fail reporting before any bytes are written. Empty
temporary reports cannot supply a trace; system tombstones/logcat are still
needed for such cases.
On API 30+, `MelonLoader/SystemExit/<timestamp>-<pid>/exit.txt` retains the latest
relevant abnormal exit of the same application process. Reasons `2` through `7`
mean signalled exit, low memory, Java crash, native crash, ANR and initialization
failure respectively; `status` contains the exit status or signal where available.
API 31+ native crashes can also supply `trace.pb` (Android's original tombstone
protobuf); ANRs can supply `trace.txt`. Eight events are retained, with an 8 MiB
limit per trace. Collection occurs on the next launch and does not require logcat.
Android may return no trace or may have overwritten it. Review raw traces for
sensitive data before sharing; collection does not upload anything.
Set `loader.capture_player_logs = true` in `Loader.cfg` to mirror Android logcat
messages tagged `Unity` into both current and retained logs. A successful setup
records `Unity player log capture enabled` near the start of `Latest.log` and
subsequent player messages use the `[UNITY]` prefix.

## Updating a patched application

An update must preserve the package identity and signing certificate. Do not
uninstall or clear app data. External tooling should use the platform's replace
installation path and should record `firstInstallTime` before and after the
update. The value must remain unchanged.

Android's APK update time invalidates runtime and deployment extraction caches,
without requiring digest/revision regeneration for manual asset edits. A replacement runtime
is copied into a staging directory before replacing the prior extraction, so
files removed from the new payload do not survive indefinitely. The packaged
deployment tree mirrors the MelonLoader base directory, so an APK can preload
`Mods`, `Plugins`, `UserLibs`, or nested `UserData` files. Deployment policies are
optional per-path overrides; undeclared assets use seed. On APK updates,
development packages seed missing files; production and locked profiles can
upgrade, refresh, or enforce selected directories without requiring a declaration
for each file. Replacements and obsolete managed files are backed up, and unknown
files are never removed. See [DEPLOYMENT.md](DEPLOYMENT.md) for the complete
policy and transaction contract.

## Current limitations

- Android ARM64 and Unity IL2CPP only.
- Active runtime profiles require API 26+. Preflight accepts 4 KiB or 16 KiB pages;
  this does not replace physical 16 KiB-device qualification.
- Game-specific Interop assemblies must be generated off device.
- Coroutine hosting is validated with asynchronous AssetBundle operations.
- `Update`, `FixedUpdate`, and `LateUpdate` use the normal injected
  `MonoBehaviour` phases and have deterministic smoke markers.
- IMGUI, quit, and scene-unload adapters exist but lack current device probes.
- APK patching, signing, and installation remain external responsibilities.
