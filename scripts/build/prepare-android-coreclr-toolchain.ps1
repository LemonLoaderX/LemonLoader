[CmdletBinding()]
param(
    [string]$Distribution = "Ubuntu-24.04",

    [string]$CacheRoot,

    [string]$JdkVersion = "21.0.12.1+1",

    [string]$JdkUrl = "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz",

    [string]$JdkSha256 = "ce79869e1307ed8ee1e2baa86a412b1eb5b75d10a01006d788a6f968bcfaee94",

    [string]$CommandLineToolsVersion = "13114758_latest",

    [string]$CommandLineToolsSha256 = "7ec965280a073311c339e571cd5de778b9975026cfcbe79f2b1cdcb1e15317ee",

    [int]$SdkApiLevel = 36,

    [string]$BuildToolsVersion = "36.0.0"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\common\Wsl.ps1")
if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
    $CacheRoot = "$(Get-WslHome -Distribution $Distribution)/.cache/lemonloader"
}

function Assert-SafeLinuxPath {
    param([Parameter(Mandatory)] [string]$Path)

    if ($Path -notmatch '^/[A-Za-z0-9._+/-]+$' -or
        $Path.Contains('/../') -or
        $Path.EndsWith('/..', [StringComparison]::Ordinal)) {
        throw "The Linux cache path is not safe: '$Path'."
    }
}

Assert-SafeLinuxPath -Path $CacheRoot
if ($JdkSha256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "JdkSha256 must be a SHA-256 value."
}
if ($CommandLineToolsSha256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw "CommandLineToolsSha256 must be a SHA-256 value."
}
if ($SdkApiLevel -lt 21 -or $SdkApiLevel -gt 99) {
    throw "SdkApiLevel must be between 21 and 99."
}
if ($BuildToolsVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "BuildToolsVersion must be a numeric Android build-tools version."
}

$jdkDirectoryName = "jdk-$($JdkVersion.Replace('+', '-'))"
$shellScript = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "prepare-android-coreclr-toolchain.sh"))
$shellScriptWsl = & wsl.exe -d $Distribution -- wslpath -a ($shellScript -replace '\\', '/')
if ($LASTEXITCODE -ne 0) {
    throw "Could not convert the toolchain preparation script path for WSL."
}
$shellScriptWsl = ($shellScriptWsl | Select-Object -Last 1).Trim()

& wsl.exe -d $Distribution -- bash $shellScriptWsl `
    $CacheRoot `
    $JdkVersion `
    $JdkUrl `
    $JdkSha256 `
    $jdkDirectoryName `
    $CommandLineToolsVersion `
    $CommandLineToolsSha256 `
    $SdkApiLevel `
    $BuildToolsVersion `
    "13.0"
if ($LASTEXITCODE -ne 0) {
    throw "Preparing the isolated Android CoreCLR toolchain failed with exit code $LASTEXITCODE."
}
