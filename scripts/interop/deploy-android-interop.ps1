[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InteropDirectory,

    [string]$Serial,

    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$')]
    [string]$PackageName,

    [string]$BackupDirectory,

    [string]$AndroidSdkRoot = $env:ANDROID_SDK_ROOT
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\common\AndroidToolchain.ps1")
$adb = Get-AndroidAdb -AndroidSdkRoot $AndroidSdkRoot
$Serial = Resolve-AndroidDeviceSerial -Adb $adb -Serial $Serial

$source = [System.IO.Path]::GetFullPath($InteropDirectory)
$manifestPath = Join-Path $source "interop-manifest.json"
if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    throw "Interop directory does not exist: $source"
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Interop manifest does not exist: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$assemblies = @($manifest.assemblies)
if ($assemblies.Count -eq 0) {
    throw "Interop manifest contains no assemblies."
}
foreach ($assembly in $assemblies) {
    $path = Join-Path $source $assembly.name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Manifest assembly is missing: $path"
    }
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -cne [string]$assembly.sha256) {
        throw "Interop assembly hash mismatch: $($assembly.name)"
    }
}

$deviceState = (@(Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @("get-state")) -join "").Trim()
if ($deviceState -cne "device") {
    throw "ADB target $Serial is not ready."
}
$packagePath = Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @("shell", "pm", "path", $PackageName)
if (-not (($packagePath -join "`n") -match "package:")) {
    throw "Package is not installed on ${Serial}: $PackageName"
}

$workspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\.."))
if ([string]::IsNullOrWhiteSpace($BackupDirectory)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $BackupDirectory = Join-Path $workspaceRoot "temp\work\device-interop-backup-$stamp"
}
$backup = [System.IO.Path]::GetFullPath($BackupDirectory)
New-Item -ItemType Directory -Force -Path $backup | Out-Null

$remote = "/sdcard/Android/data/$PackageName/files/MelonLoader/MelonLoader/Il2CppAssemblies"
Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @("shell", "am", "force-stop", $PackageName) | Out-Null
Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @("pull", $remote, $backup) | Out-Null

$sourceTree = Join-Path $source "."
Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @("push", $sourceTree, "$remote/") | Out-Null

$remoteHashes = Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @(
    "exec-out", "sh", "-c", "cd '$remote' && sha256sum *.dll interop-manifest.json"
)
$hashesByName = @{}
foreach ($line in $remoteHashes) {
    if ($line -match '^([0-9a-fA-F]{64})\s+\*?(.+)$') {
        $hashesByName[$Matches[2]] = $Matches[1].ToLowerInvariant()
    }
}

foreach ($assembly in $assemblies) {
    if (-not $hashesByName.ContainsKey([string]$assembly.name)) {
        throw "Device is missing interop assembly after deployment: $($assembly.name)"
    }
    if ($hashesByName[[string]$assembly.name] -cne [string]$assembly.sha256) {
        throw "Device interop hash mismatch after deployment: $($assembly.name)"
    }
}

$localManifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hashesByName["interop-manifest.json"] -cne $localManifestHash) {
    throw "Device interop manifest hash mismatch after deployment."
}

Write-Host "Deployed and verified $($assemblies.Count) Android interop assemblies."
Write-Host "Device: $Serial"
Write-Host "Rollback backup: $backup"
