[CmdletBinding()]
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Debug",

    [string]$AndroidNdkRoot = $env:ANDROID_NDK_ROOT,

    [string]$Il2CppInteropSourceRoot,

    [string]$MonoModSourceRoot,

    [string]$HarmonyXSourceRoot,
    [switch]$AllowDirtyDependencies
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($AndroidNdkRoot)) {
    $AndroidNdkRoot = $env:ANDROID_NDK_HOME
}

if ([string]::IsNullOrWhiteSpace($AndroidNdkRoot)) {
    throw "Set ANDROID_NDK_ROOT or ANDROID_NDK_HOME to an Android NDK installation."
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
. (Join-Path $PSScriptRoot "..\common\AndroidDependencies.ps1")
$dependencies = Get-AndroidDependencies -RepositoryRoot $repositoryRoot
$outputDirectory = Join-Path $repositoryRoot "Output\$Configuration\linux-bionic-arm64"
$debugType = if ($Configuration -eq "Release") { "None" } else { "Embedded" }
$debugSymbols = if ($Configuration -eq "Release") { "false" } else { "true" }
$loaderPathMap = "$repositoryRoot=/_/LemonLoader"

function Invoke-AndroidMonoModBuild {
    param([string]$SourceRoot)

    $version = [string]$dependencies.AndroidMonoModVersion
    $sourceRevision = [string]$dependencies.AndroidMonoModRevision
    if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
        $SourceRoot = Get-AndroidDependencySourceRoot `
            -RepositoryRoot $repositoryRoot -Name MonoMod
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
    if ($LASTEXITCODE -ne 0 -or (!$AllowDirtyDependencies -and $head -cne $sourceRevision)) {
        throw "MonoMod source HEAD '$head' does not match '$sourceRevision'."
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
    if (($sourceChanges.Count -ne 0 -or $commonChanges.Count -ne 0) -and !$AllowDirtyDependencies) {
        throw "MonoMod and MonoMod.Common source repositories must be clean before building."
    }

    $project = Join-Path $SourceRoot "MonoMod.RuntimeDetour\MonoMod.RuntimeDetour.csproj"
    $output = Join-Path $repositoryRoot "Output\Dependencies\MonoMod\$version"
    $staging = "$output.staging-$([Guid]::NewGuid().ToString('N'))"
    try {
        New-Item -ItemType Directory -Force -Path $staging | Out-Null
        dotnet build $project `
            --configuration Release `
            --no-incremental `
            --framework net5.0 `
            --output $staging `
            -p:Version=$version `
            -p:PackageVersion=$version `
            -p:DebugType=None `
            -p:DebugSymbols=false `
            -p:ContinuousIntegrationBuild=true `
            -p:ImportDirectoryBuildProps=false `
            -p:ImportDirectoryBuildTargets=false `
            -p:GenerateRepositoryUrlAttribute=false `
            "-p:PathMap=$SourceRoot=/_/MonoMod"
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
            version = $version
            sourceRevision = $head
            commonRevision = $commonRevision
            dirty = ($sourceChanges.Count -ne 0 -or $commonChanges.Count -ne 0)
            buildCommand = "dotnet build MonoMod.RuntimeDetour/MonoMod.RuntimeDetour.csproj -c Release -f net5.0 -p:DebugType=None -p:DebugSymbols=false -p:ContinuousIntegrationBuild=true -p:ImportDirectoryBuildProps=false -p:ImportDirectoryBuildTargets=false -p:GenerateRepositoryUrlAttribute=false -p:PathMap=<source>=/_/MonoMod"
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
}

function Invoke-AndroidHarmonyXBuild {
    param([string]$SourceRoot)

    $version = [string]$dependencies.AndroidHarmonyXVersion
    $sourceRevision = [string]$dependencies.AndroidHarmonyXRevision
    if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
        $SourceRoot = Get-AndroidDependencySourceRoot `
            -RepositoryRoot $repositoryRoot -Name HarmonyX
    }
    $SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
    if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot ".git"))) {
        throw "HarmonyX source was not found at '$SourceRoot'."
    }
    $head = (& git -C $SourceRoot rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or (!$AllowDirtyDependencies -and $head -cne $sourceRevision)) {
        throw "HarmonyX source HEAD '$head' does not match '$sourceRevision'."
    }
    $changes = @(& git -C $SourceRoot status --porcelain --untracked-files=no)
    if ($LASTEXITCODE -ne 0 -or (!$AllowDirtyDependencies -and $changes.Count -ne 0)) {
        throw "HarmonyX source repository must be clean before building."
    }

    $project = Join-Path $SourceRoot "Harmony\Harmony.csproj"
    $output = Join-Path $repositoryRoot "Output\Dependencies\HarmonyX\$version"
    $staging = "$output.staging-$([Guid]::NewGuid().ToString('N'))"
    try {
        New-Item -ItemType Directory -Force -Path $staging | Out-Null
        dotnet build $project `
            --configuration Release `
            --no-incremental `
            --framework netstandard2.0 `
            --output $staging `
            -p:GeneratePackageOnBuild=false `
            -p:DebugType=None `
            -p:DebugSymbols=false `
            -p:ContinuousIntegrationBuild=true `
            -p:ImportDirectoryBuildProps=false `
            -p:ImportDirectoryBuildTargets=false `
            -p:GenerateRepositoryUrlAttribute=false `
            "-p:PathMap=$SourceRoot=/_/HarmonyX"
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
            version = $version
            sourceRevision = $head
            dirty = ($changes.Count -ne 0)
            buildCommand = "dotnet build Harmony/Harmony.csproj -c Release -f netstandard2.0 -p:DebugType=None -p:DebugSymbols=false -p:ContinuousIntegrationBuild=true -p:ImportDirectoryBuildProps=false -p:ImportDirectoryBuildTargets=false -p:GenerateRepositoryUrlAttribute=false -p:PathMap=<source>=/_/HarmonyX"
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
}

Invoke-AndroidMonoModBuild -SourceRoot $MonoModSourceRoot
Invoke-AndroidHarmonyXBuild -SourceRoot $HarmonyXSourceRoot

if ([string]::IsNullOrWhiteSpace($Il2CppInteropSourceRoot)) {
    $Il2CppInteropSourceRoot = Get-AndroidDependencySourceRoot `
        -RepositoryRoot $repositoryRoot -Name Il2CppInterop
}
$Il2CppInteropSourceRoot = [System.IO.Path]::GetFullPath($Il2CppInteropSourceRoot)
$interopPathMap = "$Il2CppInteropSourceRoot=/_/Il2CppInterop"
$interopHarmonyProject = Join-Path $Il2CppInteropSourceRoot `
    "Il2CppInterop.HarmonySupport\Il2CppInterop.HarmonySupport.csproj"
if (-not (Test-Path -LiteralPath $interopHarmonyProject -PathType Leaf)) {
    throw "The modified Il2CppInterop source was not found at '$Il2CppInteropSourceRoot'."
}

dotnet build $interopHarmonyProject `
    --configuration $Configuration `
    --no-incremental `
    "-p:DebugType=$debugType" `
    "-p:DebugSymbols=$debugSymbols" `
    -p:ContinuousIntegrationBuild=true `
    "-p:PathMap=$interopPathMap"
if ($LASTEXITCODE -ne 0) {
    throw "The modified Il2CppInterop build failed with exit code $LASTEXITCODE."
}

$projects = @(
    "MelonLoader.NativeHost\MelonLoader.NativeHost.csproj",
    "Dependencies\SupportModules\Il2Cpp\Il2Cpp.csproj"
)

foreach ($relativeProject in $projects) {
    $project = Join-Path $repositoryRoot $relativeProject

    dotnet build $project `
        --configuration $Configuration `
        --no-incremental `
        --runtime linux-bionic-arm64 `
        -p:ForceRID=linux-bionic-arm64 `
        -p:AndroidNdkRoot="$AndroidNdkRoot" `
        -p:Il2CppInteropSourceRoot="$Il2CppInteropSourceRoot" `
        -p:MLOutDir="$outputDirectory" `
        "-p:DebugType=$debugType" `
        "-p:DebugSymbols=$debugSymbols" `
        -p:ContinuousIntegrationBuild=true `
        "-p:PathMap=$loaderPathMap"

    if ($LASTEXITCODE -ne 0) {
        throw "Android managed build failed for '$relativeProject' with exit code $LASTEXITCODE."
    }
}

