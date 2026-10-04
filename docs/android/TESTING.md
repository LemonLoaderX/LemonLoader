# Testing

Run the smallest boundary affected by a change. Output stays below Output/Tests
or an explicit ignored path; synthetic fixtures do not qualify Android devices.

## Script and source checks

```powershell
git diff --check
pwsh -NoProfile -File scripts/test/test-scripts.ps1
pwsh -NoProfile -File scripts/test/test-source-dependencies.ps1
```

Script tests cover profile selection, ADB errors, cleanup, publication preflight,
pack contracts and verification orchestration. On Windows, include Bash syntax
with `-SkipBash:$false -Distribution <WSL-distribution>`.
`test-runtime-source-build.ps1` separately checks the WSL launcher with fixture
sources; it does not compile CoreCLR. Actual-pack tests are documented in
[Runtime development](RUNTIME-DEVELOPMENT.md#validation-and-publication).

## Host boundaries

```bash
ANDROID_NDK_ROOT=<ndk> bash scripts/test/test-android-bootstrap.sh
bash scripts/test/test-android-logging.sh
bash scripts/test/test-android-deployment.sh
CXX=clang++ bash scripts/test/test-android-deployment.sh --libcxx
DOTNET11="<dotnet-11-sdk>/dotnet" bash scripts/test/test-crash-reporting.sh
```

Set CXX to an installed C++17 compiler. The libc++ variant also needs its host
headers/libraries. Bootstrap tests compile production code with NDK JNI and fake
Java/linker/OS inputs: bounded scans, IL2CPP handle ownership, failure rollback,
embedded crypto, process locking, editable extraction and system-exit recovery.
Logging covers severity, previous-session retention and report settings.
Publication tests cover short/interrupted I/O, failures and sendfile rejection.
The crash probe uses isolated Linux processes, disables core dumps and checks
handled faults, FailFast/native faults, report attempts, retention and opt-out.
An empty report is a coverage gap, not a successful trace.

```powershell
dotnet run --project tests/Android/Managed/AndroidManaged.Tests.csproj
dotnet run --project tests/Android/GameInformation/GameInformation.Tests.csproj -c Release -p:Platform=x64
dotnet run --project tests/Preferences/Preferences.csproj
```

Managed behavior tests cover configuration preservation, scene fallback and
hook-root retention. JniHost covers actual upstream peers/finalizers, typed calls,
automatic marshaling, exceptions and real InputStream buffer/seek cleanup.
The [JNI host regression](../../tests/Android/JniHost/README.md) exercises the
checked Mod interface with a real JVM; it does not substitute for ART acceptance.
GameInformation uses real AssetsTools parsing with generated files/bundles and
tracked source streams. Preferences checks actual save outcomes, fallback and
events without real Unity logging/watchers. See [failure contracts](HARDENING.md)
for the invariants these fixtures protect.

## Product builds

```powershell
pwsh -NoProfile -File scripts/verify.ps1 -RuntimeProfile android -AndroidNdkRoot "<ndk>"
```

This selects pinned Interop regressions, a Win64 build and one Android
build/repack. `-SkipAndroid -SkipDesktop` narrows it to script/source/Interop tests.
Explicit source/pack paths and Development follow [Building](BUILDING.md).
It does not implicitly run Patcher, native WSL suites, devices or a CoreCLR source
build. Shared managed changes need desktop validation; runtime/packaging changes
need both Android and Bionic builds sequentially because staging is shared.
Managed builds also run MonoModCoreClrProbe and HarmonyCoreClrProbe.

Patcher owns `scripts/test.ps1`, including APK/directory injection, all deployment
policies, duplicate/path/native-collision safety, runtime completeness and legacy
input rejection. Its optional ReleaseArchive input checks actual Loader ZIPs.
Native builds require AArch64/Bionic exports, 16 KiB alignment and matching
stripped/unstripped ELF build IDs. Retain exact symbols before cleaning; compare
different build roots when changing path mapping or link flags.

## Device checks

Devices must already contain the selected application. Use the same signer and
replacement updates; never uninstall, clear app data or change package identity
as a test setup shortcut. Device scripts are explicit maintainer actions.

```powershell
pwsh -NoProfile -File scripts/test/check-android-device.ps1 -PackageName com.example.game
pwsh -NoProfile -File scripts/test/build-android-smoke-mod.ps1 -Configuration Release
pwsh -NoProfile -File scripts/test/smoke-test-android.ps1 -PackageName com.example.game `
    -SmokeModPath ./Output/AndroidSmokeMod/Release/AndroidSmokeMod.dll -WaitSeconds 30
```

The smoke run requires a fresh Latest.log, managed/backend startup, a live process
and the Smoke Mod's initialization, scene, Update/FixedUpdate/LateUpdate, JNI
worker and loaded CoreCLR markers. Same-process maps/exports provide evidence
when Android denies external procfs access. No runtime-identity.json is required.
Resolve the identity probe's CoreCLR handle from its exact private path in
`/proc/self/maps`; loading only `libcoreclr.so` can fail across linker namespaces
even while the private runtime is running.

Smoke may force-stop/relaunch, clear logcat and temporarily push a Mod/HTTPS probe.
It restores existing files and removes test-created files in finally. Captured
logs, screenshots and metadata stay in Output/DeviceSmoke. Use HttpsProbeUrl with
SmokeModPath for a controlled endpoint; a positive request alone does not
establish certificate rejection or client-auth coverage.

For logging/preferences, collect the same session's Latest/Previous/historical
logs, Loader.cfg and relevant preference file. Check retained warnings and real
save outcomes rather than matching historical instrumentation strings.
[Device acceptance](../maintenance/embedded-crypto-acceptance.md) owns API26 ART,
TLS, crash coexistence, Activity recreation and physical 16 KiB coverage.
Dobby hook allocator changes also need its test-android-near-hook.ps1 on native
ARM64 and supported native-bridge devices.

Prefer up to three cold starts followed by a longer scene/GC/network/Mod session;
additional restart loops need an unresolved startup hypothesis. Keep exact source,
toolchain, archive and device identities privately. Host success, a living process
and one device run never establish broad compatibility.
