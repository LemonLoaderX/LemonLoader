#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$fixture = Join-Path $repositoryRoot ('Output/Tests/Verification Entry/' + [Guid]::NewGuid().ToString('N'))
$product = Join-Path $fixture 'Loader'
$source = Join-Path $fixture 'Il2CppInterop'
function Write-Fixture([string]$Path, [string]$Content) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path, $Content)
}
function Invoke-FixtureGit([string]$Path, [string[]]$Arguments) {
    & git -c core.longpaths=true -C $Path @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Fixture Git failed: $Arguments" }
}
function Commit-Fixture([string]$Path) {
    Invoke-FixtureGit $Path @('add', '.')
    Invoke-FixtureGit $Path @('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--quiet', '-m', 'fixture')
    return (& git -C $Path rev-parse HEAD).Trim()
}
function Reject([scriptblock]$Action, [string]$Message) {
    try { & $Action } catch {
        if ($Message -and !$_.Exception.Message.Contains($Message)) { throw }
        return
    }
    throw 'Expected verification rejection.'
}
Write-Fixture (Join-Path $source 'input.txt') 'first'
Invoke-FixtureGit $source @('init', '--quiet')
$first = Commit-Fixture $source
Write-Fixture (Join-Path $source 'input.txt') 'second'
$second = Commit-Fixture $source
Invoke-FixtureGit $source @('checkout', '--quiet', '--detach', $first)
Write-Fixture (Join-Path $product '.gitignore') "Output/`n"
Invoke-FixtureGit $product @('init', '--quiet')
foreach ($directory in @('scripts/common', 'scripts/test', 'scripts/build', 'eng')) {
    [void][IO.Directory]::CreateDirectory((Join-Path $product $directory))
}
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'scripts/verify.ps1') -Destination (Join-Path $product 'scripts')
foreach ($helper in @('AndroidDependencies.ps1', 'RuntimeProfiles.ps1')) {
    Copy-Item -LiteralPath (Join-Path $repositoryRoot "scripts/common/$helper") -Destination (Join-Path $product 'scripts/common')
}
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'eng/runtime-profiles.json') -Destination (Join-Path $product 'eng')
[xml]$manifest = Get-Content -LiteralPath (Join-Path $repositoryRoot 'eng/AndroidDependencies.props') -Raw
$manifest.Project.PropertyGroup.AndroidIl2CppInteropRevision = $first
$manifest.Save((Join-Path $product 'eng/AndroidDependencies.props'))
foreach ($name in @('test-scripts.ps1', 'test-source-dependencies.ps1')) {
    Write-Fixture (Join-Path $product "scripts/test/$name") @'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
[void][IO.Directory]::CreateDirectory((Join-Path $root 'Output'))
[IO.File]::AppendAllText((Join-Path $root 'Output/calls.txt'), $MyInvocation.MyCommand.Name + "`n")
'@
}
Write-Fixture (Join-Path $product 'scripts/build.ps1') @'
param($Configuration, $RuntimeProfile, $AndroidNdkRoot, $CoreClrRuntimePackRoot,
    $DobbySourceRoot, $Il2CppInteropSourceRoot, $HarmonyXSourceRoot, $MonoModSourceRoot, [switch]$Development)
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$PSBoundParameters | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'Output/build-args.json')
$config = Get-Content -LiteralPath (Join-Path $root 'eng/runtime-profiles.json') -Raw | ConvertFrom-Json
$profile = $config.profiles.$RuntimeProfile
if (Test-Path (Join-Path $root 'Output/wrong-stage')) { $RuntimeProfile = 'android' }
$package = Join-Path $root 'Output/Release/linux-bionic-arm64/package'
[void][IO.Directory]::CreateDirectory($package)
@{runtimeProfile=$RuntimeProfile;runtimeRid=$profile.rid;developmentBuild=[bool]$Development} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $package 'lemonloader-release.json')
$directory = if ($Development) { 'DevelopmentReleases' } else { 'Releases' }
[void][IO.Directory]::CreateDirectory((Join-Path $root "Output/$directory"))
[IO.File]::WriteAllText((Join-Path $root "Output/$directory/LemonLoader-runtime-$RuntimeProfile-arm64.zip"), 'synthetic archive bytes')
[IO.File]::AppendAllText((Join-Path $root 'Output/calls.txt'), "build`n")
'@
Write-Fixture (Join-Path $product 'scripts/test/test-android-callbacks.ps1') @'
param($AndroidSdkRoot, $JavaHome)
if ($AndroidSdkRoot -cne 'fixture SDK' -or $JavaHome -cne 'fixture JDK') { throw 'Host tool paths changed.' }
'@
Write-Fixture (Join-Path $product 'scripts/build/publish-android-release.ps1') @'
param($Configuration)
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$manifest = Get-Content (Join-Path $root 'Output/Release/linux-bionic-arm64/package/lemonloader-release.json') -Raw | ConvertFrom-Json
$directory = if ($manifest.developmentBuild) { 'DevelopmentReleases' } else { 'Releases' }
if (Test-Path (Join-Path $root 'Output/change-repack')) {
    [IO.File]::AppendAllText((Join-Path $root "Output/$directory/LemonLoader-runtime-$($manifest.runtimeProfile)-arm64.zip"), 'changed')
}
[IO.File]::AppendAllText((Join-Path $root 'Output/calls.txt'), "repack`n")
'@
$null = Commit-Fixture $product
$dotnetLog = [Collections.Generic.List[string]]::new()
$dotnetExit = 0
function dotnet {
    $dotnetLog.Add(($args -join '|'))
    $global:LASTEXITCODE = $dotnetExit
}
$entry = Join-Path $product 'scripts/verify.ps1'
$common = @{ AndroidNdkRoot='ndk with spaces'; CoreClrRuntimePackRoot='reviewed pack';
    DobbySourceRoot='dobby source'; HarmonyXSourceRoot='harmony source'; MonoModSourceRoot='monomod source' }
