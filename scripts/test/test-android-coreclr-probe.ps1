[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RuntimeRoot,
    [string]$Serial,
    [string]$AndroidSdkRoot = $env:ANDROID_SDK_ROOT,
    [string]$AndroidNdkRoot = $env:ANDROID_NDK_ROOT,
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\common\AndroidToolchain.ps1")

if ([string]::IsNullOrWhiteSpace($AndroidNdkRoot)) {
    $AndroidNdkRoot = $env:ANDROID_NDK_HOME
}
if ([string]::IsNullOrWhiteSpace($AndroidNdkRoot)) {
    throw "Set ANDROID_NDK_ROOT or pass -AndroidNdkRoot."
}
$runtimeInput = [System.IO.Path]::GetFullPath($RuntimeRoot)
$runtimeStaging = $null
try {
$upstreamProvenancePath = Join-Path $runtimeInput "upstream-pack-provenance.json"
if (Test-Path -LiteralPath $upstreamProvenancePath -PathType Leaf) {
    $upstreamProvenance = Get-Content -LiteralPath $upstreamProvenancePath -Raw |
        ConvertFrom-Json
    if ($upstreamProvenance.formatVersion -ne 1 -or
        $upstreamProvenance.backend -cne "coreclr" -or
        $upstreamProvenance.hostingModel -cne "coreclr-host-api") {
        throw "The normalized upstream runtime pack provenance is invalid."
    }
    $runtimeVersion = [string]$upstreamProvenance.runtimeVersion
    $runtimeStaging = Join-Path ([System.IO.Path]::GetTempPath()) `
        "lemonloader-coreclr-probe-$([Guid]::NewGuid().ToString('N'))"
    $sharedStaging = Join-Path $runtimeStaging `
        "shared\Microsoft.NETCore.App\$runtimeVersion"
    New-Item -ItemType Directory -Force -Path $sharedStaging | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $runtimeInput "managed") -File |
        Copy-Item -Destination $sharedStaging -Force
    Get-ChildItem -LiteralPath (Join-Path $runtimeInput "native") -File |
        Where-Object { $_.Extension -in @(".so", ".jar", ".dex") } |
        Copy-Item -Destination $sharedStaging -Force
    $provenance = [pscustomobject][ordered]@{
        formatVersion = 2
        runtimeVersion = $runtimeVersion
        backend = "coreclr"
        sourceRevision = $upstreamProvenance.sourceRevision
        buildCommand = $upstreamProvenance.buildCommand
        hostingModel = "coreclr-host-api"
        engineFile = "libcoreclr.so"
        engineSha256 = $upstreamProvenance.engineSha256
        baseRuntimePack = $upstreamProvenance.packageFile
        baseRuntimePackContentSha256 = $upstreamProvenance.packageContentSha256
    }
    $provenance | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $runtimeStaging "runtime-provenance.json") -Encoding Utf8
    $runtime = $runtimeStaging
}
else {
    $runtime = $runtimeInput
}
$provenancePath = Join-Path $runtime "runtime-provenance.json"
if (-not (Test-Path -LiteralPath $provenancePath -PathType Leaf)) {
    throw "Managed runtime provenance was not found at '$provenancePath'."
}
$provenance = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json
if ($provenance.formatVersion -ne 2 -or
    $provenance.backend -cne "coreclr" -or
    $provenance.hostingModel -cne "coreclr-host-api") {
    throw "The selected runtime is not a provenanced CoreCLR pack."
}
$runtimeVersion = [string]$provenance.runtimeVersion
$engine = Join-Path $runtime `
    "shared\Microsoft.NETCore.App\$runtimeVersion\libcoreclr.so"
if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) {
    throw "The CoreCLR engine was not found at '$engine'."
}
$engineHash = (Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash.ToLowerInvariant()
if ($engineHash -cne $provenance.engineSha256) {
    throw "The CoreCLR engine does not match runtime-provenance.json."
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$probeProject = Join-Path $repositoryRoot `
    "tests\Android\CoreClrProbe\Managed\CoreClrProbe.csproj"
$probeOutput = Join-Path $repositoryRoot `
    "tests\Android\CoreClrProbe\Managed\bin\Release"
$nativeSource = Join-Path $repositoryRoot `
    "tests\Android\CoreClrProbe\Native\coreclr_probe.cpp"
