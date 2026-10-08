$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../common/TestFixtures.ps1')
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$fixture = Join-Path $repositoryRoot ('Output/Tests/InteropDeployment/' + [Guid]::NewGuid().ToString('N'))
try {
    $scripts = Join-Path $fixture 'scripts'
    [void][IO.Directory]::CreateDirectory((Join-Path $scripts 'interop'))
    [void][IO.Directory]::CreateDirectory((Join-Path $scripts 'common'))
    $entry = Join-Path $scripts 'interop/deploy-android-interop.ps1'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../interop/deploy-android-interop.ps1') -Destination $entry
    @'
function Get-AndroidAdb { 'offline-adb' }
function Resolve-AndroidDeviceSerial { 'fixture-device' }
function Invoke-AndroidAdb {
    param($Adb, $Serial, [string[]]$Arguments)
    $state = $global:InteropDeploymentFixture
    if ($Arguments[0] -eq 'get-state') { return 'device' }
    if ($Arguments[0] -eq 'pull') {
        $destination = Join-Path $Arguments[2] 'Il2CppAssemblies'
        [void][IO.Directory]::CreateDirectory($destination)
        foreach ($name in $state.Current.Keys) { [IO.File]::WriteAllBytes((Join-Path $destination $name), $state.Current[$name]) }
        return
    }
    if ($Arguments[0] -eq 'push') {
        if ($state.Mode -eq 'push-failure') { throw 'Synthetic transfer failure.' }
        $bytes = [IO.File]::ReadAllBytes($Arguments[1])
        if ($state.Mode -eq 'hash-failure') { $bytes[0] = $bytes[0] -bxor 1 }
        $state.Staged[[IO.Path]::GetFileName($Arguments[2])] = $bytes
        return
    }
    if ($Arguments[0] -ne 'shell') { throw "Unexpected ADB call: $Arguments" }
    $command = $Arguments[1]
    if ($command -eq 'pm') { return 'package:fixture.apk' }
    if ($command -eq 'am' -or $command.StartsWith('test -d ')) { return }
    if ($command.StartsWith('mkdir ')) { $state.Staged = @{}; return }
    if ($command.StartsWith('cd ')) {
        foreach ($name in $state.Staged.Keys) {
            [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($state.Staged[$name])).ToLowerInvariant() + '  ' + $name
        }
        return
    }
    if ($command.StartsWith('mv ')) {
        $paths = [regex]::Matches($command, "'([^']*)'")
        if ($paths.Count -ne 2) { throw 'Move paths were not quoted.' }
        $source = $paths[0].Groups[1].Value
        if ($source.Contains('.stage-')) {
            if ($state.Mode -in @('publish-failure', 'restore-failure')) { throw 'Synthetic publication failure.' }
            $state.Current = $state.Staged; $state.Staged = $null
            if ($state.Mode -eq 'publish-disconnect') { throw 'Synthetic disconnect after publication.' }
        } elseif ($source.Contains('.previous-')) {
            throw 'Restoration must check the destination before moving the previous tree.'
        } else {
            if ($state.Mode -eq 'rename-failure') { throw 'Synthetic rename failure.' }
            $state.Previous = $state.Current; $state.Current = $null
            if ($state.Mode -eq 'rename-disconnect') { throw 'Synthetic disconnect after the first rename.' }
        }
        return
    }
    if ($command.StartsWith('if test ! -e ')) {
        $state.RestoreAttempted = $true
        if ($state.Mode -eq 'restore-failure') { throw 'Synthetic restore failure.' }
        if ($null -eq $state.Previous) {
            if ($null -eq $state.Current) { throw 'Missing installed tree.' }
        } else {
            if ($null -ne $state.Current) { throw 'Refusing restoration into an existing tree.' }
            $state.Current = $state.Previous; $state.Previous = $null
        }
        return
    }
    if ($command.StartsWith('rm -rf -- ')) {
        if ($command.Contains('.stage-')) { $state.Staged = $null }
        elseif ($command.Contains('.previous-')) { $state.Previous = $null }
        else { throw 'Attempted to delete the installed Interop tree.' }
        return
    }
    throw "Unexpected shell command: $command"
}
'@ | Set-Content -LiteralPath (Join-Path $scripts 'common/AndroidToolchain.ps1')
    $source = Join-Path $fixture 'source'
    [void][IO.Directory]::CreateDirectory((Join-Path $source 'nested'))
    [IO.File]::WriteAllText((Join-Path $source 'Game.DLL'), 'new interop')
    [IO.File]::WriteAllText((Join-Path $source 'nested/Ignored.dll'), 'nested')
    foreach ($mode in @('plain-dlls', 'audit-manifest', 'push-failure', 'hash-failure',
        'rename-failure', 'rename-disconnect', 'publish-failure', 'publish-disconnect', 'restore-failure')) {
        if ($mode -eq 'audit-manifest') { [IO.File]::WriteAllText((Join-Path $source 'interop-manifest.json'), 'invalid audit JSON') }
        $global:InteropDeploymentFixture = @{Mode=$mode; Current=@{'Old.dll'=[Text.Encoding]::UTF8.GetBytes('old interop')}; Previous=$null; Staged=$null; RestoreAttempted=$false}
        $backup = Join-Path $fixture "backup-$mode"
        $failed = $false
        try { & $entry -InteropDirectory $source -PackageName fixture.game -BackupDirectory $backup }
        catch { $failed = $true }
        $state = $global:InteropDeploymentFixture
        if ($mode -eq 'publish-disconnect') {
            if (!$failed -or !$state.Current.ContainsKey('Game.DLL') -or !$state.Previous.ContainsKey('Old.dll')) {
                throw 'An unacknowledged publication must preserve both trees for recovery.'
            }
        } elseif ($mode -eq 'restore-failure') {
            if (!$failed -or $null -ne $state.Current -or !$state.Previous.ContainsKey('Old.dll')) {
                throw 'A failed restore must preserve the previous tree for recovery.'
            }
        } elseif ($mode.EndsWith('failure') -or $mode -eq 'rename-disconnect') {
            if (!$failed -or $state.Current.Count -ne 1 -or !$state.Current.ContainsKey('Old.dll')) { throw "Failure changed installed Interop: $mode" }
        } else {
            if ($failed -or $state.Current.Count -ne 1 -or !$state.Current.ContainsKey('Game.DLL')) { throw "DLL-only publication failed: $mode" }
        }
        if ($mode -in @('rename-failure', 'rename-disconnect', 'publish-failure', 'publish-disconnect', 'restore-failure') -and
            !$state.RestoreAttempted) { throw "Publication failure skipped recovery: $mode" }
        if ($null -ne $state.Staged -or
            ($mode -notin @('publish-disconnect', 'restore-failure') -and $null -ne $state.Previous)) {
            throw "Device fixture was not cleaned/restored: $mode"
        }
        if ([IO.File]::ReadAllText((Join-Path $backup 'Il2CppAssemblies/Old.dll')) -cne 'old interop') { throw 'Recovery backup was not preserved.' }
    }
    Write-Host 'PASS Interop DLL-only deployment, staged hashes, rename/publication failures, lost acknowledgements and recovery preservation'
} finally {
    Remove-Variable -Name InteropDeploymentFixture -Scope Global -ErrorAction SilentlyContinue
    Remove-TestFixture -Path $fixture
}
