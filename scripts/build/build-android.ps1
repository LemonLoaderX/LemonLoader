[CmdletBinding()]
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Debug",

    [int]$AndroidApiLevel,

    [string]$AndroidNdkRoot = $env:ANDROID_NDK_ROOT,

    [string]$DobbySourceRoot,

    [string]$Il2CppInteropSourceRoot,

    [string]$MonoModSourceRoot,

    [string]$HarmonyXSourceRoot,
    [string]$JavaInteropSourceRoot,

    [string]$DotnetRuntimeVersion,

    [string]$CoreClrRuntimePackRoot,
    [ValidateSet('android','bionic')][string]$RuntimeProfile,
    [switch]$AllowDirtyDependencies
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot '../common/RuntimeProfiles.ps1')
$profile = Get-RuntimeProfile -Name $RuntimeProfile
if ($DotnetRuntimeVersion -and $DotnetRuntimeVersion -cne $profile.version) { throw 'Runtime version conflicts with profile.' }
$DotnetRuntimeVersion = $profile.version
if ($AndroidApiLevel -and $AndroidApiLevel -lt $profile.minimumApi) { throw 'Android API is below the runtime minimum.' }
if (!$AndroidApiLevel) { $AndroidApiLevel = $profile.minimumApi }
if (!$CoreClrRuntimePackRoot) {
    $CoreClrRuntimePackRoot = Join-Path $PSScriptRoot "../../Output/RuntimePacks/$($profile.revision)/$($profile.rid)"
}
if ($CoreClrRuntimePackRoot -and !(Test-Path -LiteralPath $CoreClrRuntimePackRoot -PathType Container)) {
    throw "Runtime pack directory does not exist: '$CoreClrRuntimePackRoot'."
}

if ([string]::IsNullOrWhiteSpace($AndroidNdkRoot)) {
    $AndroidNdkRoot = $env:ANDROID_NDK_HOME
}

& (Join-Path $PSScriptRoot "build-android-ndk-bootstrap.ps1") `
    -Configuration $Configuration `
    -AndroidApiLevel $AndroidApiLevel `
    -AndroidNdkRoot $AndroidNdkRoot `
    -DobbySourceRoot $DobbySourceRoot `
    -RuntimeProfile $profile.name `
    -CoreClrRuntimePackRoot $CoreClrRuntimePackRoot `
    -AllowDirtyDependencies:$AllowDirtyDependencies

& (Join-Path $PSScriptRoot "build-android-managed.ps1") `
    -Configuration $Configuration `
    -AndroidNdkRoot $AndroidNdkRoot `
    -Il2CppInteropSourceRoot $Il2CppInteropSourceRoot `
    -MonoModSourceRoot $MonoModSourceRoot `
    -HarmonyXSourceRoot $HarmonyXSourceRoot `
    -JavaInteropSourceRoot $JavaInteropSourceRoot `
    -AllowDirtyDependencies:$AllowDirtyDependencies

& (Join-Path $PSScriptRoot "stage-android-package.ps1") `
    -Configuration $Configuration `
    -AndroidNdkRoot $AndroidNdkRoot `
    -DotnetRuntimeVersion $DotnetRuntimeVersion `
    -ManagedRuntimeRevision $profile.revision `
    -RuntimeProfile $profile.name `
    -CoreClrRuntimePackRoot $CoreClrRuntimePackRoot `
    -DobbySourceRoot $DobbySourceRoot `
    -Il2CppInteropSourceRoot $Il2CppInteropSourceRoot `
    -MonoModSourceRoot $MonoModSourceRoot `
    -HarmonyXSourceRoot $HarmonyXSourceRoot `
    -JavaInteropSourceRoot $JavaInteropSourceRoot `
    -DevelopmentBuild:$AllowDirtyDependencies

& (Join-Path $PSScriptRoot "publish-android-release.ps1") `
    -Configuration $Configuration
