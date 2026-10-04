#requires -Version 7.0
[CmdletBinding()]
param([switch]$SkipBash = $IsWindows, [string]$Distribution = 'Ubuntu-24.04')
$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $PSScriptRoot '../common/Wsl.ps1')
. (Join-Path $PSScriptRoot '../common/RuntimeProfiles.ps1')
. (Join-Path $PSScriptRoot '../common/AndroidToolchain.ps1')
. (Join-Path $PSScriptRoot '../common/AndroidDependencies.ps1')
$failures = [Collections.Generic.List[string]]::new()
$count = 0
foreach ($script in Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'scripts') -Recurse -File) {
    if ($script.Extension -eq '.ps1') {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
        foreach ($error in $errors) { $failures.Add("$($script.FullName): $($error.Message)") }
        $count++
    } elseif ($script.Extension -eq '.sh' -and !$SkipBash) {
        if ($IsWindows) {
            $path = ConvertTo-WslPath -Path $script.FullName -Distribution $Distribution
            & wsl.exe -d $Distribution -- bash -n $path
        } else { & bash -n $script.FullName }
        if ($LASTEXITCODE -ne 0) { $failures.Add("Bash parsing failed: $($script.FullName)") }
        $count++
    }
}
if ($failures.Count) { throw ($failures -join "`n") }
if (@(Get-RuntimeProfileSelection).Count -ne 1 -or
    ((Get-RuntimeProfileSelection -Name all).name -join ',') -cne 'android,bionic') { throw 'Runtime profile selection regression.' }
$rejected = $false
try { Get-RuntimeProfileSelection -Name invalid | Out-Null } catch { $rejected = $true }
if (!$rejected) { throw 'Invalid runtime profile was accepted.' }
function Test-AdbSuccess {
    if (($args -join '|') -cne '-s|test-serial|push|file with spaces|remote') { throw 'ADB arguments changed.' }
    $global:LASTEXITCODE = 0
    'ok'
}
function Test-AdbFailure { $global:LASTEXITCODE = 7; 'device failure' }
if ((Invoke-AndroidAdb -Adb Test-AdbSuccess -Serial test-serial -Arguments @('push', 'file with spaces', 'remote')) -cne 'ok') {
    throw 'ADB output changed.'
}
$rejected = $false
try { Invoke-AndroidAdb -Adb Test-AdbFailure -Serial test-serial -Arguments @('get-state') } catch {
    $rejected = $_.Exception.Message.Contains('exit code 7') -and $_.Exception.Message.Contains('device failure')
}
if (!$rejected) { throw 'ADB exit status or diagnostics were lost.' }
$global:LASTEXITCODE = 0
Get-AndroidDependencies | Out-Null
$rejected = $false
try { Get-RuntimeProfileSelection -Name legacy | Out-Null } catch { $rejected = $true }
if (!$rejected) { throw 'Retired runtime profile was accepted.' }
& (Join-Path $PSScriptRoot 'test-cleanup.ps1')
& (Join-Path $PSScriptRoot 'test-runtime-profiles.ps1')
& (Join-Path $PSScriptRoot 'test-publication-scan.ps1')
& (Join-Path $PSScriptRoot 'test-verification-entry.ps1')
& (Join-Path $PSScriptRoot 'test-interop-generation.ps1')
Write-Host "Loader script syntax and helpers passed ($count scripts; SkipBash=$SkipBash)."
