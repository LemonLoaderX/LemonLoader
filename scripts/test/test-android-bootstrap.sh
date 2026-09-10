#!/usr/bin/env bash
# Linux host regression against actual bootstrap sources and the NDK JNI interface.
set -euo pipefail
repository_root=$(cd "$(dirname "$0")/../.." && pwd)
test_root="$repository_root/tests/Android/Bootstrap"
native_root="$repository_root/MelonLoader.Bootstrap/Platforms/Android/Native"
build_root="$repository_root/Output/Tests/AndroidBootstrap"
: "${ANDROID_NDK_ROOT:?Set ANDROID_NDK_ROOT to an NDK containing jni.h}"
jni_header=$(find "$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt" -path '*/sysroot/usr/include/jni.h' -print -quit)
test -n "$jni_header"
mkdir -p "$build_root/include"
cp "$jni_header" "$build_root/include/jni.h"
"${CXX:-c++}" -std=c++17 -ffunction-sections -fdata-sections \
    -I"$build_root/include" -I"$test_root/stubs" -I"$repository_root/tests/Android/Logging/stubs" \
    -I"$native_root/include" -I"$native_root/src" -I"$native_root/third_party/plthook" \
    "$test_root/bootstrap_test.cpp" -Wl,--gc-sections -ldl -pthread -o "$build_root/bootstrap-test"
fixture=$(mktemp -d "$build_root/run.XXXXXX")
"$build_root/bootstrap-test" "$fixture"
"${CXX:-c++}" -std=c++17 -ffunction-sections -fdata-sections \
    -I"$build_root/include" -I"$test_root/stubs" -I"$repository_root/tests/Android/Logging/stubs" \
    -I"$native_root/include" -I"$native_root/src" \
    "$test_root/native_load_test.cpp" -Wl,--gc-sections \
    -Wl,--wrap=dlopen,--wrap=dlsym,--wrap=dlclose -ldl -pthread -o "$build_root/native-load-test"
"$build_root/native-load-test"
