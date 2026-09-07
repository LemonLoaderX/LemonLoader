[CmdletBinding()]
param(
    [string]$Distribution = "Ubuntu-24.04",

    [string]$AndroidNdkRoot = $env:ANDROID_NDK_ROOT,

    [string]$AndroidNdkLinuxRoot,

    [string]$RuntimeVersion,

    [string]$RuntimeRevision,

    [string]$SourceRoot,

    [string]$ExpectedSha256,

    [switch]$AllowDirtySource,

    [switch]$SkipHashValidation,

    [switch]$SkipBuild,
    [switch]$Legacy
)

$ErrorActionPreference = "Stop"
if (!$Legacy) { throw 'This is the frozen .NET 10 builder. Use workspace scripts/build-runtime.ps1, or explicitly select -Legacy for recovery.' }
. (Join-Path $PSScriptRoot "..\common\AndroidToolchain.ps1")
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
. (Join-Path $PSScriptRoot "..\common\AndroidDependencies.ps1")
. (Join-Path $PSScriptRoot "..\common\Wsl.ps1")
$dependencies = Get-AndroidDependencies -RepositoryRoot $repositoryRoot
$configuration = "Release"
if ([string]::IsNullOrWhiteSpace($RuntimeVersion)) {
    $RuntimeVersion = [string]$dependencies.AndroidDotnetRuntimeVersion
}
if ([string]::IsNullOrWhiteSpace($RuntimeRevision)) {
    $RuntimeRevision = [string]$dependencies.AndroidDotnetRuntimeRevision
}

& (Join-Path $PSScriptRoot "prepare-android-coreclr-toolchain.ps1") `
    -Distribution $Distribution

$wslCacheRoot = "$(Get-WslHome -Distribution $Distribution)/.cache/lemonloader"
if ([string]::IsNullOrWhiteSpace($AndroidNdkLinuxRoot)) {
    $AndroidNdkLinuxRoot = "$wslCacheRoot/android-ndk-r27d"
}
$toolchainJson = (& wsl.exe -d $Distribution -- `
    cat "$wslCacheRoot/android-coreclr-toolchain.json" 2>&1) -join "`n"
if ($LASTEXITCODE -ne 0) {
    throw "Could not read the prepared Android CoreCLR toolchain manifest."
}
$toolchain = $toolchainJson | ConvertFrom-Json
$AndroidSdkLinuxRoot = [string]$toolchain.androidSdkRoot
$JavaHomeLinux = [string]$toolchain.jdkRoot
$sdkApiLevel = [int]$toolchain.sdkApiLevel
$buildToolsVersion = [string]$toolchain.buildToolsVersion
if ([string]::IsNullOrWhiteSpace($AndroidSdkLinuxRoot) -or
    [string]::IsNullOrWhiteSpace($JavaHomeLinux) -or
    $sdkApiLevel -lt 21 -or
    $buildToolsVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "The prepared Android CoreCLR toolchain manifest is invalid."
}

function Assert-SafeLinuxPath {
    param([Parameter(Mandatory)] [string]$Path)

    if ($Path -notmatch '^/[A-Za-z0-9._+/-]+$' -or
        $Path.Contains('/../') -or
        $Path.EndsWith('/..', [StringComparison]::Ordinal)) {
        throw "The Linux toolchain path is not safe: '$Path'."
    }
}

