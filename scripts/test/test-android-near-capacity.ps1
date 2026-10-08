[CmdletBinding()]
param(
    [string]$Executable,
    [string]$Serial
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $PSScriptRoot '../common/AndroidToolchain.ps1')
if (!$Executable) {
    $Executable = Join-Path $repositoryRoot 'Output/NativeBuild/Release/android-arm64/lemon_near_capacity_test'
}
$Executable = [IO.Path]::GetFullPath($Executable)
if (!(Test-Path -LiteralPath $Executable -PathType Leaf)) {
    throw 'Build the lemon_near_capacity_test CMake target first.'
}
$adb = Get-AndroidAdb
$Serial = Resolve-AndroidDeviceSerial -Adb $adb -Serial $Serial
$abi = (Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @('shell', 'getprop', 'ro.product.cpu.abi')) -join ''
if ($abi.Trim() -ne 'arm64-v8a') { throw 'This regression requires a native ARM64 Android device.' }
$remote = "/data/local/tmp/lemon-near-capacity-$([guid]::NewGuid().ToString('N'))"
try {
    Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @('push', $Executable, $remote) | Out-Null
    Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @('shell', 'chmod', '755', $remote) | Out-Null
    foreach ($case in @('', 'unaligned-begin', 'unaligned-end')) {
        $arguments = @('shell', $remote)
        if ($case) { $arguments += $case }
        $output = Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments $arguments
        if (($output -join "`n") -notmatch 'PASS large IL2CPP near capacity, initialization, hook, original and undo') {
            throw "The near-capacity regression did not complete: $($output -join "`n")"
        }
        $label = if ($case) { $case } else { 'large-image' }
        Write-Host "[$label] $($output -join "`n")"
    }
}
finally {
    Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @('shell', 'rm', '-f', $remote) | Out-Null
}
