#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$AndroidSdkRoot = $env:ANDROID_SDK_ROOT,
    [string]$JavaHome = $env:JAVA_HOME
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$pins = ([xml](Get-Content -LiteralPath (Join-Path $root 'eng/AndroidDependencies.props') -Raw)).Project.PropertyGroup
if (!$AndroidSdkRoot) { $AndroidSdkRoot = $env:ANDROID_HOME }
if (!$AndroidSdkRoot) { throw 'Set ANDROID_SDK_ROOT to build Android callback support.' }
$executable = if ($IsWindows) { '.exe' } else { '' }
if (!$JavaHome) { throw 'Set JAVA_HOME to the pinned JDK to build Android callback support.' }
$JavaHome = [IO.Path]::GetFullPath($JavaHome)
$javac = Join-Path $JavaHome "bin/javac$executable"
$java = Join-Path $JavaHome "bin/java$executable"
$compilerVersion = (& $javac -version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $compilerVersion -cne "javac $($pins.AndroidJavaCompilerVersion)") {
    throw "Expected javac $($pins.AndroidJavaCompilerVersion), got '$compilerVersion'."
}
$d8Jar = Join-Path $AndroidSdkRoot "build-tools/$($pins.AndroidBuildToolsRevision)/lib/d8.jar"
if (!(Test-Path -LiteralPath $d8Jar -PathType Leaf)) { throw "Install Android build-tools $($pins.AndroidBuildToolsRevision) for d8." }
$out = Join-Path $root 'Output/AndroidCallbacks'
foreach ($path in @((Join-Path $root 'Output'), $out)) {
    if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Callback output must not traverse a linked directory: $path"
    }
}
$stage = [IO.Path]::GetFullPath((Join-Path $out "stage-$([guid]::NewGuid().ToString('N'))"))
if (!$stage.StartsWith([IO.Path]::GetFullPath($out) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Callback staging path must stay inside its output directory.'
}
$classes = Join-Path $stage 'classes'
$dex = Join-Path $stage 'dex'
New-Item -ItemType Directory -Path $classes, $dex -Force | Out-Null
try {
    & $javac --release 8 -encoding UTF-8 -g:none -d $classes (Join-Path $root 'MelonLoader/Android/Java/NativeCallback.java')
    if ($LASTEXITCODE) { throw 'Android callback javac failed.' }
    $inputs = @(Get-ChildItem -LiteralPath $classes -Recurse -File -Filter '*.class' | Sort-Object FullName | ForEach-Object FullName)
    # Invoke d8 with the same pinned JDK; SDK launchers can select ambient java.
    & $java -cp $d8Jar com.android.tools.r8.D8 --release --min-api $pins.AndroidApiLevel --output $dex @inputs
    if ($LASTEXITCODE) { throw 'Android callback d8 failed.' }
    [IO.File]::Move((Join-Path $dex 'classes.dex'), (Join-Path $out 'classes.dex'), $true)
} finally {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
Write-Host 'Built embedded Android Java callback support.'
