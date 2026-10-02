[CmdletBinding()]
param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Debug",

    [int]$AndroidApiLevel,

    [string]$AndroidNdkRoot = $env:ANDROID_NDK_ROOT,

    [string]$AndroidSdkRoot = $env:ANDROID_SDK_ROOT,

    [string]$DobbySourceRoot,

    [string]$DobbyRevision,

    [string]$ExpectedNdkRevision,
    [ValidateSet('android','bionic','legacy')][string]$RuntimeProfile,
    [string]$CoreClrRuntimePackRoot,
    [switch]$AllowDirtyDependencies
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\common\AndroidToolchain.ps1")
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
. (Join-Path $PSScriptRoot "..\common\AndroidDependencies.ps1")
$dependencies = Get-AndroidDependencies -RepositoryRoot $repositoryRoot
. (Join-Path $PSScriptRoot '../common/RuntimeProfiles.ps1')
$profile = Get-RuntimeProfile -Name $RuntimeProfile
if ($AndroidApiLevel -eq 0) {
    $AndroidApiLevel = [int]$profile.minimumApi
}
if ($AndroidApiLevel -lt $profile.minimumApi) { throw 'Android API is below the product minimum.' }
if ([string]::IsNullOrWhiteSpace($DobbyRevision)) {
    $DobbyRevision = [string]$dependencies.AndroidDobbyRevision
}
if ([string]::IsNullOrWhiteSpace($ExpectedNdkRevision)) {
    $ExpectedNdkRevision = [string]$dependencies.AndroidNdkRevision
}

if ([string]::IsNullOrWhiteSpace($AndroidNdkRoot)) {
    $AndroidNdkRoot = $env:ANDROID_NDK_HOME
}
if ([string]::IsNullOrWhiteSpace($AndroidNdkRoot)) {
    throw "Set ANDROID_NDK_ROOT or ANDROID_NDK_HOME to an Android NDK installation."
}

$ndkRoot = [System.IO.Path]::GetFullPath($AndroidNdkRoot)
$sourceProperties = Join-Path $ndkRoot "source.properties"
if (-not (Test-Path -LiteralPath $sourceProperties -PathType Leaf)) {
    throw "Android NDK was not found at '$ndkRoot'."
}
$sourcePropertiesText = Get-Content -LiteralPath $sourceProperties -Raw
$revisionMatch = [regex]::Match($sourcePropertiesText, '(?m)^Pkg\.Revision\s*=\s*(\S+)')
if (-not $revisionMatch.Success) {
    throw "Could not determine the Android NDK revision from '$sourceProperties'."
}
if ($ExpectedNdkRevision -and $revisionMatch.Groups[1].Value -ne $ExpectedNdkRevision) {
    throw "Android NDK $ExpectedNdkRevision is required, but '$ndkRoot' contains $($revisionMatch.Groups[1].Value)."
}

