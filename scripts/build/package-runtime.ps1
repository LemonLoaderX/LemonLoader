[CmdletBinding()]
param([ValidateSet('android','bionic','all')][string]$RuntimeProfile='all')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../common/RuntimeProfiles.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$output=Join-Path $repository 'Output/RuntimeArtifacts'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$names=if($RuntimeProfile -eq 'all'){@('android','bionic')}else{@($RuntimeProfile)}
foreach($name in $names) {
    $profile=Get-RuntimeProfile -Name $name
    $pack=Join-Path $repository "Output/RuntimePacks/$($profile.revision)/$($profile.rid)"
    Test-RuntimeProfilePack -Root $pack -Profile $profile
    $path=Join-Path $output "dotnet-runtime-$($profile.version)-$($profile.rid).zip"
    $temporary="$path.$([Guid]::NewGuid().ToString('N')).staging"
    try {
        [IO.Compression.ZipFile]::CreateFromDirectory($pack,$temporary,[IO.Compression.CompressionLevel]::Optimal,$false)
        [IO.File]::Move($temporary,$path,$true)
        $hash=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()
        Set-Content -LiteralPath "$path.sha256" -Value "$hash  $([IO.Path]::GetFileName($path))"
        Write-Host "$($profile.rid): $path ($hash)"
    } finally { if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force} }
}
