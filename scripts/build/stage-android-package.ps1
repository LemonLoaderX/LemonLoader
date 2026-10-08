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

    [string]$HarmonyXSourceRoot,
    [string]$JavaInteropSourceRoot,

    [ValidateSet('android','bionic')][string]$RuntimeProfile,
    [switch]$DevelopmentBuild
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\common\AndroidToolchain.ps1")
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
. (Join-Path $PSScriptRoot "..\common\AndroidDependencies.ps1")
$dependencies = Get-AndroidDependencies -RepositoryRoot $repositoryRoot
. (Join-Path $PSScriptRoot '../common/RuntimeProfiles.ps1')
$profile = Get-RuntimeProfile -Name $RuntimeProfile
$assetLayoutVersion = 9
$useOpenSsl = $profile.cryptoBackend -eq 'openssl'
if ([string]::IsNullOrWhiteSpace($DotnetRuntimeVersion)) {
    $DotnetRuntimeVersion = $profile.version
}
if ([string]::IsNullOrWhiteSpace($ManagedRuntimeRevision)) {
    $ManagedRuntimeRevision = $profile.revision
}
$managedRuntimeBackendId = "coreclr"
if ($DotnetRuntimeVersion -cne $profile.version -or $ManagedRuntimeRevision -cne $profile.revision) {
    throw 'Runtime version/revision conflicts with the selected profile.'
}
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

function Copy-NormalizedTextFile {
    param(
        [Parameter(Mandatory)] [string]$Source,
        [Parameter(Mandatory)] [string]$Destination
    )

    $text = [IO.File]::ReadAllText($Source).Replace("`r`n", "`n").Replace("`r", "`n")
    [IO.File]::WriteAllText($Destination, $text, [Text.UTF8Encoding]::new($false))
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
    Join-Path $repositoryRoot "Output/RuntimePacks/$($profile.revision)/$($profile.rid)"
}
$managedRuntimeProvenance = Test-RuntimeProfilePack -Root $managedRuntimeBuildRoot -Profile $profile -PassThru -Development:$DevelopmentBuild
$ManagedRuntimeRevision = $managedRuntimeProvenance.sourceRevision
$runtimeManaged = Join-Path $managedRuntimeBuildRoot "managed"
$runtimeNative = Join-Path $managedRuntimeBuildRoot "native"
$managedRuntimeEngine = Join-Path $runtimeNative "libcoreclr.so"

