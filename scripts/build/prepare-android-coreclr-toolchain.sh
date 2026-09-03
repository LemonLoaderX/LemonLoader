#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 10 ]]; then
    echo "Usage: $0 <cache-root> <jdk-version> <jdk-url> <jdk-sha256> <jdk-directory> <cmdline-version> <cmdline-sha256> <sdk-api> <build-tools-version> <cmdline-directory>" >&2
    exit 2
fi

cache_root=$1
jdk_version=$2
jdk_url=$3
jdk_sha256=$4
jdk_directory=$5
cmdline_version=$6
cmdline_sha256=$7
sdk_api=$8
build_tools_version=$9
cmdline_directory=${10}

if [[ ! $cache_root =~ ^/[A-Za-z0-9._+/-]+$ ]] ||
    [[ $cache_root == *'/../'* ]] || [[ $cache_root == */.. ]]; then
    echo "Unsafe Linux cache path: $cache_root" >&2
    exit 2
fi
if [[ ! $jdk_sha256 =~ ^[0-9a-fA-F]{64}$ ]] || [[ ! $cmdline_sha256 =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "Invalid toolchain archive checksum." >&2
    exit 2
fi

jdk_root="$cache_root/$jdk_directory"
sdk_root="$cache_root/android-sdk"
downloads="$cache_root/downloads"
staging="$cache_root/.android-coreclr-toolchain-$$"
jdk_archive="$downloads/OpenJDK21U-jdk_x64_linux_hotspot_${jdk_version/+/_}.tar.gz"
cmdline_archive="$downloads/commandlinetools-linux-$cmdline_version.zip"
cmdline_url="https://dl.google.com/android/repository/commandlinetools-linux-$cmdline_version.zip"
cmdline_root="$sdk_root/cmdline-tools/$cmdline_directory"

cleanup() {
    rm -rf -- "$staging"
}
trap cleanup EXIT

mkdir -p "$downloads" "$staging"

download_file() {
    local url=$1
    local destination=$2
    local partial="$destination.partial-$$"
    rm -f -- "$partial"
    curl --fail --location --retry 5 --retry-delay 2 \
        --connect-timeout 30 --max-time 1800 \
        --output "$partial" "$url"
    mv -f -- "$partial" "$destination"
}

if [[ ! -f $jdk_archive ]] ||
    ! printf '%s  %s\n' "$jdk_sha256" "$jdk_archive" | sha256sum --check --status; then
    rm -f -- "$jdk_archive"
    download_file "$jdk_url" "$jdk_archive"
fi
printf '%s  %s\n' "$jdk_sha256" "$jdk_archive" | sha256sum --check --status

if [[ ! -x $jdk_root/bin/java ]]; then
    jdk_staging="$staging/jdk"
    mkdir -p "$jdk_staging"
    tar -xzf "$jdk_archive" --strip-components=1 -C "$jdk_staging"
    test -x "$jdk_staging/bin/java"
    rm -rf -- "$jdk_root"
    mv -- "$jdk_staging" "$jdk_root"
fi

if [[ ! -f $cmdline_archive ]] ||
    ! printf '%s  %s\n' "$cmdline_sha256" "$cmdline_archive" | sha256sum --check --status; then
    rm -f -- "$cmdline_archive"
    download_file "$cmdline_url" "$cmdline_archive"
fi
printf '%s  %s\n' "$cmdline_sha256" "$cmdline_archive" | sha256sum --check --status

if [[ ! -x $cmdline_root/bin/sdkmanager ]]; then
    cmdline_staging="$staging/cmdline"
    mkdir -p "$cmdline_staging"
    python3 - "$cmdline_archive" "$cmdline_staging" <<'PY'
import pathlib
import sys
import zipfile

archive_path = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
with zipfile.ZipFile(archive_path) as archive:
    for entry in archive.infolist():
        path = pathlib.PurePosixPath(entry.filename)
        if path.is_absolute() or ".." in path.parts:
            raise RuntimeError(f"Unsafe SDK archive entry: {entry.filename}")
    archive.extractall(destination)
PY
    chmod +x "$cmdline_staging/cmdline-tools/bin/"*
    test -x "$cmdline_staging/cmdline-tools/bin/sdkmanager"
    rm -rf -- "$cmdline_root"
    mkdir -p "$sdk_root/cmdline-tools"
    mv -- "$cmdline_staging/cmdline-tools" "$cmdline_root"
fi

export JAVA_HOME="$jdk_root"
export PATH="$JAVA_HOME/bin:$PATH"
sdkmanager="$cmdline_root/bin/sdkmanager"

set +o pipefail
yes | timeout 1800 "$sdkmanager" --sdk_root="$sdk_root" --licenses \
    > "$cache_root/sdkmanager-licenses.log" 2>&1
license_status=${PIPESTATUS[1]}
set -o pipefail
if [[ $license_status -ne 0 ]]; then
    cat "$cache_root/sdkmanager-licenses.log"
    exit "$license_status"
fi

timeout 3600 "$sdkmanager" --sdk_root="$sdk_root" \
    "platform-tools" \
    "platforms;android-$sdk_api" \
    "build-tools;$build_tools_version" \
    > "$cache_root/sdkmanager-install.log" 2>&1

test -f "$sdk_root/platforms/android-$sdk_api/android.jar"
test -x "$sdk_root/build-tools/$build_tools_version/aapt2"
test -x "$sdk_root/platform-tools/adb"
"$JAVA_HOME/bin/java" -version

cmdline_sha256=$(sha256sum "$cmdline_archive" | awk '{print $1}')
python3 - \
    "$cache_root/android-coreclr-toolchain.json" \
    "$jdk_version" "$jdk_url" "$jdk_sha256" \
    "$cmdline_version" "$cmdline_sha256" \
    "$sdk_api" "$build_tools_version" \
    "$jdk_root" "$sdk_root" <<'PY'
import json
import os
import pathlib
import sys

output = pathlib.Path(sys.argv[1])
document = {
    "formatVersion": 1,
    "jdkVersion": sys.argv[2],
    "jdkUrl": sys.argv[3],
    "jdkSha256": sys.argv[4],
    "commandLineToolsVersion": sys.argv[5],
    "commandLineToolsSha256": sys.argv[6],
    "sdkApiLevel": int(sys.argv[7]),
    "buildToolsVersion": sys.argv[8],
    "jdkRoot": sys.argv[9],
    "androidSdkRoot": sys.argv[10],
}
temporary = output.with_suffix(output.suffix + ".tmp")
temporary.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
os.replace(temporary, output)
PY

printf 'Prepared isolated Android CoreCLR toolchain:\n'
printf '  JAVA_HOME: %s\n' "$jdk_root"
printf '  ANDROID_SDK_ROOT: %s\n' "$sdk_root"
printf '  Manifest: %s\n' "$cache_root/android-coreclr-toolchain.json"
