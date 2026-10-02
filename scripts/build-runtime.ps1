#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('android', 'bionic', 'all')][string]$RuntimeProfile = 'all',
    [string]$SourceRoot,
    [string]$OutputRoot,
    [string]$Distribution = 'Ubuntu-24.04',
    [switch]$Plan,
    [Alias('Development')][switch]$AllowDirtySource
)
$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'common/AndroidDependencies.ps1')
. (Join-Path $PSScriptRoot 'common/RuntimeProfiles.ps1')
. (Join-Path $PSScriptRoot 'common/Wsl.ps1')
if (!$OutputRoot) { $OutputRoot = Join-Path $repositoryRoot 'Output/RuntimeDevelopment' }
$script = ConvertTo-WslPath -Path (Join-Path $PSScriptRoot 'build/build-runtime.sh') -Distribution $Distribution
$output = ConvertTo-WslPath -Path $OutputRoot -Distribution $Distribution
$mode = if ($Plan) { 'plan' } else { 'build' }
$policy = if ($AllowDirtySource) { 'development' } else { 'locked' }
foreach ($profile in Get-RuntimeProfileSelection -Name $RuntimeProfile) {
    $source = Get-RuntimeSourceRoot -Profile $profile -SourceRoot $SourceRoot
    if (!(Test-Path -LiteralPath (Join-Path $source '.git'))) {
        throw "Runtime source missing at '$source'; run scripts/setup-runtime.ps1 or supply -SourceRoot."
    }
    $source = ConvertTo-WslPath -Path $source -Distribution $Distribution
    & wsl.exe -d $Distribution -- bash $script $source $output $profile.revision $profile.rid $mode $policy
    if ($LASTEXITCODE -ne 0) {
        throw "Runtime build failed for '$($profile.name)' with exit code $LASTEXITCODE."
    }
}
