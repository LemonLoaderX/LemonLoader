function Get-RuntimeProfile {
    param([string]$Name, [string]$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')))
    $config = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'eng/runtime-profiles.json') -Raw | ConvertFrom-Json
    if ($config.formatVersion -ne 1) { throw 'Unsupported runtime profile configuration.' }
    if (!$Name) { $Name = $config.defaultProfile }
    $profile = $config.profiles.PSObject.Properties[$Name]
    if (!$profile) { throw "Unknown runtime profile '$Name'." }
    $value = $profile.Value
    if ($value.rid -notin @('android-arm64','linux-bionic-arm64') -or
        $value.revision -notmatch '^[0-9a-f]{40}$' -or
        $value.version -notmatch '^\d+\.\d+\.\d+$' -or
        $value.cryptoBackend -notin @('android-jni','openssl') -or
        (($value.rid -eq 'android-arm64') -ne ($value.cryptoBackend -eq 'android-jni'))) {
        throw "Invalid runtime profile '$Name'."
    }
    $value | Add-Member -NotePropertyName name -NotePropertyValue $Name
    return $value
}

function Get-RuntimeProfileSelection {
    param([string]$Name)

    $names = if ($Name -eq 'all') { @('android', 'bionic') } else { @($Name) }
    foreach ($selected in $names) {
        Get-RuntimeProfile -Name $selected
    }
}

function Test-RuntimeProfilePack {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)]$Profile,
        [switch]$PassThru, [switch]$Development)
    $provenance = Get-Content -LiteralPath (Join-Path $Root 'runtime-provenance.json') -Raw | ConvertFrom-Json
    $engine = Join-Path $Root 'native/libcoreclr.so'
    $engineHash = (Get-FileHash -LiteralPath $engine).Hash.ToLowerInvariant()
    if ($provenance.sourceRevision -notmatch '^[0-9a-f]{40}$' -or
        (!$Development -and ($provenance.developmentBuild -or $provenance.sourceRevision -cne $Profile.revision))) {
        throw 'Runtime source differs from the locked profile; explicit development mode is required.'
    }
    if ($provenance.formatVersion -ne 2 -or $provenance.backend -cne 'coreclr' -or
        $provenance.hostingModel -cne 'coreclr-host-api' -or
        $provenance.runtimeVersion -cne $Profile.version -or
        $provenance.engineSha256 -cne $engineHash) {
        throw 'Runtime pack identity does not match the selected profile.'
    }
    if ($Profile.channel -ne 'legacy' -and
        ($provenance.runtimeRid -cne $Profile.rid -or $provenance.cryptoBackend -cne $Profile.cryptoBackend)) {
        throw 'Runtime pack RID/cryptography does not match the selected profile.'
    }
    $required = @('LICENSE.TXT','THIRD-PARTY-NOTICES.TXT','managed/System.Net.Http.dll','native/libcoreclr.so','native/libclrjit.so')
    $coreLib = Join-Path $Root 'managed/System.Private.CoreLib.dll'
    if (!(Test-Path -LiteralPath $coreLib -PathType Leaf)) { $coreLib = Join-Path $Root 'native/System.Private.CoreLib.dll' }
    if (!(Test-Path -LiteralPath $coreLib -PathType Leaf) -or (Get-Item -LiteralPath $coreLib).Length -eq 0) {
        throw 'Runtime pack has no CoreLib.'
    }
    if ($Profile.cryptoBackend -eq 'openssl') {
        $required += @('native/libSystem.Security.Cryptography.Native.OpenSsl.so','native/libssl.so','native/libcrypto.so','licenses/OpenSSL/LICENSE.txt')
        $forbidden = 'native/libSystem.Security.Cryptography.Native.Android.so'
    } else {
        $required += @('native/libSystem.Security.Cryptography.Native.Android.so','native/lemonloader-coreclr-crypto.dex')
        $forbidden = 'native/libSystem.Security.Cryptography.Native.OpenSsl.so'
    }
    foreach ($file in $required) {
        $path = Join-Path $Root $file
        if (!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) {
            throw "Runtime pack is missing '$file'."
        }
    }
    if (Test-Path -LiteralPath (Join-Path $Root $forbidden)) { throw 'Mixed cryptography pack.' }
    if ($Profile.channel -ne 'legacy') {
        $inventory = Get-Content -LiteralPath (Join-Path $Root 'pack-files.json') -Raw | ConvertFrom-Json
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($file in $inventory) {
            if ($file.path -match '(^/|\\|:|(^|/)\.\.(/|$))' -or !$seen.Add($file.path)) { throw 'Unsafe pack inventory.' }
            $path = Join-Path $Root $file.path
            if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Runtime pack file is missing: '$($file.path)'." }
            $actualHash = if ($file.path -ceq 'native/libcoreclr.so') { $engineHash } else {
                (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()
            }
            if ($actualHash -cne $file.sha256) {
                throw "Runtime pack integrity failed: '$($file.path)'."
            }
        }
        $actual = @(Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object {
            [IO.Path]::GetRelativePath($Root,$_.FullName) -cne 'pack-files.json'
        })
        if ($actual.Count -ne $seen.Count) { throw 'Unexpected runtime pack files.' }
        foreach ($file in $actual) {
            if (!$seen.Contains([IO.Path]::GetRelativePath($Root,$file.FullName).Replace('\','/'))) { throw 'Unlisted runtime pack file.' }
        }
    }
    if ($PassThru) { return $provenance }
}
