[CmdletBinding()]
param(
    [string]$InteropInputPath,

    [string]$Cpp2IlAssembliesPath,

    [string]$Cpp2IlPath,

    [string]$Cpp2IlVersion = "2022.1.0-pre-release.21",

    [string]$UnityVersion,

    [string]$UnityAssembliesPath,

    [string]$OutputPath,

    [string]$PatcherCliProject,

    [string]$Il2CppInteropCliProject
)

$ErrorActionPreference = "Stop"

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
if ([string]::IsNullOrWhiteSpace($InteropInputPath)) {
    $InteropInputPath = Join-Path $repositoryRoot "Output\InteropInput"
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repositoryRoot "Output\GeneratedInterop"
}

$inputRoot = [System.IO.Path]::GetFullPath($InteropInputPath)
$outputRoot = [System.IO.Path]::GetFullPath($OutputPath)
$libIl2Cpp = Join-Path $inputRoot "libil2cpp.so"
$metadata = Join-Path $inputRoot "global-metadata.dat"
if (-not (Test-Path -LiteralPath $libIl2Cpp) -or
    -not (Test-Path -LiteralPath $metadata)) {
    throw "Prepare libil2cpp.so and global-metadata.dat with prepare-android-interop-input.ps1 first."
}

$inputManifest = Join-Path $inputRoot "interop-input.json"
if ([string]::IsNullOrWhiteSpace($UnityVersion) -and
    (Test-Path -LiteralPath $inputManifest -PathType Leaf)) {
    $manifestData = Get-Content -LiteralPath $inputManifest -Raw | ConvertFrom-Json
    $UnityVersion = $manifestData.unityVersion
}
if ([string]::IsNullOrWhiteSpace($UnityVersion)) {
    $globalManagers = Join-Path $inputRoot "globalgamemanagers"
    if (Test-Path -LiteralPath $globalManagers -PathType Leaf) {
        $managerText = [System.Text.Encoding]::ASCII.GetString(
            [System.IO.File]::ReadAllBytes($globalManagers))
        $versions = @([regex]::Matches(
            $managerText,
            '(?<![0-9])\d+\.\d+\.\d+[abfp]\d+(?![0-9])') |
            ForEach-Object Value |
            Sort-Object -Unique)
        if ($versions.Count -eq 1) {
            $UnityVersion = $versions[0]
        }
    }
}
if ([string]::IsNullOrWhiteSpace($UnityVersion)) {
    throw "Unity version could not be detected. Supply -UnityVersion."
}

