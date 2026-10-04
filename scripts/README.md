# Script catalog

Run from the Loader root with PowerShell 7; Bash backends use WSL on Windows.
Caller-relative input paths resolve from the working directory. Procedures belong
to [Building](../docs/android/BUILDING.md), [Runtime development](../docs/android/RUNTIME-DEVELOPMENT.md),
[Interop](../docs/android/INTEROP.md), [Testing](../docs/android/TESTING.md) and
[Maintenance](../docs/android/MAINTENANCE.md).

## Supported entries

| Entry | Purpose |
| --- | --- |
| setup-android-dependencies.ps1 | Prepare exact Dobby/Interop/Harmony/MonoMod/Java.Interop source pins |
| build.ps1 | Build Android, Bionic or both; explicit development/source/pack inputs |
| verify.ps1 | Script/source/Interop checks, optional desktop/selected Android build and repack |
| setup-runtime.ps1 | Prepare exact runtime source without switching existing checkouts |
| build-runtime.ps1 | Explicit serialized runtime source build or read-only Plan |
| build/prepare-android-coreclr-toolchain.ps1 | Prepare hash-verified isolated WSL SDK/JDK tools |
| build/prepare-runtime-pack.ps1 | Normalize verified nupkg and selected crypto inputs |
| build/import-runtime-pack.ps1 | Validate/import an already normalized pack |
| build/package-runtime.ps1 | Deterministically package validated packs |
| clean.ps1 | Named product-output cleanup with WhatIf; archives require AllOutputs |
| scan-publication.ps1 | Audit explicit producing histories/final archives; no publication |

## Narrow backends

These are callable for a targeted rebuild; build.ps1 owns normal orchestration.

| Entry | Purpose |
| --- | --- |
| build/build-android.ps1 | One native/managed/staging/release profile |
| build/build-android-ndk-bootstrap.ps1 | NDK libmain.so; Android requires matching crypto pack |
| build/build-android-managed.ps1 | Managed host/support and source-built dependencies |
| build/build-android-callbacks.ps1 | javac/d8 callback helper embedded in managed Loader |
| build/stage-android-package.ps1 | Assemble and validate the game-independent payload |
| build/publish-android-release.ps1 | Archive an existing stage; refresh the default alias |
| build/verify-android-bootstrap.ps1 | Check a bootstrap's ELF/exports/build ID |

build/build-runtime.sh, prepare-android-coreclr-toolchain.sh and
build-android-coreclr-crypto-loader.sh are internal backends of their PowerShell
owners. common/* defines helpers only. No backend owns APK signing/installation.

## Interop and explicit device work

| Entry | Purpose |
| --- | --- |
| interop/prepare-android-interop-input.ps1 | Normalize decoded game inputs |
| interop/generate-android-interop.ps1 | Host generation with explicit Unity references or optional Patcher integration |
| interop/deploy-android-interop.ps1 | Back up/replace device Interop; default Output/DeviceBackups |
| test/deploy-android-managed-file.ps1 | Back up/replace one device file; Output/DeviceBackups |
| test/check-android-device.ps1 | ABI/API/page-size/package preflight |
| test/build-android-smoke-mod.ps1 | Build the generic lifecycle/host probe |
| test/smoke-test-android.ps1 | Explicit installed-app smoke; Output/DeviceSmoke |

Device commands select the only authorized ADB device or require Serial when
multiple devices exist. Do not persist changing wireless ports. Smoke can
temporarily deploy test inputs and restores them; file replacement commands
intentionally leave the requested replacement and a backup. None authorizes
uninstalling, app-data clearing or signing changes.

## Tests and diagnostics

| Entry | Boundary |
| --- | --- |
| test/test-scripts.ps1 | PowerShell/Bash syntax and cleanup/profile/publication/orchestration helpers |
| test/test-source-dependencies.ps1 | Independent pins, sibling/cache selection and setup preservation |
| test/test-runtime-source-build.ps1 | WSL launcher, output/source protection and failures using fixtures |
| test/test-runtime-profiles.ps1 | Pack/embedded-byte contracts; optional actual-pack reproducibility |
| test/test-cleanup.ps1 | Synthetic cleanup scope and link/repository protection |
| test/test-publication-scan.ps1 | Preflight fixtures; optional real Gitleaks inputs |
| test/test-verification-entry.ps1 | Selected sources, skipped boundaries and repack failures |
| test/test-android-bootstrap.sh | Native/JNI/crypto/exit/extraction host fixtures |
| test/test-android-logging.sh | Log output/rotation and crash-report settings |
| test/test-android-deployment.sh | Checked file publication; optional libc++ variant |
| test/test-crash-reporting.sh | Explicit .NET11 Linux fatal/handled-fault subprocesses |
| test/inspect-runtime-native.sh | Raw nupkg ARM64/alignment/import/host-export diagnosis |
| test-release-notes.sh | Release-note baseline/filter contract |

generate-release-notes.sh is the release-note producer used by CI.
Keep one-off scripts and private diagnostic evidence outside maintained source.
Do not delete a narrow entry merely because it is not part of the default test
command; its independent boundary determines whether it is useful.