function Convert-ToWslPath {
    param([Parameter(Mandatory)] [string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $converted = & wsl.exe -d $Distribution -- wslpath -a ($fullPath -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) {
        throw "Could not convert '$fullPath' to a WSL path."
    }
    return ($converted | Select-Object -Last 1).Trim()
}

function Get-RuntimeContentSha256 {
    param(
        [Parameter(Mandatory)] [string]$ManagedRoot,
        [Parameter(Mandatory)] [string]$NativeRoot
    )

    [string[]]$lines = @("runtime-pack-content=1")
    foreach ($scope in @(
        [pscustomobject]@{ Name = "managed"; Root = $ManagedRoot },
        [pscustomobject]@{ Name = "native"; Root = $NativeRoot })) {
        $files = Get-ChildItem -LiteralPath $scope.Root -File -Recurse
        if ($scope.Name -eq "native") {
            $files = $files | Where-Object {
                $_.Extension -in @(".so", ".dex") -or
                $_.Name -ceq "System.Private.CoreLib.dll"
            }
        }
        $lines += $files |
            ForEach-Object {
                $relativePath = [System.IO.Path]::GetRelativePath(
                    $scope.Root,
                    $_.FullName).Replace('\', '/')
                $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                "$($scope.Name)/$relativePath|$($_.Length)|$hash"
            }
    }
    [Array]::Sort($lines, 1, $lines.Length - 1, [StringComparer]::Ordinal)
    $contentHash = [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))))
    return $contentHash.ToLowerInvariant()
}

if ([string]::IsNullOrWhiteSpace($AndroidNdkRoot)) {
    $AndroidNdkRoot = $env:ANDROID_NDK_HOME
}
if ([string]::IsNullOrWhiteSpace($AndroidNdkRoot)) {
    throw "Set ANDROID_NDK_ROOT or pass -AndroidNdkRoot."
}
foreach ($path in @($AndroidNdkLinuxRoot, $AndroidSdkLinuxRoot, $JavaHomeLinux)) {
    Assert-SafeLinuxPath -Path $path
}

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Get-AndroidDependencySourceRoot `
        -RepositoryRoot $repositoryRoot -Name runtime
}
$SourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)
if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot ".git"))) {
    throw "The .NET runtime source checkout was not found at '$SourceRoot'."
}
$head = (& git -C $SourceRoot rev-parse HEAD).Trim()
$repositoryChanges = @(& git -C $SourceRoot status --porcelain --untracked-files=no)
if ($LASTEXITCODE -ne 0 -or $head -cne $RuntimeRevision -or
    (!$AllowDirtySource -and $repositoryChanges.Count -ne 0)) {
    throw "The .NET runtime source must be exactly at '$RuntimeRevision' and clean unless AllowDirtySource is explicit."
}

$sourceWsl = Convert-ToWslPath -Path $SourceRoot
$toolchainChecks = @(
    "$AndroidNdkLinuxRoot/toolchains/llvm/prebuilt/linux-x86_64/bin/clang",
    "$AndroidSdkLinuxRoot/platforms/android-$sdkApiLevel/android.jar",
    "$AndroidSdkLinuxRoot/build-tools/$buildToolsVersion/aapt2",
    "$JavaHomeLinux/bin/java"
)
foreach ($tool in $toolchainChecks) {
    & wsl.exe -d $Distribution -- bash -lc "test -e '$tool'"
    if ($LASTEXITCODE -ne 0) {
        throw "The isolated Android build tool was not found: '$tool'."
    }
}

$buildCommand =
    "./build.sh " +
    "clr.runtime+clr.corelib+clr.packages+libs " +
    "-os android -arch arm64 -c $configuration -p:PublishReadyToRun=false"
$shellScript = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "build-android-managed-runtime.sh"))
$shellScriptWsl = & wsl.exe -d $Distribution -- wslpath -a ($shellScript -replace '\\', '/')
if ($LASTEXITCODE -ne 0) {
    throw "Could not convert the CoreCLR build script path for WSL."
}
$shellScriptWsl = ($shellScriptWsl | Select-Object -Last 1).Trim()
if (-not $SkipBuild) {
    & wsl.exe -d $Distribution -- bash $shellScriptWsl `
        $sourceWsl `
        $AndroidNdkLinuxRoot `
        $AndroidSdkLinuxRoot `
        $JavaHomeLinux `
        $configuration
    if ($LASTEXITCODE -ne 0) {
        throw "The Android CoreCLR runtime build failed with exit code $LASTEXITCODE."
    }
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$shippingRoot = Join-Path $SourceRoot "artifacts\packages\$configuration\Shipping"
if (-not (Test-Path -LiteralPath $shippingRoot -PathType Container)) {
    throw "The upstream Shipping package directory was not produced: '$shippingRoot'."
}

