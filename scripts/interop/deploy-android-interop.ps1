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
$source = [System.IO.Path]::GetFullPath($InteropDirectory)
if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    throw "Interop directory does not exist: $source"
}
$assemblies = @(Get-ChildItem -LiteralPath $source -File | Where-Object Extension -IEQ '.dll' | Sort-Object Name)
if ($assemblies.Count -eq 0) {
    throw 'Interop directory contains no DLLs.'
}
$hashes = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
foreach ($assembly in $assemblies) {
    if ($assembly.Length -eq 0 -or ($assembly.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Interop assembly must be a nonempty ordinary file: $($assembly.FullName)"
    }
    $hashes.Add($assembly.Name, (Get-FileHash -LiteralPath $assembly.FullName -Algorithm SHA256).Hash.ToLowerInvariant())
}
function Quote-ShellPath([string]$Path) { "'" + $Path.Replace("'", "'\''") + "'" }

$adb = Get-AndroidAdb -AndroidSdkRoot $AndroidSdkRoot
$Serial = Resolve-AndroidDeviceSerial -Adb $adb -Serial $Serial
$deviceState = (@(Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @("get-state")) -join "").Trim()
if ($deviceState -cne "device") {
    throw "ADB target $Serial is not ready."
}
$packagePath = Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @("shell", "pm", "path", $PackageName)
if (-not (($packagePath -join "`n") -match "package:")) {
    throw "Package is not installed on ${Serial}: $PackageName"
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
if ([string]::IsNullOrWhiteSpace($BackupDirectory)) {
    $stamp = (Get-Date -Format "yyyyMMdd-HHmmss") + '-' + [Guid]::NewGuid().ToString('N')
    $BackupDirectory = Join-Path $repositoryRoot "Output\DeviceBackups\device-interop-backup-$stamp"
}
$backup = [System.IO.Path]::GetFullPath($BackupDirectory)
if (Test-Path -LiteralPath $backup) { throw "Use a new backup directory: '$backup'." }
New-Item -ItemType Directory -Path $backup | Out-Null

$remote = "/sdcard/Android/data/$PackageName/files/MelonLoader/MelonLoader/Il2CppAssemblies"
$token = [Guid]::NewGuid().ToString('N')
$staged = "$remote.stage-$token"
$previous = "$remote.previous-$token"
$remoteArg = Quote-ShellPath $remote
$stagedArg = Quote-ShellPath $staged
$previousArg = Quote-ShellPath $previous
Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @('shell', "test -d $remoteArg && test ! -L $remoteArg && test ! -e $stagedArg && test ! -L $stagedArg && test ! -e $previousArg && test ! -L $previousArg") | Out-Null
Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @("shell", "am", "force-stop", $PackageName) | Out-Null
Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @("pull", $remote, $backup) | Out-Null

$stageCreated = $false
$installed = $false
try {
    Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @('shell', "mkdir $stagedArg") | Out-Null
    $stageCreated = $true
    foreach ($assembly in $assemblies) {
        Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @('push', $assembly.FullName, "$staged/$($assembly.Name)") | Out-Null
    }
    $remoteHashes = Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @('shell', "cd $stagedArg && sha256sum -- *.[dD][lL][lL]")
    $verified = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($line in $remoteHashes) {
        if ($line -notmatch '^([0-9a-fA-F]{64})\s+\*?(.+)$' -or
            !$hashes.ContainsKey($Matches[2]) -or !$verified.Add($Matches[2]) -or
            $hashes[$Matches[2]] -cne $Matches[1].ToLowerInvariant()) {
            throw "Device Interop staging hash mismatch: $line"
        }
    }
    if ($verified.Count -ne $assemblies.Count) { throw 'Device Interop staging is incomplete.' }
    try {
        Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @('shell', "mv $remoteArg $previousArg") | Out-Null
        Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @('shell', "mv $stagedArg $remoteArg") | Out-Null
        $installed = $true
    } catch {
        # ADB can lose the reply after either rename has already completed.
        # Restore only into an absent destination; never nest the backup in a new tree.
        $restore = "if test ! -e $previousArg && test ! -L $previousArg; then " +
            "test -d $remoteArg && test ! -L $remoteArg; else " +
            "test -d $previousArg && test ! -L $previousArg && " +
            "test ! -e $remoteArg && test ! -L $remoteArg && mv $previousArg $remoteArg; fi"
        try { Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @('shell', $restore) | Out-Null }
        catch { Write-Warning "Could not restore device Interop; recovery copies remain at '$previous' and '$backup': $_" }
        throw
    }
} finally {
    if ($stageCreated -and !$installed) {
        try { Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @('shell', "rm -rf -- $stagedArg") | Out-Null }
        catch { Write-Warning "Could not remove device Interop staging '$staged': $_" }
    }
}
try { Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @('shell', "rm -rf -- $previousArg") | Out-Null }
catch { Write-Warning "Interop is installed; could not remove previous device tree '$previous': $_" }

Write-Host "Deployed and verified $($assemblies.Count) Android interop assemblies."
Write-Host "Device: $Serial"
Write-Host "Rollback backup: $backup"
