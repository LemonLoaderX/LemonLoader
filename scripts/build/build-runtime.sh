#!/usr/bin/env bash
set -euo pipefail
source_root=${1:?source checkout}
root=${2:?output root}
revision=${3:?pinned revision}
rid=${4:?runtime RID}
mode=${5:-build}
policy=${6:-locked}
[[ $policy == locked || $policy == development ]]
source_root=$(realpath -e "$source_root")
root=$(realpath -m "$root")
[[ $revision =~ ^[0-9a-f]{40}$ ]]
[[ $rid == android-arm64 || $rid == linux-bionic-arm64 ]]
[[ $mode == plan || $mode == build ]]
if [[ $source_root != /mnt/[a-z]/* || $root != /mnt/[a-z]/* ||
      $root == /mnt/c/* || ${source_root:5:1} != ${root:5:1} ]]; then
    echo 'Runtime source and output must be on the same non-C Windows drive.' >&2
    exit 2
fi
[[ $root != "$source_root" && $root != "$source_root/"* ]]
# Linux Git re-stats Windows index entries through DrvFS and can reread the
# entire runtime tree. Native Git preserves the same checks without that cost.
source_git=(git -C "$source_root")
if command -v git.exe >/dev/null 2>&1; then
    source_git=(git.exe -C "$(wslpath -w "$source_root")")
fi
actual_revision=$("${source_git[@]}" rev-parse HEAD)
actual_revision=${actual_revision%$'\r'}
if [[ $policy == locked ]]; then
    [[ $actual_revision == "$revision" ]]
fi
os=${rid%-arm64}
target="$root/$revision/$rid"
if [[ $policy == development ]]; then
    target="$root/local/$actual_revision/$rid"
fi
args=(clr.runtime+clr.corelib+clr.packages+libs+host.native+packs.product
    -os "$os" -arch arm64 -c Release -p:PublishReadyToRun=false
    -p:PrimaryRuntimeFlavor=CoreCLR -p:DebugType=None -p:DebugSymbols=false -p:_BuildBundle=false
    "-p:RestoreConfigFile=$source_root/NuGet.config")
if [[ $os == linux-bionic ]]; then
    args+=(-p:FeatureXplatEventSource=false)
    headers=${OPENSSL_INCLUDE_DIR:-"$HOME/.cache/lemonloader/openssl-build-headers/extracted/usr/include"}
    args+=(-cmakeargs "-DOPENSSL_INCLUDE_DIR=$headers")
fi
printf 'source=%s\nrevision=%s\nrid=%s\nartifacts=%s\n' "$source_root" "$revision" "$rid" "$target/artifacts"
printf '%q ' ./build.sh "${args[@]}"
printf '\n'
[[ $mode == plan ]] && exit 0
mkdir -p "$root/cache" "$target/artifacts"
# One source checkout, one serialized build; outputs belong to Loader or an explicit root.
exec 9>"$source_root/.lemonloader-runtime-build.lock"
flock -n 9 || { echo 'Another runtime build owns this checkout' >&2; exit 1; }
source_changes=$("${source_git[@]}" status --porcelain --untracked-files=no)
[[ $policy == development || -z $source_changes ]]
if [[ -e "$source_root/artifacts" && ! -L "$source_root/artifacts" ]]; then
    echo 'Preserve the pre-existing artifacts directory outside this checkout before building.' >&2
    exit 1
fi
ln -sfn "$target/artifacts" "$source_root/artifacts"
export ANDROID_NDK_ROOT=${ANDROID_NDK_ROOT:-"$HOME/.cache/lemonloader/android-ndk-r27d"}
export ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT:-"$HOME/.cache/lemonloader/android-sdk"}
export JAVA_HOME=${JAVA_HOME:-"$HOME/.cache/lemonloader/jdk-21.0.12.1-1"}
export PATH="$JAVA_HOME/bin:$PATH"
export NUGET_PACKAGES="$root/cache/nuget/packages"
export NUGET_HTTP_CACHE_PATH="$root/cache/nuget/http"
export DOTNET_CLI_HOME="$root/cache/dotnet-home"
export TMPDIR="$root/cache/tmp"
mkdir -p "$NUGET_PACKAGES" "$NUGET_HTTP_CACHE_PATH" "$DOTNET_CLI_HOME" "$TMPDIR"
test -x "$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/clang"
test -x "$JAVA_HOME/bin/java"
[[ $os != linux-bionic ]] || test -f "$headers/openssl/ssl.h"
cd "$source_root"
stamp=$(date +%Y%m%dT%H%M%S)
printf '%s\n' "$actual_revision" > "$target/source-revision.txt"
printf '%s\n' "$source_changes" > "$target/source-status.txt"
"${source_git[@]}" diff HEAD --binary > "$target/source-changes.patch"
printf '%q ' ./build.sh "${args[@]}" > "$target/build-command.txt"
./build.sh "${args[@]}" > "$target/build-$stamp.log" 2>&1 && status=0 || status=$?
printf '%s\n' "$status" > "$target/exit-code.txt"
[[ $status == 0 ]] || { tail -n 40 "$target/build-$stamp.log"; exit "$status"; }
find artifacts/packages/Release/Shipping -maxdepth 1 -name '*.nupkg' -type f -print0 | sort -z | xargs -0 -r sha256sum > "$target/packages.sha256"
echo "Built $rid; log=$target/build-$stamp.log"