$candidates = [System.Collections.Generic.List[object]]::new()
$escapedRuntimeVersion = [Regex]::Escape($RuntimeVersion)
foreach ($package in Get-ChildItem -LiteralPath $shippingRoot -Filter "*.nupkg" -File) {
    if ($package.Name.EndsWith(".symbols.nupkg", [StringComparison]::OrdinalIgnoreCase)) {
        continue
    }
    if ($package.Name -notmatch "\.$escapedRuntimeVersion(?:-|\.nupkg$)") {
        continue
    }
    $archive = [System.IO.Compression.ZipFile]::OpenRead($package.FullName)
    try {
        [string[]]$entries = @($archive.Entries.FullName)
        [string[]]$engineEntry = @(
            $entries | Where-Object { $_ -match '^runtimes/[^/]+/native/libcoreclr\.so$' })
        if ($engineEntry.Count -ne 1) {
            continue
        }
        $prefix = $engineEntry[0].Substring(
            0,
            $engineEntry[0].Length - "native/libcoreclr.so".Length)
        if ($entries -notcontains "${prefix}native/libclrjit.so" -or
            $entries -notcontains "${prefix}lib/net$(([Version]$RuntimeVersion).Major).0/System.Private.CoreLib.dll") {
            continue
        }
        $candidates.Add([pscustomobject]@{
            Package = $package
            Prefix = $prefix
            Entries = $entries
        })
    }
    finally {
        $archive.Dispose()
    }
}
if ($candidates.Count -ne 1) {
    throw "Expected one upstream Android CoreCLR runtime pack, found $($candidates.Count)."
}

$candidate = $candidates[0]
$managedPrefix = "$($candidate.Prefix)lib/net$(([Version]$RuntimeVersion).Major).0/"
$nativePrefix = "$($candidate.Prefix)native/"
if ($candidate.Entries -notcontains "${managedPrefix}System.Runtime.dll") {
    throw "The upstream Android CoreCLR pack does not contain its managed framework libraries."
}

