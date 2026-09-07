[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$LocalFile,

    [Parameter(Mandatory)]
    [string]$RemoteRelativePath,

    [string]$Serial,

    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$')]
    [string]$PackageName,

    [string]$AndroidSdkRoot = $env:ANDROID_SDK_ROOT
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\common\AndroidToolchain.ps1")
$adb = Get-AndroidAdb -AndroidSdkRoot $AndroidSdkRoot
$Serial = Resolve-AndroidDeviceSerial -Adb $adb -Serial $Serial

$source = [System.IO.Path]::GetFullPath($LocalFile)
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Managed file does not exist: $source"
}
if ([System.IO.Path]::IsPathRooted($RemoteRelativePath) -or $RemoteRelativePath.Contains("..")) {
    throw "RemoteRelativePath must be a relative path below the MelonLoader runtime directory."
}

$deviceState = (@(Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @("get-state")) -join "").Trim()
if ($deviceState -cne "device") {
    throw "ADB target $Serial is not ready."
}

$relative = $RemoteRelativePath.Replace('\', '/')
$runtime = "/sdcard/Android/data/$PackageName/files/MelonLoader"
$remote = "$runtime/$relative"
$workspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\.."))
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupRoot = Join-Path $workspaceRoot "temp\work\device-managed-backup-$stamp"
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
$backup = Join-Path $backupRoot ([System.IO.Path]::GetFileName($source))

Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @("shell", "am", "force-stop", $PackageName) | Out-Null
Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @("pull", $remote, $backup) | Out-Null
Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @("push", $source, $remote) | Out-Null

$localHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
$remoteHash = (@(Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @("shell", "sha256sum", $remote)) -join " ").Split()[0]
if ($remoteHash -cne $localHash) {
    throw "Device hash mismatch after managed file deployment."
}

Write-Host "Deployed managed file: $remote"
Write-Host "SHA-256: $localHash"
Write-Host "Rollback file: $backup"
