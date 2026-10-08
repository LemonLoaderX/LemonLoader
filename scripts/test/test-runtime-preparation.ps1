$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../common/TestFixtures.ps1')
. (Join-Path $PSScriptRoot '../common/RuntimeProfiles.ps1')
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$fixture = Join-Path $repositoryRoot ('Output/Tests/RuntimePreparation/' + [Guid]::NewGuid().ToString('N'))
function Write-Fixture([string]$Path, [string]$Content) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path, $Content)
}
try {
    $product = Join-Path $fixture 'Loader'
    foreach ($path in @('scripts/build/prepare-runtime-pack.ps1','scripts/build/import-runtime-pack.ps1',
        'scripts/common/RuntimeProfiles.ps1','scripts/common/Wsl.ps1','scripts/common/Cleanup.ps1','eng/runtime-profiles.json')) {
        Write-Fixture (Join-Path $product $path) ([IO.File]::ReadAllText((Join-Path $repositoryRoot $path)))
    }
    $profile = Get-RuntimeProfile -Name bionic
    $sourceRevision = $profile.revision
    function git {
        if ($args[-2] -cne 'rev-parse' -or $args[-1] -cne 'HEAD') { throw 'Unexpected source lookup.' }
        $global:LASTEXITCODE = 0
        return $sourceRevision
    }
    $source = Join-Path $fixture 'runtime-source'
    Write-Fixture (Join-Path $source 'LICENSE.TXT') 'license'
    Write-Fixture (Join-Path $source 'THIRD-PARTY-NOTICES.TXT') 'notices'
    $openssl = Join-Path $fixture 'openssl'
    foreach ($name in @('libssl.so','libcrypto.so','LICENSE.txt')) { Write-Fixture (Join-Path $openssl $name) 'fixture' }
    $nupkg = Join-Path $fixture 'runtime.nupkg'
    $zip = [IO.Compression.ZipFile]::Open($nupkg, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in @("lib/$($profile.tfm)/System.Private.CoreLib.dll", "lib/$($profile.tfm)/System.Net.Http.dll",
            'native/libcoreclr.so','native/libclrjit.so','native/libSystem.Security.Cryptography.Native.OpenSsl.so')) {
            $writer = [IO.StreamWriter]::new($zip.CreateEntry("runtimes/$($profile.rid)/$name").Open())
            try { $writer.Write('fixture') } finally { $writer.Dispose() }
        }
    } finally { $zip.Dispose() }
    $entry = Join-Path $product 'scripts/build/prepare-runtime-pack.ps1'
    $destination = Join-Path $fixture 'pack'
    $arguments = @{ RuntimeProfile='bionic'; Nupkg=$nupkg; ExpectedSha256=(Get-FileHash $nupkg).Hash;
        RuntimeSourceRoot=$source; OpenSslRoot=$openssl; OpenSslLicense=(Join-Path $openssl 'LICENSE.txt'); Destination=$destination }
    & $entry @arguments | Out-Null
    if (!(Test-Path -LiteralPath (Join-Path $destination 'pack-files.json'))) { throw 'Prepared pack was not published.' }
    $originalEngine = (Get-FileHash (Join-Path $destination 'native/libcoreclr.so')).Hash
    foreach ($failure in @('existing-destination','missing-license','unsafe-zip')) {
        if ($failure -eq 'missing-license') {
            $arguments.Destination = Join-Path $fixture 'failed-pack'
            $arguments.OpenSslLicense = Join-Path $fixture 'missing-license'
        }
        if ($failure -eq 'unsafe-zip') {
            $zip = [IO.Compression.ZipFile]::Open($nupkg, [IO.Compression.ZipArchiveMode]::Update)
            try { [void]$zip.CreateEntry('../escape') } finally { $zip.Dispose() }
            $arguments.ExpectedSha256 = (Get-FileHash $nupkg).Hash
        }
        $rejected = $false
        try { & $entry @arguments | Out-Null } catch { $rejected = $true }
        if (!$rejected) { throw "Expected preparation rejection: $failure" }
        if (@(Get-ChildItem -LiteralPath (Join-Path $product 'Output/RuntimePreparation') -Force).Count -ne 0) {
            throw "Runtime preparation retained temporary files: $failure"
        }
    }
    if ((Get-FileHash (Join-Path $destination 'native/libcoreclr.so')).Hash -cne $originalEngine -or
        (Test-Path -LiteralPath (Join-Path $fixture 'failed-pack'))) { throw 'Failed preparation changed published inputs.' }
    Write-Host 'PASS runtime preparation cleans success/failure intermediates, rejects unsafe ZIPs and preserves existing packs'
} finally { Remove-TestFixture -Path $fixture }
