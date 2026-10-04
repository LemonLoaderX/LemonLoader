#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root = Join-Path $repositoryRoot ('Output/Tests/InteropGeneration/' + [Guid]::NewGuid().ToString('N'))
$inputRoot = Join-Path $root 'input'
$dummy = Join-Path $root 'dummy'
$unity = Join-Path $root 'unity'
$output = Join-Path $root 'output'
$project = Join-Path $root 'generator.csproj'
$script = Join-Path $PSScriptRoot '../interop/generate-android-interop.ps1'
New-Item -ItemType Directory -Path $inputRoot, $dummy, $unity, $output | Out-Null
[IO.File]::WriteAllText((Join-Path $inputRoot 'libil2cpp.so'), 'binary')
[IO.File]::WriteAllText((Join-Path $inputRoot 'global-metadata.dat'), 'metadata')
[IO.File]::WriteAllText((Join-Path $dummy 'Game.dll'), 'dummy')
[IO.File]::WriteAllText((Join-Path $unity 'UnityEngine.dll'), 'unity')
[IO.File]::WriteAllText((Join-Path $output 'prior.dll'), 'prior')
[IO.File]::WriteAllText($project, '<Project/>')
$parameters = @{
    InteropInputPath = $inputRoot; Cpp2IlAssembliesPath = $dummy
    UnityVersion = '2022.3.1f1'; UnityAssembliesPath = $unity
    Il2CppInteropCliProject = $project; OutputPath = $output
}
function Assert-Rejected([hashtable]$Overrides) {
    $arguments = $parameters.Clone()
    foreach ($key in $Overrides.Keys) { $arguments[$key] = $Overrides[$key] }
    $rejected = $false
    try { & $script @arguments } catch { $rejected = $true }
    if (!$rejected) { throw 'Unsafe or failing generation was accepted.' }
    if ([IO.File]::ReadAllText((Join-Path $inputRoot 'libil2cpp.so')) -cne 'binary' -or
        [IO.File]::ReadAllText((Join-Path $output 'prior.dll')) -cne 'prior') {
        throw 'Generation destroyed inputs or prior output.'
    }
}
$global:interopFixtureFailGeneration = $true
$global:interopFixtureRestoredUnity = $false
function dotnet {
    $arguments = @($args)
    $outputIndex = [Array]::IndexOf($arguments, '--output')
    if ($arguments -contains 'unity-dependencies') {
        $versionIndex = [Array]::IndexOf($arguments, 'unity-dependencies') + 1
        if ($arguments[$versionIndex] -cne '2022.3.1f1') { throw 'Unity version is not positional.' }
        $path = $arguments[$outputIndex + 1]
        New-Item -ItemType Directory -Path $path | Out-Null
        [IO.File]::WriteAllText((Join-Path $path 'UnityEngine.dll'), 'unity')
        $global:interopFixtureRestoredUnity = $true
        $global:LASTEXITCODE = 0
    } elseif ($global:interopFixtureFailGeneration) {
        $global:LASTEXITCODE = 1
    } else {
        [IO.File]::WriteAllText((Join-Path $arguments[$outputIndex + 1] 'Generated.dll'), 'generated')
        $global:LASTEXITCODE = 0
    }
}
try {
    foreach ($path in @($inputRoot, $dummy, $unity, $root)) { Assert-Rejected @{ OutputPath = $path } }
    $linkedInput = Join-Path $root 'linked-input'
    $linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
    New-Item -ItemType $linkType -Path $linkedInput -Target $inputRoot | Out-Null
    try { Assert-Rejected @{ InteropInputPath = $linkedInput; OutputPath = $inputRoot } }
    finally { Remove-Item -LiteralPath $linkedInput -Force }
    Assert-Rejected @{ Il2CppInteropCliProject = (Join-Path $root 'missing.csproj') }
    Assert-Rejected @{}
    $global:interopFixtureFailGeneration = $false
    $parameters.UnityAssembliesPath = $null
    $parameters.PatcherCliProject = $project
    & $script @parameters
    if (!$global:interopFixtureRestoredUnity -or !(Test-Path (Join-Path $output 'Generated.dll')) -or
        (Test-Path (Join-Path $output 'prior.dll'))) { throw 'Successful generation was not published.' }
    Write-Host 'PASS Interop generation: overlap rejection, prior-output preservation, staged publication and positional Unity restore'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force
    Remove-Variable -Scope Global interopFixtureFailGeneration, interopFixtureRestoredUnity
    $global:LASTEXITCODE = 0
}
