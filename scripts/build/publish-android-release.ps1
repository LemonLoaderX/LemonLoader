[CmdletBinding()]
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$packageRoot = Join-Path $repositoryRoot "Output\$Configuration\linux-bionic-arm64\package"
$manifestPath = Join-Path $packageRoot "lemonloader-release.json"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Stage the Android package before publishing a release."
}

$gameAssemblies = @(Get-ChildItem `
    -LiteralPath (Join-Path $packageRoot "assets\LemonLoader\runtime\loader\Il2CppAssemblies") `
    -Filter "*.dll" -File -ErrorAction SilentlyContinue)
if ($gameAssemblies.Count -ne 0) {
    throw "A LemonLoader Release must not contain game-specific Interop assemblies."
}

$versionOutput = & dotnet msbuild `
    (Join-Path $repositoryRoot "MelonLoader\MelonLoader.csproj") `
    -nologo -getProperty:Version
if ($LASTEXITCODE -ne 0) {
    throw "Reading the LemonLoader version failed with exit code $LASTEXITCODE."
}
$version = ($versionOutput | Select-Object -Last 1).Trim()
$releaseRoot = Join-Path $repositoryRoot "Output\Releases"
$archivePath = Join-Path $releaseRoot "LemonLoader-Android-arm64.zip"
$stagingArchivePath = Join-Path $releaseRoot ".LemonLoader-Android-arm64.staging.zip"
New-Item -ItemType Directory -Force -Path $releaseRoot | Out-Null
if (Test-Path -LiteralPath $stagingArchivePath) {
    Remove-Item -LiteralPath $stagingArchivePath -Force
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$payloadFiles = @(
    foreach ($treeName in @("assets", "lib", "tools", "licenses")) {
        $tree = Join-Path $packageRoot $treeName
        if (Test-Path -LiteralPath $tree -PathType Container) {
            Get-ChildItem -LiteralPath $tree -Recurse -File
        }
    }
    Get-Item -LiteralPath (Join-Path $packageRoot "LICENSE.md")
    Get-Item -LiteralPath (Join-Path $packageRoot "NOTICE.txt")
    Get-Item -LiteralPath $manifestPath
) | ForEach-Object {
    [pscustomobject]@{
        Path = $_.FullName
        EntryName = [System.IO.Path]::GetRelativePath($packageRoot, $_.FullName).Replace('\', '/')
    }
} | Sort-Object EntryName

$duplicateEntries = @($payloadFiles | Group-Object EntryName | Where-Object Count -ne 1)
if ($duplicateEntries.Count -ne 0) {
    throw "Release package contains duplicate ZIP entry names: $($duplicateEntries.Name -join ', ')."
}

$fixedTimestamp = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
try {
    $output = [System.IO.File]::Open(
        $stagingArchivePath,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None)
    try {
        $archive = [System.IO.Compression.ZipArchive]::new(
            $output,
            [System.IO.Compression.ZipArchiveMode]::Create,
            $true)
        try {
            foreach ($file in $payloadFiles) {
                $entry = $archive.CreateEntry(
                    $file.EntryName,
                    [System.IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = $fixedTimestamp
                $input = [System.IO.File]::OpenRead($file.Path)
                try {
                    $entryStream = $entry.Open()
                    try {
                        $input.CopyTo($entryStream)
                    }
                    finally {
                        $entryStream.Dispose()
                    }
                }
                finally {
                    $input.Dispose()
                }
            }
        }
        finally {
            $archive.Dispose()
        }
    }
    finally {
        $output.Dispose()
    }

    $verificationArchive = [System.IO.Compression.ZipFile]::OpenRead($stagingArchivePath)
    try {
        $actualEntries = @($verificationArchive.Entries.FullName | Sort-Object)
        $expectedEntries = @($payloadFiles.EntryName)
        if (($actualEntries -join "`n") -cne ($expectedEntries -join "`n")) {
            throw "Published Release ZIP entries do not match the staged package."
        }
    }
    finally {
        $verificationArchive.Dispose()
    }

    [System.IO.File]::Move($stagingArchivePath, $archivePath, $true)
}
finally {
    if (Test-Path -LiteralPath $stagingArchivePath) {
        Remove-Item -LiteralPath $stagingArchivePath -Force
    }
}

$hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "Published game-independent LemonLoader Release:"
Write-Host "  $archivePath"
Write-Host "  SHA-256: $hash"
