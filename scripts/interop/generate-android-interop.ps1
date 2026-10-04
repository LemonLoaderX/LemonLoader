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
. (Join-Path $PSScriptRoot "..\common\AndroidDependencies.ps1")
if ([string]::IsNullOrWhiteSpace($InteropInputPath)) {
    $InteropInputPath = Join-Path $repositoryRoot "Output\InteropInput"
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repositoryRoot "Output\GeneratedInterop"
}

$inputRoot = [System.IO.Path]::GetFullPath($InteropInputPath)
$outputRoot = [System.IO.Path]::GetFullPath($OutputPath)
function Test-ContainsPath([string]$ParentPath, [string]$ChildPath) {
    $relative = [IO.Path]::GetRelativePath($ParentPath, $ChildPath)
    return -not ([IO.Path]::IsPathRooted($relative) -or $relative -eq '..' -or
        $relative.StartsWith('../') -or $relative.StartsWith('..\'))
}
function Assert-UnlinkedPath([string]$Path) {
    for ($current = [IO.Path]::GetFullPath($Path); $current; $current = [IO.Path]::GetDirectoryName($current)) {
        if ((Test-Path -LiteralPath $current) -and
            ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Output must not traverse a link: '$current'."
        }
    }
}
$repositoryOutput = Join-Path $repositoryRoot 'Output'
if ($outputRoot -eq $repositoryOutput -or -not (Test-ContainsPath $repositoryOutput $outputRoot)) {
    throw "Interop output must remain below '$repositoryOutput'."
}
Assert-UnlinkedPath $outputRoot
if (Test-Path -LiteralPath $outputRoot -PathType Leaf) { throw 'Interop output must be a directory.' }
if ([string]::IsNullOrWhiteSpace($Il2CppInteropCliProject)) {
    $interopSource = Get-AndroidDependencySourceRoot -RepositoryRoot $repositoryRoot -Name Il2CppInterop
    $Il2CppInteropCliProject = Join-Path $interopSource 'Il2CppInterop.CLI/Il2CppInterop.CLI.csproj'
}
$sourceCli = [IO.Path]::GetFullPath($Il2CppInteropCliProject)
if (-not (Test-Path -LiteralPath $sourceCli -PathType Leaf)) {
    throw "The maintained Il2CppInterop.CLI source project was not found at '$sourceCli'."
}
foreach ($inputPath in @($inputRoot, $Cpp2IlAssembliesPath, $UnityAssembliesPath,
        $Cpp2IlPath, $sourceCli, $PatcherCliProject, (Join-Path $repositoryOutput 'Tools'))) {
    if ([string]::IsNullOrWhiteSpace($inputPath)) { continue }
    $inputPath = [IO.Path]::GetFullPath($inputPath)
    Assert-UnlinkedPath $inputPath
    if ((Test-ContainsPath $outputRoot $inputPath) -or (Test-ContainsPath $inputPath $outputRoot)) {
        throw "Interop output must not overlap an input or tool: '$inputPath'."
    }
}
$workRoot = Join-Path $repositoryOutput ('.interop-' + [Guid]::NewGuid().ToString('N'))
Assert-UnlinkedPath $workRoot
New-Item -ItemType Directory -Path $workRoot | Out-Null
try {
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

        $cpp2IlOutput = Join-Path $workRoot 'Cpp2IL'
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

        $UnityAssembliesPath = Join-Path $workRoot 'UnityDependencies'
        $unityCache = Join-Path $repositoryRoot "Output\Tools\UnityDependencies"
        dotnet run --project $patcherCli --configuration Release -- `
            unity-dependencies `
            $UnityVersion `
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

    $stagedOutput = Join-Path $workRoot 'GeneratedInterop'
    New-Item -ItemType Directory -Path $stagedOutput | Out-Null

    $generatorArguments = @(
        "generate",
        "--input", $cpp2IlAssemblies,
        "--output", $stagedOutput,
        "--game-assembly", $libIl2Cpp,
        "--no-xref-cache",
        "--use-opt-out-prefixing"
    )

    $generatorArguments += @("--unity", $unityAssemblies)

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

    $generatedAssemblies = Get-ChildItem -LiteralPath $stagedOutput -Filter "*.dll" -File
    if ($generatedAssemblies.Count -eq 0) {
        throw "Il2CppInterop did not generate any assemblies."
    }

    $manifest = [ordered]@{
        formatVersion = 1
        frontEnd = "Cpp2IL"
        cpp2IlVersion = $Cpp2IlVersion
        unityVersion = $UnityVersion
        unstripping = $true
        xrefCache = $false
        assemblies = $generatedAssemblies | Sort-Object Name | ForEach-Object {
            [ordered]@{
                name = $_.Name
                size = $_.Length
            }
        }
    }
    $manifest | ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath (Join-Path $stagedOutput 'interop-manifest.json') -Encoding Utf8

    # Publish only a complete generation; keep prior output if replacement fails.
    Assert-UnlinkedPath $outputRoot
    $backup = $outputRoot + '.backup-' + [Guid]::NewGuid().ToString('N')
    New-Item -ItemType Directory -Force -Path (Split-Path $outputRoot -Parent) | Out-Null
    if (Test-Path -LiteralPath $outputRoot) { [IO.Directory]::Move($outputRoot, $backup) }
    try { [IO.Directory]::Move($stagedOutput, $outputRoot) }
    catch {
        if (Test-Path -LiteralPath $backup) { [IO.Directory]::Move($backup, $outputRoot) }
        throw
    }
    if (Test-Path -LiteralPath $backup) {
        try { Remove-Item -LiteralPath $backup -Recurse -Force }
        catch { Write-Warning "Generation is published; could not remove backup '$backup': $_" }
    }

    Write-Host "Generated Android Il2CppInterop assemblies:"
    Write-Host "  $outputRoot"
    Write-Host "  Assemblies: $($generatedAssemblies.Count)"
    Write-Host "  Xref cache: disabled for Android ELF input"
}
finally {
    try { Remove-Item -LiteralPath $workRoot -Recurse -Force }
    catch { Write-Warning "Could not remove Interop staging '$workRoot': $_" }
}
