# Android Il2CppInterop workflow

On-device generation is intentionally not part of the Android runtime. The
bundled Cpp2IL executable targets desktop hosts, adds substantial startup and
download cost, and is not an Android ARM64 executable. LemonLoader instead
consumes pre-generated Interop assemblies.

## Prepare generator inputs

Decode the APK with the tool of your choice, then run:

```powershell
./scripts/interop/prepare-android-interop-input.ps1 `
    -DecodedApkPath "<decoded-apk>"
```

The command validates and copies:

```text
lib/arm64-v8a/libil2cpp.so
assets/bin/Data/Managed/Metadata/global-metadata.dat
assets/bin/Data/globalgamemanagers                 optional
```

The normalized files and `interop-input.json` are written to
`Output/InteropInput`. The manifest records sizes and SHA-256 hashes so a
desktop generator can cache by actual game content rather than APK filename.

## Generate Interop assemblies

The repository uses the same two-stage pipeline as desktop MelonLoader:
Cpp2IL produces dummy assemblies on the development host, then the
`Il2CppInterop.CLI` version pinned in `eng/AndroidDependencies.props` produces
runtime wrappers.

```powershell
./scripts/interop/generate-android-interop.ps1 `
    -InteropInputPath ./Output/InteropInput
```

The workspace defaults to the maintained source fork. A standalone checkout can
pass its CLI project explicitly:

```powershell
./scripts/interop/generate-android-interop.ps1 `
    -InteropInputPath ./Output/InteropInput `
    -Il2CppInteropCliProject ../dependencies/Il2CppInterop/Il2CppInterop.CLI/Il2CppInterop.CLI.csproj
```

The selected source project is recorded in `interop-manifest.json`.
Published Patcher packages include the fixed Il2CppInterop fork generator and do
not restore the older NuGet tool. They accept another built source-fork CLI with
`--il2cppinterop-cli <Il2CppInterop.CLI.dll>` only as an explicit development
override. The override is executed in place so its adjacent dependencies remain
available. Patcher manifests record both the main CLI hash and a content hash
over the adjacent DLL/runtime JSON dependency set and bundled provenance when
present; do not copy only the CLI DLL away from its build directory.

The script downloads the upstream-pinned Cpp2IL
`2022.1.0-pre-release.21` Windows host executable and verifies its SHA-256 before
execution. An existing host executable or Cpp2IL output can be supplied with
`-Cpp2IlPath` or `-Cpp2IlAssembliesPath` respectively. Cpp2IL never runs on the
Android device.

The Android ELF is passed through `--game-assembly` so Il2CppInterop can detect
exported runtime services such as `il2cpp_gc_wbarrier_set_field`. Generation also
uses `--no-xref-cache`; runtime xref behavior must be evaluated per Mod.
The generation script resolves matching Android Unity base libraries through
`LemonLoader.Patcher` when `-UnityAssembliesPath` is not supplied. The primary
source is `MelonLoader.UnityDependencies`; `unity.bepinex.dev` is the fallback.
The cache is content-validated and records its source, normalized Unity version,
archive hash, and extracted content hash. The script then always passes
`--unity` to Il2CppInterop, so the standalone workflow cannot silently skip
unstripping.

Omitting `--game-assembly` makes the generator skip this capability scan. That
can select a fallback write-barrier stub even when the target ELF exports the
native service, causing reference-field updates to fail at runtime. Both
supported generation entry points therefore pass the exact input ELF.

The maintained generator validates optional-parameter metadata and removes only
an orphaned `HasDefault` flag if a supplied Cpp2IL assembly lacks the required
Constant row. Valid constants and `Optional` are unchanged. Generated assemblies
and their manifest are written to `Output/GeneratedInterop`.
The manifest records the Unity dependency directory and `unstripping: true`.

### Unstripped value-type layouts

Unity base libraries contain nested explicit-layout value types such as
`<PrivateImplementationDetails>/__StaticArrayInitTypeSize=6`. Unstripping used
to copy their layout attributes but discard the `ClassLayout` row, changing
the generated type from size 6, pack 1 to size 0, pack 0. Managed runtimes can
observe the metadata mismatch even when one backend happens to tolerate it.

The maintained Il2CppInterop fork now copies both packing size and class size
when it restores a value type. A generator regression builds the nested
explicit-layout fixture, runs the real unstripping pass, and checks the emitted
layout. This is a generator metadata fix; it does not create Unity native
implementations or resolve missing ICalls.

## APK integration

LemonLoader.Patcher now owns this pipeline. It extracts the same inputs directly
from the APK, runs Cpp2IL and Il2CppInterop, optionally writes a developer copy,
and places the assemblies into the patched APK:

```powershell
dotnet run --project ../LemonLoader.Patcher/src/LemonLoader.Patcher.CLI -- patch `
    "<input.apk>" `
    --release ./Output/Releases/LemonLoader-Android-arm64.zip `
    --output "<output.apk>" `
    --interop-output "<interop-output>"
```

The patcher copies only top-level `.dll` files into the independent
`assets/LemonLoader/runtime/interop` domain. At startup Android verifies that
this directory contains assemblies, publishes it as runtime
`MelonLoader/Il2CppAssemblies`, and skips the desktop generator module.
`interop-manifest.json` is copied beside those DLLs to preserve input, tool,
Unity dependency, and output hashes for later verification.

Unstripping restores the managed API surface used to compile and run ordinary
Mods. It does not synthesize native Unity ICalls that were omitted from the
Android player; unresolved native ICalls remain a separate runtime compatibility
problem.

Mods that can operate without an optional Unity ICall may use
`IL2CPP.TryResolveICall<T>` to test the current player without creating a
throwing delegate. Existing generated wrappers remain compatible with
`IL2CPP.ResolveICall<T>`; when its native lookup fails, invoking the returned
delegate now throws `MissingIl2CppInternalCallException`, whose `Signature`
property preserves the exact Unity ICall name. The exception message remains
unchanged for log and tooling compatibility. This reports player capability; it
does not emulate a missing native implementation.

Cpp2IL is the only maintained front end. The historical on-device generator and
the migration-only Il2CppDumper path are not restored.

## Android ARM64 runtime ABI

Android releases build `Il2CppInterop.Runtime` and
`Il2CppInterop.HarmonySupport` from `dependencies/Il2CppInterop`; they are not
opaque prebuilt replacements. LemonLoader explicitly sets the runtime's Android
platform flag from the Android build target instead of relying on runtime
environment heuristics.

For native-to-managed Harmony trampolines, small IL2CPP value-type arguments are
received as ARM64 aggregates and their addresses are passed to
`il2cpp_value_box`. This is required even for an all-zero value such as
`CancellationToken.None`: treating its register value as a pointer would pass a
null source to IL2CPP's eight-byte copy. Non-HFA value-type returns up to 16 bytes
use the native return adapter. ARM64 homogeneous floating-point aggregates use
`v0` through `v3`, and larger aggregates use the managed runtime's AAPCS64 indirect-result
handling. The carrier is derived from the managed value layout instead of
assuming every aggregate belongs in `x0`/`x1`.
