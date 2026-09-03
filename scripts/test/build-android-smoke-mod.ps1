[CmdletBinding()]
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",

    [string]$MelonLoaderAssemblyPath,

    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
if ([string]::IsNullOrWhiteSpace($MelonLoaderAssemblyPath)) {
    $MelonLoaderAssemblyPath = Join-Path $repositoryRoot `
        "Output\$Configuration\linux-bionic-arm64\MelonLoader\net6\MelonLoader.dll"
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repositoryRoot "Output\AndroidSmokeMod\$Configuration"
}

$loaderAssembly = [System.IO.Path]::GetFullPath($MelonLoaderAssemblyPath)
$outputDirectory = [System.IO.Path]::GetFullPath($OutputPath)
if (-not (Test-Path -LiteralPath $loaderAssembly -PathType Leaf)) {
    throw "Build the Android managed host before the smoke Mod. Missing '$loaderAssembly'."
}

$project = Join-Path $repositoryRoot "tests\Android\SmokeMod\AndroidSmokeMod.csproj"
dotnet build $project `
    --configuration $Configuration `
    --output $outputDirectory `
    "-p:MelonLoaderAssemblyPath=$loaderAssembly"
if ($LASTEXITCODE -ne 0) {
    throw "Building the Android smoke Mod failed with exit code $LASTEXITCODE."
}

$smokeMod = Join-Path $outputDirectory "AndroidSmokeMod.dll"
if (-not (Test-Path -LiteralPath $smokeMod -PathType Leaf)) {
    throw "The Android smoke Mod was not produced at '$smokeMod'."
}

Write-Host "Built Android lifecycle smoke Mod:"
Write-Host "  $smokeMod"
