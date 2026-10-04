#requires -Version 7.0
[CmdletBinding()]
param([string]$AndroidSdkRoot = $env:ANDROID_SDK_ROOT, [string]$JavaHome = $env:JAVA_HOME)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$build = Join-Path $root 'scripts/build/build-android-callbacks.ps1'
$out = Join-Path $root 'Output/AndroidCallbacks'
foreach ($path in @((Join-Path $root 'Output'), $out, (Join-Path $out 'classes'))) {
    if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Callback test must not traverse a linked directory: $path"
    }
}
$stage = [IO.Path]::GetFullPath((Join-Path $out "test-$([guid]::NewGuid().ToString('N'))"))
if (!$stage.StartsWith([IO.Path]::GetFullPath($out) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Callback test staging must stay inside its output directory.'
}
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$legacyFixture = Join-Path $out 'classes/IgnoredCallbackFixture.class'
if (Test-Path -LiteralPath $legacyFixture) { throw 'Callback fixture path is already occupied.' }
try {
    & $build -AndroidSdkRoot $AndroidSdkRoot -JavaHome $JavaHome
    $before = (Get-FileHash (Join-Path $out 'classes.dex') -Algorithm SHA256).Hash
    $suffix = if ($IsWindows) { '.exe' } else { '' }
    & (Join-Path $JavaHome "bin/javac$suffix") --release 8 -encoding UTF-8 -g:none -d $stage `
        (Join-Path $root 'MelonLoader/Android/Java/NativeCallback.java') `
        (Join-Path $root 'tests/Android/JniHost/NativeCallbackTests.java')
    if ($LASTEXITCODE) { throw 'Callback Java fixture compilation failed.' }
    & (Join-Path $JavaHome "bin/java$suffix") -Xcheck:jni -cp $stage NativeCallbackTests
    if ($LASTEXITCODE) { throw 'Callback proxy regression failed.' }
    New-Item -ItemType Directory -Path (Split-Path $legacyFixture) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $stage 'NativeCallbackTests.class') -Destination $legacyFixture
    & $build -AndroidSdkRoot $AndroidSdkRoot -JavaHome $JavaHome
    if ((Get-FileHash (Join-Path $out 'classes.dex') -Algorithm SHA256).Hash -cne $before) {
        throw 'Stale callback classes changed the embedded DEX.'
    }
    New-Item -ItemType Directory -Path (Join-Path $stage 'sdk/build-tools/99.0.0') -Force | Out-Null
    $rejected = $false
    try { & $build -AndroidSdkRoot (Join-Path $stage 'sdk') -JavaHome $JavaHome } catch {
        $rejected = $_.Exception.Message.StartsWith('Install Android build-tools ')
    }
    if (!$rejected -or (Get-FileHash (Join-Path $out 'classes.dex') -Algorithm SHA256).Hash -cne $before) {
        throw 'Missing pinned build-tools were accepted or damaged the previous DEX.'
    }
    Write-Host 'PASS isolated callback staging/repeatable DEX'
} finally {
    Remove-Item -LiteralPath $stage -Recurse -Force
    if (Test-Path -LiteralPath $legacyFixture) { Remove-Item -LiteralPath $legacyFixture -Force }
}
