# Managed JNI regression

Prepare the pinned source with scripts/setup-android-dependencies.ps1.
JniHost uses a real host JVM with CheckJNI and borrows the VM:

```powershell
dotnet run --project tests/Android/JniHost/JniHost.csproj -c Release -- java-interop '<JDK>/bin/server/jvm.dll'
```

Pass -p:JavaInteropSourceRoot=<dotnet/android> before -- for an explicit checkout.
Each invocation uses a separate process; JVM unloading/recreation within a live
CLR is not supported. Assertions cover exceptions, reference invalidation,
frame/thread lifetime, shared caches and source-buffer bounds. Host tests do not
qualify ART. AndroidManaged.Tests retains fake JNI tables for targeted asset-stream
and finalizer regressions; those tables are fixtures rather than product ABI.

Build DeviceMod.csproj with MelonLoaderAssemblyPath pointing at the built Android
MelonLoader.dll. The temporary JniMigrationProbe runs these assertions, checks real
APK assets/missing files, application-class lookup on a CLR worker and a subsequent
frame. Capture logs privately and remove the probe afterward. Follow existing
device procedures; no uninstall or data reset.