$managedRuntimeEngineHash = $managedRuntimeProvenance.engineSha256
$embeddedCrypto = $profile.name -eq 'android'
$bootstrapIdentity = Get-Content -LiteralPath (Join-Path $outputRoot 'bootstrap-crypto.json') -Raw | ConvertFrom-Json
if ($bootstrapIdentity.runtimeProfile -cne $profile.name -or
    $bootstrapIdentity.minimumAndroidApi -lt $profile.minimumApi -or
    $bootstrapIdentity.bootstrapSha256 -cne (Get-FileHash -LiteralPath $bootstrap).Hash.ToLowerInvariant()) {
    throw 'Bootstrap identity does not match the selected product profile.'
}
if ($embeddedCrypto -and
    ($bootstrapIdentity.cryptoDexSha256 -cne (Get-FileHash -LiteralPath (Join-Path $runtimeNative 'lemonloader-coreclr-crypto.dex')).Hash.ToLowerInvariant() -or
     $bootstrapIdentity.cryptoLibrarySha256 -cne (Get-FileHash -LiteralPath (Join-Path $runtimeNative 'libSystem.Security.Cryptography.Native.Android.so')).Hash.ToLowerInvariant())) {
    throw 'Bootstrap embedded crypto inputs differ from the selected runtime pack.'
}
if ($embeddedCrypto) {
    Test-BootstrapEmbeddedCrypto -Bootstrap $bootstrap -Dex (Join-Path $runtimeNative 'lemonloader-coreclr-crypto.dex')
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
$deploymentOutput = Join-Path $payloadOutput "deployment"
$sharedRuntimeOutput = Join-Path $dotnetOutput `
    "shared\Microsoft.NETCore.App\$DotnetRuntimeVersion"

New-Item -ItemType Directory -Force -Path $nativeOutput | Out-Null
Copy-Item -LiteralPath $bootstrap -Destination (Join-Path $nativeOutput "libmain.so")
foreach ($legalFile in @("LICENSE.md", "NOTICE.txt")) {
    $legalSource = Join-Path $repositoryRoot $legalFile
    if (-not (Test-Path -LiteralPath $legalSource -PathType Leaf)) {
        throw "The release attribution file '$legalFile' is missing."
    }
    Copy-NormalizedTextFile `
        -Source $legalSource `
        -Destination (Join-Path $packageRoot $legalFile)
}
$dependencyLicenses = [ordered]@{
    "Java.Interop/LICENSE" = Join-Path $(if ($JavaInteropSourceRoot) { $JavaInteropSourceRoot } else {
        Get-PinnedSourceRoot -Name DotnetAndroid -Revision $dependencies.JavaInteropRevision -RepositoryRoot $repositoryRoot
    }) 'external/Java.Interop/LICENSE'
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
    Copy-NormalizedTextFile -Source $licenseSource -Destination $licenseOutput
}
$runtimeLegalOutput = Join-Path $packageRoot "licenses\dotnet-runtime"
New-Item -ItemType Directory -Force -Path $runtimeLegalOutput | Out-Null
foreach ($legalFile in @("LICENSE.TXT", "THIRD-PARTY-NOTICES.TXT")) {
    Copy-NormalizedTextFile `
        -Source (Join-Path $managedRuntimeBuildRoot $legalFile) `
        -Destination (Join-Path $runtimeLegalOutput $legalFile)
}

Copy-DirectoryContents -Source $managedSource -Destination $melonOutput
if ($useOpenSsl) {
    $opensslLegalOutput = Join-Path $packageRoot 'licenses/OpenSSL'
    New-Item -ItemType Directory -Force -Path $opensslLegalOutput | Out-Null
    Copy-NormalizedTextFile -Source (Join-Path $managedRuntimeBuildRoot 'licenses/OpenSSL/LICENSE.txt') `
        -Destination (Join-Path $opensslLegalOutput 'LICENSE.txt')
}
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

if ($Configuration -eq "Release") {
    $sourceBuiltAssemblies = @(
        (Join-Path $melonOutput "net6\MelonLoader.dll"),
        (Join-Path $melonOutput "net6\Java.Interop.dll"),
        (Join-Path $melonOutput "net6\MelonLoader.NativeHost.dll"),
        (Join-Path $melonOutput "net6\Il2CppInterop.Common.dll"),
        (Join-Path $melonOutput "net6\Il2CppInterop.HarmonySupport.dll"),
        (Join-Path $melonOutput "net6\Il2CppInterop.Runtime.dll"),
        (Join-Path $melonOutput "net6\0Harmony.dll"),
        (Join-Path $melonOutput "net6\MonoMod.RuntimeDetour.dll"),
        (Join-Path $melonOutput "net6\MonoMod.Utils.dll"),
        (Join-Path $melonOutput "Dependencies\SupportModules\Il2Cpp.dll")
    )
    foreach ($assembly in $sourceBuiltAssemblies) {
        if (-not (Test-Path -LiteralPath $assembly -PathType Leaf)) {
            throw "The source-built Android assembly was not found at '$assembly'."
        }
        $stream = [IO.File]::OpenRead($assembly)
        $peReader = $null
        try {
            $peReader = [System.Reflection.PortableExecutable.PEReader]::new($stream)
            $privateDebugEntries = @($peReader.ReadDebugDirectory() | Where-Object {
                $_.Type -eq [System.Reflection.PortableExecutable.DebugDirectoryEntryType]::CodeView -or
                $_.Type -eq [System.Reflection.PortableExecutable.DebugDirectoryEntryType]::EmbeddedPortablePdb
            })
            if ($privateDebugEntries.Count -ne 0) {
                throw "The Android Release assembly '$assembly' contains embedded or path-bearing debug data."
            }
        }
        finally {
            if ($null -ne $peReader) { $peReader.Dispose() }
            $stream.Dispose()
        }
    }
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
        $_.Extension -eq ".so" -and
        $_.Name -ne "libhostfxr.so" -and
        ($useOpenSsl -or $_.Name -ne "libSystem.Security.Cryptography.Native.OpenSsl.so") -and
        ($Configuration -ne "Release" -or
            $_.Name -notin @("libmscordaccore.so", "libmscordbi.so"))
    } |
    Copy-Item -Destination $sharedRuntimeOutput -Force
