# Android scripts

Scripts are grouped by workflow so callers can find the narrowest command
without scanning one flat directory.

## Build

| Script | Purpose |
| --- | --- |
| `build/build-android.ps1` | Full CoreCLR Android orchestration |
| `build/build-android-ndk-bootstrap.ps1` | Build the pure NDK `libmain.so` |
| `build/build-android-managed.ps1` | Build the Android managed host and Il2Cpp support module |
| `build/stage-android-package.ps1` | Assemble and verify the unpacked APK payload |
| `build/resolve-android-runtime-pack.ps1` | Download, verify, and cache the pinned CoreCLR artifact |
| `build/build-android-managed-runtime.ps1` | Rebuild CoreCLR from the maintained runtime fork |
| `build/publish-android-runtime-pack.ps1` | Create the deterministic runtime release archive |
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

Run all scripts from the repository root. Build output and captured device logs
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

Normal builds resolve the runtime artifact pinned in
`eng/AndroidDependencies.props`. Building the runtime source is a separate
maintainer workflow and is not part of ordinary LemonLoader builds.
