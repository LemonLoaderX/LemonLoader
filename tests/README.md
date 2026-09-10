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

## Android bootstrap and managed boundaries

```bash
ANDROID_NDK_ROOT=<ndk> bash scripts/test/test-android-bootstrap.sh
```

```powershell
dotnet run --project tests/Android/Managed/AndroidManaged.Tests.csproj
```

These link actual native/managed sources to controlled OS/JNI/Unity fixtures.
Hook regressions exercise both the legacy pointer contract and the optional
checked export, including older-bootstrap fallback and failure root retention.
JNI regressions require stack description before clearing the original exception,
including when obtaining the Latest.log summary raises a secondary exception.
Coverage and remaining device boundaries are listed in
[Android hardening](../docs/android/HARDENING.md).

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

## Deployment file publication

```bash
# Linux/WSL, with CXX selecting a C++17 compiler if needed.
bash scripts/test/test-android-deployment.sh
# Also test with the standard library family used by the Android NDK:
CXX=clang++ bash scripts/test/test-android-deployment.sh --libcxx
```

This exercises the production publication helper used for staged files, backups
and rollback. It covers first install, replacement, failures at directory creation,
temporary-file removal, copy and rename, and retry after a failure. Assertions
require the original nonzero system error and failing step to survive cleanup,
and check that a failed copy/rename preserves the existing destination. Fixtures
stay in `Output/Tests/AndroidDeployment`. Android storage permissions and the full
deployment transaction remain device/integration-test boundaries.

Each run repeats the suite with a preload library that rejects `sendfile` with
`EINVAL`. The libc++ 18 version of the original copy path fails in that environment;
buffered publication must succeed. Linker wrappers also inject interrupted/short
reads and writes, read/write/close errors, and premature EOF. They verify that a
partial file is never published. Multi-buffer binary input and empty files are
included. `--libcxx` requires Clang and installed libc++ headers/libraries; the
default invocation uses the selected compiler's normal C++ standard library.