$nativeOutput = Join-Path $repositoryRoot "Output\CoreClrProbe\coreclr_probe"
New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($nativeOutput)) |
    Out-Null

dotnet build $probeProject --configuration Release
if ($LASTEXITCODE -ne 0) {
    throw "Building the managed CoreCLR probe failed with exit code $LASTEXITCODE."
}
$clang = Get-AndroidNdkTool -AndroidNdkRoot $AndroidNdkRoot -Name "clang++"
& $clang `
    --target=aarch64-linux-android23 `
    -std=c++17 `
    -O2 `
    -fPIE `
    -pie `
    -static-libstdc++ `
    "-Wl,-z,max-page-size=16384" `
    "-Wl,-z,common-page-size=16384" `
    $nativeSource `
    -o $nativeOutput
if ($LASTEXITCODE -ne 0) {
    throw "Building the native CoreCLR probe host failed with exit code $LASTEXITCODE."
}

$adb = Get-AndroidAdb -AndroidSdkRoot $AndroidSdkRoot
$Serial = Resolve-AndroidDeviceSerial -Adb $adb -Serial $Serial
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputPath = Join-Path $repositoryRoot "Output\CoreClrProbe\$timestamp"
}
$evidence = [System.IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
$remote = "/data/local/tmp/lemonloader-coreclr-probe-$([Guid]::NewGuid().ToString('N'))"

try {
    Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @("shell", "mkdir", "-p", "$remote/dotnet", "$remote/probe") |
        Out-Null
    Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @("push", "$runtime/.", "$remote/dotnet/") | Out-Null
    foreach ($file in @(
        "LemonLoader.CoreClrProbe.dll",
        "LemonLoader.CoreClrProbe.deps.json",
        "LemonLoader.CoreClrProbe.runtimeconfig.json")) {
        Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @("push", (Join-Path $probeOutput $file), "$remote/probe/$file") |
            Out-Null
    }
    Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @("push", $nativeOutput, "$remote/coreclr_probe") | Out-Null
    Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @("shell", "chmod", "700", "$remote/coreclr_probe") | Out-Null
    Invoke-AndroidAdb -Adb $adb -Serial $Serial -Arguments @("logcat", "-c") | Out-Null

    $shared = "$remote/dotnet/shared/Microsoft.NETCore.App/$runtimeVersion"
    $command =
        "export LD_LIBRARY_PATH='${shared}'; " +
        "exec '$remote/coreclr_probe' '$remote/dotnet' '$remote/probe' '$runtimeVersion'"
    $result = & $adb -s $Serial shell $command 2>&1
    $exitCode = $LASTEXITCODE
    [IO.File]::WriteAllText(
        (Join-Path $evidence "probe.log"),
        (@($result) -join [Environment]::NewLine),
        [Text.UTF8Encoding]::new($false))
    $logcat = & $adb -s $Serial logcat -d -v threadtime 2>&1
    @($logcat) | Set-Content -LiteralPath (Join-Path $evidence "logcat.txt") -Encoding Utf8
    $provenance | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $evidence "runtime-provenance.json") -Encoding Utf8
    [ordered]@{
        capturedAtUtc = [DateTimeOffset]::UtcNow.ToString("O")
        deviceSerial = $Serial
        runtimeVersion = $runtimeVersion
        backend = "coreclr"
        engineSha256 = $engineHash
        exitCode = $exitCode
    } | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $evidence "probe-metadata.json") -Encoding Utf8
    $combinedEvidence = (@($result) + @($logcat)) -join "`n"
    if ($exitCode -ne 0 -or
        -not ($combinedEvidence.Contains(
            "CORECLR_PROBE_PASS",
            [StringComparison]::Ordinal))) {
        throw "The Android CoreCLR probe failed. See '$evidence'."
    }

    Write-Host "Android CoreCLR probe passed:"
    Write-Host "  Device: $Serial"
    Write-Host "  Evidence: $evidence"
}
finally {
    & $adb -s $Serial shell rm -rf -- $remote 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not remove CoreCLR probe directory '$remote'."
    }
}
}
finally {
    if ($null -ne $runtimeStaging -and
        (Test-Path -LiteralPath $runtimeStaging -PathType Container)) {
        Remove-Item -LiteralPath $runtimeStaging -Recurse -Force
    }
}
