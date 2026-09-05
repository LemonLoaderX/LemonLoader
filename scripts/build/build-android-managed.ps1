[CmdletBinding()]
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Debug",

    [string]$AndroidNdkRoot = $env:ANDROID_NDK_ROOT,

    [string]$Il2CppInteropSourceRoot,

    [string]$MonoModSourceRoot,

    [string]$HarmonyXSourceRoot
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

& (Join-Path $PSScriptRoot "build-android-monomod.ps1") -SourceRoot $MonoModSourceRoot
& (Join-Path $PSScriptRoot "build-android-harmonyx.ps1") -SourceRoot $HarmonyXSourceRoot

if ([string]::IsNullOrWhiteSpace($Il2CppInteropSourceRoot)) {
    $Il2CppInteropSourceRoot = Get-AndroidDependencySourceRoot `
        -RepositoryRoot $repositoryRoot -Name Il2CppInterop
}
$Il2CppInteropSourceRoot = [System.IO.Path]::GetFullPath($Il2CppInteropSourceRoot)
$interopHarmonyProject = Join-Path $Il2CppInteropSourceRoot `
    "Il2CppInterop.HarmonySupport\Il2CppInterop.HarmonySupport.csproj"
if (-not (Test-Path -LiteralPath $interopHarmonyProject -PathType Leaf)) {
    throw "The modified Il2CppInterop source was not found at '$Il2CppInteropSourceRoot'."
}

dotnet build $interopHarmonyProject `
    --configuration $Configuration `
    --no-incremental `
    "-p:DebugType=$debugType" `
    "-p:DebugSymbols=$debugSymbols"
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
        "-p:DebugSymbols=$debugSymbols"

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
