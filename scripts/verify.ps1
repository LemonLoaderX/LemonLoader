#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$AndroidNdkRoot = $env:ANDROID_NDK_ROOT,
    [ValidateSet('android', 'bionic')][string]$RuntimeProfile,
    [string]$CoreClrRuntimePackRoot,
    [string]$DobbySourceRoot,
    [string]$Il2CppInteropSourceRoot,
    [string]$HarmonyXSourceRoot,
    [string]$MonoModSourceRoot,
    [string]$JavaInteropSourceRoot,
    [Alias('AllowDirtyDependencies')][switch]$Development,
    [switch]$SkipAndroid,
    [switch]$SkipDesktop,
    [switch]$HostTests,
    [string]$JvmLibrary,
    [string]$AndroidSdkRoot = $env:ANDROID_SDK_ROOT,
    [string]$JavaHome = $env:JAVA_HOME
)
$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'common/AndroidDependencies.ps1')
. (Join-Path $PSScriptRoot 'common/RuntimeProfiles.ps1')
$profile = Get-RuntimeProfile -Name $RuntimeProfile
$dependencies = Get-AndroidDependencies
$interop = Get-AndroidDependencySourceRoot -Name Il2CppInterop -SourceRoot $Il2CppInteropSourceRoot
if ($Development) {
    $head = @(& git -c core.longpaths=true -C $interop rev-parse HEAD)
    if ($LASTEXITCODE -ne 0 -or $head.Count -ne 1 -or $head[0].Trim() -notmatch '^[0-9a-f]{40}$') {
        throw "Interop source is not a valid checkout: '$interop'."
    }
} else {
    Assert-AndroidSourceCheckout -Path $interop -Revision $dependencies.AndroidIl2CppInteropRevision -AllowUntracked
}
& (Join-Path $PSScriptRoot 'test/test-scripts.ps1')
& (Join-Path $PSScriptRoot 'test/test-source-dependencies.ps1')
foreach ($name in @('Il2CppInterop.Runtime.Tests', 'Il2CppInterop.Generator.Tests')) {
    & dotnet run --project (Join-Path $interop "$name/$name.csproj") --configuration Release
    if ($LASTEXITCODE -ne 0) { throw "$name failed with exit code $LASTEXITCODE." }
}
if ($HostTests) {
    if ([string]::IsNullOrWhiteSpace($JvmLibrary) -or !(Test-Path -LiteralPath $JvmLibrary -PathType Leaf)) {
        throw 'HostTests requires -JvmLibrary pointing to the host JVM shared library.'
    }
    foreach ($project in @('Managed/AndroidManaged.Tests.csproj', 'GameInformation/GameInformation.Tests.csproj')) {
        & dotnet run --project (Join-Path $repositoryRoot "tests/Android/$project") -c Release -p:Platform=x64
        if ($LASTEXITCODE -ne 0) { throw "$project failed with exit code $LASTEXITCODE." }
    }
    & dotnet run --project (Join-Path $repositoryRoot 'tests/Android/JniHost/JniHost.csproj') -c Release -- java-interop $JvmLibrary
    if ($LASTEXITCODE -ne 0) { throw "JNI host tests failed with exit code $LASTEXITCODE." }
    & (Join-Path $PSScriptRoot 'test/test-android-callbacks.ps1') -AndroidSdkRoot $AndroidSdkRoot -JavaHome $JavaHome
}
if (!$SkipDesktop) {
    & dotnet build (Join-Path $repositoryRoot 'MelonLoader.sln') --configuration Release -p:Platform=x64 -p:PublishAot=false
    if ($LASTEXITCODE -ne 0) { throw "Desktop build failed with exit code $LASTEXITCODE." }
}
if (!$SkipAndroid) {
    & (Join-Path $PSScriptRoot 'build.ps1') -Configuration Release -RuntimeProfile $profile.name `
        -AndroidNdkRoot $AndroidNdkRoot -CoreClrRuntimePackRoot $CoreClrRuntimePackRoot `
        -DobbySourceRoot $DobbySourceRoot -Il2CppInteropSourceRoot $interop `
        -HarmonyXSourceRoot $HarmonyXSourceRoot -MonoModSourceRoot $MonoModSourceRoot `
        -JavaInteropSourceRoot $JavaInteropSourceRoot -Development:$Development
    $manifest = Get-Content -LiteralPath (Join-Path $repositoryRoot 'Output/Release/linux-bionic-arm64/package/lemonloader-release.json') -Raw | ConvertFrom-Json
    if ($manifest.runtimeRid -cne $profile.rid -or
        [bool]$manifest.developmentBuild -ne [bool]$Development) {
        throw 'Staged release does not match the selected verification profile/development mode.'
    }
    $releaseDirectory = if ($Development) { 'DevelopmentReleases' } else { 'Releases' }
    $archive = Join-Path $repositoryRoot "Output/$releaseDirectory/LemonLoader-runtime-$($profile.name)-arm64.zip"
    $firstHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    & (Join-Path $PSScriptRoot 'build/publish-android-release.ps1') -Configuration Release
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -cne $firstHash) {
        throw 'Selected Android Release repack is not deterministic.'
    }
}
& git -C $repositoryRoot diff --check
if ($LASTEXITCODE -ne 0) { throw 'Loader diff contains whitespace errors.' }
Write-Host "Loader verification passed. Profile=$($profile.name); Development=$Development; SkipAndroid=$SkipAndroid; SkipDesktop=$SkipDesktop"
