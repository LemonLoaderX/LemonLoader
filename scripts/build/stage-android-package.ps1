[CmdletBinding()]
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Debug",

    [string]$AndroidNdkRoot = $env:ANDROID_NDK_ROOT,

    [string]$DotnetRuntimeVersion,

    [string]$ManagedRuntimeRevision,

    [string]$CoreClrRuntimePackRoot,

    [string]$DobbySourceRoot,

    [string]$Il2CppInteropSourceRoot,

    [string]$MonoModSourceRoot,

    [string]$HarmonyXSourceRoot
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\common\AndroidToolchain.ps1")
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
. (Join-Path $PSScriptRoot "..\common\AndroidDependencies.ps1")
$dependencies = Get-AndroidDependencies -RepositoryRoot $repositoryRoot
if ([string]::IsNullOrWhiteSpace($DotnetRuntimeVersion)) {
    $DotnetRuntimeVersion = [string]$dependencies.AndroidDotnetRuntimeVersion
}
if ([string]::IsNullOrWhiteSpace($ManagedRuntimeRevision)) {
    $ManagedRuntimeRevision = [string]$dependencies.AndroidDotnetRuntimeRevision
}
$managedRuntimeBackendId = "coreclr"
$dependencySourceRoots = [ordered]@{
    Dobby = if ([string]::IsNullOrWhiteSpace($DobbySourceRoot)) {
        Get-AndroidDependencySourceRoot -RepositoryRoot $repositoryRoot -Name Dobby
    } else { $DobbySourceRoot }
    Il2CppInterop = if ([string]::IsNullOrWhiteSpace($Il2CppInteropSourceRoot)) {
        Get-AndroidDependencySourceRoot -RepositoryRoot $repositoryRoot -Name Il2CppInterop
    } else { $Il2CppInteropSourceRoot }
    HarmonyX = if ([string]::IsNullOrWhiteSpace($HarmonyXSourceRoot)) {
        Get-AndroidDependencySourceRoot -RepositoryRoot $repositoryRoot -Name HarmonyX
    } else { $HarmonyXSourceRoot }
    MonoMod = if ([string]::IsNullOrWhiteSpace($MonoModSourceRoot)) {
        Get-AndroidDependencySourceRoot -RepositoryRoot $repositoryRoot -Name MonoMod
    } else { $MonoModSourceRoot }
}

if ([string]::IsNullOrWhiteSpace($AndroidNdkRoot)) {
    $AndroidNdkRoot = $env:ANDROID_NDK_HOME
}

if ([string]::IsNullOrWhiteSpace($AndroidNdkRoot)) {
    throw "Set ANDROID_NDK_ROOT or ANDROID_NDK_HOME to an Android NDK installation."
}

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory)] [string]$Source,
        [Parameter(Mandatory)] [string]$Destination
    )

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Get-ChildItem -LiteralPath $Source -Force |
        Copy-Item -Destination $Destination -Recurse -Force
}

$outputRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "Output\$Configuration\linux-bionic-arm64"))
$packageRoot = [System.IO.Path]::GetFullPath((Join-Path $outputRoot "package"))
$expectedPrefix = $outputRoot.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar

if (-not $packageRoot.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to stage outside the Android output directory: '$packageRoot'."
}

$bootstrap = Join-Path $outputRoot "libmain.so"
$managedSource = Join-Path $outputRoot "MelonLoader"
if (-not (Test-Path -LiteralPath $bootstrap)) {
    throw "Build the Android bootstrap before staging the package."
}
if (-not (Test-Path -LiteralPath $managedSource)) {
    throw "Build the Android managed host before staging the package."
}