if ([string]::IsNullOrWhiteSpace($AndroidSdkRoot)) {
    $ndkParent = Split-Path -Parent $ndkRoot
    $AndroidSdkRoot = Split-Path -Parent $ndkParent
}
$sdkRoot = [System.IO.Path]::GetFullPath($AndroidSdkRoot)
$cmakeInstall = Get-ChildItem -LiteralPath (Join-Path $sdkRoot "cmake") `
    -Directory -ErrorAction SilentlyContinue |
    Sort-Object { [version]$_.Name } -Descending |
    Select-Object -First 1
if (-not $cmakeInstall) {
    throw "Install an Android SDK CMake package under '$sdkRoot\cmake'."
}
$cmake = Join-Path $cmakeInstall.FullName (
    "bin/{0}" -f (Get-HostExecutableName "cmake"))
$ninja = Join-Path $cmakeInstall.FullName (
    "bin/{0}" -f (Get-HostExecutableName "ninja"))
foreach ($tool in @($cmake, $ninja)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Required Android build tool was not found at '$tool'."
    }
}

if ([string]::IsNullOrWhiteSpace($DobbySourceRoot)) {
    $DobbySourceRoot = Get-AndroidDependencySourceRoot `
        -RepositoryRoot $repositoryRoot -Name Dobby
}
$dobbyRoot = [System.IO.Path]::GetFullPath($DobbySourceRoot)
if (-not (Test-Path -LiteralPath (Join-Path $dobbyRoot ".git"))) {
    throw "The complete Dobby source repository was not found at '$dobbyRoot'."
}
if (-not (Test-Path -LiteralPath (Join-Path $dobbyRoot "CMakeLists.txt") -PathType Leaf)) {
    throw "Dobby source at '$dobbyRoot' does not contain CMakeLists.txt."
}
$dobbyHead = (& git -C $dobbyRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or (!$AllowDirtyDependencies -and $dobbyHead -ne $DobbyRevision)) {
    throw "Dobby source HEAD '$dobbyHead' does not match '$DobbyRevision'."
}
$dobbyChanges = @(& git -C $dobbyRoot status --porcelain --untracked-files=no)
if ($LASTEXITCODE -ne 0 -or (!$AllowDirtyDependencies -and $dobbyChanges.Count -ne 0)) {
    throw "The Dobby source repository must be clean before building."
}
$sourceRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "MelonLoader.Bootstrap\Platforms\Android\Native"))
$buildRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryRoot "Output\NativeBuild\$Configuration\android-arm64"))
$outputRoot = Join-Path $repositoryRoot "Output\$Configuration\linux-bionic-arm64"

$cryptoDex = ''
$cryptoHash = $null
$dexHash = $null
if ($profile.name -eq 'android') {
    if (!$CoreClrRuntimePackRoot) {
        $CoreClrRuntimePackRoot = Join-Path $repositoryRoot "Output/RuntimePacks/$($profile.revision)/$($profile.rid)"
    }
    Test-RuntimeProfilePack -Root $CoreClrRuntimePackRoot -Profile $profile -Development:$AllowDirtyDependencies
    $cryptoDex = [IO.Path]::GetFullPath((Join-Path $CoreClrRuntimePackRoot 'native/lemonloader-coreclr-crypto.dex'))
    $magic = [IO.File]::ReadAllBytes($cryptoDex)
    if ($magic.Length -lt 112 -or [Text.Encoding]::ASCII.GetString($magic,0,4) -cne "dex`n") {
        throw 'The embedded crypto input is not a DEX file.'
    }
    $cryptoLibrary = Join-Path $CoreClrRuntimePackRoot 'native/libSystem.Security.Cryptography.Native.Android.so'
    $llvmNm = Get-AndroidNdkTool -AndroidNdkRoot $ndkRoot -Name 'llvm-nm'
    $exports = (& $llvmNm -D --defined-only $cryptoLibrary 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $exports -notmatch '(?m)\bAndroidCryptoNative_InitWithClassLoader\s*$') {
        throw 'Embedded crypto requires a rebuilt runtime pack with AndroidCryptoNative_InitWithClassLoader.'
    }
    $cryptoHash = (Get-FileHash -LiteralPath $cryptoLibrary).Hash.ToLowerInvariant()
    $dexHash = (Get-FileHash -LiteralPath $cryptoDex).Hash.ToLowerInvariant()
}

$cmakeCache = Join-Path $buildRoot "CMakeCache.txt"
if (Test-Path -LiteralPath $cmakeCache -PathType Leaf) {
    $cacheText = Get-Content -LiteralPath $cmakeCache -Raw
    $homeMatch = [regex]::Match($cacheText, '(?m)^CMAKE_HOME_DIRECTORY:INTERNAL=(.+)$')
    $cachedSourceRoot = if ($homeMatch.Success) {
        [System.IO.Path]::GetFullPath($homeMatch.Groups[1].Value.Trim())
    }
    else {
        ""
    }
    if ($cachedSourceRoot -cne $sourceRoot) {
        $expectedBuildRoot = [System.IO.Path]::GetFullPath(
            (Join-Path $repositoryRoot "Output\NativeBuild\$Configuration\android-arm64"))
        if ($buildRoot -cne $expectedBuildRoot) {
            throw "Refusing to clean an unexpected native build directory: '$buildRoot'."
        }
        Remove-Item -LiteralPath $buildRoot -Recurse -Force
    }
}
New-Item -ItemType Directory -Force -Path $buildRoot, $outputRoot | Out-Null

