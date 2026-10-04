# Android architecture

The port keeps Android-specific behavior behind a small platform layer while
preserving the stable desktop implementation. It targets Android API 26+,
ARM64 IL2CPP, deterministic desktop-generated Interop assemblies, and
pinned NDK r27d builds. APK patching, signing, Mono games, and 32-bit ABIs
remain outside the LemonLoader runtime repository.

## Startup sequence

```text
Unity Java player
  -> System.loadLibrary("main")
  -> NDK libmain.so: JNI_OnLoad
  -> register com.unity3d.player.NativeLoader.load/unload
  -> NativeLoader.load
  -> load libunity.so and invoke its JNI_OnLoad
  -> discover Android application paths through JNI
  -> extract MelonLoader and the private dotnet runtime from APK assets
  -> PLT redirect dlsym
  -> intercept il2cpp_init
  -> load CoreCLR and check its required exports (reject MonoVM)
  -> initialize the selected cryptography backend (JNI for Android, OpenSSL for Bionic)
  -> initialize Android CoreCLR through its direct host API
  -> load MelonLoader.NativeHost.dll
  -> intercept the first active-scene transition
  -> start managed MelonLoader and Mods
```

The native stack is process-scoped. Unity may call `NativeLoader.unload` while
destroying a `UnityPlayer` Activity without terminating the application process;
the bootstrap therefore keeps Unity, CoreCLR, managed callbacks, and hook
trampolines loaded until process exit. A later `NativeLoader.load` in that process
reuses the completed bootstrap instead of invoking Unity or CoreCLR initialization
again. A failed first load is terminal for that process because partially initialized
native runtimes cannot be retried safely.

## Bootstrap implementations

The primary bootstrap is the C++17 NDK module under
`MelonLoader.Bootstrap/Platforms/Android/Native`. It owns Android startup behind the
`libmain.so` interface and exports only JNI plus the native hook, logging, and
Java VM functions consumed by managed MelonLoader. Its implementation is split
by responsibility:

- `bootstrap.cpp`: JNI registration and Unity loading;
- `android_environment.cpp`: path discovery, asset enumeration, and extraction;
- `android_crypto.cpp`: Android crypto class-loader initialization and CoreCLR
  P/Invoke override;
- `runtime.cpp`: Unity symbol interception, CoreCLR hosting, and managed handoff;
- `logging.cpp`: logcat and managed logging ABI;
- `arm64_il2cpp_resolver.cpp`: stripped Unity 6 injection-target resolution.

The NDK module replaces the retired Android NativeAOT adapter: it matches Unity's
Java/native startup directly without ILCompiler or glibc dependencies. Desktop
NativeAOT remains the upstream implementation.

## Managed seam

The NDK bootstrap provides application paths through:

```text
MELONLOADER_BASE_DIR
MELONLOADER_DOTNET_ROOT
MELONLOADER_MANAGED_RUNTIME_BACKEND
```

The NDK bootstrap additionally identifies itself with
`MELONLOADER_BOOTSTRAP_KIND=ndk`. This keeps Android directory discovery and
managed-runtime startup out of desktop code.

Android managed Loader targets `net10.0` for Java.Interop; desktop targets remain
unchanged. Android generates a structured runtimeconfig with `LatestMajor`
roll-forward and ships the selected .NET 11 CoreCLR pack. The historical
`loader/net6` installation path remains a layout contract, not the compiler target.
See [JNI interface](JNI.md) for Mod ownership, calls and migration rules.
Native environment discovery retains the application ClassLoader as a borrowed
process-scoped global before managed hosting starts. Java.Interop uses it as its
class fallback. Lazy callback helpers use their own child loader and remain
separate from private CoreCLR crypto hosting.

## Build seam

`Directory.Build.Android.props` defines the Android RID, constants, ABI, and
API level for managed projects. The primary bootstrap is configured by CMake
using the NDK toolchain and built by
`scripts/build/build-android-ndk-bootstrap.ps1`. It has no ILCompiler or glibc
dependency and is separate from the private managed runtime.

The linker uses `--no-undefined`, and post-build verification explicitly rejects
`__errno_location`. Using the glibc pack is not an acceptable fallback upgrade
path.

