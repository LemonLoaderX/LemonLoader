#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
    echo "Usage: $0 <source-root> <ndk-root> <sdk-root> <java-home> <configuration>" >&2
    exit 2
fi

source_root=$1
ndk_root=$2
sdk_root=$3
java_home=$4
configuration=$5

for path in "$source_root" "$ndk_root" "$sdk_root" "$java_home"; do
    if [[ ! $path =~ ^/[A-Za-z0-9._+/-]+$ ]] ||
        [[ $path == *'/../'* ]] || [[ $path == */.. ]]; then
        echo "Unsafe Android CoreCLR build path: $path" >&2
        exit 2
    fi
done
if [[ $configuration != Debug && $configuration != Release ]]; then
    echo "Configuration must be Debug or Release." >&2
    exit 2
fi

test -x "$ndk_root/toolchains/llvm/prebuilt/linux-x86_64/bin/clang"
test -f "$sdk_root/platforms/android-36/android.jar"
test -x "$sdk_root/build-tools/36.0.0/aapt2"
test -x "$java_home/bin/java"

export ANDROID_NDK_ROOT="$ndk_root"
export ANDROID_SDK_ROOT="$sdk_root"
export JAVA_HOME="$java_home"
export PATH="$JAVA_HOME/bin:$PATH"

cd "$source_root"
timeout 21600 ./build.sh \
    clr.runtime+clr.corelib+clr.packages+libs \
    -os android \
    -arch arm64 \
    -c "$configuration" \
    -p:PublishReadyToRun=false
