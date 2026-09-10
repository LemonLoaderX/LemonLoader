#!/usr/bin/env bash
# Host-side regression; requires Linux, a C++17 compiler and no Android device.
set -euo pipefail
repository_root=$(cd "$(dirname "$0")/../.." && pwd)
test_root="$repository_root/tests/Android/Logging"
native_root="$repository_root/MelonLoader.Bootstrap/Platforms/Android/Native"
build_root="$repository_root/Output/Tests/AndroidLogging"
mkdir -p "$build_root"
"${CXX:-c++}" -std=c++17 -pthread \
    -I"$test_root/stubs" -I"$native_root/include" -I"$native_root/src" \
    "$native_root/src/logging.cpp" "$test_root/logging_test.cpp" \
    -ldl -o "$build_root/logging-test"
run_root=$(mktemp -d "$build_root/run.XXXXXX")
"$build_root/logging-test" "$run_root"
