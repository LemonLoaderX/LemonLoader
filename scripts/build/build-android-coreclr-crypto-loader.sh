#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
    echo "Usage: $0 <crypto-jar> <output-dex> <cache-root> <sdk-root> <java-home>" >&2
    exit 2
fi

crypto_jar=$1
output_dex=$2
cache_root=$3
sdk_root=$4
java_home=$5

for path in "$crypto_jar" "$output_dex" "$cache_root" "$sdk_root" "$java_home"; do
    if [[ ! $path =~ ^/[A-Za-z0-9._+/-]+$ ]] ||
        [[ $path == *'/../'* ]] || [[ $path == */.. ]]; then
        echo "Unsafe Android crypto loader path: $path" >&2
        exit 2
    fi
done

test -f "$crypto_jar"
test -f "$sdk_root/platforms/android-36/android.jar"
test -x "$sdk_root/build-tools/36.0.0/d8"
test -x "$java_home/bin/java"

staging="$cache_root/.coreclr-crypto-loader-$$"
cleanup() {
    rm -rf -- "$staging"
}
trap cleanup EXIT
mkdir -p "$staging/dex"

export JAVA_HOME="$java_home"
export PATH="$JAVA_HOME/bin:$PATH"
"$sdk_root/build-tools/36.0.0/d8" \
    --min-api 26 \
    --lib "$sdk_root/platforms/android-36/android.jar" \
    --output "$staging/dex" \
    "$crypto_jar"

test -f "$staging/dex/classes.dex"
mkdir -p "$(dirname "$output_dex")"
temporary="$output_dex.tmp-$$"
cp -- "$staging/dex/classes.dex" "$temporary"
mv -f -- "$temporary" "$output_dex"
