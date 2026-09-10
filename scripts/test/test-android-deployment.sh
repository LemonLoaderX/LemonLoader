#!/usr/bin/env bash
# Linux/WSL host regression for file publication and its failure diagnostics.
set -euo pipefail
compiler_flags=()
if [[ "${1:-}" == "--libcxx" ]]; then
    compiler_flags+=(-stdlib=libc++)
    shift
fi
if [[ $# -ne 0 ]]; then
    echo "Usage: $0 [--libcxx]" >&2
    exit 2
fi
repository_root=$(cd "$(dirname "$0")/../.." && pwd)
native_root="$repository_root/MelonLoader.Bootstrap/Platforms/Android/Native"
build_root="$repository_root/Output/Tests/AndroidDeployment"
mkdir -p "$build_root"
"${CXX:-c++}" -std=c++17 "${compiler_flags[@]}" -I"$native_root/src" \
    "$repository_root/tests/Android/Deployment/deployment_file_test.cpp" \
    -Wl,--wrap=read,--wrap=write,--wrap=close \
    -o "$build_root/deployment-file-test"
run_root=$(mktemp -d "$build_root/run.XXXXXX")
"$build_root/deployment-file-test" "$run_root"
"${CXX:-c++}" -std=c++17 "${compiler_flags[@]}" -shared -fPIC \
    "$repository_root/tests/Android/Deployment/reject_sendfile.cpp" \
    -o "$build_root/reject-sendfile.so"
run_root=$(mktemp -d "$build_root/run.XXXXXX")
LD_PRELOAD="$build_root/reject-sendfile.so${LD_PRELOAD:+:$LD_PRELOAD}" \
    "$build_root/deployment-file-test" "$run_root"
