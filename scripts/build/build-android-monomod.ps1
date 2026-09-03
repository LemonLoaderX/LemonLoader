[CmdletBinding()]
param(
    [string]$Version,
    [string]$SourceRevision,
    [string]$SourceRoot
)

$ErrorActionPreference = "Stop"
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
. (Join-Path $PSScriptRoot "..\common\AndroidDependencies.ps1")
$dependencies = Get-AndroidDependencies -RepositoryRoot $repositoryRoot
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = [string]$dependencies.AndroidMonoModVersion
}
if ([string]::IsNullOrWhiteSpace($SourceRevision)) {
    $SourceRevision = [string]$dependencies.AndroidMonoModRevision
}
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Join-Path $repositoryRoot "..\dependencies\MonoMod"
}
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
$commonRoot = Join-Path $SourceRoot "MonoMod.Common"
foreach ($repository in @(
    @{ Path = $SourceRoot; Name = "MonoMod" },
    @{ Path = $commonRoot; Name = "MonoMod.Common" })) {
    if (-not (Test-Path -LiteralPath (Join-Path $repository.Path ".git"))) {
        throw "$($repository.Name) source was not found at '$($repository.Path)'."
    }
}
$head = (& git -C $SourceRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $head -ne $SourceRevision) {
    throw "MonoMod source HEAD '$head' does not match '$SourceRevision'."
}
$commonRevision = (& git -C $commonRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $commonRevision -notmatch '^[0-9a-f]{40}$') {
    throw "Could not resolve the MonoMod.Common submodule revision."
}

$sourceChanges = @(& git -C $SourceRoot status --porcelain --untracked-files=no)
if ($LASTEXITCODE -ne 0) {
    throw "Could not inspect the MonoMod source state."
}
$commonChanges = @(& git -C $commonRoot status --porcelain --untracked-files=no)
if ($LASTEXITCODE -ne 0) {
    throw "Could not inspect the MonoMod.Common source state."
}
if ($sourceChanges.Count -ne 0 -or $commonChanges.Count -ne 0) {
    throw "MonoMod and MonoMod.Common source repositories must be clean before building."
}
$expectedFix = "Utils/DMDGenerators/DMDEmitDynamicMethodGenerator.cs"
$generatorSource = Get-Content -LiteralPath (Join-Path $commonRoot $expectedFix) -Raw
if ($generatorSource -notmatch 'GetField\("_returnType"') {
    throw "The MonoMod .NET 10 DynamicMethod return-type fix is missing."
}

$project = Join-Path $SourceRoot "MonoMod.RuntimeDetour\MonoMod.RuntimeDetour.csproj"
$output = Join-Path $repositoryRoot "Output\Dependencies\MonoMod\$Version"
$staging = "$output.staging-$([Guid]::NewGuid().ToString('N'))"
try {
    New-Item -ItemType Directory -Force -Path $staging | Out-Null
    dotnet build $project `
        --configuration Release `
        --framework net5.0 `
        --output $staging `
        -p:Version=$Version `
        -p:PackageVersion=$Version
    if ($LASTEXITCODE -ne 0) {
        throw "Building the Android MonoMod source fork failed with exit code $LASTEXITCODE."
    }

    foreach ($assembly in @("MonoMod.RuntimeDetour.dll", "MonoMod.Utils.dll")) {
        if (-not (Test-Path -LiteralPath (Join-Path $staging $assembly) -PathType Leaf)) {
            throw "The MonoMod source build did not produce '$assembly'."
        }
    }
    $utilsHash = (Get-FileHash -LiteralPath (Join-Path $staging "MonoMod.Utils.dll") `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    [ordered]@{
        formatVersion = 1
        version = $Version
        sourceRevision = $SourceRevision
        commonRevision = $commonRevision
        buildCommand = "dotnet build MonoMod.RuntimeDetour/MonoMod.RuntimeDetour.csproj -c Release -f net5.0"
        utilsSha256 = $utilsHash
    } | ConvertTo-Json | Set-Content `
        -LiteralPath (Join-Path $staging "lemonloader-monomod.json") `
        -Encoding Utf8

    if (Test-Path -LiteralPath $output) {
        Remove-Item -LiteralPath $output -Recurse -Force
    }
    Move-Item -LiteralPath $staging -Destination $output
    Write-Host "Built Android MonoMod source fork:"
    Write-Host "  $output"
    Write-Host "  MonoMod.Utils SHA-256: $utilsHash"
}
finally {
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force
    }
}
