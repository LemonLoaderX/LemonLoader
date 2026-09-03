# Pure NDK Android bootstrap

This directory contains the Android bootstrap.
It owns only the Android native startup chain:

- Unity `NativeLoader` JNI registration;
- APK path and asset discovery;
- Unity loading and PLT symbol redirection;
- IL2CPP initialization hooks;
- direct CoreCLR host startup and the native/managed bootstrap ABI;
- native hook, logging, and Java VM exports used by managed MelonLoader.

The managed interface is deliberately limited to `NativeHookAttach`,
`NativeHookDetach`, `LogMsg`, `LogError`, `LogMelonInfo`, `IsConsoleOpen`, and
`GetJavaVM`. Configuration parsing belongs to managed CoreCLR and is not part of
the native ABI.

The implementation produces `lib/arm64-v8a/libmain.so`. Build it with:

```powershell
./scripts/build/build-android-ndk-bootstrap.ps1 `
    -Configuration Release `
    -AndroidNdkRoot $env:ANDROID_NDK_ROOT `
    -DobbySourceRoot ..\dependencies\Dobby
```

The full Android build always uses this implementation. The obsolete NativeAOT
bootstrap has been removed.

Build files and objects belong under `Output/NativeBuild`; this source directory
must remain free of generated files.

Use the shared verification script after linker or dependency changes. It must
remain ARM64 Bionic at API 23, export the managed interface, contain no glibc
symbols, and use at least 16 KiB `LOAD` segment alignment.
