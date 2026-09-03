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

function Invoke-Adb {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = @(& $adb -s $Serial @Arguments 2>&1 | ForEach-Object { $_.ToString() })
    if ($LASTEXITCODE -ne 0) {
        throw "adb $($Arguments -join ' ') failed: $($output -join [Environment]::NewLine)"
    }
    return $output
}

$source = [System.IO.Path]::GetFullPath($LocalFile)
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Managed file does not exist: $source"
}
if ([System.IO.Path]::IsPathRooted($RemoteRelativePath) -or $RemoteRelativePath.Contains("..")) {
    throw "RemoteRelativePath must be a relative path below the MelonLoader runtime directory."
}

$deviceState = (@(Invoke-Adb -Arguments @("get-state")) -join "").Trim()
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

Invoke-Adb -Arguments @("shell", "am", "force-stop", $PackageName) | Out-Null
Invoke-Adb -Arguments @("pull", $remote, $backup) | Out-Null
Invoke-Adb -Arguments @("push", $source, $remote) | Out-Null

$localHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
$remoteHash = (@(Invoke-Adb -Arguments @("shell", "sha256sum", $remote)) -join " ").Split()[0]
if ($remoteHash -cne $localHash) {
    throw "Device hash mismatch after managed file deployment."
}

Write-Host "Deployed managed file: $remote"
Write-Host "SHA-256: $localHash"
Write-Host "Rollback file: $backup"