& $cmake `
    -S $sourceRoot `
    -B $buildRoot `
    -G Ninja `
    "-DCMAKE_MAKE_PROGRAM=$ninja" `
    "-DCMAKE_TOOLCHAIN_FILE=$ndkRoot\build\cmake\android.toolchain.cmake" `
    "-DANDROID_NDK=$ndkRoot" `
    -DANDROID_ABI=arm64-v8a `
    "-DANDROID_PLATFORM=android-$AndroidApiLevel" `
    -DANDROID_STL=c++_static `
    "-DLEMON_DOBBY_SOURCE_DIR=$dobbyRoot" `
    "-DLEMON_CRYPTO_DEX=$cryptoDex" `
    "-DCMAKE_BUILD_TYPE=$Configuration"
if ($LASTEXITCODE -ne 0) {
    throw "Configuring the pure NDK bootstrap failed with exit code $LASTEXITCODE."
}

& $cmake --build $buildRoot --config $Configuration
if ($LASTEXITCODE -ne 0) {
    throw "Building the pure NDK bootstrap failed with exit code $LASTEXITCODE."
}

$builtLibrary = Join-Path $buildRoot "libmain.so"
if (-not (Test-Path -LiteralPath $builtLibrary -PathType Leaf)) {
    throw "The pure NDK bootstrap was not produced at '$builtLibrary'."
}
$outputLibrary = Join-Path $outputRoot "libmain.so"
Copy-Item -LiteralPath $builtLibrary -Destination $outputLibrary -Force

if ($Configuration -eq "Release") {
    $llvmStrip = Get-AndroidNdkTool -AndroidNdkRoot $ndkRoot -Name "llvm-strip"
    & $llvmStrip --strip-all $outputLibrary
    if ($LASTEXITCODE -ne 0) {
        throw "Stripping the Android Release bootstrap failed with exit code $LASTEXITCODE."
    }
}

$readElf = Get-AndroidNdkTool -AndroidNdkRoot $ndkRoot -Name "llvm-readelf"
$buildIds = foreach ($library in @($builtLibrary, $outputLibrary)) {
    $notes = (& $readElf --notes $library 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Could not read bootstrap build ID: '$library'." }
    $match = [regex]::Match($notes, '(?m)^\s*Build ID:\s*([0-9a-fA-F]{40})\s*$')
    if (!$match.Success) { throw "Bootstrap build ID is missing or invalid: '$library'." }
    $match.Groups[1].Value.ToLowerInvariant()
}
if ($buildIds[0] -cne $buildIds[1]) { throw 'Stripping changed the bootstrap build ID.' }

& (Join-Path $PSScriptRoot "verify-android-bootstrap.ps1") `
    -LibraryPath $outputLibrary `
    -AndroidNdkRoot $ndkRoot `
    -AndroidApiLevel $AndroidApiLevel

if ($cryptoDex) { Test-BootstrapEmbeddedCrypto -Bootstrap $outputLibrary -Dex $cryptoDex }
@{ runtimeProfile=$profile.name; minimumAndroidApi=$AndroidApiLevel;
    bootstrapSha256=(Get-FileHash -LiteralPath $outputLibrary).Hash.ToLowerInvariant();
    cryptoLibrarySha256=$cryptoHash; cryptoDexSha256=$dexHash } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outputRoot 'bootstrap-crypto.json') -Encoding Utf8

Write-Host "Built pure NDK Android bootstrap:"
Write-Host "  $outputLibrary"
