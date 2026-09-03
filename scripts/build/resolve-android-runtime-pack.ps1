[CmdletBinding()]
param(
    [string]$ArchivePath,
    [string]$CacheRoot,
    [string]$RuntimeVersion,
    [string]$RuntimeRevision,
    [string]$ExpectedSha256,
    [string]$ArtifactUrl
)

$ErrorActionPreference = "Stop"
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
. (Join-Path $PSScriptRoot "..\common\AndroidDependencies.ps1")
$dependencies = Get-AndroidDependencies -RepositoryRoot $repositoryRoot
$runtimeVersion = if ([string]::IsNullOrWhiteSpace($RuntimeVersion)) {
    [string]$dependencies.AndroidDotnetRuntimeVersion
} else { $RuntimeVersion }
$runtimeRevision = if ([string]::IsNullOrWhiteSpace($RuntimeRevision)) {
    [string]$dependencies.AndroidDotnetRuntimeRevision
} else { $RuntimeRevision }
$expectedHash = if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) {
    [string]$dependencies.AndroidDotnetRuntimeArtifactSha256
} else { $ExpectedSha256.ToLowerInvariant() }
$artifactUrl = if ([string]::IsNullOrWhiteSpace($ArtifactUrl)) {
    [string]$dependencies.AndroidDotnetRuntimeArtifactUrl
} else { $ArtifactUrl }
if ($runtimeRevision -notmatch '^[0-9a-f]{40}$') {
    throw "RuntimeRevision must be a full lowercase Git revision."
}
if ($expectedHash -notmatch '^[0-9a-f]{64}$') {
    throw "AndroidDotnetRuntimeArtifactSha256 is missing or invalid."
}
if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
    $CacheRoot = Join-Path $repositoryRoot "Output\Dependencies\RuntimeCache"
}
$cache = [IO.Path]::GetFullPath($CacheRoot)
$destination = Join-Path $cache "$runtimeVersion\$expectedHash\pack"
$cachePrefix = $cache.TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $destination.StartsWith($cachePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Resolved runtime cache path escapes '$cache'."
}
$cachedProvenance = Join-Path $destination "runtime-provenance.json"
if (Test-Path -LiteralPath $cachedProvenance -PathType Leaf) {
    $cached = Get-Content -LiteralPath $cachedProvenance -Raw | ConvertFrom-Json
    $cachedEngine = Join-Path $destination "native\libcoreclr.so"
    $cachedEngineHash = if (Test-Path -LiteralPath $cachedEngine -PathType Leaf) {
        (Get-FileHash -LiteralPath $cachedEngine -Algorithm SHA256).Hash.ToLowerInvariant()
    } else { "" }
    if ($cached.sourceRevision -ceq $runtimeRevision -and
        $cached.runtimeVersion -ceq $runtimeVersion -and
        $cached.backend -ceq "coreclr" -and
        $cached.engineSha256 -ceq $cachedEngineHash -and
        (Test-Path -LiteralPath (Join-Path $destination "LICENSE.TXT") -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $destination "THIRD-PARTY-NOTICES.TXT") -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $destination "managed") -PathType Container) -and
        (Test-Path -LiteralPath `
            (Join-Path $destination "native\libSystem.Security.Cryptography.Native.Android.so") `
            -PathType Leaf) -and
        (Test-Path -LiteralPath `
            (Join-Path $destination "native\lemonloader-coreclr-crypto.dex") `
            -PathType Leaf)) {
        Write-Output $destination
        return
    }
}