$interopBin = Join-Path $Il2CppInteropSourceRoot "bin"
$managedOutput = Join-Path $outputDirectory "MelonLoader\net6"
$monoModOutput = Join-Path $repositoryRoot `
    "Output\Dependencies\MonoMod\$($dependencies.AndroidMonoModVersion)"
foreach ($monoModAssembly in @("MonoMod.RuntimeDetour.dll", "MonoMod.Utils.dll")) {
    $source = Join-Path $monoModOutput $monoModAssembly
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "The source-built MonoMod assembly was not found at '$source'."
    }
    Copy-Item -LiteralPath $source -Destination $managedOutput -Force
}
$harmonyOutput = Join-Path $repositoryRoot `
    "Output\Dependencies\HarmonyX\$($dependencies.AndroidHarmonyXVersion)"
$harmonyAssembly = Join-Path $harmonyOutput "0Harmony.dll"
if (-not (Test-Path -LiteralPath $harmonyAssembly -PathType Leaf)) {
    throw "The source-built HarmonyX assembly was not found at '$harmonyAssembly'."
}
Copy-Item -LiteralPath $harmonyAssembly -Destination $managedOutput -Force
$monoModProbe = Join-Path $repositoryRoot `
    "tests\Android\MonoModCoreClrProbe\MonoModCoreClrProbe.csproj"
dotnet run --project $monoModProbe --configuration Release `
    -p:Platform=x64 `
    "-p:MonoModBuildRoot=$monoModOutput"
if ($LASTEXITCODE -ne 0) {
    throw "The MonoMod .NET 10 CoreCLR probe failed with exit code $LASTEXITCODE."
}
$harmonyProbe = Join-Path $repositoryRoot `
    "tests\Android\HarmonyCoreClrProbe\HarmonyCoreClrProbe.csproj"
dotnet run --project $harmonyProbe --configuration Release `
    -p:Platform=x64 `
    "-p:MonoModBuildRoot=$monoModOutput" `
    "-p:HarmonyBuildRoot=$harmonyOutput"
if ($LASTEXITCODE -ne 0) {
    throw "The HarmonyX .NET 10 CoreCLR probe failed with exit code $LASTEXITCODE."
}
foreach ($interopAssembly in @(
    @{ Name = "Il2CppInterop.Common"; Framework = "netstandard2.0" },
    @{ Name = "Il2CppInterop.Runtime"; Framework = "net6.0" },
    @{ Name = "Il2CppInterop.HarmonySupport"; Framework = "net6.0" })) {
    $assemblyName = $interopAssembly.Name
    $source = Join-Path $interopBin `
        "$assemblyName\$($interopAssembly.Framework)\$assemblyName.dll"
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "The modified $assemblyName assembly was not found at '$source'."
    }
    Copy-Item -LiteralPath $source -Destination $managedOutput -Force
}
