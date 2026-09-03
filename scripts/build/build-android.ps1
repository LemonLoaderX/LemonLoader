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

    [string]$DotnetRuntimeVersion,

    [string]$CoreClrRuntimePackRoot
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($AndroidNdkRoot)) {
    $AndroidNdkRoot = $env:ANDROID_NDK_HOME
}

& (Join-Path $PSScriptRoot "build-android-ndk-bootstrap.ps1") `
    -Configuration $Configuration `
    -AndroidApiLevel $AndroidApiLevel `
    -AndroidNdkRoot $AndroidNdkRoot `
    -DobbySourceRoot $DobbySourceRoot

& (Join-Path $PSScriptRoot "build-android-managed.ps1") `
    -Configuration $Configuration `
    -AndroidNdkRoot $AndroidNdkRoot `
    -Il2CppInteropSourceRoot $Il2CppInteropSourceRoot `
    -MonoModSourceRoot $MonoModSourceRoot `
    -HarmonyXSourceRoot $HarmonyXSourceRoot

if ([string]::IsNullOrWhiteSpace($CoreClrRuntimePackRoot)) {
    $CoreClrRuntimePackRoot = & (Join-Path $PSScriptRoot "resolve-android-runtime-pack.ps1")
    if ([string]::IsNullOrWhiteSpace($CoreClrRuntimePackRoot)) {
        throw "Resolving the Android CoreCLR runtime artifact failed."
    }
    $CoreClrRuntimePackRoot = ($CoreClrRuntimePackRoot | Select-Object -Last 1).Trim()
}

& (Join-Path $PSScriptRoot "stage-android-package.ps1") `
    -Configuration $Configuration `
    -AndroidNdkRoot $AndroidNdkRoot `
    -DotnetRuntimeVersion $DotnetRuntimeVersion `
    -CoreClrRuntimePackRoot $CoreClrRuntimePackRoot `
    -DobbySourceRoot $DobbySourceRoot `
    -Il2CppInteropSourceRoot $Il2CppInteropSourceRoot `
    -MonoModSourceRoot $MonoModSourceRoot `
    -HarmonyXSourceRoot $HarmonyXSourceRoot

& (Join-Path $PSScriptRoot "publish-android-release.ps1") `
    -Configuration $Configuration
