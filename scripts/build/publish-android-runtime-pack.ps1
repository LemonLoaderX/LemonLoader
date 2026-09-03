[CmdletBinding()]
param(
    [string]$RuntimePackRoot,
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
. (Join-Path $PSScriptRoot "..\common\AndroidDependencies.ps1")
$dependencies = Get-AndroidDependencies -RepositoryRoot $repositoryRoot
$runtimeVersion = [string]$dependencies.AndroidDotnetRuntimeVersion
$runtimeRevision = [string]$dependencies.AndroidDotnetRuntimeRevision

if ([string]::IsNullOrWhiteSpace($RuntimePackRoot)) {
    $RuntimePackRoot = Join-Path $repositoryRoot `
        "Output\Dependencies\dotnet-runtime\$runtimeVersion\coreclr"
}
$runtimeRoot = [IO.Path]::GetFullPath($RuntimePackRoot)
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repositoryRoot `
        "Output\RuntimeArtifacts\dotnet-runtime-$runtimeVersion-android-arm64.zip"
}
$archivePath = [IO.Path]::GetFullPath($OutputPath)
$archiveDirectory = Split-Path -Parent $archivePath
$stagingArchive = Join-Path $archiveDirectory ".$([IO.Path]::GetFileName($archivePath)).staging"

$provenancePath = Join-Path $runtimeRoot "runtime-provenance.json"
foreach ($required in @(
    (Join-Path $runtimeRoot "managed"),
    (Join-Path $runtimeRoot "native"),
    $provenancePath,
    (Join-Path $runtimeRoot "LICENSE.TXT"),
    (Join-Path $runtimeRoot "THIRD-PARTY-NOTICES.TXT"),
    (Join-Path $runtimeRoot "native\libcoreclr.so"),
    (Join-Path $runtimeRoot "native\lemonloader-coreclr-crypto.dex"))) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Runtime pack input is missing '$required'."
    }
}
$provenance = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json
if ($provenance.formatVersion -ne 2 -or
    $provenance.runtimeVersion -cne $runtimeVersion -or
    $provenance.sourceRevision -cne $runtimeRevision -or
    $provenance.backend -cne "coreclr" -or
    $provenance.hostingModel -cne "coreclr-host-api") {
    throw "Runtime pack provenance does not match eng/AndroidDependencies.props."
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$files = @(Get-ChildItem -LiteralPath $runtimeRoot -File -Recurse | ForEach-Object {
    $entryName = [IO.Path]::GetRelativePath($runtimeRoot, $_.FullName).Replace('\', '/')
    $publish = $entryName -in @("LICENSE.TXT", "THIRD-PARTY-NOTICES.TXT") -or
        $entryName.StartsWith("managed/", [StringComparison]::Ordinal) -or
        ($entryName.StartsWith("native/", [StringComparison]::Ordinal) -and
            $_.Extension -in @(".so", ".dex") -and
            $_.Name -notin @(
                "libhostfxr.so",
                "libmscordaccore.so",
                "libmscordbi.so",
                "libSystem.Security.Cryptography.Native.OpenSsl.so"))
    if ($publish) {
        [pscustomobject]@{
            Path = $_.FullName
            EntryName = $entryName
        }
    }
} | Sort-Object EntryName)
if ($files.Count -eq 0 -or
    @($files | Group-Object EntryName | Where-Object Count -ne 1).Count -ne 0) {
    throw "Runtime pack input is empty or contains duplicate entry names."
}
$publicProvenance = [ordered]@{
    formatVersion = 2
    runtimeVersion = $runtimeVersion
    backend = "coreclr"
    sourceRevision = $runtimeRevision
    hostingModel = "coreclr-host-api"
    engineSha256 = [string]$provenance.engineSha256
}
$provenanceBytes = [Text.UTF8Encoding]::new($false).GetBytes(
    (($publicProvenance | ConvertTo-Json) + "`n"))
$entries = @(
    $files
    [pscustomobject]@{
        Path = $null
        EntryName = "runtime-provenance.json"
        Bytes = $provenanceBytes
    }
) | Sort-Object EntryName

New-Item -ItemType Directory -Force -Path $archiveDirectory | Out-Null
if (Test-Path -LiteralPath $stagingArchive) {
    Remove-Item -LiteralPath $stagingArchive -Force
}
$fixedTimestamp = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
try {
    $stream = [IO.File]::Open(
        $stagingArchive,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None)
    try {
        $archive = [IO.Compression.ZipArchive]::new(
            $stream,
            [IO.Compression.ZipArchiveMode]::Create,
            $true)
        try {
            foreach ($file in $entries) {
                $entry = $archive.CreateEntry(
                    $file.EntryName,
                    [IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = $fixedTimestamp
                $output = $entry.Open()
                try {
                    if ($null -ne $file.Bytes) {
                        $output.Write($file.Bytes, 0, $file.Bytes.Length)
                    }
                    else {
                        $input = [IO.File]::OpenRead($file.Path)
                        try { $input.CopyTo($output) }
                        finally { $input.Dispose() }
                    }
                }
                finally { $output.Dispose() }
            }
        }
        finally { $archive.Dispose() }
    }
    finally { $stream.Dispose() }

    $verification = [IO.Compression.ZipFile]::OpenRead($stagingArchive)
    try {
        $actualEntries = @($verification.Entries |
            Where-Object { -not [string]::IsNullOrEmpty($_.Name) } |
            ForEach-Object FullName)
        if (($actualEntries -join "`n") -cne ($entries.EntryName -join "`n")) {
            throw "Runtime archive entries do not match the source pack."
        }
    }
    finally { $verification.Dispose() }

    [IO.File]::Move($stagingArchive, $archivePath, $true)
}
finally {
    if (Test-Path -LiteralPath $stagingArchive) {
        Remove-Item -LiteralPath $stagingArchive -Force
    }
}

$hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "Published Android CoreCLR runtime artifact:"
Write-Host "  $archivePath"
Write-Host "  SHA-256: $hash"
Write-Output $archivePath
