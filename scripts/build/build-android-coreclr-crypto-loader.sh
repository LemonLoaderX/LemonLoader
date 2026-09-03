#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 6 ]]; then
    echo "Usage: $0 <java-source> <crypto-jar> <output-dex> <cache-root> <sdk-root> <java-home>" >&2
    exit 2
fi

java_source=$1
crypto_jar=$2
output_dex=$3
cache_root=$4
sdk_root=$5
java_home=$6

for path in "$java_source" "$crypto_jar" "$output_dex" "$cache_root" "$sdk_root" "$java_home"; do
    if [[ ! $path =~ ^/[A-Za-z0-9._+/-]+$ ]] ||
        [[ $path == *'/../'* ]] || [[ $path == */.. ]]; then
        echo "Unsafe Android crypto loader path: $path" >&2
        exit 2
    fi
done

test -f "$java_source"
test -f "$crypto_jar"
test -f "$sdk_root/platforms/android-36/android.jar"
test -x "$sdk_root/build-tools/36.0.0/d8"
test -x "$java_home/bin/javac"

staging="$cache_root/.coreclr-crypto-loader-$$"
cleanup() {
    rm -rf -- "$staging"
}
trap cleanup EXIT
mkdir -p "$staging/classes" "$staging/dex"

"$java_home/bin/javac" \
    -Xlint:-options \
    -source 8 \
    -target 8 \
    -bootclasspath "$sdk_root/platforms/android-36/android.jar" \
    -d "$staging/classes" \
    "$java_source"

export JAVA_HOME="$java_home"
export PATH="$JAVA_HOME/bin:$PATH"
"$sdk_root/build-tools/36.0.0/d8" \
    --min-api 23 \
    --lib "$sdk_root/platforms/android-36/android.jar" \
    --output "$staging/dex" \
    "$crypto_jar" \
    "$staging/classes/net/dot/android/crypto/LemonLoaderCryptoBootstrap.class"

test -f "$staging/dex/classes.dex"
mkdir -p "$(dirname "$output_dex")"
temporary="$output_dex.tmp-$$"
cp -- "$staging/dex/classes.dex" "$temporary"
mv -f -- "$temporary" "$output_dex"
