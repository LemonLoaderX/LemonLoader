# Tests

Android device probes live under `Android` and are built through scripts rather
than the desktop solution.

`Android/SmokeMod` contains the minimal Mod used by the startup smoke workflow.
It logs deterministic markers for initialization, scene load, first Update, and
first LateUpdate. Add a marker here before claiming another Android lifecycle
path as supported.

The remaining Android projects are focused host-side regressions for CoreCLR
embedding, Harmony resolver precedence, MonoMod dynamic methods, and IL2CPP
injection behavior. Run them through the corresponding scripts in
`scripts/test`; they are not packaged into releases.

## Preference save results

```powershell
dotnet run --project tests/Preferences/Preferences.csproj
```

This host regression links the production preference sources with the pinned
Tomlet package. It replaces Unity/native logging and file watching with test
hosts, so it does not validate watcher timing or device behavior. It checks
ordinary, reflective and global saves: success messages require actual writes;
failed, disabled and fallback saves must not claim success. A failed file must
not stop the global save from writing healthy files. Successful writes retain
their saved event even when `printmsg` is false. Fixtures live below the test
build output.

## Android logging

On Linux (or inside WSL), with a C++17 compiler:

```bash
bash scripts/test/test-android-logging.sh
```

Set `CXX` if the compiler is not available as `c++`. This compiles the production
Android logging source with stub JNI/liblog headers and a recording liblog sink.
It checks stripped ANSI text, null/empty text fallback, warning/error priorities,
one native error record, and matching Latest/historical files. Output stays in
`Output/Tests/AndroidLogging`. Android ABI and real liblog hooks still require
the NDK build and device validation.
