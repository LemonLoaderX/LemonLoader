# Android architecture

The port keeps Android-specific behavior behind a small platform layer while
preserving the stable desktop implementation. It targets Android API 23+,
ARM64 IL2CPP, deterministic desktop-generated Interop assemblies, and
reproducible NDK r27d builds. APK patching, signing, Mono games, and 32-bit ABIs
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
  -> verify the selected engine identity
  -> initialize source-built Android crypto through the application class loader
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

The obsolete NativeAOT adapter and its ILCompiler-specific build configuration
have been removed. The NDK module is the only Android bootstrap.

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

Stable MelonLoader remains compiled for `net6`. Android generates a structured
runtimeconfig with `LatestMajor` roll-forward and ships the source-built .NET
versioned .NET 10 Android CoreCLR runtime pack. This
keeps the upstream target unchanged and replaces the legacy port's runtimeconfig
text mutation with an MSBuild-owned setting.

## Build seam

`Directory.Build.Android.props` defines the Android RID, constants, ABI, and
API level for managed projects. The primary bootstrap is configured by CMake
using the NDK toolchain and built by
`scripts/build/build-android-ndk-bootstrap.ps1`. It has no ILCompiler or glibc
dependency and is separate from the private .NET 10 managed runtime.

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
- Runtime extraction uses independent loader, dotnet, and Interop domain hashes
  in `assets/LemonLoader/payload.json`. A matching marker and existing owned
  directory are sufficient on the normal startup path; complete file hashing is
  confined to Release/APK validation. Deployment staging is verified on every
  launch because an `enforce` policy may need to restore a changed file even
  when the packaged revision has not changed.
- Changed runtime directories are fully copied into a sibling staging directory
  before replacing the prior extraction, and obsolete files do not survive an
  update.
- Deployment files are planned and applied according to their layout v8
  `seed`, `upgrade`, `refresh`, or `enforce` policy. Unknown files are preserved;
  changed managed files are backed up and the ownership-state tree is committed
  only after all file actions succeed.
- The private dotnet path is supplied before the first `il2cpp_init` call.
- CoreCLR Android crypto helper classes must be promoted by the Patcher into the
  application class loader, and all crypto P/Invokes must resolve to that one
  `JNI_OnLoad`-initialized module.
- Android initialization must return failure to Java rather than terminating
  the game process when the bootstrap cannot start.
- Android consumes pre-generated Il2CppInterop assemblies. It does not execute
  the legacy desktop Cpp2IL binary inside the application process.

## Change placement

| Concern | Location |
| --- | --- |
| RID, ABI, API, and constants | `Directory.Build.Android.props` |
| Native bootstrap and CoreCLR startup | `MelonLoader.Bootstrap/Platforms/Android/Native` |
| Managed Android environment | `MelonLoader/JNI`, `MelonLoader/Utils` |
| Il2Cpp Android ABI and injection compatibility | `dependencies/Il2CppInterop` in the workspace |
| MonoMod .NET 10 compatibility | `dependencies/MonoMod` in the workspace |
| HarmonyX .NET 9+ emit compatibility | `dependencies/HarmonyX` in the workspace |
| Unity lifecycle adaptation | `Dependencies/SupportModules/Il2Cpp` |
| Build orchestration | `scripts/build` |
| APK contract | `docs/android/ARTIFACTS.md` |
