# JNI library experiment

This opt-in experiment compares the current managed JNI wrapper, Java.Interop's
direct JNI implementation, and Rxmxnx.JNetInterface's normal high-level API.
It does not replace production JNI or add candidate libraries to Loader releases.

## Build

Use .NET 10 and a separate checkout of dotnet/android. JavaInteropSource points
to its external/Java.Interop folder. The source project compiles the original
managed files and runs the original JNI environment generator; it does not need
the Android workload build, native shim or Java helper JAR. Record the exact source
commit with private evidence. Rxmxnx.JNetInterface is pinned to NuGet 1.2.0.

```powershell
./tests/Android/JniLibraries/build.ps1 `
    -JavaInteropSource '<dotnet/android>/external/Java.Interop' `
    -MelonLoaderAssemblyPath '<Android output>/MelonLoader/net6/MelonLoader.dll'
```

All three candidate binaries are built against net10.0. This requires an installed
Loader runtime that can load .NET 10 assemblies; the product runtime is .NET 11.

## Host

```powershell
dotnet tests/Android/JniLibraries/bin/Host/Release/net10.0/Host.dll `
    java-interop '<JDK>/bin/server/jvm.dll'
```

Repeat with `jnet` and `baseline`, in separate processes. The host independently
creates and destroys a JVM with CheckJNI enabled. Each library only borrows the VM.
Host correctness is separate from ART acceptance. Preserve standard output/error
outside Git; CheckJNI warnings must not be treated as performance observations.

## Device

The device must already have the specified game and Loader installed. Use an
explicit serial. No package is uninstalled and no application data is cleared.

```powershell
./tests/Android/JniLibraries/run-device.ps1 -Serial '<serial>' -Adb '<adb>' `
    -PackageName '<package>' -OutputPath Output/JniLibraries/device
```

The script warms the installed APK before isolating Mods, tests each candidate
in a fresh game process, captures logs, and restores the original Mod directory.
APK-update deployment can regenerate Mods; such inputs are captured separately
before restoring originals. New test paths must not exist. Logcat is not cleared.
The temporary probe and candidate files are removed on exit.

`run-profile.ps1` wraps this workflow with a same-package `adb install -r` and
restores a privately pulled copy of the installed APK. Use only the existing
signer and a compatible test APK. The install itself enforces signing identity.
APK replacement necessarily changes the package update token; the warm-up consumes
the resulting deployment refresh before Mod isolation.

## Scope and interpretation

- Borrow the Loader VM, application ClassLoader and AssetManager; copy owned JNI
  references before adopting them. A dedicated noncollectible AssemblyLoadContext
  prevents baseline state from touching production JNI. Candidate contexts live
  until process exit, consistent with JNI/native runtime lifetime.
- Test UTF-16 including NUL/surrogates, static and instance calls, lookup-mode
  isolation, exception recovery, primitive arrays/bounds, repeated local disposal,
  and two attach/detach scopes on one CLR worker with a cross-thread global reference.
- Device tests read the actual payload through AssetManager and InputStream, then
  require a game frame callback and a living process. `LIMIT application class`
  is a compatibility finding even when the basic suite reaches `PASS ALL`.
- Java.Interop disables managed-peer registration before runtime initialization,
  supplies the app ClassLoader, and implements basic Throwable-to-managed exception
  conversion. It uses explicit thread attachment and host detachment; a production
  adapter must additionally guarantee no access to cached JNIEnv after detach.
- JNetInterface uses its standard package, not Mobile (which requires Java.Interop).
  Its default FindClass behavior may need an app-ClassLoader bridge on CLR workers.
- Benchmarks run 1,000 warm-up operations and three 10,000-operation samples.
  Report elapsed time and managed bytes per thread; do not infer whole-game startup
  gains. JIT tier transitions can affect the first sample. Baseline explicitly checks
  Java exceptions after method calls to keep CheckJNI and error behavior comparable.
  String round trips create from UTF-16 spans and read back through JNI; JNetInterface
  must not benchmark its managed string input cache instead of JNI reading.
- This is not an adversarial lifetime test, API26/16KiB qualification, full-gameplay
  test or public API migration. Do not intentionally submit stale JNI references to ART.

The candidate libraries are MIT licensed; distribution requires their appropriate
license notices. No third-party source or binaries are vendored by these tests.