$managedRuntimeBuildRoot = if (-not [string]::IsNullOrWhiteSpace($CoreClrRuntimePackRoot)) {
    [System.IO.Path]::GetFullPath($CoreClrRuntimePackRoot)
}
else {
    Join-Path $repositoryRoot `
        "Output\Dependencies\dotnet-runtime\$DotnetRuntimeVersion\$managedRuntimeBackendId"
}
$managedRuntimeProvenancePath = Join-Path $managedRuntimeBuildRoot "runtime-provenance.json"
$runtimeManaged = Join-Path $managedRuntimeBuildRoot "managed"
$runtimeNative = Join-Path $managedRuntimeBuildRoot "native"
$managedRuntimeEngine = Join-Path $runtimeNative "libcoreclr.so"

if (-not (Test-Path -LiteralPath $runtimeManaged) -or
    -not (Test-Path -LiteralPath $runtimeNative)) {
    throw "The Android $managedRuntimeBackendId runtime pack is incomplete at '$managedRuntimeBuildRoot'."
}
if (-not (Test-Path -LiteralPath $managedRuntimeEngine -PathType Leaf)) {
    throw "The Android $managedRuntimeBackendId engine was not found at '$managedRuntimeEngine'."
}
if (-not (Test-Path -LiteralPath $managedRuntimeProvenancePath -PathType Leaf)) {
    throw "The Android managed runtime provenance was not found at '$managedRuntimeProvenancePath'."
}
foreach ($legalFile in @("LICENSE.TXT", "THIRD-PARTY-NOTICES.TXT")) {
    if (-not (Test-Path -LiteralPath (Join-Path $managedRuntimeBuildRoot $legalFile) -PathType Leaf)) {
        throw "The Android managed runtime attribution file '$legalFile' is missing."
    }
}
if (-not (Test-Path -LiteralPath `
    (Join-Path $runtimeNative "libSystem.Security.Cryptography.Native.Android.so") `
    -PathType Leaf)) {
    throw "The Android CoreCLR runtime pack is missing its source-built Android cryptography library."
}
$managedRuntimeProvenance = Get-Content -LiteralPath $managedRuntimeProvenancePath -Raw |
    ConvertFrom-Json
$managedRuntimeEngineHash = (Get-FileHash -LiteralPath $managedRuntimeEngine -Algorithm SHA256).Hash.ToLowerInvariant()
if ($managedRuntimeProvenance.formatVersion -ne 2 -or
    $managedRuntimeProvenance.runtimeVersion -cne $DotnetRuntimeVersion -or
    $managedRuntimeProvenance.backend -cne $managedRuntimeBackendId -or
    $managedRuntimeProvenance.sourceRevision -cne $ManagedRuntimeRevision -or
    $managedRuntimeProvenance.hostingModel -cne "coreclr-host-api" -or
    $managedRuntimeProvenance.engineSha256 -cne $managedRuntimeEngineHash) {
    throw "The Android $managedRuntimeBackendId output does not match the locked runtime source '$ManagedRuntimeRevision'."
}

if (Test-Path -LiteralPath $packageRoot) {
    Remove-Item -LiteralPath $packageRoot -Recurse -Force
}

$nativeOutput = Join-Path $packageRoot "lib\arm64-v8a"
$assetsOutput = Join-Path $packageRoot "assets"
$payloadOutput = Join-Path $assetsOutput "LemonLoader"
$runtimeOutput = Join-Path $payloadOutput "runtime"
$melonOutput = Join-Path $runtimeOutput "loader"
$dotnetOutput = Join-Path $runtimeOutput "dotnet"
$runtimeIdentityOutput = Join-Path $dotnetOutput "runtime-identity.json"
$deploymentOutput = Join-Path $payloadOutput "deployment"
$sharedRuntimeOutput = Join-Path $dotnetOutput `
    "shared\Microsoft.NETCore.App\$DotnetRuntimeVersion"
$patcherToolsOutput = Join-Path $packageRoot "tools\android"
$coreClrCryptoDexName = "lemonloader-coreclr-crypto.dex"
$coreClrCryptoDexOutput = Join-Path $patcherToolsOutput $coreClrCryptoDexName

New-Item -ItemType Directory -Force -Path $nativeOutput | Out-Null
Copy-Item -LiteralPath $bootstrap -Destination (Join-Path $nativeOutput "libmain.so")
foreach ($legalFile in @("LICENSE.md", "NOTICE.txt")) {
    $legalSource = Join-Path $repositoryRoot $legalFile
    if (-not (Test-Path -LiteralPath $legalSource -PathType Leaf)) {
        throw "The release attribution file '$legalFile' is missing."
    }
    Copy-Item -LiteralPath $legalSource -Destination (Join-Path $packageRoot $legalFile)
}
$dependencyLicenses = [ordered]@{
    "Dobby/LICENSE" = Join-Path $dependencySourceRoots.Dobby "LICENSE"
    "Il2CppInterop/LICENSE" = Join-Path $dependencySourceRoots.Il2CppInterop "LICENSE"
    "HarmonyX/LICENSE" = Join-Path $dependencySourceRoots.HarmonyX "LICENSE"
    "HarmonyX/LICENSE.Harmony" = Join-Path $dependencySourceRoots.HarmonyX "LICENSE.Harmony"
    "MonoMod/LICENSE" = Join-Path $dependencySourceRoots.MonoMod "LICENSE"
    "MonoMod.Common/LICENSE" = Join-Path $dependencySourceRoots.MonoMod "MonoMod.Common\LICENSE"
}
foreach ($license in $dependencyLicenses.GetEnumerator()) {
    $licenseSource = [IO.Path]::GetFullPath($license.Value)
    if (-not (Test-Path -LiteralPath $licenseSource -PathType Leaf)) {
        throw "The dependency attribution file '$($license.Key)' is missing at '$licenseSource'."
    }
    $licenseOutput = Join-Path $packageRoot ("licenses\" + $license.Key.Replace('/', '\'))
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $licenseOutput) | Out-Null
    Copy-Item -LiteralPath $licenseSource -Destination $licenseOutput
}
$runtimeLegalOutput = Join-Path $packageRoot "licenses\dotnet-runtime"
New-Item -ItemType Directory -Force -Path $runtimeLegalOutput | Out-Null
foreach ($legalFile in @("LICENSE.TXT", "THIRD-PARTY-NOTICES.TXT")) {
    Copy-Item -LiteralPath (Join-Path $managedRuntimeBuildRoot $legalFile) `
        -Destination (Join-Path $runtimeLegalOutput $legalFile)
}

Copy-DirectoryContents -Source $managedSource -Destination $melonOutput
$documentationPath = Join-Path $melonOutput "Documentation"
if (Test-Path -LiteralPath $documentationPath) {
    Remove-Item -LiteralPath $documentationPath -Recurse -Force
}
foreach ($deploymentDirectory in @("Mods", "Plugins", "UserLibs", "UserData")) {
    New-Item -ItemType Directory -Force `
        -Path (Join-Path $deploymentOutput $deploymentDirectory) | Out-Null
}

$desktopOnlyDirectories = @(
    (Join-Path $melonOutput "Dependencies\MonoBleedingEdgePatches"),
    (Join-Path $melonOutput "Dependencies\NetStandardPatches")
)
foreach ($desktopOnlyDirectory in $desktopOnlyDirectories) {
    if (Test-Path -LiteralPath $desktopOnlyDirectory) {
        Remove-Item -LiteralPath $desktopOnlyDirectory -Recurse -Force
    }
}

if ($Configuration -eq "Release") {
    Get-ChildItem -LiteralPath $melonOutput -Filter "*.pdb" -File -Recurse |
        Remove-Item -Force
}

$legacyInteropOutput = Join-Path $melonOutput "Il2CppAssemblies"
if (Test-Path -LiteralPath $legacyInteropOutput) {
    Remove-Item -LiteralPath $legacyInteropOutput -Recurse -Force
}
$interopOutput = Join-Path $runtimeOutput "interop"
if (Test-Path -LiteralPath $interopOutput) {
    Remove-Item -LiteralPath $interopOutput -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $interopOutput | Out-Null

New-Item -ItemType Directory -Force -Path $sharedRuntimeOutput | Out-Null

Get-ChildItem -LiteralPath $runtimeManaged -File |
    Copy-Item -Destination $sharedRuntimeOutput -Force
Get-ChildItem -LiteralPath $runtimeNative -File |
    Where-Object {
        $_.Extension -in @(".so", ".dex") -and
        $_.Name -ne "libhostfxr.so" -and
        $_.Name -ne "libSystem.Security.Cryptography.Native.OpenSsl.so" -and
        $_.Name -ne $coreClrCryptoDexName -and
        ($Configuration -ne "Release" -or
            $_.Name -notin @("libmscordaccore.so", "libmscordbi.so"))
    } |
    Copy-Item -Destination $sharedRuntimeOutput -Force
$coreClrCryptoDexSource = Join-Path $runtimeNative $coreClrCryptoDexName
if (-not (Test-Path -LiteralPath $coreClrCryptoDexSource -PathType Leaf)) {
    throw "The Android CoreCLR runtime pack is missing its crypto helper dex."
}
New-Item -ItemType Directory -Force -Path $patcherToolsOutput | Out-Null
Copy-Item -LiteralPath $coreClrCryptoDexSource `
    -Destination $coreClrCryptoDexOutput -Force
$coreLibSource = Join-Path $runtimeNative "System.Private.CoreLib.dll"
if (-not (Test-Path -LiteralPath $coreLibSource -PathType Leaf)) {
    $coreLibSource = Join-Path $runtimeManaged "System.Private.CoreLib.dll"
}
Copy-Item -LiteralPath $coreLibSource `
    -Destination $sharedRuntimeOutput -Force
Copy-Item -LiteralPath $managedRuntimeEngine `
    -Destination (Join-Path $sharedRuntimeOutput "libcoreclr.so") -Force
[ordered]@{
    formatVersion = 1
    runtimeVersion = $DotnetRuntimeVersion
    backend = $managedRuntimeBackendId
    hostingModel = "coreclr-host-api"
    engineFile = "libcoreclr.so"
    engineSha256 = $managedRuntimeEngineHash
} | ConvertTo-Json | Set-Content -LiteralPath $runtimeIdentityOutput -Encoding Utf8

$runtimeConfigs = Get-ChildItem -LiteralPath $melonOutput `
    -Filter "MelonLoader.runtimeconfig.json" -File -Recurse
if ($runtimeConfigs.Count -ne 1) {
    throw "Expected exactly one MelonLoader.runtimeconfig.json in the staged payload."
}

$runtimeConfig = Get-Content -LiteralPath $runtimeConfigs[0].FullName -Raw |
    ConvertFrom-Json
if ($runtimeConfig.runtimeOptions.rollForward -ne "LatestMajor") {
    throw "The Android runtimeconfig must explicitly use LatestMajor roll-forward."
}
$runtimeProperties = $runtimeConfig.runtimeOptions.configProperties
if ($managedRuntimeProvenance.hostingModel -cne "coreclr-host-api" -or
    $runtimeProperties.'System.Globalization.Invariant' -ne $true -or
    $runtimeProperties.'System.Globalization.PredefinedCulturesOnly' -ne $true -or
    $runtimeProperties.'System.Reflection.Metadata.MetadataUpdater.IsSupported' -ne $false) {
    throw "The Android CoreCLR runtime configuration does not match its direct native host."
}

$readElf = Get-AndroidNdkTool -AndroidNdkRoot $AndroidNdkRoot -Name "llvm-readelf"
$llvmNm = Get-AndroidNdkTool -AndroidNdkRoot $AndroidNdkRoot -Name "llvm-nm"
$nativeLibraries = Get-ChildItem -LiteralPath $packageRoot -Filter "*.so" -File -Recurse
foreach ($library in $nativeLibraries) {
    $elfOutput = & $readElf -h -l $library.FullName 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "llvm-readelf failed for '$($library.FullName)'."
    }

    $elfText = $elfOutput -join [Environment]::NewLine
    if ($elfText -notmatch '(?m)^\s*Machine:\s+AArch64\s*$') {
        throw "'$($library.FullName)' is not an AArch64 ELF library."
    }

    $segments = [regex]::Matches(
        $elfText,
        '(?m)^\s*LOAD\s+.*\s(0x[0-9a-fA-F]+)\s*$')
    $hasSmallLoadAlignment = $segments.Count -eq 0 -or
        [bool]($segments | Where-Object {
            [Convert]::ToInt64($_.Groups[1].Value, 16) -lt 0x4000
        })
    if ($hasSmallLoadAlignment) {
        throw "'$($library.FullName)' is not compatible with 16 KiB pages."
    }
}

$stagedBootstrap = Join-Path $nativeOutput "libmain.so"
$bootstrapDynamic = (& $readElf -d $stagedBootstrap 2>&1) -join [Environment]::NewLine
if ($LASTEXITCODE -ne 0) {
    throw "llvm-readelf failed while reading '$stagedBootstrap' dynamic dependencies."
}
if ($bootstrapDynamic -match '\(NEEDED\).*\[libc\+\+_shared\.so\]') {
    throw "The Android bootstrap still depends on public libc++_shared.so; build it with c++_static."
}
$bootstrapSymbols = (& $llvmNm -D --defined-only $stagedBootstrap 2>&1) -join [Environment]::NewLine
if ($LASTEXITCODE -ne 0) {
    throw "llvm-nm failed for '$stagedBootstrap'."
}
foreach ($requiredSymbol in @(
    "CreateArm64ValueReturnAdapter",
    "DestroyArm64ValueReturnAdapter",
    "ResolveArm64Il2CppInjectionTarget")) {
    if ($bootstrapSymbols -notmatch "(?m)\b$requiredSymbol\s*$") {
        throw "The staged Android bootstrap is missing '$requiredSymbol'."
    }
}

$stagedManagedRuntimeEngine = Join-Path $sharedRuntimeOutput "libcoreclr.so"
$managedRuntimeSymbols = & $llvmNm -D --defined-only $stagedManagedRuntimeEngine 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "llvm-nm failed for '$stagedManagedRuntimeEngine'."
}
$managedRuntimeSymbolText = $managedRuntimeSymbols -join [Environment]::NewLine
$hasMonoVmIdentity =
    $managedRuntimeSymbolText -match '(?m)\bmonovm_initialize\s*$' -and
    $managedRuntimeSymbolText -match '(?m)\bmono_jit_init_version\s*$'
