#!/usr/bin/env bash
# Linux host tests of Loader defaults against a .NET 11 runtime, not Android qualification.
set -euo pipefail
repository_root=$(cd "$(dirname "$0")/../.." && pwd)
native_root="$repository_root/MelonLoader.Bootstrap/Platforms/Android/Native"
test_root="$repository_root/tests/Android/CrashReport"
build_root="$repository_root/Output/Tests/CrashReport"
: "${DOTNET11:?Set DOTNET11 to a .NET 11 SDK dotnet executable}"
dotnet=$(realpath "$DOTNET11")
mkdir -p "$build_root"
"${CXX:-c++}" -std=c++17 -pthread \
    -I"$repository_root/tests/Android/Logging/stubs" -I"$native_root/include" -I"$native_root/src" \
    "$native_root/src/logging.cpp" "$test_root/launcher.cpp" -ldl -o "$build_root/launcher"
"${CXX:-c++}" -std=c++17 -shared -fPIC -pthread "$test_root/previous_handler.cpp" -o "$build_root/libcrash-fixture.so"
# Select the provided SDK, without inheriting the product's .NET 10 global.json.
(cd / && "$dotnet" build "$test_root/CrashReportProbe.csproj" -c Release \
    -p:ImportDirectoryBuildProps=false -p:ImportDirectoryBuildTargets=false -p:UseAppHost=false \
    -p:BaseIntermediateOutputPath="$build_root/obj/" -o "$build_root/probe")
run_root=$(mktemp -d "$build_root/run.XXXXXX")
probe="$build_root/probe/CrashReportProbe.dll"
ulimit -c 0
unset DOTNET_EnableCrashReport DOTNET_EnableCrashReportOnly COMPlus_EnableCrashReport COMPlus_EnableCrashReportOnly
unset DOTNET_CrashReportRootPath COMPlus_CrashReportRootPath DOTNET_CrashReportMaxFileCount COMPlus_CrashReportMaxFileCount
unset DOTNET_CrashReportBeforeSignalChaining COMPlus_CrashReportBeforeSignalChaining
export LD_LIBRARY_PATH="$build_root${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
"$build_root/launcher" "$run_root/handled" "$dotnet" "$probe" handled
"$dotnet" "$probe" check "$run_root/handled/MelonLoader/.dotnet/crash-reports" 0 0
for mode in failfast native failfast; do
    status=0
    DOTNET_CrashReportMaxFileCount=2 "$build_root/launcher" "$run_root/fatal" "$dotnet" "$probe" "$mode" \
        > "$run_root/$mode.log" 2>&1 &
    pid=$!
    wait "$pid" || status=$?
    expected=134
    if [[ "$mode" == native ]]; then expected=139; fi
    if [[ "$status" != "$expected" ]]; then
        printf 'FAIL %s: exit=%s expected=%s; see %s\n' "$mode" "$status" "$expected" "$run_root/$mode.log"
        exit 1
    fi
    "$dotnet" "$probe" check "$run_root/fatal/MelonLoader/.dotnet/crash-reports" 1 2 "$((expected-128))" "$pid"
done
status=0
DOTNET_EnableCrashReportOnly=0 "$build_root/launcher" "$run_root/disabled" "$dotnet" "$probe" failfast \
    > "$run_root/disabled.log" 2>&1 || status=$?
test "$status" -eq 134
"$dotnet" "$probe" check "$run_root/disabled/MelonLoader/.dotnet/crash-reports" 0 0
LEMON_TEST_PREVIOUS_HANDLER=1 LD_PRELOAD="$build_root/libcrash-fixture.so" "$build_root/launcher" "$run_root/chained-handled" "$dotnet" "$probe" handled
"$dotnet" "$probe" check "$run_root/chained-handled/MelonLoader/.dotnet/crash-reports" 0 0
for before in 0 1; do
    status=0
    LEMON_TEST_PREVIOUS_HANDLER=1 LD_PRELOAD="$build_root/libcrash-fixture.so" DOTNET_CrashReportBeforeSignalChaining="$before" \
        "$build_root/launcher" "$run_root/chained-$before" "$dotnet" "$probe" native \
        > "$run_root/chained-$before.log" 2>&1 &
    pid=$!
    wait "$pid" || status=$?
    test "$status" -eq 73
    if [[ "$before" == 1 ]]; then
        "$dotnet" "$probe" check "$run_root/chained-$before/MelonLoader/.dotnet/crash-reports" 1 1 11 "$pid"
    else
        "$dotnet" "$probe" check "$run_root/chained-$before/MelonLoader/.dotnet/crash-reports" 0 0
    fi
done
status=0
"$build_root/launcher" "$run_root/pinvoke" "$dotnet" "$probe" pinvoke > "$run_root/pinvoke.log" 2>&1 &
pid=$!
wait "$pid" || status=$?
test "$status" -eq 139
"$dotnet" "$probe" evidence "$run_root/pinvoke/MelonLoader/.dotnet/crash-reports" "$pid"
partial=0
if compgen -G "$run_root/pinvoke/MelonLoader/.dotnet/crash-reports/*-$pid.crashreport.json.tmp" > /dev/null; then
    if test -s "$run_root/pinvoke/MelonLoader/.dotnet/crash-reports/"*"-$pid.crashreport.json.tmp"; then partial=1; fi
fi
"$build_root/launcher" "$run_root/pinvoke" "$dotnet" "$probe" handled
if [[ "$partial" == 1 ]]; then test -s "$run_root/pinvoke/MelonLoader/PreviousCrashReport.partial.json"; fi
printf 'PASS handled faults, fatal reports, bounded retention, opt-out and previous-handler chaining\n'
