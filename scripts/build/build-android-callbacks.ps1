#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$AndroidSdkRoot = $env:ANDROID_SDK_ROOT,
    [string]$JavaHome = $env:JAVA_HOME
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (!$AndroidSdkRoot) { $AndroidSdkRoot = $env:ANDROID_HOME }
if (!$AndroidSdkRoot) { throw 'Set ANDROID_SDK_ROOT to build Android callback support.' }
$executable = if ($IsWindows) { '.exe' } else { '' }
$javac = if ($JavaHome) { Join-Path $JavaHome "bin/javac$executable" } else { 'javac' }
$jar = if ($JavaHome) { Join-Path $JavaHome "bin/jar$executable" } else { 'jar' }
$buildTools = Get-ChildItem -LiteralPath (Join-Path $AndroidSdkRoot 'build-tools') -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (!$buildTools) { throw 'Android build-tools are required for d8.' }
$d8 = Join-Path $buildTools.FullName $(if ($IsWindows) { 'd8.bat' } else { 'd8' })
$out = Join-Path $root 'Output/AndroidCallbacks'
$classes = Join-Path $out 'classes'
New-Item -ItemType Directory -Force -Path $classes | Out-Null
& $javac --release 8 -encoding UTF-8 -d $classes (Join-Path $root 'MelonLoader/Android/Java/NativeCallback.java')
if ($LASTEXITCODE) { throw 'Android callback javac failed.' }
$archive = Join-Path $out 'callbacks.jar'
& $jar cf $archive -C $classes .
if ($LASTEXITCODE) { throw 'Android callback jar failed.' }
& $d8 --release --min-api 26 --output $out $archive
if ($LASTEXITCODE) { throw 'Android callback d8 failed.' }
Write-Host 'Built embedded Android Java callback support.'
