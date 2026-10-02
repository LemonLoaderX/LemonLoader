[CmdletBinding()]
param([string]$EmbeddedBootstrapPath, [string]$CryptoDexPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../common/RuntimeProfiles.ps1')
if ([bool]$EmbeddedBootstrapPath -ne [bool]$CryptoDexPath) { throw 'Supply both bootstrap and helper DEX paths.' }
if ($EmbeddedBootstrapPath) { Test-BootstrapEmbeddedCrypto -Bootstrap $EmbeddedBootstrapPath -Dex $CryptoDexPath }
function Reject([scriptblock]$Action) {
    $failed=$false
    try { & $Action } catch { $failed=$true }
    if(!$failed){throw 'Expected rejection did not occur'}
}
if((Get-RuntimeProfile).name -cne 'android'){throw 'Unexpected default profile'}
Reject { Get-RuntimeProfile -Name invalid }
$android=Get-RuntimeProfile -Name android
$bionic=Get-RuntimeProfile -Name bionic
if($android.revision -cne $bionic.revision){throw 'Mainline targets must share one revision'}
if($android.minimumApi -ne 26 -or $bionic.minimumApi -ne 26 -or (Get-RuntimeProfile -Name legacy).minimumApi -ne 23) {
    throw 'Active products require API 26; frozen legacy must retain API 23.'
}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot ('../../Output/Tests/runtime-profiles-'+[Guid]::NewGuid().ToString('N'))))
New-Item -ItemType Directory -Force -Path $root | Out-Null
try {
    $dexBytes = [byte[]]::new(112)
    [Text.Encoding]::ASCII.GetBytes("dex`n035`0").CopyTo($dexBytes, 0)
    $dex = Join-Path $root 'helper.dex'
    $bootstrap = Join-Path $root 'bootstrap.so'
    [IO.File]::WriteAllBytes($dex, $dexBytes)
    [IO.File]::WriteAllBytes($bootstrap, [byte[]](@(127,69,76,70) + $dexBytes + @(1,2,3)))
    Test-BootstrapEmbeddedCrypto -Bootstrap $bootstrap -Dex $dex
    $dexBytes[111] = 1
    [IO.File]::WriteAllBytes($dex, $dexBytes)
    Reject { Test-BootstrapEmbeddedCrypto -Bootstrap $bootstrap -Dex $dex }
    [IO.File]::WriteAllBytes($dex, [byte[]]::new(112))
    Reject { Test-BootstrapEmbeddedCrypto -Bootstrap $bootstrap -Dex $dex }
    foreach($profile in @($android,$bionic)) {
        $pack=Join-Path $root $profile.name
        $files=@('LICENSE.TXT','THIRD-PARTY-NOTICES.TXT','managed/System.Private.CoreLib.dll','managed/System.Net.Http.dll','native/libcoreclr.so','native/libclrjit.so')
        $files+=if($profile.name -eq 'android'){@('native/libSystem.Security.Cryptography.Native.Android.so','native/lemonloader-coreclr-crypto.dex')}else{@('native/libSystem.Security.Cryptography.Native.OpenSsl.so','native/libssl.so','native/libcrypto.so','licenses/OpenSSL/LICENSE.txt')}
        foreach($file in $files) {
            $path=Join-Path $pack $file
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
            Set-Content -LiteralPath $path -Value 'fixture'
        }
        @{formatVersion=2;backend='coreclr';hostingModel='coreclr-host-api';runtimeVersion=$profile.version;
            sourceRevision=$profile.revision;runtimeRid=$profile.rid;cryptoBackend=$profile.cryptoBackend;
            engineSha256=(Get-FileHash "$pack/native/libcoreclr.so").Hash.ToLowerInvariant()} | ConvertTo-Json | Set-Content "$pack/runtime-provenance.json"
        @(Get-ChildItem $pack -File -Recurse | ForEach-Object {
            @{path=[IO.Path]::GetRelativePath($pack,$_.FullName).Replace('\','/');sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}
        }) | ConvertTo-Json | Set-Content "$pack/pack-files.json"
        Test-RuntimeProfilePack -Root $pack -Profile $profile
        if ((Test-RuntimeProfilePack -Root $pack -Profile $profile -PassThru).runtimeRid -cne $profile.rid) { throw 'Verified identity was not returned.' }
        $identity = Get-Content "$pack/runtime-provenance.json" -Raw | ConvertFrom-Json
        $identity.sourceRevision = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        $identity | Add-Member -NotePropertyName developmentBuild -NotePropertyValue $true
        $identity | ConvertTo-Json | Set-Content "$pack/runtime-provenance.json"
        $inventory = Get-Content "$pack/pack-files.json" -Raw | ConvertFrom-Json
        ($inventory | Where-Object path -eq 'runtime-provenance.json').sha256 = (Get-FileHash "$pack/runtime-provenance.json").Hash.ToLowerInvariant()
        $inventory | ConvertTo-Json | Set-Content "$pack/pack-files.json"
        Reject { Test-RuntimeProfilePack -Root $pack -Profile $profile }
        Test-RuntimeProfilePack -Root $pack -Profile $profile -Development
        $import = Join-Path $PSScriptRoot '../build/import-runtime-pack.ps1'
        $imported = Join-Path $root ('import-' + $profile.name)
        $license = Join-Path $pack 'licenses/OpenSSL/LICENSE.txt'
        Reject { & $import -RuntimeProfile $profile.name -SourceRoot $pack -Destination $imported -OpenSslLicense $license }
        & $import -RuntimeProfile $profile.name -SourceRoot $pack -Destination $imported -OpenSslLicense $license -Development | Out-Null
        Test-RuntimeProfilePack -Root $imported -Profile $profile -Development
        Reject { Test-RuntimeProfilePack -Root $imported -Profile $profile }
        $identity.sourceRevision = $profile.revision
        $identity.developmentBuild = $false
        $identity | ConvertTo-Json | Set-Content "$pack/runtime-provenance.json"
        ($inventory | Where-Object path -eq 'runtime-provenance.json').sha256 = (Get-FileHash "$pack/runtime-provenance.json").Hash.ToLowerInvariant()
        $inventory | ConvertTo-Json | Set-Content "$pack/pack-files.json"
        $other=if($profile.name -eq 'android'){$bionic}else{$android}
        Reject { Test-RuntimeProfilePack -Root $pack -Profile $other }
        Set-Content "$pack/native/unlisted.so" 'unexpected'
        Reject { Test-RuntimeProfilePack -Root $pack -Profile $profile }
        Remove-Item -LiteralPath "$pack/native/unlisted.so"
        Set-Content "$pack/managed/System.Net.Http.dll" 'corruption'
        Reject { Test-RuntimeProfilePack -Root $pack -Profile $profile -Development }
        Reject { Test-RuntimeProfilePack -Root $pack -Profile $profile }
        Remove-Item -LiteralPath "$pack/managed/System.Net.Http.dll"
        Reject { Test-RuntimeProfilePack -Root $pack -Profile $profile }
    }
    Write-Host 'PASS: profile selection, development import isolation, identity, RID, missing/tampered/unexpected inputs'
} finally {
    $allowed=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../Output/Tests'))+[IO.Path]::DirectorySeparatorChar
    if(!$root.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe test cleanup'}
    Remove-Item -LiteralPath $root -Recurse -Force
}
