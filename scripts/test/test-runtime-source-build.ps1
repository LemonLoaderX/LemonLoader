#requires -Version 7.0
[CmdletBinding()]
param([string]$Distribution = 'Ubuntu-24.04')
$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $repositoryRoot 'scripts/common/Wsl.ps1')
$fixture = Join-Path $repositoryRoot "Output/Tests/Runtime Source Build/$([Guid]::NewGuid().ToString('N'))"
$product = Join-Path $fixture 'Loader'
$source = Join-Path $fixture 'dotnet-runtime'
$output = Join-Path $product 'Output/RuntimeDevelopment'
function Write-FixtureFile([string]$Path, [string]$Content) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path, $Content)
}
function Invoke-Git([string[]]$Arguments) {
    & git -C $source @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Fixture git failed: $Arguments" }
}
function Reject([scriptblock]$Action, [string]$Message) {
    try { & $Action } catch {
        if ($Message -and !$_.Exception.Message.Contains($Message)) { throw }
        return
    }
    throw 'Expected runtime build rejection.'
}
$body = @'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p artifacts/packages/Release/Shipping
printf '%s\n' "$@" > artifacts/build-args.txt
printf '%s\n' "$@" > artifacts/packages/Release/Shipping/fixture.nupkg
'@
Write-FixtureFile (Join-Path $source 'build.sh') ($body + "`n")
Write-FixtureFile (Join-Path $source '.gitignore') "artifacts/`n"
Invoke-Git @('init', '--quiet')
Invoke-Git @('add', '.')
Invoke-Git @('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--quiet', '-m', 'runtime fixture')
$revision = (& git -C $source rev-parse HEAD).Trim()
$scripts = Join-Path $product 'scripts'
[void][IO.Directory]::CreateDirectory((Join-Path $scripts 'common'))
[void][IO.Directory]::CreateDirectory((Join-Path $scripts 'build'))
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'scripts/build-runtime.ps1') -Destination $scripts
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'scripts/setup-runtime.ps1') -Destination $scripts
foreach ($helper in @('AndroidDependencies.ps1', 'RuntimeProfiles.ps1', 'Wsl.ps1')) {
    Copy-Item -LiteralPath (Join-Path $repositoryRoot "scripts/common/$helper") -Destination (Join-Path $scripts 'common')
}
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'scripts/build/build-runtime.sh') -Destination (Join-Path $scripts 'build')
$config = Get-Content -LiteralPath (Join-Path $repositoryRoot 'eng/runtime-profiles.json') -Raw | ConvertFrom-Json
$config.profiles.android.revision = $revision
$config.profiles.bionic.revision = $revision
Write-FixtureFile (Join-Path $product 'eng/runtime-profiles.json') ($config | ConvertTo-Json -Depth 5)
$ndk = Join-Path $fixture 'ndk'
$java = Join-Path $fixture 'jdk'
$headers = Join-Path $fixture 'headers'
Write-FixtureFile (Join-Path $ndk 'toolchains/llvm/prebuilt/linux-x86_64/bin/clang') "#!/bin/sh`nexit 0`n"
Write-FixtureFile (Join-Path $java 'bin/java') "#!/bin/sh`nexit 0`n"
Write-FixtureFile (Join-Path $headers 'openssl/ssl.h') ''
$linuxSource = ConvertTo-WslPath -Path $source -Distribution $Distribution
$linuxOutput = ConvertTo-WslPath -Path $output -Distribution $Distribution
$backend = ConvertTo-WslPath -Path (Join-Path $scripts 'build/build-runtime.sh') -Distribution $Distribution
& wsl.exe -d $Distribution -- chmod +x "$linuxSource/build.sh"
if ($LASTEXITCODE -ne 0) { throw 'Fixture chmod failed.' }
$savedEnvironment = @{}
foreach ($name in @('WSLENV', 'ANDROID_NDK_ROOT', 'JAVA_HOME', 'OPENSSL_INCLUDE_DIR')) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    $env:ANDROID_NDK_ROOT = $ndk
    $env:JAVA_HOME = $java
    $env:OPENSSL_INCLUDE_DIR = $headers
    $preservedWslEntries = @($env:WSLENV -split ':' | Where-Object {
        $_ -and ($_ -split '/')[0] -notin @('ANDROID_NDK_ROOT', 'JAVA_HOME', 'OPENSSL_INCLUDE_DIR')
    })
    $env:WSLENV = (@($preservedWslEntries) + @('ANDROID_NDK_ROOT/p', 'JAVA_HOME/p', 'OPENSSL_INCLUDE_DIR/p')) -join ':'
    $entry = Join-Path $scripts 'build-runtime.ps1'
    & $entry -Distribution $Distribution -Plan
    if ((Test-Path -LiteralPath $output) -or (Test-Path -LiteralPath (Join-Path $source 'artifacts'))) {
        throw 'Plan changed runtime outputs.'
    }
    & $entry -Distribution $Distribution
    foreach ($rid in @('android-arm64', 'linux-bionic-arm64')) {
        $target = Join-Path $output "$revision/$rid"
        if ((Get-Content (Join-Path $target 'exit-code.txt') -Raw).Trim() -cne '0' -or
            !(Test-Path -LiteralPath (Join-Path $target 'packages.sha256'))) { throw 'Missing target evidence.' }
        $argsText = Get-Content (Join-Path $target 'artifacts/build-args.txt') -Raw
        if ($argsText.Contains('FeatureXplatEventSource=false') -ne ($rid -eq 'linux-bionic-arm64')) {
            throw 'Runtime target options mixed.'
        }
    }
    & (Join-Path $scripts 'setup-runtime.ps1')
    Write-FixtureFile (Join-Path $source 'build.sh') ($body + "`n# tracked local change`n")
    Reject { & (Join-Path $scripts 'setup-runtime.ps1') } 'local changes'
    Reject { & $entry -Distribution $Distribution -RuntimeProfile android } 'exit code'
    & $entry -Distribution $Distribution -RuntimeProfile android -Development
    $development = Join-Path $output "local/$revision/android-arm64"
    if (!(Get-Content (Join-Path $development 'source-changes.patch') -Raw).Contains('tracked local change')) {
        throw 'Development source evidence missing.'
    }
    Invoke-Git @('add', 'build.sh')
    Invoke-Git @('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--quiet', '-m', 'another source revision')
    Reject { & $entry -Distribution $Distribution -RuntimeProfile android -SourceRoot $source -Plan } 'exit code'
    & $entry -Distribution $Distribution -RuntimeProfile android -SourceRoot $source -Plan -Development
    $lockTest = Join-Path $fixture 'lock-test.sh'
    Write-FixtureFile $lockTest ('exec 8>"$1/.lemonloader-runtime-build.lock"; flock -n 8 || exit 9; bash "$2" "$1" "$3" "$4" android-arm64 build development' + "`n")
    $linuxLockTest = ConvertTo-WslPath -Path $lockTest -Distribution $Distribution
    & wsl.exe -d $Distribution -- bash $linuxLockTest $linuxSource $backend $linuxOutput $revision
    if ($LASTEXITCODE -ne 1) { throw 'Runtime exclusive lock did not reject concurrent build.' }
    & wsl.exe -d $Distribution -- mv -- "$linuxSource/artifacts" "$linuxSource/artifacts-link"
    if ($LASTEXITCODE -ne 0) { throw 'Could not preserve fixture artifacts link.' }
    [void][IO.Directory]::CreateDirectory((Join-Path $source 'artifacts'))
    Reject { & $entry -Distribution $Distribution -RuntimeProfile android -SourceRoot $source -Development } 'exit code'
    & wsl.exe -d $Distribution -- rmdir -- "$linuxSource/artifacts"
    if ($LASTEXITCODE -ne 0) { throw 'Builder modified protected artifacts directory.' }
    & wsl.exe -d $Distribution -- mv -- "$linuxSource/artifacts-link" "$linuxSource/artifacts"
    if ($LASTEXITCODE -ne 0) { throw 'Could not restore fixture artifacts link.' }
    Write-FixtureFile (Join-Path $source 'build.sh') "#!/usr/bin/env bash`nexit 7`n"
    Reject { & $entry -Distribution $Distribution -RuntimeProfile android -SourceRoot $source -Development } 'exit code 7'
    $actual = (& git -C $source rev-parse HEAD).Trim()
    if ((Get-Content (Join-Path $output "local/$actual/android-arm64/exit-code.txt") -Raw).Trim() -cne '7') {
        throw 'Failed build exit code was not retained.'
    }
    Reject { & $entry -Distribution $Distribution -SourceRoot (Join-Path $fixture 'missing') -Plan } 'Runtime source missing'
    Write-Host 'PASS standalone runtime launcher/backend, read-only plan, per-RID isolation, development evidence, lock, protected artifacts and build failures'
} finally {
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
}
