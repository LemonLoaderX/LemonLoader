#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param([switch]$AllOutputs)
$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'common/Cleanup.ps1')
$outputNames = @('Debug', 'Release', 'Dependencies')
if ($AllOutputs) {
    $outputNames += @('RuntimePacks', 'RuntimeArtifacts', 'RuntimeDownloads', 'Releases',
        'Packages', 'DevelopmentReleases', 'DevelopmentRuntimeArtifacts')
}
$paths = @(
    foreach ($name in $outputNames) { Join-Path $repositoryRoot "Output/$name" }
    foreach ($name in @('MelonLoader', 'MelonLoader.Bootstrap', 'MelonLoader.NativeHost',
        'Dependencies', 'PortablePdbToMdb', 'UnityUtilities', 'build', 'tests')) {
        Get-GeneratedBuildDirectory -Root (Join-Path $repositoryRoot $name)
    }
    foreach ($name in @('Dependencies/SupportModules/Il2Cpp/Output', 'MelonLoader.Bootstrap/Output',
        'MelonLoader.NativeHost/Output', 'MelonLoader/Output', '.vs')) {
        Join-Path $repositoryRoot $name
    }
)
# Validate the whole selection before deleting any tree, including nested links.
foreach ($path in $paths) { Assert-GeneratedCleanupPath -Path $path -RepositoryRoot $repositoryRoot }
foreach ($path in $paths) {
    if ((Test-Path -LiteralPath $path) -and $PSCmdlet.ShouldProcess($path, 'Remove generated product tree')) {
        Remove-Item -LiteralPath $path -Recurse -Force
        Write-Host "Removed $path"
    }
}
Write-Host "Loader cleanup completed. AllOutputs=$AllOutputs; WhatIf=$WhatIfPreference"
