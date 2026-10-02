# Android testing

## Test levels

### Static checks

Run before every commit that changes Android files or scripts:

```powershell
git diff --check
pwsh -NoProfile -File scripts/test/test-scripts.ps1
```

This product-owned entry parses PowerShell scripts and tests profile selection,
ADB argument/error handling, legacy metadata boundaries, cleanup, runtime pack
fixtures and publication scanner orchestration. No parent checkout or device is
required. Bash parsing defaults on Linux and off on Windows; on Windows use
`-SkipBash:$false -Distribution <WSL-distribution>` to include WSL Bash parsing.
The heavier runtime source build fixture is a separate WSL test entry.

The Android build adds ELF architecture, Android API, required export, Bionic
symbol, and 16 KiB segment-alignment checks automatically.
Product cleanup safety has a standalone synthetic-tree regression:

```powershell
pwsh -NoProfile -File scripts/test/test-cleanup.ps1
```

It checks previews, retained packs/archives/evidence, source/cache boundaries and
link rejection without cleaning actual builds or dependency checkouts.
The native bootstrap host suite includes system-exit recovery tests against
the NDK JNI interface: API gating, current-process selection, exact trace bytes,
stream errors/closure, retry, capacity limits and safe retention. These fake-JNI
tests do not establish OEM tombstone availability or Android permission behavior.
The same suite exercises editable deployment through real extraction/transaction
code with fake APK/JNI inputs: stale/absent metadata, add/edit/delete, user-edit
protection, no unchanged-package scan and pre-hook Loader disabling on failure.
Runtime extraction cases cover absent/minimal configuration, no generated
digest/identity/Interop manifest, APK update replacement/removal and retry when
the platform update token is unavailable.
Patcher regressions cover active layout-9 APK/directory injection with plain
Interop DLLs, non-default policy overrides, manual asset add/delete, malformed
policies and Release-file corruption. Historical layout-8 hash, external-DEX and
embedded-bootstrap checks remain separate compatibility cases.
Native build verification requires an ELF build ID and checks that stripping
preserves the private symbol file's ID. Release staging rejects DWARF/static
symbols while retaining this diagnostic identifier. When changing native build
flags/toolchains, compare builds from different source/build roots using the same
inputs to check that local paths do not change the output.

For native-hook changes, run the maintained Dobby far-target regression on both
a native ARM64 device and any supported native-bridge emulator:

```powershell
pwsh -NoProfile -File "<Dobby-source-root>/scripts/test-android-near-hook.ps1" `
    -DeviceSerial "<serial>"
```

### Managed compatibility tests

Preference persistence and Android logging have focused host regressions:

```powershell
dotnet run --project tests/Preferences/Preferences.csproj
```

```bash
# Linux/WSL; CXX may select a C++17 compiler.
bash scripts/test/test-android-logging.sh
```

See `tests/README.md` for their boundaries. Preference save success messages are
emitted only after a write; an I/O failure keeps the existing fallback behavior
and error diagnostics. Fix the path/permissions and restart to leave fallback
mode. Android logs use stripped text for file/logcat output and preserve WARN
and ERROR priorities; native errors produce one logcat record.
The native logging regression also exercises previous-session retention before
managed history setup, empty-session handling, history limits and append fallback
when rotation fails.

Runtime report defaults and overrides are covered by that native logging test.
To exercise the upstream reporter in isolated Linux host subprocesses:

```bash
DOTNET11="<dotnet-11-sdk>/dotnet" bash scripts/test/test-crash-reporting.sh
```

The probe checks handled faults, FailFast/native faults, report JSON, retention
and explicit opt-out. It disables host core dumps and writes evidence below
Output/Tests. It does not qualify Android signal coexistence or ARM64 crash traces.

```powershell
../LemonLoader.Patcher/scripts/test.ps1 -Configuration Release
```

Patcher tests cover release validation, runtime selection, APK and directory
assembly, deployment policies, native collisions, and CLI/signing contracts.
They use synthetic inputs and do not rewrite dependency binaries.

Android managed builds also run `MonoModCoreClrProbe` and
`HarmonyCoreClrProbe`. They exercise the source-built CoreCLR DynamicMethod and
RuntimeLocalBuilder paths before packaging.

### Build tests

For runtime or packaging changes, provide validated packs and build both profiles
sequentially (the staging directory is shared):

```powershell
./scripts/build/build-android.ps1 -Configuration Release -RuntimeProfile android
./scripts/build/build-android.ps1 -Configuration Release -RuntimeProfile bionic
```

For shared managed code, also run the Win64 Il2Cpp support-module build from
`BUILDING.md`. A successful Android build alone does not prove desktop behavior
was preserved.

### Device preflight

```powershell
./scripts/test/check-android-device.ps1 `
    -PackageName com.example.game
```

The device must advertise ARM64, use API 26+ for active profiles, use a 4 KiB or
16 KiB page size, and already contain the selected package. A legacy preflight's
API 23 acceptance does not qualify the .NET 11 runtime for that API.

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
    -LatestLog "<pulled-MelonLoader-base>/MelonLoader/Latest.log" `
    -RuntimeRoot "<pulled-MelonLoader-base>" `
    -RequiredPreferenceFile "<mod-preferences>.cfg" `
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

Record the following in ignored workspace evidence for a release candidate;
keep `STATUS.md` limited to stable capabilities and qualification gaps:

- commit, SDK, NDK, bootstrap flavor, and private runtime versions;
- device Android API, ABI, page size, package version, and Unity version;
- full build result and known warnings;
- smoke-test output directory and observed markers;
- APK signature/alignment verification performed by external packaging;
- whether app data and `firstInstallTime` were preserved.
