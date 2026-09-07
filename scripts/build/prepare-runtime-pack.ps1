[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('android','bionic')][string]$RuntimeProfile,
    [Parameter(Mandatory)][string]$Nupkg,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedSha256,
    [Parameter(Mandatory)][string]$RuntimeSourceRoot,
    [string]$OpenSslRoot,
    [string]$OpenSslLicense,
    [string]$Destination,
    [string]$Distribution='Ubuntu-24.04',
    [string]$LinuxAndroidSdkRoot,
    [string]$LinuxJavaHome,
    [switch]$Development
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../common/RuntimeProfiles.ps1')
. (Join-Path $PSScriptRoot '../common/Wsl.ps1')
$profile=Get-RuntimeProfile -Name $RuntimeProfile
$revision=(& git -C $RuntimeSourceRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -or (!$Development -and $revision -cne $profile.revision)) { throw 'Runtime source revision mismatch.' }
if ((Get-FileHash -LiteralPath $Nupkg).Hash -ine $ExpectedSha256) { throw 'Runtime nupkg hash mismatch.' }
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$work=Join-Path $repository ('Output/RuntimePreparation/'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path "$work/managed","$work/native" | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($Nupkg))
try {
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($entry in $archive.Entries) {
        $name=$entry.FullName
        if ($name -match '(^/|\\|:|(^|/)\.\.(/|$))' -or !$seen.Add($name) -or
            (($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw 'Unsafe nupkg entry.' }
        if ($name -match "^runtimes/$($profile.rid)/(native|lib/$([regex]::Escape($profile.tfm)))/([^/]+)$") {
            $scope=if($Matches[1] -eq 'native'){'native'}else{'managed'}
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,"$work/$scope/$($Matches[2])",$false)
        }
    }
} finally { $archive.Dispose() }
Copy-Item -LiteralPath "$RuntimeSourceRoot/LICENSE.TXT","$RuntimeSourceRoot/THIRD-PARTY-NOTICES.TXT" -Destination $work
if ($profile.cryptoBackend -eq 'openssl') {
    Copy-Item -LiteralPath "$OpenSslRoot/libssl.so","$OpenSslRoot/libcrypto.so" -Destination "$work/native"
} else {
    $linuxHome = Get-WslHome -Distribution $Distribution
    if(!$LinuxAndroidSdkRoot){$LinuxAndroidSdkRoot="$linuxHome/.cache/lemonloader/android-sdk"}
    if(!$LinuxJavaHome){$LinuxJavaHome="$linuxHome/.cache/lemonloader/jdk-21.0.12.1-1"}
    $linuxWork = ConvertTo-WslPath -Path $work -Distribution $Distribution
    $linuxRepo = ConvertTo-WslPath -Path $repository -Distribution $Distribution
    & wsl.exe -d $Distribution -- bash "$linuxRepo/scripts/build/build-android-coreclr-crypto-loader.sh" `
        "$linuxRepo/MelonLoader.Bootstrap/Platforms/Android/Native/java/net/dot/android/crypto/LemonLoaderCryptoBootstrap.java" `
        "$linuxWork/native/libSystem.Security.Cryptography.Native.Android.jar" `
        "$linuxWork/native/lemonloader-coreclr-crypto.dex" "$linuxWork/cache" $LinuxAndroidSdkRoot $LinuxJavaHome
    if($LASTEXITCODE){throw 'Crypto helper build failed'}
}
@{formatVersion=2;runtimeVersion=$profile.version;backend='coreclr';sourceRevision=$revision;
    hostingModel='coreclr-host-api';engineSha256=(Get-FileHash "$work/native/libcoreclr.so").Hash.ToLowerInvariant();
    sourcePackageSha256=$ExpectedSha256.ToLowerInvariant();developmentBuild=[bool]$Development} | ConvertTo-Json | Set-Content "$work/runtime-provenance.json"
& (Join-Path $PSScriptRoot 'import-runtime-pack.ps1') -RuntimeProfile $RuntimeProfile -SourceRoot $work `
    -OpenSslLicense $OpenSslLicense -Destination $Destination -Development:$Development
