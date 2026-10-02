# Android scripts

Scripts are grouped by workflow so callers can find the narrowest command
without scanning one flat directory.

## Build

| Script | Purpose |
| --- | --- |
| `setup-android-dependencies.ps1` | Resolve maintained source forks at their manifest revisions |
| `build.ps1` | Product build entry, profile selection and explicit development source roots; no parent workspace required |
| `verify.ps1` | Loader script/host/Interop checks and optional desktop/Android build/repack; independent of Patcher |
| `setup-runtime.ps1` | Resolve the active runtime fork at Loader's own pin without changing existing sources |
| `build-runtime.ps1` | WSL runtime source entry; serialized Android/Bionic builds and read-only Plan |
| `build/build-runtime.sh` | Internal WSL backend, per-RID artifacts and source lock |
| `clean.ps1` | Remove known product build trees; packs/archives require AllOutputs, diagnostics and shared sources are retained |
| `scan-publication.ps1` | Audit product HEAD plus explicitly selected source histories/final archives with Gitleaks |
| `build/build-android.ps1` | Full CoreCLR Android orchestration |
| `build/build-android-ndk-bootstrap.ps1` | Build NDK `libmain.so`; active Android requires a validated matching runtime pack for embedded crypto |
| `build/build-android-managed.ps1` | Build the managed host, support module, and maintained managed dependencies |
| `build/stage-android-package.ps1` | Assemble and verify the unpacked APK payload |
| `build/resolve-android-runtime-pack.ps1` | Download, verify, and cache the pinned CoreCLR artifact |
| `build/prepare-runtime-pack.ps1` | Normalize a hash-verified .NET 11 nupkg and compile matching crypto inputs |
| `build/import-runtime-pack.ps1` | Validate/import a normalized Android or Bionic pack |
| `build/package-runtime.ps1` | Deterministically package validated active packs; supports all and OutputRoot |
| `build/publish-android-release.ps1` | Package the staged Loader variant; refresh only the default alias |
| `build/build-android-managed-runtime.ps1` | Frozen .NET 10 source recovery, requires -Legacy |
| `build/publish-android-runtime-pack.ps1` | Frozen .NET 10 archive recovery, requires -Legacy |
| `build/verify-android-bootstrap.ps1` | Verify an existing Android bootstrap ELF |

## Interop

| Script | Purpose |
| --- | --- |
| `interop/prepare-android-interop-input.ps1` | Normalize decoded APK IL2CPP inputs |
| `interop/generate-android-interop.ps1` | Generate game-specific Il2CppInterop assemblies on desktop |
| `interop/deploy-android-interop.ps1` | Back up and replace device Interop assemblies with hash checks |

## Test

| Script | Purpose |
| --- | --- |
| `test/check-android-device.ps1` | Validate device ABI, API, page size, and package presence |
| `test/build-android-smoke-mod.ps1` | Build the lifecycle smoke Mod |
| `test/smoke-test-android.ps1` | Relaunch an installed app and assert startup/lifecycle markers |
| `test/deploy-android-managed-file.ps1` | Back up and replace one device managed file with hash checks |
| `test/verify-android-runtime-parity.ps1` | Verify clean logs, Unity capture, preferences, and historical log output |
| `test/test-android-logging.sh` | Run the Linux/WSL host regression for Android log text, severity, and file output |
| `test/test-android-bootstrap.sh` | Run Linux/WSL regressions for instruction bounds, JNI failures, embedded crypto, asset I/O and runtime process locking; requires NDK headers |
| `test/test-android-deployment.sh` | Run the Linux/WSL file-publication regression for preserved destinations and failure diagnostics |
| `test/test-source-dependencies.ps1` | Local Git fixtures for independent pins, sibling/cache selection and setup preservation |
| `test/test-runtime-source-build.ps1` | WSL fixtures for runtime output isolation, source protection and failure propagation |
| `test/test-cleanup.ps1` | Standalone cleanup fixtures for output retention, preview and linked-tree rejection |
| `test/test-scripts.ps1` | Product script parsing and profile/ADB/cleanup/pack/publication helper regressions |
| `test/test-publication-scan.ps1` | Publication preflight fixtures; optional real Gitleaks marker/history/archive tests |
| `test/test-verification-entry.ps1` | Synthetic orchestration fixtures for selected sources, omitted builds, failure propagation and repacking |
| `test/inspect-runtime-native.sh` | Explicit raw-nupkg native diagnostic: ARM64/alignment/glibc/host exports; not device qualification |

Use PowerShell 7. Internal paths resolve from the script location; caller-supplied
relative paths resolve from the current directory. Build output and captured device logs
remain under `Output`. Scripts do not own APK decoding, signing, installation,
uninstallation, or data clearing.

Device scripts automatically select the only connected and authorized ADB
device. Do not persist wireless-debugging serials because their ports change;
use `-Serial` only when multiple devices are connected.

The NDK script is the only Android bootstrap build and writes
`Output/<Configuration>/linux-bionic-arm64/libmain.so`. Confirm
`bootstrapFlavor: Ndk` in `lemonloader-release.json` and use
`-ExpectedBootstrapFlavor Ndk` for device smoke tests so stale logs cannot
satisfy the check.

Normal builds use `eng/runtime-profiles.json`: Android is the default, Bionic is
selectable, and all means both active profiles. .NET 10 properties in
`eng/AndroidDependencies.props` are only for explicit legacy fallback. Source
builds use scripts/build-runtime.ps1 and are separate from product builds; see
[runtime source development](../docs/android/RUNTIME-DEVELOPMENT.md).

`build.ps1 -Development` with explicit source paths enables local source
iteration, including a different HEAD. Its Loader archives go to
`Output/DevelopmentReleases`, never the normal default alias. The narrow build
scripts retain `-AllowDirtyDependencies`. Source status is recorded
outside release archives; existing MonoMod/Harmony behavior probes still run.
Runtime prepare/import accepts `-Development` for local source packs. Staging
rejects such packs without development mode and always verifies their full file
inventory, runtime version, RID and cryptography layout.

Common helpers own profile selection/integrity, WSL conversion and ADB execution.
Device callers pass the executable and serial explicitly; no helper changes the
selected device implicitly. Checks that intentionally inspect nonzero ADB status
remain local rather than using the throwing helper. Interop and device workflows
remain supported and are not replaced by Patcher release production.