$hasCoreClrIdentity =
    $managedRuntimeSymbolText -match '(?m)\bcoreclr_initialize(?:@@\S+)?\s*$' -and
    $managedRuntimeSymbolText -match '(?m)\bcoreclr_create_delegate(?:@@\S+)?\s*$' -and
    $managedRuntimeSymbolText -match '(?m)\bcoreclr_shutdown(?:@@\S+)?\s*$'
if (-not $hasCoreClrIdentity -or $hasMonoVmIdentity) {
    throw "The staged Android CoreCLR engine does not have an unambiguous CoreCLR identity."
}

function Get-PayloadTreeHash {
    param(
        [Parameter(Mandatory)] [string]$PayloadRoot,
        [Parameter(Mandatory)] [string]$Scope
    )

    $scopeRoot = Join-Path $PayloadRoot $Scope
    [string[]]$lines = @(
        if (Test-Path -LiteralPath $scopeRoot -PathType Container) {
            Get-ChildItem -LiteralPath $scopeRoot -File -Recurse |
                ForEach-Object {
                    $relativePath = [System.IO.Path]::GetRelativePath(
                        $PayloadRoot,
                        $_.FullName).Replace('\', '/')
                    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                    "$relativePath|$($_.Length)|$hash"
                }
        }
    )
    [Array]::Sort($lines, [StringComparer]::Ordinal)
    $hashPayload = @("layout-version=8", "scope=$Scope") + $lines
    $hashBytes = [System.Text.Encoding]::UTF8.GetBytes(($hashPayload -join "`n"))
    return [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($hashBytes)).ToLowerInvariant()
}

if (Test-Path -LiteralPath (Join-Path $melonOutput "Documentation")) {
    throw "Android Release must not contain 'Documentation'."
}

$payloadDescriptor = [ordered]@{
    formatVersion = 8
    loaderSha256 = Get-PayloadTreeHash -PayloadRoot $payloadOutput -Scope "runtime/loader"
    dotnetSha256 = Get-PayloadTreeHash -PayloadRoot $payloadOutput -Scope "runtime/dotnet"
    interopSha256 = Get-PayloadTreeHash -PayloadRoot $payloadOutput -Scope "runtime/interop"
    deploymentSha256 = Get-PayloadTreeHash -PayloadRoot $payloadOutput -Scope "deployment"
    managedRuntimeBackend = $managedRuntimeBackendId
    managedRuntimeIdentitySha256 = (Get-FileHash `
        -LiteralPath $runtimeIdentityOutput `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    coreClrCryptoDexSha256 = (Get-FileHash `
        -LiteralPath $coreClrCryptoDexOutput `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    deploymentProfile = "development"
    deploymentRevisionSha256 = [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes("deployment-revision=1"))).ToLowerInvariant()
    deploymentFiles = @()
    privateNativeLibraries = @()
}
$payloadDescriptor | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath (Join-Path $payloadOutput "payload.json") -Encoding Utf8

$manifestFiles = Get-ChildItem -LiteralPath $packageRoot -File -Recurse |
    Sort-Object FullName |
    ForEach-Object {
        [ordered]@{
            path = [System.IO.Path]::GetRelativePath($packageRoot, $_.FullName).Replace('\', '/')
            size = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
$manifest = [ordered]@{
    formatVersion = 2
    assetLayoutVersion = 8
    rid = "linux-bionic-arm64"
    abi = "arm64-v8a"
    configuration = $Configuration
    bootstrapFlavor = "Ndk"
    managedRuntimeVersion = $DotnetRuntimeVersion
    managedRuntimeBackend = $managedRuntimeBackendId
    managedRuntimeSourceRevision = $ManagedRuntimeRevision
    managedRuntimeEngineFile = "libcoreclr.so"
    managedRuntimeEngineSha256 = $managedRuntimeEngineHash
    gameAssembliesIncluded = $false
    files = $manifestFiles
}
$manifest | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath (Join-Path $packageRoot "lemonloader-release.json") -Encoding Utf8

Write-Host "Staged Android package tree:"
Write-Host "  $packageRoot"
Write-Host "  Bootstrap flavor: Ndk"
Write-Host "  .NET runtime: $DotnetRuntimeVersion ($managedRuntimeBackendId)"
Write-Host "  Native libraries checked: $($nativeLibraries.Count)"
Write-Host "  Game-specific Interop assemblies included: False"
