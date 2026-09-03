[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$DecodedApkPath,

    [string]$UnityVersion,

    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$decodedRoot = [System.IO.Path]::GetFullPath($DecodedApkPath)
if (-not (Test-Path -LiteralPath $decodedRoot -PathType Container)) {
    throw "The decoded APK directory was not found at '$decodedRoot'."
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repositoryRoot "Output\InteropInput"
}
$destination = [System.IO.Path]::GetFullPath($OutputPath)

$il2CppSource = Join-Path $decodedRoot "lib\arm64-v8a\libil2cpp.so"
$metadataSource = Join-Path $decodedRoot `
    "assets\bin\Data\Managed\Metadata\global-metadata.dat"
$globalManagersSource = Join-Path $decodedRoot "assets\bin\Data\globalgamemanagers"

if (-not (Test-Path -LiteralPath $il2CppSource)) {
    throw "ARM64 libil2cpp.so was not found at '$il2CppSource'."
}
if (-not (Test-Path -LiteralPath $metadataSource)) {
    throw "IL2CPP metadata was not found at '$metadataSource'."
}

New-Item -ItemType Directory -Force -Path $destination | Out-Null
$il2CppOutput = Join-Path $destination "libil2cpp.so"
$metadataOutput = Join-Path $destination "global-metadata.dat"
$globalManagersOutput = Join-Path $destination "globalgamemanagers"
$manifestOutput = Join-Path $destination "interop-input.json"
foreach ($staleFile in @($il2CppOutput, $metadataOutput, $globalManagersOutput, $manifestOutput)) {
    if (Test-Path -LiteralPath $staleFile -PathType Leaf) {
        Remove-Item -LiteralPath $staleFile -Force
    }
}

Copy-Item -LiteralPath $il2CppSource -Destination $il2CppOutput -Force
Copy-Item -LiteralPath $metadataSource -Destination $metadataOutput -Force

$hasGlobalManagers = $false
if (Test-Path -LiteralPath $globalManagersSource) {
    Copy-Item -LiteralPath $globalManagersSource -Destination $globalManagersOutput -Force
    $hasGlobalManagers = $true
}

if ([string]::IsNullOrWhiteSpace($UnityVersion) -and $hasGlobalManagers) {
    $managerText = [System.Text.Encoding]::ASCII.GetString(
        [System.IO.File]::ReadAllBytes($globalManagersOutput))
    $versions = @([regex]::Matches(
        $managerText,
        '(?<![0-9])\d+\.\d+\.\d+[abfp]\d+(?![0-9])') |
        ForEach-Object Value |
        Sort-Object -Unique)
    if ($versions.Count -eq 1) {
        $UnityVersion = $versions[0]
    }
}

$files = @($il2CppOutput, $metadataOutput)
if ($hasGlobalManagers) {
    $files += $globalManagersOutput
}

$manifest = [ordered]@{
    formatVersion = 1
    source = $decodedRoot
    architecture = "arm64-v8a"
    unityVersion = $UnityVersion
    files = $files | ForEach-Object {
        [ordered]@{
            name = [System.IO.Path]::GetFileName($_)
            size = (Get-Item -LiteralPath $_).Length
            sha256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
}
$manifest | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath $manifestOutput -Encoding Utf8

Write-Host "Prepared Android IL2CPP generator input:"
Write-Host "  $destination"
Write-Host "  libil2cpp.so and global-metadata.dat: present"
Write-Host "  globalgamemanagers: $hasGlobalManagers"
