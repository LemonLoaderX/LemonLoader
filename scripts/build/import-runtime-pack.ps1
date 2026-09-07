[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('android','bionic')][string]$RuntimeProfile,
    [Parameter(Mandatory)][string]$SourceRoot,
    [string]$OpenSslLicense,
    [string]$Destination,
    [switch]$Development
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../common/RuntimeProfiles.ps1')
$profile = Get-RuntimeProfile -Name $RuntimeProfile
$source = [IO.Path]::GetFullPath($SourceRoot)
$provenance = Get-Content -LiteralPath (Join-Path $source 'runtime-provenance.json') -Raw | ConvertFrom-Json
if ($Development -and !$Destination) {
    $Destination = Join-Path $PSScriptRoot "../../Output/RuntimePacks/local/$($provenance.sourceRevision)/$($profile.rid)"
}
if (!$Destination) { $Destination = Join-Path $PSScriptRoot "../../Output/RuntimePacks/$($profile.revision)/$($profile.rid)" }
$destination = [IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $destination) { throw "Destination already exists: '$destination'. Import to a new path instead." }
if ($provenance.sourceRevision -notmatch '^[0-9a-f]{40}$' -or
    (!$Development -and ($provenance.developmentBuild -or $provenance.sourceRevision -cne $profile.revision)) -or $provenance.runtimeVersion -cne $profile.version -or
    $provenance.engineSha256 -cne (Get-FileHash -LiteralPath (Join-Path $source 'native/libcoreclr.so')).Hash.ToLowerInvariant()) {
    throw 'Source runtime identity does not match the reviewed profile.'
}
if ($profile.cryptoBackend -eq 'openssl' -and !(Test-Path -LiteralPath $OpenSslLicense -PathType Leaf)) {
    throw 'The OpenSSL source license must be supplied.'
}
$staging = "$destination.import-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path $staging | Out-Null
try {
    foreach ($name in @('managed','native','LICENSE.TXT','THIRD-PARTY-NOTICES.TXT')) {
        Copy-Item -LiteralPath (Join-Path $source $name) -Destination $staging -Recurse
    }
    $provenance | Add-Member -NotePropertyName runtimeRid -NotePropertyValue $profile.rid -Force
    $provenance | Add-Member -NotePropertyName developmentBuild -NotePropertyValue ([bool]$Development) -Force
    $provenance | Add-Member -NotePropertyName cryptoBackend -NotePropertyValue $profile.cryptoBackend -Force
    $provenance | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $staging 'runtime-provenance.json')
    if ($profile.cryptoBackend -eq 'openssl') {
        New-Item -ItemType Directory -Force -Path (Join-Path $staging 'licenses/OpenSSL') | Out-Null
        Copy-Item -LiteralPath $OpenSslLicense -Destination (Join-Path $staging 'licenses/OpenSSL/LICENSE.txt')
    }
    @(Get-ChildItem -LiteralPath $staging -Recurse -File | Sort-Object FullName | ForEach-Object {
        @{path=[IO.Path]::GetRelativePath($staging,$_.FullName).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}
    }) | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $staging 'pack-files.json')
    Test-RuntimeProfilePack -Root $staging -Profile $profile -Development:$Development
    Move-Item -LiteralPath $staging -Destination $destination
    Write-Output $destination
} finally {
    if (Test-Path -LiteralPath $staging) {
        if (![IO.Path]::GetFullPath($staging).StartsWith($destination + '.import-', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cleanup.' }
        Remove-Item -LiteralPath $staging -Recurse -Force
    }
}
