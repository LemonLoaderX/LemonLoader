[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$LibraryPath,

    [Parameter(Mandatory)]
    [string]$AndroidNdkRoot,

    [int]$AndroidApiLevel = 23
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\common\AndroidToolchain.ps1")

if (-not (Test-Path -LiteralPath $LibraryPath)) {
    throw "Android bootstrap was not found at '$LibraryPath'."
}

$readElf = Get-AndroidNdkTool -AndroidNdkRoot $AndroidNdkRoot -Name "llvm-readelf"
$nm = Get-AndroidNdkTool -AndroidNdkRoot $AndroidNdkRoot -Name "llvm-nm"

$readElfOutput = & $readElf -h -l --notes $LibraryPath 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "llvm-readelf failed with exit code $LASTEXITCODE."
}
$readElfText = $readElfOutput -join [Environment]::NewLine

if ($readElfText -notmatch '(?m)^\s*Machine:\s+AArch64\s*$') {
    throw "The bootstrap is not an AArch64 ELF shared library."
}

$loadSegments = [regex]::Matches(
    $readElfText,
    '(?m)^\s*LOAD\s+.*\s(0x[0-9a-fA-F]+)\s*$')
if ($loadSegments.Count -eq 0) {
    throw "No ELF LOAD segments were found."
}

$invalidAlignment = $loadSegments |
    Where-Object { [Convert]::ToInt64($_.Groups[1].Value, 16) -lt 0x4000 }
if ($invalidAlignment) {
    throw "Every ELF LOAD segment must be aligned to at least 16 KiB."
}

$description = [regex]::Match(
    $readElfText,
    'description data:\s+((?:[0-9a-fA-F]{2}\s+){4})')
if (-not $description.Success) {
    throw "The Android ELF identification note was not found."
}

$apiBytes = $description.Groups[1].Value.Trim() -split '\s+' |
    ForEach-Object { [Convert]::ToInt32($_, 16) }
$actualApiLevel = $apiBytes[0] -bor
    ($apiBytes[1] -shl 8) -bor
    ($apiBytes[2] -shl 16) -bor
    ($apiBytes[3] -shl 24)
if ($actualApiLevel -ne $AndroidApiLevel) {
    throw "Expected Android API $AndroidApiLevel, but the ELF note reports API $actualApiLevel."
}

$nmOutput = & $nm -D --defined-only $LibraryPath 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "llvm-nm failed with exit code $LASTEXITCODE."
}
$nmText = $nmOutput -join [Environment]::NewLine

$requiredExports = @(
    "JNI_OnLoad",
    "NativeHookAttach",
    "NativeHookDetach",
    "CreateArm64ValueReturnAdapter",
    "DestroyArm64ValueReturnAdapter",
    "ResolveArm64Il2CppInjectionTarget",
    "ConfigureLogging",
    "GetJavaVM"
)
foreach ($symbol in $requiredExports) {
    if ($nmText -notmatch "(?m)\b$([regex]::Escape($symbol))\s*$") {
        throw "Required export '$symbol' was not found."
    }
}

$undefinedOutput = & $nm -D --undefined-only $LibraryPath 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Reading undefined bootstrap symbols failed with exit code $LASTEXITCODE."
}
$undefinedText = $undefinedOutput -join [Environment]::NewLine
if ($undefinedText -match '(?m)\b__errno_location\s*$') {
    throw "The bootstrap contains glibc symbol '__errno_location' and cannot load on Android Bionic."
}

$versionOutput = & $readElf --version-info $LibraryPath 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Reading bootstrap symbol versions failed with exit code $LASTEXITCODE."
}
if (($versionOutput -join [Environment]::NewLine) -match '\bGLIBC(?:_|\b)') {
    throw "The bootstrap contains GLIBC-versioned symbols and cannot load on Android Bionic."
}

$dynamicOutput = & $readElf -d $LibraryPath 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Reading bootstrap dynamic dependencies failed with exit code $LASTEXITCODE."
}
if (($dynamicOutput -join [Environment]::NewLine) -match '\(NEEDED\).*\[libc\+\+_shared\.so\]') {
    throw "The bootstrap must statically link libc++; libc++_shared.so is still required."
}

Write-Host "Verified Android ARM64 bootstrap:"
Write-Host "  $LibraryPath"
Write-Host "  API level: $actualApiLevel"
Write-Host "  LOAD alignment: >= 16 KiB"
Write-Host "  JNI and native hook exports: present"
Write-Host "  Bionic symbol check: passed"
Write-Host "  C++ runtime: statically linked"
