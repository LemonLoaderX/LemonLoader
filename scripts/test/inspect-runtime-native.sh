#!/usr/bin/env bash
set -euo pipefail
package=${1:?Pass the runtime nupkg path}
rid=${2:?Pass the runtime RID}
[[ $rid == android-arm64 || $rid == linux-bionic-arm64 ]]
tools="${ANDROID_NDK_ROOT:-$HOME/.cache/lemonloader/android-ndk-r27d}/toolchains/llvm/prebuilt/linux-x86_64/bin"
scratch=$(mktemp -d "$(dirname "$package")/native-inspection.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
# Extract only flat .so entry basenames, never archive-controlled paths.
unzip -Z1 "$package" | while IFS= read -r entry; do
    [[ $entry == runtimes/$rid/native/*.so ]] || continue
    name=${entry#runtimes/$rid/native/}
    [[ $name != */* && $name != *\\* ]]
    unzip -p "$package" "$entry" > "$scratch/$name"
done
count=0
for file in "$scratch"/*.so; do
    test -f "$file"
    count=$((count + 1))
    printf '\nFILE %s\n' "$(basename "$file")"
    "$tools/llvm-readelf" -h -lW "$file" > "$scratch/elf.txt"
    grep -Eq 'Machine:.*AArch64' "$scratch/elf.txt"
    segments=0
    while IFS= read -r alignment; do
        (( alignment >= 0x4000 ))
        segments=$((segments + 1))
    done < <(awk '$1 == "LOAD" {print $NF}' "$scratch/elf.txt")
    (( segments > 0 ))
    "$tools/llvm-nm" -D --undefined-only "$file" > "$scratch/imports.txt"
    if grep -Eq '__errno_location|GLIBC_[0-9]' "$scratch/imports.txt"; then
        echo 'glibc import detected' >&2
        exit 1
    fi
    "$tools/llvm-readelf" -d "$file" | grep NEEDED || true
    "$tools/llvm-readelf" --notes "$file"
    if [[ $(basename "$file") == libcoreclr.so ]]; then
        "$tools/llvm-nm" -D --defined-only "$file" > "$scratch/exports.txt"
        for symbol in coreclr_initialize coreclr_create_delegate coreclr_shutdown; do
            grep -Eq "[[:space:]]$symbol(@@[^[:space:]]+)?$" "$scratch/exports.txt"
        done
    fi
done
printf '\nPASS: %s ELF files; AArch64, >=16KiB alignment, no checked glibc imports.\n' "$count"
echo 'Dependency availability, API compatibility and device execution are not validated.'
