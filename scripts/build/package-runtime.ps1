#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('android', 'bionic', 'all')]
    [string]$RuntimeProfile = 'all',
    [string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../common/RuntimeProfiles.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (!$OutputRoot) { $OutputRoot = Join-Path $repositoryRoot 'Output/RuntimeArtifacts' }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
[void][IO.Directory]::CreateDirectory($OutputRoot)
foreach ($profile in Get-RuntimeProfileSelection -Name $RuntimeProfile) {
    $pack = Join-Path $repositoryRoot "Output/RuntimePacks/$($profile.revision)/$($profile.rid)"
    Test-RuntimeProfilePack -Root $pack -Profile $profile
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
