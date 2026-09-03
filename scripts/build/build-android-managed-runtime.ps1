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
    [string]$SourceRoot
)

$ErrorActionPreference = "Stop"
$parameters = @{
    Distribution = $Distribution
    AndroidNdkRoot = $AndroidNdkRoot
    RuntimeVersion = $RuntimeVersion
    RuntimeRevision = $RuntimeRevision
    AllowDirtySource = $AllowDirtySource
    SkipHashValidation = $SkipHashValidation
    SourceRoot = $SourceRoot
}
if (-not [string]::IsNullOrWhiteSpace($AndroidNdkLinuxRoot)) {
    $parameters.AndroidNdkLinuxRoot = $AndroidNdkLinuxRoot
}
$parameters.SkipBuild = $SkipBuild
if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
    $parameters.ExpectedSha256 = $ExpectedSha256
}
& (Join-Path $PSScriptRoot "build-android-real-coreclr.ps1") @parameters
if ($LASTEXITCODE -ne 0) {
    throw "The Android CoreCLR runtime build failed with exit code $LASTEXITCODE."
}