& $entry @common -RuntimeProfile bionic -Development
$arguments = Get-Content (Join-Path $product 'Output/build-args.json') -Raw | ConvertFrom-Json
if ($arguments.RuntimeProfile -cne 'bionic' -or !$arguments.Development.IsPresent -or
    $arguments.Il2CppInteropSourceRoot -cne $source -or $arguments.CoreClrRuntimePackRoot -cne 'reviewed pack' -or
    $arguments.DobbySourceRoot -cne 'dobby source' -or $arguments.HarmonyXSourceRoot -cne 'harmony source' -or
    $arguments.MonoModSourceRoot -cne 'monomod source' -or $arguments.AndroidNdkRoot -cne 'ndk with spaces') {
    throw 'Verification lost selected profile/development/source/pack arguments.'
}
if ($dotnetLog.Count -ne 3 -or !$dotnetLog[0].Contains($source) -or !$dotnetLog[1].Contains($source) -or
    !$dotnetLog[2].StartsWith('build|')) { throw 'Verification did not use selected sources and desktop boundary.' }
Reject { & $entry -RuntimeProfile legacy -SkipDesktop } ''
& $entry -RuntimeProfile android -SkipDesktop
if (!(Test-Path (Join-Path $product 'Output/Releases/LemonLoader-runtime-android-arm64.zip'))) {
    throw 'Android verification selected the wrong archive.'
}
$before = [IO.File]::ReadAllText((Join-Path $product 'Output/build-args.json'))
$dotnetLog.Clear()
& $entry -SkipAndroid -SkipDesktop
if ($dotnetLog.Count -ne 2 -or [IO.File]::ReadAllText((Join-Path $product 'Output/build-args.json')) -cne $before) {
    throw 'Skipped build boundaries still ran.'
}
Invoke-FixtureGit $source @('checkout', '--quiet', '--detach', $second)
Reject { & $entry -Il2CppInteropSourceRoot $source -HostTests -Development -SkipAndroid -SkipDesktop } 'requires -JvmLibrary'
$dotnetLog.Clear()
& $entry -Il2CppInteropSourceRoot $source -HostTests -JvmLibrary (Join-Path $source 'input.txt') -AndroidSdkRoot 'fixture SDK' `
    -JavaHome 'fixture JDK' -Development -SkipAndroid -SkipDesktop
if ($dotnetLog.Count -ne 5 -or !$dotnetLog[4].Contains('java-interop')) { throw 'Host suites were not selected.' }
Reject { & $entry -Il2CppInteropSourceRoot $source -SkipAndroid -SkipDesktop } 'does not match pinned'
Write-Fixture (Join-Path $source 'input.txt') 'local tracked edit'
& $entry -Il2CppInteropSourceRoot $source -Development -SkipAndroid -SkipDesktop
$dotnetExit = 7
Reject { & $entry -Il2CppInteropSourceRoot $source -Development -SkipAndroid -SkipDesktop } 'exit code 7'
$dotnetExit = 0
Write-Fixture (Join-Path $product 'Output/wrong-stage') 'fixture'
Reject { & $entry -RuntimeProfile bionic -Il2CppInteropSourceRoot $source -Development -SkipDesktop } 'Staged release does not match'
[IO.File]::Delete((Join-Path $product 'Output/wrong-stage'))
Write-Fixture (Join-Path $product 'Output/change-repack') 'fixture'
Reject { & $entry -RuntimeProfile bionic -Il2CppInteropSourceRoot $source -Development -SkipDesktop } 'not deterministic'
$global:LASTEXITCODE = 0
Write-Host 'PASS standalone Loader verification selection, explicit paths, retired-profile rejection, release/development archives, skipped boundaries, source pins, failure propagation and repack checks'