$outputRoot = Join-Path $repositoryRoot `
    "Output\Dependencies\dotnet-runtime\$RuntimeVersion\coreclr"
$staging = "$outputRoot.staging-$([Guid]::NewGuid().ToString('N'))"
try {
    $managedOutput = Join-Path $staging "managed"
    $nativeOutput = Join-Path $staging "native"
    New-Item -ItemType Directory -Force -Path $managedOutput, $nativeOutput | Out-Null
    foreach ($legalFile in @("LICENSE.TXT", "THIRD-PARTY-NOTICES.TXT")) {
        $legalSource = Join-Path $SourceRoot $legalFile
        if (-not (Test-Path -LiteralPath $legalSource -PathType Leaf)) {
            throw "The runtime source attribution file '$legalFile' is missing."
        }
        Copy-Item -LiteralPath $legalSource -Destination (Join-Path $staging $legalFile)
    }

    $archive = [System.IO.Compression.ZipFile]::OpenRead($candidate.Package.FullName)
    try {
        $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($entry in $archive.Entries) {
            $destinationRoot = $null
            $relativePath = $null
            if ($entry.FullName.StartsWith($managedPrefix, [StringComparison]::Ordinal)) {
                $destinationRoot = $managedOutput
                $relativePath = $entry.FullName.Substring($managedPrefix.Length)
            }
            elseif ($entry.FullName.StartsWith($nativePrefix, [StringComparison]::Ordinal)) {
                $destinationRoot = $nativeOutput
                $relativePath = $entry.FullName.Substring($nativePrefix.Length)
            }
            if ([string]::IsNullOrEmpty($relativePath) -or $entry.FullName.EndsWith('/')) {
                continue
            }
            if ($relativePath.Contains('/') -or $relativePath.Contains('\') -or
                -not $seen.Add("$destinationRoot|$relativePath")) {
                throw "The upstream runtime pack contains an unsafe or duplicate entry: '$($entry.FullName)'."
            }

            $destination = Join-Path $destinationRoot $relativePath
            $input = $entry.Open()
            try {
                $output = [System.IO.File]::Open(
                    $destination,
                    [System.IO.FileMode]::CreateNew,
                    [System.IO.FileAccess]::Write,
                    [System.IO.FileShare]::None)
                try {
                    $input.CopyTo($output)
                }
                finally {
                    $output.Dispose()
                }
            }
            finally {
                $input.Dispose()
            }
        }
    }
    finally {
        $archive.Dispose()
    }

    $cryptoJar = Join-Path $nativeOutput "libSystem.Security.Cryptography.Native.Android.jar"
    $cryptoDex = Join-Path $nativeOutput "lemonloader-coreclr-crypto.dex"
    if (-not (Test-Path -LiteralPath $cryptoJar -PathType Leaf)) {
        throw "The upstream Android crypto support JAR was not found in the runtime pack."
    }
    $cryptoLoaderSource = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot `
        "MelonLoader.Bootstrap\Platforms\Android\Native\java\net\dot\android\crypto\LemonLoaderCryptoBootstrap.java"))
    $cryptoLoaderScript = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot `
        "build-android-coreclr-crypto-loader.sh"))
    $cryptoLoaderScriptWsl = (& wsl.exe -d $Distribution -- wslpath -a `
        ($cryptoLoaderScript -replace '\\', '/') | Select-Object -Last 1).Trim()
    $cryptoLoaderSourceWsl = (& wsl.exe -d $Distribution -- wslpath -a `
        ($cryptoLoaderSource -replace '\\', '/') | Select-Object -Last 1).Trim()
    $cryptoJarWsl = (& wsl.exe -d $Distribution -- wslpath -a `
        ($cryptoJar -replace '\\', '/') | Select-Object -Last 1).Trim()
    $cryptoDexWsl = (& wsl.exe -d $Distribution -- wslpath -a `
        ($cryptoDex -replace '\\', '/') | Select-Object -Last 1).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($cryptoDexWsl)) {
        throw "Converting the Android crypto loader paths for WSL failed."
    }
    & wsl.exe -d $Distribution -- bash $cryptoLoaderScriptWsl `
        $cryptoLoaderSourceWsl `
        $cryptoJarWsl `
        $cryptoDexWsl `
        $wslCacheRoot `
        $AndroidSdkLinuxRoot `
        $JavaHomeLinux
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $cryptoDex -PathType Leaf)) {
        throw "Building the Android CoreCLR crypto loader dex failed."
    }

    $engine = Join-Path $nativeOutput "libcoreclr.so"
    $jit = Join-Path $nativeOutput "libclrjit.so"
    $coreLib = Join-Path $managedOutput "System.Private.CoreLib.dll"
    foreach ($required in @($engine, $jit, $coreLib, (Join-Path $managedOutput "System.Runtime.dll"))) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "The normalized upstream Android pack is incomplete: '$required'."
        }
    }
    $engineHash = (Get-FileHash $engine -Algorithm SHA256).Hash.ToLowerInvariant()
    if (!$SkipHashValidation -and
        -not [string]::IsNullOrWhiteSpace($ExpectedSha256) -and
        $engineHash -cne $ExpectedSha256.ToLowerInvariant()) {
        throw "CoreCLR SHA-256 '$engineHash' does not match '$ExpectedSha256'."
    }

    $readElf = Get-AndroidNdkTool -AndroidNdkRoot $AndroidNdkRoot -Name "llvm-readelf"
    $llvmNm = Get-AndroidNdkTool -AndroidNdkRoot $AndroidNdkRoot -Name "llvm-nm"
    foreach ($nativeFile in Get-ChildItem -LiteralPath $nativeOutput -Filter "*.so" -File) {
        $elf = (& $readElf -h -lW $nativeFile.FullName 2>&1) -join [Environment]::NewLine
        if ($LASTEXITCODE -ne 0 -or $elf -notmatch '(?m)^\s*Machine:\s+AArch64\s*$') {
            throw "Upstream runtime native file '$($nativeFile.Name)' is not AArch64."
        }
        $segments = [regex]::Matches($elf, '(?m)^\s*LOAD\s+.*\s(0x[0-9a-fA-F]+)\s*$')
        if ($segments.Count -eq 0 -or [bool]($segments | Where-Object {
            [Convert]::ToInt64($_.Groups[1].Value, 16) -lt 0x4000
        })) {
            throw "Upstream runtime native file '$($nativeFile.Name)' is not 16 KiB page compatible."
        }
        $undefined = (& $llvmNm -D --undefined-only $nativeFile.FullName 2>&1) -join [Environment]::NewLine
        if ($undefined -match '(?m)\b__errno_location\b|\bGLIBC_[0-9]') {
            throw "Upstream runtime native file '$($nativeFile.Name)' contains glibc-only imports."
        }
    }

    $symbols = (& $llvmNm -D --defined-only $engine 2>&1) -join [Environment]::NewLine
    if ($symbols -notmatch '(?m)\bcoreclr_initialize(?:@@\S+)?\s*$' -or
        $symbols -notmatch '(?m)\bcoreclr_create_delegate(?:@@\S+)?\s*$' -or
        $symbols -notmatch '(?m)\bcoreclr_shutdown(?:@@\S+)?\s*$' -or
        $symbols -match '(?m)\bmonovm_initialize(?:@@\S+)?\s*$|\bmono_jit_init_version(?:@@\S+)?\s*$') {
        throw "The upstream runtime pack does not have an unambiguous CoreCLR identity."
    }

    $runtimeContentHash = Get-RuntimeContentSha256 `
        -ManagedRoot $managedOutput `
        -NativeRoot $nativeOutput

    $provenance = [ordered]@{
        formatVersion = 1
        runtimeVersion = $RuntimeVersion
        backend = "coreclr"
        sourceRevision = $RuntimeRevision
        buildCommand = $buildCommand
        hostingModel = "coreclr-host-api"
        packageFile = $candidate.Package.Name
        packageContentSha256 = $runtimeContentHash
        runtimePrefix = $candidate.Prefix
        engineSha256 = $engineHash
        coreLibSha256 = (Get-FileHash $coreLib -Algorithm SHA256).Hash.ToLowerInvariant()
        jitSha256 = (Get-FileHash $jit -Algorithm SHA256).Hash.ToLowerInvariant()
        cryptoLibrarySha256 = (Get-FileHash `
            (Join-Path $nativeOutput "libSystem.Security.Cryptography.Native.Android.so") `
            -Algorithm SHA256).Hash.ToLowerInvariant()
        cryptoJarSha256 = (Get-FileHash $cryptoJar -Algorithm SHA256).Hash.ToLowerInvariant()
        cryptoDexSha256 = (Get-FileHash $cryptoDex -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $provenance | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $staging "upstream-pack-provenance.json") -Encoding Utf8
    [ordered]@{
        formatVersion = 2
        runtimeVersion = $RuntimeVersion
        backend = "coreclr"
        sourceRevision = $RuntimeRevision
        buildCommand = $buildCommand
        hostingModel = "coreclr-host-api"
        engineFile = "libcoreclr.so"
        engineSha256 = $provenance.engineSha256
        baseRuntimePack = $candidate.Package.Name
        baseRuntimePackContentSha256 = $runtimeContentHash
    } | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $staging "runtime-provenance.json") -Encoding Utf8

    if (Test-Path -LiteralPath $outputRoot -PathType Container) {
        Remove-Item -LiteralPath $outputRoot -Recurse -Force
    }
    Move-Item -LiteralPath $staging -Destination $outputRoot
}
finally {
    if (Test-Path -LiteralPath $staging -PathType Container) {
        Remove-Item -LiteralPath $staging -Recurse -Force
    }
}

Write-Host "Built and normalized the Android CoreCLR runtime pack:"
Write-Host "  $outputRoot"
Write-Host "  Package: $($candidate.Package.Name)"
Write-Host "  Package file SHA-256: $((Get-FileHash $candidate.Package.FullName -Algorithm SHA256).Hash.ToLowerInvariant())"
Write-Host "  Runtime content SHA-256: $runtimeContentHash"
