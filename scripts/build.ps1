[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Release',
    [ValidateSet('android', 'bionic', 'all')][string]$RuntimeProfile,
    [string]$AndroidNdkRoot = $env:ANDROID_NDK_ROOT,
    [string]$CoreClrRuntimePackRoot,
    [string]$DobbySourceRoot,
    [string]$Il2CppInteropSourceRoot,
    [string]$HarmonyXSourceRoot,
    [string]$MonoModSourceRoot,
    [Alias('AllowDirtyDependencies')][switch]$Development
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common/RuntimeProfiles.ps1')
$profiles = @(Get-RuntimeProfileSelection -Name $RuntimeProfile)
if ($profiles.Count -gt 1 -and $CoreClrRuntimePackRoot) {
    throw 'Select one profile with an explicit runtime pack, or prepare per-profile caches.'
}
foreach ($profile in $profiles) {
    & (Join-Path $PSScriptRoot 'build/build-android.ps1') `
        -Configuration $Configuration -RuntimeProfile $profile.name `
        -AndroidNdkRoot $AndroidNdkRoot -CoreClrRuntimePackRoot $CoreClrRuntimePackRoot `
        -DobbySourceRoot $DobbySourceRoot -Il2CppInteropSourceRoot $Il2CppInteropSourceRoot `
        -HarmonyXSourceRoot $HarmonyXSourceRoot -MonoModSourceRoot $MonoModSourceRoot `
        -AllowDirtyDependencies:$Development
}
