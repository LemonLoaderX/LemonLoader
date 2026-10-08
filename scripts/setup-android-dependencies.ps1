[CmdletBinding()]
param(
    [string]$SourceRoot,
    [switch]$JavaInteropOnly
)

$ErrorActionPreference = "Stop"
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
. (Join-Path $PSScriptRoot "common\AndroidDependencies.ps1")
$dependencies = Get-AndroidDependencies -RepositoryRoot $repositoryRoot

$sources = @(
    [pscustomobject]@{
        Name = "Dobby"
        Url = [string]$dependencies.AndroidDobbyRepositoryUrl
        Revision = [string]$dependencies.AndroidDobbyRevision
        Recursive = $false
    },
    [pscustomobject]@{
        Name = "Il2CppInterop"
        Url = [string]$dependencies.AndroidIl2CppInteropRepositoryUrl
        Revision = [string]$dependencies.AndroidIl2CppInteropRevision
        Recursive = $false
    },
    [pscustomobject]@{
        Name = "HarmonyX"
        Url = [string]$dependencies.AndroidHarmonyXRepositoryUrl
        Revision = [string]$dependencies.AndroidHarmonyXRevision
        Recursive = $false
    },
    [pscustomobject]@{
        Name = "MonoMod"
        Url = [string]$dependencies.AndroidMonoModRepositoryUrl
        Revision = [string]$dependencies.AndroidMonoModRevision
        Recursive = $true
    }
)

if (!$JavaInteropOnly) {
    foreach ($source in $sources) {
        $destination = if ($SourceRoot) {
            [IO.Path]::GetFullPath((Join-Path $SourceRoot $source.Name))
        } else {
            Get-AndroidDependencySourceRoot -RepositoryRoot $repositoryRoot -Name $source.Name
        }
        Initialize-AndroidSourceCheckout -Path $destination -Url $source.Url `
            -Revision $source.Revision -Recursive:$source.Recursive
        Write-Host "$($source.Name) @ $($source.Revision.Substring(0, 12)): $destination"
    }
}

$javaDestination = if ($SourceRoot) {
    [IO.Path]::GetFullPath((Join-Path $SourceRoot 'DotnetAndroid'))
} else {
    Get-PinnedSourceRoot -Name DotnetAndroid -Revision $dependencies.JavaInteropRevision -RepositoryRoot $repositoryRoot
}
Initialize-AndroidSourceCheckout -Path $javaDestination -Url $dependencies.JavaInteropRepositoryUrl `
    -Revision $dependencies.JavaInteropRevision -SparsePaths @('external/Java.Interop')
Write-Host "Java.Interop @ $($dependencies.JavaInteropRevision.Substring(0, 12)): $javaDestination"
