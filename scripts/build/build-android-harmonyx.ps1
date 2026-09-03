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
    $Version = [string]$dependencies.AndroidHarmonyXVersion
}
if ([string]::IsNullOrWhiteSpace($SourceRevision)) {
    $SourceRevision = [string]$dependencies.AndroidHarmonyXRevision
}
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Get-AndroidDependencySourceRoot `
        -RepositoryRoot $repositoryRoot -Name HarmonyX
}
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot ".git"))) {
    throw "HarmonyX source was not found at '$SourceRoot'."
}
$head = (& git -C $SourceRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $head -ne $SourceRevision) {
    throw "HarmonyX source HEAD '$head' does not match '$SourceRevision'."
}

$changes = @(& git -C $SourceRoot status --porcelain --untracked-files=no)
if ($LASTEXITCODE -ne 0 -or $changes.Count -ne 0) {
    throw "HarmonyX source repository must be clean before building."
}
$emitterSource = Get-Content -LiteralPath `
    (Join-Path $SourceRoot "Harmony/Internal/Util/EmitterExtensions.cs") -Raw
if ($emitterSource -notmatch 'System\.Reflection\.Emit\.RuntimeLocalBuilder') {
    throw "The HarmonyX RuntimeLocalBuilder compatibility fix is missing."
}
$delegateFactorySource = Get-Content -LiteralPath `
    (Join-Path $SourceRoot "Harmony/Extras/DelegateTypeFactory.cs") -Raw
if ($delegateFactorySource -notmatch 'ContainsDynamicType' -or
    $delegateFactorySource -notmatch 'CreateEmittedDelegateType') {
    throw "The HarmonyX dynamic delegate compatibility fix is missing."
}
foreach ($resolverSourcePath in @(
    "Harmony/Public/Patching/ManagedMethodPatcher.cs",
    "Harmony/Public/Patching/NativeDetourMethodPatcher.cs")) {
    $resolverSource = Get-Content -LiteralPath (Join-Path $SourceRoot $resolverSourcePath) -Raw
    if ($resolverSource -notmatch 'args\.MethodPatcher\s*!=\s*null') {
        throw "The HarmonyX resolver precedence fix is missing from '$resolverSourcePath'."
    }
}

$project = Join-Path $SourceRoot "Harmony\Harmony.csproj"
$output = Join-Path $repositoryRoot "Output\Dependencies\HarmonyX\$Version"
$staging = "$output.staging-$([Guid]::NewGuid().ToString('N'))"
try {
    New-Item -ItemType Directory -Force -Path $staging | Out-Null
    dotnet build $project `
        --configuration Release `
        --framework netstandard2.0 `
        --output $staging `
        -p:GeneratePackageOnBuild=false
    if ($LASTEXITCODE -ne 0) {
        throw "Building the Android HarmonyX source fork failed with exit code $LASTEXITCODE."
    }
    $assembly = Join-Path $staging "0Harmony.dll"
    if (-not (Test-Path -LiteralPath $assembly -PathType Leaf)) {
        throw "The HarmonyX source build did not produce '0Harmony.dll'."
    }
    $assemblyHash = (Get-FileHash -LiteralPath $assembly -Algorithm SHA256).Hash.ToLowerInvariant()
    [ordered]@{
        formatVersion = 1
        version = $Version
        sourceRevision = $SourceRevision
        buildCommand = "dotnet build Harmony/Harmony.csproj -c Release -f netstandard2.0"
        assemblySha256 = $assemblyHash
    } | ConvertTo-Json | Set-Content `
        -LiteralPath (Join-Path $staging "lemonloader-harmonyx.json") `
        -Encoding Utf8

    if (Test-Path -LiteralPath $output) {
        Remove-Item -LiteralPath $output -Recurse -Force
    }
    Move-Item -LiteralPath $staging -Destination $output
    Write-Host "Built Android HarmonyX source fork:"
    Write-Host "  $output"
    Write-Host "  0Harmony SHA-256: $assemblyHash"
}
finally {
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force
    }
}