$cpp2Il = $null
if ([string]::IsNullOrWhiteSpace($Cpp2IlAssembliesPath)) {
    $cpp2IlHash = "663fb432433b4371fd1ee0ebc321a8fff2a9aac5ac4230c843f9e03ddee4e04c"
    if ([string]::IsNullOrWhiteSpace($Cpp2IlPath)) {
        if (-not $IsWindows) {
            throw "The pinned Cpp2IL artifact is Windows-only. Pass -Cpp2IlPath for the current host, or supply -Cpp2IlAssembliesPath."
        }
        $cpp2IlToolRoot = Join-Path $repositoryRoot "Output\Tools\Cpp2IL\$Cpp2IlVersion"
        New-Item -ItemType Directory -Force -Path $cpp2IlToolRoot | Out-Null
        $Cpp2IlPath = Join-Path $cpp2IlToolRoot "Cpp2IL.exe"
        if (-not (Test-Path -LiteralPath $Cpp2IlPath -PathType Leaf)) {
            $cpp2IlUrl = "https://github.com/SamboyCoding/Cpp2IL/releases/download/" +
                "$Cpp2IlVersion/Cpp2IL-$Cpp2IlVersion-Windows.exe"
            Invoke-WebRequest -Uri $cpp2IlUrl -OutFile $Cpp2IlPath -UseBasicParsing
        }
        $actualCpp2IlHash = (Get-FileHash -LiteralPath $Cpp2IlPath -Algorithm SHA256).Hash
        if ($actualCpp2IlHash -ne $cpp2IlHash) {
            throw "Pinned Cpp2IL executable hash mismatch at '$Cpp2IlPath'."
        }
    }

    $cpp2Il = [System.IO.Path]::GetFullPath($Cpp2IlPath)
    if (-not (Test-Path -LiteralPath $cpp2Il -PathType Leaf)) {
        throw "Cpp2IL was not found at '$cpp2Il'."
    }

    $cpp2IlOutput = [System.IO.Path]::GetFullPath(
        (Join-Path $repositoryRoot "Output\Cpp2IL"))
    $expectedOutputPrefix = [System.IO.Path]::GetFullPath(
        (Join-Path $repositoryRoot "Output")).TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $cpp2IlOutput.StartsWith(
        $expectedOutputPrefix,
        [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to run Cpp2IL outside the repository output directory."
    }

    if (Test-Path -LiteralPath $cpp2IlOutput) {
        Remove-Item -LiteralPath $cpp2IlOutput -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $cpp2IlOutput | Out-Null

    $cpp2IlArguments = @(
        "--game-path", $inputRoot,
        "--force-binary-path", $libIl2Cpp,
        "--force-metadata-path", $metadata,
        "--force-unity-version", $UnityVersion,
        "--output-as", "dummydll",
        "--output-to", $cpp2IlOutput,
        "--use-processor", "attributeanalyzer,attributeinjector"
    )
    $previousNoColor = $env:NO_COLOR
    $env:NO_COLOR = "1"
    try {
        & $cpp2Il @cpp2IlArguments
        $cpp2IlExitCode = $LASTEXITCODE
    }
    finally {
        $env:NO_COLOR = $previousNoColor
    }
    if ($cpp2IlExitCode -ne 0) {
        throw "Cpp2IL failed with exit code $cpp2IlExitCode."
    }

    $Cpp2IlAssembliesPath = $cpp2IlOutput
}

$cpp2IlAssemblies = [System.IO.Path]::GetFullPath($Cpp2IlAssembliesPath)
if (-not (Test-Path -LiteralPath $cpp2IlAssemblies -PathType Container) -or
    (Get-ChildItem -LiteralPath $cpp2IlAssemblies -Filter "*.dll" -File).Count -eq 0) {
    throw "Cpp2IL dummy assemblies were not found at '$cpp2IlAssemblies'."
}

if ([string]::IsNullOrWhiteSpace($UnityAssembliesPath)) {
    if ([string]::IsNullOrWhiteSpace($PatcherCliProject)) {
        $PatcherCliProject = Join-Path $repositoryRoot `
            "..\LemonLoader.Patcher\src\LemonLoader.Patcher.CLI\LemonLoader.Patcher.CLI.csproj"
    }
    $patcherCli = [System.IO.Path]::GetFullPath($PatcherCliProject)
    if (-not (Test-Path -LiteralPath $patcherCli -PathType Leaf)) {
        throw "LemonLoader.Patcher was not found at '$patcherCli'. Pass -PatcherCliProject."
    }

    $UnityAssembliesPath = Join-Path $repositoryRoot "Output\UnityDependencies"
    $unityCache = Join-Path $repositoryRoot "Output\Tools\UnityDependencies"
    dotnet run --project $patcherCli --configuration Release -- `
        unity-dependencies `
        --unity-version $UnityVersion `
        --output $UnityAssembliesPath `
        --cache $unityCache
    if ($LASTEXITCODE -ne 0) {
        throw "Restoring Unity base libraries failed with exit code $LASTEXITCODE."
    }
}

$unityAssemblies = [System.IO.Path]::GetFullPath($UnityAssembliesPath)
if (-not (Test-Path -LiteralPath $unityAssemblies -PathType Container) -or
    -not (Test-Path -LiteralPath (Join-Path $unityAssemblies "UnityEngine.dll") -PathType Leaf)) {
    throw "Unity base assemblies were not found or are incomplete at '$unityAssemblies'."
}

$repositoryOutput = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "Output")).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if (-not $outputRoot.StartsWith($repositoryOutput, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Interop output must remain under '$repositoryOutput'."
}

if (Test-Path -LiteralPath $outputRoot) {
    Remove-Item -LiteralPath $outputRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

$generatorArguments = @(
    "generate",
    "--input", $cpp2IlAssemblies,
    "--output", $outputRoot,
    "--game-assembly", $libIl2Cpp,
    "--no-xref-cache",
    "--use-opt-out-prefixing"
)

$generatorArguments += @("--unity", $unityAssemblies)

if ([string]::IsNullOrWhiteSpace($Il2CppInteropCliProject)) {
    $Il2CppInteropCliProject = Join-Path $repositoryRoot `
        "..\dependencies\Il2CppInterop\Il2CppInterop.CLI\Il2CppInterop.CLI.csproj"
}
$sourceCli = [System.IO.Path]::GetFullPath($Il2CppInteropCliProject)
if (-not (Test-Path -LiteralPath $sourceCli -PathType Leaf)) {
    throw "The maintained Il2CppInterop.CLI source project was not found at '$sourceCli'."
}
$arguments = @(
    "run", "--project", $sourceCli,
    "--configuration", "Release", "--"
) + $generatorArguments

Push-Location $repositoryRoot
try {
    & dotnet @arguments
    $generatorExitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}
if ($generatorExitCode -ne 0) {
    throw "Il2CppInterop generation failed with exit code $generatorExitCode."
}

$generatedAssemblies = Get-ChildItem -LiteralPath $outputRoot -Filter "*.dll" -File
if ($generatedAssemblies.Count -eq 0) {
    throw "Il2CppInterop did not generate any assemblies."
}

$manifest = [ordered]@{
    formatVersion = 1
    sourceInput = $inputRoot
    frontEnd = "Cpp2IL"
    cpp2IlVersion = $Cpp2IlVersion
    cpp2IlExecutableSha256 = if ($cpp2Il) {
        (Get-FileHash -LiteralPath $cpp2Il -Algorithm SHA256).Hash.ToLowerInvariant()
    } else {
        $null
    }
    cpp2IlAssemblies = $cpp2IlAssemblies
    unityVersion = $UnityVersion
    unityAssemblies = $unityAssemblies
    unstripping = $true
    xrefCache = $false
    il2CppInteropCli = $sourceCli
    assemblies = $generatedAssemblies | Sort-Object Name | ForEach-Object {
        [ordered]@{
            name = $_.Name
            size = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
}
$manifest | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath (Join-Path $outputRoot "interop-manifest.json") -Encoding Utf8

Write-Host "Generated Android Il2CppInterop assemblies:"
Write-Host "  $outputRoot"
Write-Host "  Assemblies: $($generatedAssemblies.Count)"
Write-Host "  Xref cache: disabled for Android ELF input"
