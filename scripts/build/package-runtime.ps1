#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('android', 'bionic', 'all')]
    [string]$RuntimeProfile = 'all',
    [string]$OutputRoot,
    [string]$RuntimePackRoot,
    [switch]$Development
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../common/RuntimeProfiles.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if ($RuntimePackRoot -and $RuntimeProfile -eq 'all') { throw 'An explicit runtime pack requires a single profile.' }
if (!$OutputRoot) {
    $OutputRoot = Join-Path $repositoryRoot $(if ($Development) { 'Output/DevelopmentRuntimeArtifacts' } else { 'Output/RuntimeArtifacts' })
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
[void][IO.Directory]::CreateDirectory($OutputRoot)
foreach ($profile in Get-RuntimeProfileSelection -Name $RuntimeProfile) {
    $pack = if ($RuntimePackRoot) { [IO.Path]::GetFullPath($RuntimePackRoot) } else {
        Join-Path $repositoryRoot "Output/RuntimePacks/$($profile.revision)/$($profile.rid)"
    }
    $provenance = Test-RuntimeProfilePack -Root $pack -Profile $profile -Development:$Development -PassThru
    # Repacking a historical normalized pack must not republish private fields.
    $publicIdentity = Get-PublicRuntimeProvenance -Provenance $provenance -Profile $profile -Development:$Development
    $identityBytes = [Text.Encoding]::UTF8.GetBytes(($publicIdentity | ConvertTo-Json) + "`n")
    $inventory = @(Get-Content -LiteralPath (Join-Path $pack 'pack-files.json') -Raw | ConvertFrom-Json | ForEach-Object {
        [ordered]@{ path=$_.path; sha256=$_.sha256 }
    })
    ($inventory | Where-Object path -CEQ 'runtime-provenance.json').sha256 =
        [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($identityBytes)).ToLowerInvariant()
    $generated = @{
        'runtime-provenance.json' = $identityBytes
        'pack-files.json' = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $inventory) + "`n")
    }
    $path = Join-Path $OutputRoot "dotnet-runtime-$($profile.version)-$($profile.rid).zip"
    $temporary = "$path.$([Guid]::NewGuid().ToString('N')).staging"
    try {
        # Stable entry order and timestamps make identical packs reproducible.
        $files = @{}
        foreach ($file in Get-ChildItem -LiteralPath $pack -Recurse -File) {
            $files[[IO.Path]::GetRelativePath($pack, $file.FullName).Replace('\', '/')] = $file.FullName
        }
        [string[]]$names = @($files.Keys)
        [Array]::Sort($names, [StringComparer]::Ordinal)
        $archive = [IO.Compression.ZipFile]::Open($temporary, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($name in $names) {
                $entry = $archive.CreateEntry($name, [IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
                if ($generated.ContainsKey($name)) {
                    $stream = $entry.Open()
                    try { $stream.Write($generated[$name], 0, $generated[$name].Length) } finally { $stream.Dispose() }
                    continue
                }
                $input = [IO.File]::OpenRead($files[$name])
                try {
                    $stream = $entry.Open()
                    try { $input.CopyTo($stream) } finally { $stream.Dispose() }
                } finally { $input.Dispose() }
            }
        } finally { $archive.Dispose() }
        $hash = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash.ToLowerInvariant()
        $unchanged = (Test-Path -LiteralPath $path -PathType Leaf) -and
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $hash
        if (!$unchanged) {
            try { [IO.File]::Move($temporary, $path, $true) } catch {
                throw "Could not publish runtime archive '$temporary' to '$path': $($_.Exception.Message)"
            }
        }
        Set-Content -LiteralPath "$path.sha256" -Value "$hash  $([IO.Path]::GetFileName($path))" -Encoding utf8
        Write-Host "$($profile.rid): $path ($hash)"
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}
