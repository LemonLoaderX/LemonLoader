# Managed JNI regression

Prepare the pinned source with scripts/setup-android-dependencies.ps1.
JniHost uses a real host JVM with CheckJNI and borrows the VM:

```powershell
dotnet run --project tests/Android/JniHost/JniHost.csproj -c Release -- java-interop '<JDK>/bin/server/jvm.dll'
```

Pass -p:JavaInteropSourceRoot=<dotnet/android> before -- for an explicit checkout.
Each invocation uses a separate process; JVM unloading/recreation within a live
CLR is not supported. Assertions exercise the production peer registry/finalizer,
typed delegate binding, UTF16/NUL, string/primitive/object-array marshaling,
JavaException recovery, repeated worker scopes and real InputStream buffer/seek
cleanup. Host tests do not qualify ART. AndroidManaged.Tests covers independent
configuration/scene/hook behavior and contains no JNI function-table fixture.

Build DeviceMod.csproj with MelonLoaderAssemblyPath pointing at the built Android
MelonLoader.dll; Java.Interop.dll is resolved beside it. The temporary probe runs
these assertions, real APK assets/missing files, application-class lookup on a CLR
worker, interface callbacks/boxing/errors and Android UI dispatch followed by a
frame. Isolate incompatible old JNI Mods without deleting them. Capture logs
privately and remove the probe afterward. Follow existing
device procedures; no uninstall or data reset.