$coreLibSource = Join-Path $runtimeNative "System.Private.CoreLib.dll"
if (-not (Test-Path -LiteralPath $coreLibSource -PathType Leaf)) {
    $coreLibSource = Join-Path $runtimeManaged "System.Private.CoreLib.dll"
}
Copy-Item -LiteralPath $coreLibSource `
    -Destination $sharedRuntimeOutput -Force
Copy-Item -LiteralPath $managedRuntimeEngine `
    -Destination (Join-Path $sharedRuntimeOutput "libcoreclr.so") -Force

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
$bootstrapSections = (& $readElf -S $stagedBootstrap 2>&1) -join [Environment]::NewLine
if ($LASTEXITCODE -ne 0) {
    throw "llvm-readelf failed while reading '$stagedBootstrap' sections."
}
if ($Configuration -eq "Release" -and
    $bootstrapSections -match '(?m)\.(?:debug_[A-Za-z0-9_.-]*|symtab|strtab)\b') {
    throw "The Android Release bootstrap contains debug or static symbol sections."
}
if ($Configuration -eq "Release" -and
    $bootstrapSections -notmatch '(?m)\.note\.gnu\.build-id\b') {
    throw "The Android Release bootstrap is missing its crash-symbol build ID."
}
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

$stagedHashes = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
function Get-StagedFileHash([string]$Path) {
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (!$stagedHashes.ContainsKey($fullPath)) {
        $stagedHashes[$fullPath] = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $stagedHashes[$fullPath]
}

if (Test-Path -LiteralPath (Join-Path $melonOutput "Documentation")) {
    throw "Android Release must not contain 'Documentation'."
}
if ((Get-StagedFileHash -Path $stagedManagedRuntimeEngine) -cne $managedRuntimeEngineHash) {
    throw 'The staged CoreCLR engine differs from the verified runtime pack.'
}

$payloadDescriptor = [ordered]@{ formatVersion = $assetLayoutVersion; runtimeRid = $profile.rid }
$payloadDescriptor | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath (Join-Path $payloadOutput "payload.json") -Encoding Utf8

$manifestFiles = Get-ChildItem -LiteralPath $packageRoot -File -Recurse |
    Sort-Object FullName |
    ForEach-Object {
        [ordered]@{
            path = [System.IO.Path]::GetRelativePath($packageRoot, $_.FullName).Replace('\', '/')
            size = $_.Length
            sha256 = Get-StagedFileHash -Path $_.FullName
        }
    }
$manifest = [ordered]@{
    formatVersion = 3
    runtimeRid = $profile.rid
    managedRuntimeVersion = $DotnetRuntimeVersion
    managedRuntimeSourceRevision = $ManagedRuntimeRevision
    minimumAndroidApi = $bootstrapIdentity.minimumAndroidApi
    developmentBuild = [bool]$DevelopmentBuild
    files = $manifestFiles
}
if ($DevelopmentBuild) {
    $sourceStates = foreach ($source in $dependencySourceRoots.GetEnumerator()) {
        $head = & git -C $source.Value rev-parse HEAD
        if ($LASTEXITCODE -ne 0) { throw "Cannot record source revision for $($source.Key)." }
        $changes = @(& git -C $source.Value status --porcelain)
        if ($LASTEXITCODE -ne 0) { throw "Cannot record source state for $($source.Key)." }
        @{ name=$source.Key; revision=$head; changes=$changes }
    }
    $sourceStates | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path (Split-Path $packageRoot) 'development-sources.json')
}
$manifest | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath (Join-Path $packageRoot "lemonloader-release.json") -Encoding Utf8

Write-Host "Staged Android package tree:"
Write-Host "  $packageRoot"
Write-Host "  Bootstrap flavor: Ndk"
Write-Host "  .NET runtime: $DotnetRuntimeVersion ($managedRuntimeBackendId)"
Write-Host "  Native libraries checked: $($nativeLibraries.Count)"
Write-Host "  Game-specific Interop assemblies included: False"
