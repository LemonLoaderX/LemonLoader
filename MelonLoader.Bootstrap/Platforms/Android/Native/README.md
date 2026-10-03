# Pure NDK Android bootstrap

This directory contains the Android bootstrap.
It owns only the Android native startup chain:

- Unity `NativeLoader` JNI registration;
- APK path and asset discovery;
- Unity loading and PLT symbol redirection;
- IL2CPP initialization hooks;
- direct CoreCLR host startup and the native/managed bootstrap ABI;
- native hook, logging, and Java VM exports used by managed MelonLoader.

The managed interface is declared in `include/lemon_bootstrap.h`. It includes
hooking, logging, Java VM access and `GetIl2CppLibraryHandle`, which exposes the
borrowed, process-scoped IL2CPP handle captured from Unity. Managed consumers must
not close that handle or replace it with a by-name load in another linker namespace.
Configuration parsing belongs to managed CoreCLR and is not part of the native ABI.

The implementation produces `lib/arm64-v8a/libmain.so` through Loader's
[build workflow](../../../../docs/android/BUILDING.md). Android needs its
matching validated runtime pack for embedded helper DEX; Bionic uses OpenSSL.
Both product profiles target API26+. This NDK module is the only Android bootstrap.

Build files and objects belong under `Output/NativeBuild`; this source directory
must remain free of generated files.

It must export the native/managed interface, contain no glibc imports and retain
16 KiB LOAD alignment and the stripped/unstripped build ID.
[Architecture](../../../../docs/android/ARCHITECTURE.md) owns startup;
[failure contracts](../../../../docs/android/HARDENING.md) and
[tests](../../../../docs/android/TESTING.md) own verification boundaries.