The final Android shared libraries are linked with:

```text
-Wl,-z,max-page-size=16384
-Wl,-z,common-page-size=16384
```

All additional native libraries shipped in an APK must be checked separately;
alignment of `libmain.so` does not make the managed runtime, OpenSSL, Unity, or IL2CPP
libraries compatible automatically.

`stage-android-package.ps1` records the CoreCLR runtime identity and
`bootstrapFlavor`, creates the private dotnet layout, adds NDK
libc++ to `libmain.so` statically, emits a file/hash manifest, and validates every staged `.so`
as AArch64 with at least `0x4000` segment alignment.

## Runtime directories

```text
<application-external-files>/MelonLoader/
  MelonLoader/
  Mods/
  Plugins/
  UserData/

<application-data>/dotnet/
  shared/Microsoft.NETCore.App/...
```

The private managed runtime stays in application storage because executing native code from
shared storage is not portable across Android versions and security policies.
The Mod directory uses `Activity.getExternalFilesDir(null)`, so normal startup
does not depend on broad storage permissions. If external storage is unavailable,
the adapter falls back to the application's internal files directory.

## Invariants

- `JNI_OnLoad` must not start the managed runtime. It only registers native methods.
- Unity's `JNI_OnLoad` runs before the common bootstrap installs IL2CPP hooks.
- Runtime and deployment extraction use Android's package update time. A matching
  local marker and existing runtime directory take the cached path without
  installed-file hashing. payload.json supplies optional RID/deployment policies,
  not required generated digests. Only explicit enforce deployment policies
  continuously compare destination bytes against locally saved ownership hashes.
- Changed runtime directories are fully copied into a sibling staging directory
  before replacing the prior extraction, and obsolete files do not survive an
  update.
- Deployment files are planned and applied according to their explicit
  `seed`, `upgrade`, `refresh`, or `enforce` policy. Unknown files are preserved;
  changed managed files are backed up and the ownership-state tree is committed
  only after all file actions succeed.
- The private dotnet path is supplied before the first `il2cpp_init` call.
- The active Android profile embeds the validated runtime helper DEX in
  `libmain.so` and uses `InMemoryDexClassLoader` (API 26+). The crypto shim receives
  that loader explicitly; all crypto P/Invokes resolve to the same initialized
  `dlopen` module. Application-ClassLoader promotion is retired.
- Android initialization must return failure to Java rather than terminating
  the game process when the bootstrap cannot start.
- Android consumes pre-generated Il2CppInterop assemblies. It does not execute
  the legacy desktop Cpp2IL binary inside the application process.
- Parsed game information is cached after successful parsing, keyed by APK update
  time, Loader module and Unity version override. Cache errors fall back to asset
  parsing. Delete MelonLoader/GameInformation.json after manually replacing game
  metadata without updating the APK.
- The bootstrap retains the process-scoped IL2CPP handle observed in Unity's
  symbol lookups. Managed P/Invoke, injection helpers and the ARM64 resolver use
  that same instance. They must not reopen `libil2cpp.so` by name: another linker
  namespace can create a second, uninitialized IL2CPP runtime. The resolver reads
  only the selected instance's readable ELF code ranges, including when the
  caller's `dl_iterate_phdr` cannot enumerate the owning namespace.

## Change placement

| Concern | Location |
| --- | --- |
| RID, ABI, API, and constants | `Directory.Build.Android.props` |
| Native bootstrap and CoreCLR startup | `MelonLoader.Bootstrap/Platforms/Android/Native` |
| Managed Android environment | `MelonLoader/JNI`, `MelonLoader/Utils` |
| Il2Cpp Android ABI and injection compatibility | Maintained Il2CppInterop fork selected by product pin (matching sibling or revision cache) |
| MonoMod CoreCLR compatibility | Maintained MonoMod fork and its MonoMod.Common submodule |
| HarmonyX .NET 9+ emit compatibility | Maintained HarmonyX fork selected by product pin (matching sibling or revision cache) |
| Unity lifecycle adaptation | `Dependencies/SupportModules/Il2Cpp` |
| Build orchestration | `scripts/build` |
| APK contract | `docs/android/ARTIFACTS.md` |
