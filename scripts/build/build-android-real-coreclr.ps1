[CmdletBinding()]
param(
    [string]$Distribution = "Ubuntu-24.04",

    [string]$AndroidNdkRoot = $env:ANDROID_NDK_ROOT,

    [string]$RuntimeVersion,

    [string]$RuntimeRevision,

    [string]$ExpectedSha256,

    [switch]$AllowDirtySource,

    [switch]$SkipHashValidation,

    [switch]$SkipBuild,

    [string]$AndroidNdkLinuxRoot,

    [string]$AndroidSdkLinuxRoot,

    [string]$JavaHomeLinux,

    [switch]$SkipToolchainPreparation,

    [string]$SourceRoot
)

$ErrorActionPreference = "Stop"
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
. (Join-Path $PSScriptRoot "..\common\AndroidDependencies.ps1")
$dependencies = Get-AndroidDependencies -RepositoryRoot $repositoryRoot
if ([string]::IsNullOrWhiteSpace($RuntimeVersion)) {
    $RuntimeVersion = [string]$dependencies.AndroidDotnetRuntimeVersion
}
if ([string]::IsNullOrWhiteSpace($RuntimeRevision)) {
    $RuntimeRevision = [string]$dependencies.AndroidDotnetRuntimeRevision
}
if (-not $SkipToolchainPreparation) {
    & (Join-Path $PSScriptRoot "prepare-android-coreclr-toolchain.ps1") `
        -Distribution $Distribution
}

$parameters = @{
    Configuration = "Release"
    Distribution = $Distribution
    AndroidNdkRoot = $AndroidNdkRoot
    RuntimeVersion = $RuntimeVersion
    RuntimeRevision = $RuntimeRevision
    SourceRoot = $SourceRoot
    AllowDirtySource = $AllowDirtySource
    SkipHashValidation = $SkipHashValidation
    OutputBackendName = "coreclr"
    SkipBuild = $SkipBuild
}
foreach ($optionalPath in @("AndroidNdkLinuxRoot", "AndroidSdkLinuxRoot", "JavaHomeLinux")) {
    if (-not [string]::IsNullOrWhiteSpace((Get-Variable $optionalPath -ValueOnly))) {
        $parameters[$optionalPath] = Get-Variable $optionalPath -ValueOnly
    }
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
    $parameters.ExpectedSha256 = $ExpectedSha256
}
& (Join-Path $PSScriptRoot "build-android-full-coreclr-pack.ps1") @parameters
