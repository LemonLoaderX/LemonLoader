[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$testRoot = Join-Path $repositoryRoot "Output\RuntimeResolverTests"
$sourceRoot = Join-Path $testRoot "source"
$cacheRoot = Join-Path $testRoot "cache"
$archivePath = Join-Path $testRoot "runtime.zip"
$maliciousArchivePath = Join-Path $testRoot "malicious.zip"
$resolver = Join-Path $repositoryRoot "scripts\build\resolve-android-runtime-pack.ps1"
$runtimeVersion = "10.0.0-test"
$runtimeRevision = "1111111111111111111111111111111111111111"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
try {
    New-Item -ItemType Directory -Force -Path `
        (Join-Path $sourceRoot "managed"), `
        (Join-Path $sourceRoot "native") | Out-Null
    Set-Content -LiteralPath (Join-Path $sourceRoot "managed\System.Private.CoreLib.dll") `
        -Value "managed" -Encoding Ascii -NoNewline
    $enginePath = Join-Path $sourceRoot "native\libcoreclr.so"
    Set-Content -LiteralPath $enginePath -Value "engine" -Encoding Ascii -NoNewline
    Set-Content -LiteralPath `
        (Join-Path $sourceRoot "native\libSystem.Security.Cryptography.Native.Android.so") `
        -Value "crypto" -Encoding Ascii -NoNewline
    Set-Content -LiteralPath `
        (Join-Path $sourceRoot "native\lemonloader-coreclr-crypto.dex") `
        -Value "dex" -Encoding Ascii -NoNewline
    Set-Content -LiteralPath (Join-Path $sourceRoot "LICENSE.TXT") `
        -Value "license" -Encoding Ascii -NoNewline
    Set-Content -LiteralPath (Join-Path $sourceRoot "THIRD-PARTY-NOTICES.TXT") `
        -Value "notices" -Encoding Ascii -NoNewline
    $engineHash = (Get-FileHash -LiteralPath $enginePath -Algorithm SHA256).Hash.ToLowerInvariant()
    [ordered]@{
        formatVersion = 2
        runtimeVersion = $runtimeVersion
        backend = "coreclr"
        hostingModel = "coreclr-host-api"
        sourceRevision = $runtimeRevision
        buildCommand = "synthetic-test"
        engineFile = "libcoreclr.so"
        engineSha256 = $engineHash
    } | ConvertTo-Json | Set-Content `
        -LiteralPath (Join-Path $sourceRoot "runtime-provenance.json") `
        -Encoding Utf8
    [IO.Compression.ZipFile]::CreateFromDirectory(
        $sourceRoot,
        $archivePath,
        [IO.Compression.CompressionLevel]::Optimal,
        $false)
    $archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()

    $resolveOutput = @(& $resolver `
        -ArchivePath $archivePath `
        -CacheRoot $cacheRoot `
        -RuntimeVersion $runtimeVersion `
        -RuntimeRevision $runtimeRevision `
        -ExpectedSha256 $archiveHash)
    if ($resolveOutput.Count -ne 1 -or $resolveOutput[0] -isnot [string]) {
        throw "The resolver wrote unexpected pipeline output."
    }
    $resolved = $resolveOutput[0].Trim()
    if (-not (Test-Path -LiteralPath (Join-Path $resolved "native\libcoreclr.so") -PathType Leaf)) {
        throw "The resolver did not publish the synthetic runtime pack."
    }

    Set-Content -LiteralPath (Join-Path $resolved "native\libcoreclr.so") `
        -Value "tampered" -Encoding Ascii -NoNewline
    $repairOutput = @(& $resolver `
        -ArchivePath $archivePath `
        -CacheRoot $cacheRoot `
        -RuntimeVersion $runtimeVersion `
        -RuntimeRevision $runtimeRevision `
        -ExpectedSha256 $archiveHash)
    if ($repairOutput.Count -ne 1 -or $repairOutput[0] -isnot [string]) {
        throw "The resolver wrote unexpected pipeline output while repairing the cache."
    }
    $repaired = $repairOutput[0].Trim()
    $repairedHash = (Get-FileHash -LiteralPath (Join-Path $repaired "native\libcoreclr.so") `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($repairedHash -cne $engineHash) {
        throw "The resolver did not repair a changed cached runtime."
    }

    $stream = [IO.File]::Open(
        $maliciousArchivePath,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None)
    try {
        $archive = [IO.Compression.ZipArchive]::new(
            $stream,
            [IO.Compression.ZipArchiveMode]::Create,
            $false)
        $entry = $archive.CreateEntry("../escape.txt")
        $writer = [IO.StreamWriter]::new($entry.Open())
        try { $writer.Write("escape") }
        finally { $writer.Dispose() }
        $archive.Dispose()
    }
    finally { $stream.Dispose() }
    $maliciousHash = (Get-FileHash -LiteralPath $maliciousArchivePath `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    try {
        & $resolver `
            -ArchivePath $maliciousArchivePath `
            -CacheRoot (Join-Path $testRoot "malicious-cache") `
            -RuntimeVersion $runtimeVersion `
            -RuntimeRevision $runtimeRevision `
            -ExpectedSha256 $maliciousHash | Out-Null
        throw "The resolver accepted a path-traversal archive."
    }
    catch {
        if ($_.Exception.Message -eq "The resolver accepted a path-traversal archive.") {
            throw
        }
    }
    if (Test-Path -LiteralPath (Join-Path $testRoot "escape.txt")) {
        throw "The resolver wrote a path-traversal entry."
    }

    Write-Host "Android runtime artifact resolver tests passed."
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
