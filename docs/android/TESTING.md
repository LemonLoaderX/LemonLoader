# Android testing

## Test levels

### Static checks

Run before every commit that changes Android files or scripts:

```powershell
git diff --check

$errors = @()
Get-ChildItem ./scripts -Filter *.ps1 -File -Recurse | ForEach-Object {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $_.FullName, [ref]$tokens, [ref]$parseErrors)
    $errors += $parseErrors
}
if ($errors.Count) { $errors; exit 1 }
```

The Android build adds ELF architecture, Android API, required export, Bionic
symbol, and 16 KiB segment-alignment checks automatically.

### Managed compatibility tests

```powershell
../LemonLoader.Patcher/scripts/test.ps1 -Configuration Release
```

This copies raw pinned NuGet assemblies, applies the Android transformations,
and verifies that a second pass is byte-for-byte idempotent. It must fail when
assembly identity or expected IL shape changes.

Android managed builds also run `MonoModCoreClrProbe` and
`HarmonyCoreClrProbe`. They exercise the source-built .NET 10 DynamicMethod and
RuntimeLocalBuilder paths before packaging.

### Build tests

For Android runtime or packaging changes:

```powershell
./scripts/build/build-android.ps1 `
    -Configuration Release
```

For shared managed code, also run the Win64 Il2Cpp support-module build from
`BUILDING.md`. A successful Android build alone does not prove desktop behavior
was preserved.

### Device preflight

```powershell
./scripts/test/check-android-device.ps1 `
    -PackageName com.example.game
```

The device must advertise ARM64, use API 23+, use a 4 KiB or 16 KiB page size,
and already contain the selected package.

### Device smoke test

```powershell
./scripts/test/build-android-smoke-mod.ps1 -Configuration Release
./scripts/test/smoke-test-android.ps1 `
    -PackageName com.example.game `
    -SmokeModPath ./Output/AndroidSmokeMod/Release/AndroidSmokeMod.dll `
    -ExpectedBootstrapFlavor Ndk `
    -WaitSeconds 30
```

The test requires the managed startup banner and these exact marker classes:

```text
[Android_Smoke_Mod] Initialize
[Android_Smoke_Mod] SceneLoaded
[Android_Smoke_Mod] FirstUpdate
[Android_Smoke_Mod] FirstFixedUpdate
[Android_Smoke_Mod] FirstLateUpdate
[Android_Smoke_Mod] JniWorker 10006 True
[Android_Smoke_Mod] RuntimeIdentity CoreClr True MonoVm False Maps True
[Android_Smoke_Mod] RuntimeIdentityFile coreclr <version> coreclr-host-api Hash True
```

It also asserts that the game process stays alive, rejects a stale `Latest.log`,
checks the pure NDK/backend markers, and archives `Latest.log` and logcat under
`Output/DeviceSmoke`. When Android blocks external `/proc/<pid>/maps` or
`run-as`, the Smoke Mod supplies same-process map, symbol, engine-hash, and
runtime-identity evidence instead of weakening the assertion. Known framework
startup failures in Harmony's local-builder initialization also fail the smoke
test even when later lifecycle markers are present.

After a logging or preference change, pull the app's MelonLoader base directory
and run the parity contract against the same launch:

```powershell
./scripts/test/verify-android-runtime-parity.ps1 `
    -LatestLog <pulled-MelonLoader-base>/MelonLoader/Latest.log `
    -RuntimeRoot <pulled-MelonLoader-base> `
    -RequiredPreferenceFile <mod-preferences>.cfg `
    -RequireUnityLogs
```

This rejects temporary `[DEBUG-*]` instrumentation, the obsolete component-
sibling warning, missing Unity capture, a missing `Loader.cfg`, a missing Mod
preference file, and an empty historical log directory. A synthetic log can
validate the script itself but is not device evidence.

Game-specific reproduction matrices and their logs belong in the workspace
`temp/` evidence tree, not in the reusable runtime script set. Promote only a
generic regression that can run against more than one game.

Do not use large restart counts as a default reliability test. Run no more than
three consecutive cold starts for one build, then prefer one longer session that
covers scene changes, repeated managed and IL2CPP GC activity, HTTPS, and real Mod
workflows. More restarts require a specific unresolved startup hypothesis.

## Device safety

- The smoke script may force-stop and relaunch the app.
- It may temporarily push `AndroidSmokeMod.dll` and an HTTPS probe into the
  app-scoped files directory. It restores pre-existing files and removes files
  created by the test in `finally`, including after a failed assertion.
- It must not uninstall the package or clear application data.
- Installing a newly packaged test APK is an external step. When replacement is
  required, use a non-incremental replacement install and verify the package's
  `firstInstallTime` did not change.
- Never use an uninstall/reinstall sequence as a test setup shortcut.

## Coverage claims

The generic device probe covers managed initialization, scene-loaded callbacks,
normal Update, FixedUpdate, and LateUpdate phases, plus JNI attachment from a
managed worker thread. The current game regression also covers coroutine hosting,
but does not prove IMGUI, scene unload, or quit behavior across games. Add a
deterministic marker before broadening a claim.

## Release evidence

Record the following in the workspace `STATUS.md` for a release candidate:

- commit, SDK, NDK, bootstrap flavor, and private runtime versions;
- device Android API, ABI, page size, package version, and Unity version;
- full build result and known warnings;
- smoke-test output directory and observed markers;
- APK signature/alignment verification performed by external packaging;
- whether app data and `firstInstallTime` were preserved.