$workRoot = Join-Path $cache ".resolve-$([Guid]::NewGuid().ToString('N'))"
$download = Join-Path $workRoot "runtime.zip"
$staging = Join-Path $workRoot "pack"
New-Item -ItemType Directory -Force -Path $staging | Out-Null
try {
    if (-not [string]::IsNullOrWhiteSpace($ArchivePath)) {
        $sourceArchive = [IO.Path]::GetFullPath($ArchivePath)
        if (-not (Test-Path -LiteralPath $sourceArchive -PathType Leaf)) {
            throw "Runtime archive was not found at '$sourceArchive'."
        }
        Copy-Item -LiteralPath $sourceArchive -Destination $download
    }
    else {
        $resolvedArtifactUri = $null
        if (-not [Uri]::TryCreate(
            $artifactUrl,
            [UriKind]::Absolute,
            [ref]$resolvedArtifactUri)) {
            throw "AndroidDotnetRuntimeArtifactUrl is missing or invalid."
        }
        $client = [Net.Http.HttpClient]::new()
        $client.Timeout = [TimeSpan]::FromMinutes(10)
        try {
            $response = $client.GetAsync($resolvedArtifactUri).GetAwaiter().GetResult()
            [void]$response.EnsureSuccessStatusCode()
            $input = $response.Content.ReadAsStream()
            try {
                $output = [IO.File]::Create($download)
                try { $input.CopyTo($output) }
                finally { $output.Dispose() }
            }
            finally { $input.Dispose() }
        }
        finally { $client.Dispose() }
    }

    $actualHash = (Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -cne $expectedHash) {
        throw "Runtime archive SHA-256 '$actualHash' does not match '$expectedHash'."
    }

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($download)
    try {
        $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $stagingPrefix = $staging.TrimEnd(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        foreach ($entry in $archive.Entries) {
            $entryName = $entry.FullName.Replace('\', '/')
            if ([string]::IsNullOrWhiteSpace($entryName) -or
                $entryName.StartsWith('/') -or
                $entryName.Contains(':') -or
                -not $paths.Add($entryName)) {
                throw "Runtime archive contains an unsafe or duplicate entry '$entryName'."
            }
            $unixMode = ($entry.ExternalAttributes -shr 16) -band 0xF000
            if ($unixMode -eq 0xA000) {
                throw "Runtime archive contains unsupported symbolic link '$entryName'."
            }
            $target = [IO.Path]::GetFullPath(
                (Join-Path $staging $entryName.Replace('/', [IO.Path]::DirectorySeparatorChar)))
            if (-not $target.StartsWith($stagingPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Runtime archive entry escapes the staging directory: '$entryName'."
            }
            if ([string]::IsNullOrEmpty($entry.Name)) {
                New-Item -ItemType Directory -Force -Path $target | Out-Null
                continue
            }
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            $input = $entry.Open()
            try {
                $output = [IO.File]::Create($target)
                try { $input.CopyTo($output) }
                finally { $output.Dispose() }
            }
            finally { $input.Dispose() }
        }
    }
    finally { $archive.Dispose() }

    $provenancePath = Join-Path $staging "runtime-provenance.json"
    $enginePath = Join-Path $staging "native\libcoreclr.so"
    foreach ($required in @(
        $provenancePath,
        $enginePath,
        (Join-Path $staging "LICENSE.TXT"),
        (Join-Path $staging "THIRD-PARTY-NOTICES.TXT"),
        (Join-Path $staging "managed"),
        (Join-Path $staging "native\libSystem.Security.Cryptography.Native.Android.so"),
        (Join-Path $staging "native\lemonloader-coreclr-crypto.dex"))) {
        if (-not (Test-Path -LiteralPath $required)) {
            throw "Runtime archive is missing '$required'."
        }
    }
    $provenance = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json
    $engineHash = (Get-FileHash -LiteralPath $enginePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($provenance.formatVersion -ne 2 -or
        $provenance.runtimeVersion -cne $runtimeVersion -or
        $provenance.sourceRevision -cne $runtimeRevision -or
        $provenance.backend -cne "coreclr" -or
        $provenance.hostingModel -cne "coreclr-host-api" -or
        $provenance.engineSha256 -cne $engineHash) {
        throw "Runtime archive provenance is invalid."
    }

    $destinationParent = Split-Path -Parent $destination
    New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }
    Move-Item -LiteralPath $staging -Destination $destination
    Write-Output $destination
}
finally {
    if (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }
}
