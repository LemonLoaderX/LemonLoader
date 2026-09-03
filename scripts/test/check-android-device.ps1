[CmdletBinding()]
param(
    [string]$Serial,

    [string]$PackageName,

    [string]$AndroidSdkRoot = $env:ANDROID_SDK_ROOT
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\common\AndroidToolchain.ps1")

$adb = Get-AndroidAdb -AndroidSdkRoot $AndroidSdkRoot
$Serial = Resolve-AndroidDeviceSerial -Adb $adb -Serial $Serial

function Invoke-DeviceShell {
    param([Parameter(Mandatory)] [string[]]$Arguments)

    $result = & $adb -s $Serial shell @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb shell $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
    return ($result -join "`n").Trim()
}

$abiList = Invoke-DeviceShell -Arguments @("getprop", "ro.product.cpu.abilist")
$sdkText = Invoke-DeviceShell -Arguments @("getprop", "ro.build.version.sdk")
$sdkLevel = 0
if (-not [int]::TryParse($sdkText, [ref]$sdkLevel)) {
    throw "Could not read the Android SDK level from device '$Serial'."
}

$pageSizeText = Invoke-DeviceShell -Arguments @("getconf", "PAGESIZE")
$pageSize = 0
if (-not [int]::TryParse($pageSizeText, [ref]$pageSize)) {
    throw "Could not read the device page size from '$pageSizeText'."
}

if (($abiList -split ',') -notcontains "arm64-v8a") {
    throw "Device '$Serial' does not advertise the arm64-v8a ABI."
}
if ($sdkLevel -lt 23) {
    throw "Device '$Serial' uses Android API $sdkLevel; API 23 or newer is required."
}
if ($pageSize -notin @(4096, 16384)) {
    throw "Unexpected Android page size $pageSize on device '$Serial'."
}

$installed = $null
if (-not [string]::IsNullOrWhiteSpace($PackageName)) {
    $packagePath = Invoke-DeviceShell -Arguments @("pm", "path", $PackageName)
    $installed = $packagePath -match '(?m)^package:'
    if (-not $installed) {
        throw "Package '$PackageName' is not installed on device '$Serial'."
    }
}

Write-Host "Android device is compatible with the current migration target:"
Write-Host "  Serial: $Serial"
Write-Host "  ABI list: $abiList"
Write-Host "  Android API: $sdkLevel"
Write-Host "  Page size: $pageSize"
if ($PackageName) {
    Write-Host "  Package installed: $PackageName"
}
