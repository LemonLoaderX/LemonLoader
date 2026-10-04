param(
    [Parameter(Mandatory)][string]$Serial,
    [Parameter(Mandatory)][string]$Apk,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$Adb = 'adb',
    [string]$PackageName = 'jp.co.fanzagames.dotabyss_x_a'
)
$ErrorActionPreference = 'Stop'
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $OutputPath) { throw 'Evidence directory already exists.' }
[void][IO.Directory]::CreateDirectory($OutputPath)
function Invoke-Adb([string[]]$Arguments) {
    $result = & $Adb -s $Serial @Arguments 2>&1
    if ($LASTEXITCODE) { throw "ADB failed: $($result -join ' ')" }
    return $result
}
$paths = @(Invoke-Adb @('shell','pm','path',$PackageName))
if ($paths.Count -ne 1 -or -not $paths[0].StartsWith('package:')) { throw 'Expected an installed standalone APK.' }
$rollback = Join-Path $OutputPath 'original-installed.apk'
Invoke-Adb @('pull',$paths[0].Substring(8).Trim(),$rollback) | Out-Null
$installed = $false
try {
    Invoke-Adb @('shell','am','force-stop',$PackageName) | Out-Null
    Invoke-Adb @('install','-r',[IO.Path]::GetFullPath($Apk)) | Set-Content "$OutputPath/install.txt"
    $installed = $true
    & "$PSScriptRoot/run-device.ps1" -Serial $Serial -Adb $Adb -PackageName $PackageName -OutputPath "$OutputPath/results"
}
finally {
    if ($installed) {
        Invoke-Adb @('shell','am','force-stop',$PackageName) | Out-Null
        Invoke-Adb @('install','-r',$rollback) | Set-Content "$OutputPath/restore.txt"
    }
}
