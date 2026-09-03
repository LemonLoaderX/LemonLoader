[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PackageName,

    [string]$Serial,

    [string]$SmokeModPath,

    [string]$HttpsProbeUrl,

    [ValidateRange(5, 120)]
    [int]$WaitSeconds = 20,

    [ValidateSet("Ndk")]
    [string]$ExpectedBootstrapFlavor = "Ndk",

    [string]$AndroidSdkRoot = $env:ANDROID_SDK_ROOT,

    [string]$OutputPath
)

$ErrorActionPreference = "Stop"
$expectedManagedRuntimeBackend = "coreclr"
. (Join-Path $PSScriptRoot "..\common\AndroidToolchain.ps1")

$adb = Get-AndroidAdb -AndroidSdkRoot $AndroidSdkRoot
$Serial = Resolve-AndroidDeviceSerial -Adb $adb -Serial $Serial

$checkParameters = @{
    PackageName = $PackageName
    AndroidSdkRoot = $AndroidSdkRoot
    Serial = $Serial
}
& (Join-Path $PSScriptRoot "check-android-device.ps1") @checkParameters

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputPath = Join-Path $repositoryRoot "Output\DeviceSmoke\$PackageName\$timestamp"
}
$outputDirectory = [System.IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

function Invoke-Adb {
    param([Parameter(Mandatory)] [string[]]$Arguments)

    $result = & $adb -s $Serial @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
    return @($result)
}

$remoteBase = "/sdcard/Android/data/$PackageName/files/MelonLoader"
$remoteLatestLog = "$remoteBase/MelonLoader/Latest.log"
$smokeMod = $null
if (-not [string]::IsNullOrWhiteSpace($SmokeModPath)) {
    $smokeMod = [System.IO.Path]::GetFullPath($SmokeModPath)
    if (-not (Test-Path -LiteralPath $smokeMod -PathType Leaf)) {
        throw "The smoke Mod was not found at '$smokeMod'."
    }
}

function Test-RemotePath {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [ValidateSet("Directory", "File")] [string]$PathType = "Directory"
    )

    $testArgument = if ($PathType -eq "Directory") { "-d" } else { "-f" }
    & $adb -s $Serial shell test $testArgument $Path 2>&1 | Out-Null
    return $LASTEXITCODE -eq 0
}

$remoteRestores = [System.Collections.Generic.List[object]]::new()
$restoreDirectory = Join-Path $outputDirectory ".restore"

function Protect-RemoteFile {
    param([Parameter(Mandatory)] [string]$Path)

    $exists = Test-RemotePath -Path $Path -PathType File
    $backup = $null
    if ($exists) {
        New-Item -ItemType Directory -Force -Path $restoreDirectory | Out-Null
        $backup = Join-Path $restoreDirectory "$($remoteRestores.Count).backup"
        Invoke-Adb -Arguments @("pull", $Path, $backup) | Out-Null
    }
    $remoteRestores.Add([pscustomobject]@{
        Path = $Path
        Existed = $exists
        Backup = $backup
    })
}

function Start-Package {
    Invoke-Adb -Arguments @("logcat", "-c") | Out-Null
    Invoke-Adb -Arguments @("shell", "am", "force-stop", $PackageName) | Out-Null
    Invoke-Adb -Arguments @(
        "shell", "monkey", "-p", $PackageName,
        "-c", "android.intent.category.LAUNCHER", "1") | Out-Null
}

$testError = $null
$cleanupErrors = [System.Collections.Generic.List[string]]::new()
try {
if ($smokeMod) {
    $remoteMods = "$remoteBase/Mods"
    if (-not (Test-RemotePath -Path $remoteMods)) {
        # The application must create its own app-scoped external directories.
        # Directories created by adb shell are owned by shell and are not
        # writable by the application on current Android releases.
        Start-Package
        $deadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
        while ([DateTime]::UtcNow -lt $deadline) {
            if ((Test-RemotePath -Path $remoteMods) -and
                (Test-RemotePath -Path $remoteLatestLog -PathType File)) {
                break
            }
            Start-Sleep -Milliseconds 500
        }
        Invoke-Adb -Arguments @("shell", "am", "force-stop", $PackageName) | Out-Null

        if (-not (Test-RemotePath -Path $remoteMods)) {
            throw "The application did not create '$remoteMods' during bootstrap."
        }
    }

    $remoteSmokeMod = "$remoteMods/AndroidSmokeMod.dll"
    Protect-RemoteFile -Path $remoteSmokeMod
    Invoke-Adb -Arguments @("push", $smokeMod, $remoteSmokeMod) | Out-Null
}
if (-not [string]::IsNullOrWhiteSpace($HttpsProbeUrl)) {
    if (-not $smokeMod) {
        throw "HttpsProbeUrl requires SmokeModPath."
    }
    if (-not [Uri]::TryCreate($HttpsProbeUrl, [UriKind]::Absolute, [ref]$null) -or
        -not $HttpsProbeUrl.StartsWith("https://", [StringComparison]::OrdinalIgnoreCase)) {
        throw "HttpsProbeUrl must be an absolute HTTPS URL."
    }

    $probeFile = Join-Path $outputDirectory "AndroidSmoke.https-url"
    Set-Content -LiteralPath $probeFile -Value $HttpsProbeUrl -Encoding Ascii -NoNewline
    $remoteProbeFile = "$remoteBase/UserData/AndroidSmoke.https-url"
    Protect-RemoteFile -Path $remoteProbeFile
    Invoke-Adb -Arguments @(
        "push",
        $probeFile,
        $remoteProbeFile) | Out-Null
}

$testStartedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Start-Package

Start-Sleep -Seconds $WaitSeconds

$screenshotPath = Join-Path $outputDirectory "screen.png"
$remoteScreenshot =
    "/sdcard/Download/lemonloader-smoke-$([Guid]::NewGuid().ToString('N')).png"
try {
    Invoke-Adb -Arguments @(
        "shell", "screencap", "-p", $remoteScreenshot) | Out-Null
    Invoke-Adb -Arguments @("pull", $remoteScreenshot, $screenshotPath) | Out-Null
    if (-not (Test-Path -LiteralPath $screenshotPath -PathType Leaf) -or
        (Get-Item -LiteralPath $screenshotPath).Length -eq 0) {
        throw "The device screenshot is missing or empty at '$screenshotPath'."
    }
}
finally {
    & $adb -s $Serial shell rm -f -- $remoteScreenshot 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $cleanupErrors.Add("Could not remove temporary device screenshot '$remoteScreenshot'.")
    }
}

$logcatPath = Join-Path $outputDirectory "logcat.txt"
$logcat = Invoke-Adb -Arguments @("logcat", "-d", "-v", "threadtime")
$logcat | Set-Content -LiteralPath $logcatPath -Encoding Utf8

$pidOutput = & $adb -s $Serial shell pidof $PackageName 2>&1
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($pidOutput -join ""))) {
    throw "The game process exited during the smoke-test window. See '$logcatPath'."
}
$processId = (($pidOutput -join " ").Trim() -split '\s+')[0]

$mapsOutput = & $adb -s $Serial shell run-as $PackageName cat "/proc/$processId/maps" 2>&1
if ($LASTEXITCODE -ne 0) {
    $mapsOutput = & $adb -s $Serial shell cat "/proc/$processId/maps" 2>&1
}
$externalProcessMapsCaptured = $LASTEXITCODE -eq 0
if (-not $externalProcessMapsCaptured -and -not $smokeMod) {
    throw "Could not capture /proc/$processId/maps for managed runtime verification."
}
$mapsPath = Join-Path $outputDirectory "process-maps.txt"
$mapsOutput | Set-Content -LiteralPath $mapsPath -Encoding Utf8
$managedRuntimeMaps = if ($externalProcessMapsCaptured) {
    @($mapsOutput | Where-Object {
        $_ -match '/dotnet/shared/Microsoft\.NETCore\.App/[^/]+/libcoreclr\.so(?:\s|$)'
    })
}
else {
    @()
}
if ($managedRuntimeMaps.Count -eq 0 -and -not $smokeMod) {
    throw "The loaded private managed runtime engine was not found in '$mapsPath'."
}

$remoteRuntimeIdentity = "/data/user/0/$PackageName/dotnet/runtime-identity.json"
$runtimeIdentityOutput = & $adb -s $Serial shell run-as $PackageName `
    cat $remoteRuntimeIdentity 2>&1
$runtimeIdentityCaptured = $LASTEXITCODE -eq 0
if (-not $runtimeIdentityCaptured -and -not $smokeMod) {
    throw "Could not read the extracted managed runtime identity from '$remoteRuntimeIdentity'."
}
$runtimeIdentityPath = Join-Path $outputDirectory "runtime-identity.json"
$runtimeIdentityOutput | Set-Content -LiteralPath $runtimeIdentityPath -Encoding Utf8
$runtimeIdentity = if ($runtimeIdentityCaptured) {
    Get-Content -LiteralPath $runtimeIdentityPath -Raw | ConvertFrom-Json
}
else {
    $null
}
if ($runtimeIdentityCaptured -and
    $runtimeIdentity.backend -cne $expectedManagedRuntimeBackend) {
    throw "Managed runtime identity backend '$($runtimeIdentity.backend)' does not match expected '$expectedManagedRuntimeBackend'."
}

$latestExists = & $adb -s $Serial shell test -f $remoteLatestLog
if ($LASTEXITCODE -ne 0) {
    throw "MelonLoader did not create '$remoteLatestLog'. See '$logcatPath'."
}

$latestTimestampOutput = Invoke-Adb -Arguments @(
    "shell", "stat", "-c", "%Y", $remoteLatestLog)
$latestTimestamp = 0L
if (-not [long]::TryParse(($latestTimestampOutput -join "").Trim(), [ref]$latestTimestamp) -or
    $latestTimestamp -lt ($testStartedAt - 2)) {
    throw "'$remoteLatestLog' was not updated by the current smoke-test launch."
}

$latestLogPath = Join-Path $outputDirectory "Latest.log"
Invoke-Adb -Arguments @("pull", $remoteLatestLog, $latestLogPath) | Out-Null
$latestLog = Get-Content -LiteralPath $latestLogPath -Raw

if ($latestLog -notmatch '(?m)(?:Lemon|Melon)Loader v\d') {
    throw "The managed loader startup banner was not found in '$latestLogPath'."
}

if ($ExpectedBootstrapFlavor -eq "Ndk" -and
    -not $latestLog.Contains(
        "Pure NDK Android bootstrap initialized",
        [StringComparison]::Ordinal)) {
    throw "The NDK bootstrap marker was not found in '$latestLogPath'."
}
if (-not $latestLog.Contains(
        "Managed runtime backend verified: $expectedManagedRuntimeBackend",
        [StringComparison]::Ordinal)) {
    throw "The verified managed runtime backend marker was not found in '$latestLogPath'."
}

if (-not [string]::IsNullOrWhiteSpace($SmokeModPath)) {
    $runtimeIdentityMarker =
        "[Android_Smoke_Mod] RuntimeIdentity CoreClr True MonoVm False Maps True"
    foreach ($marker in @(
        "[Android_Smoke_Mod] Initialize",
        $runtimeIdentityMarker,
        "[Android_Smoke_Mod] JniWorker 10006 True",
        "[Android_Smoke_Mod] SceneLoaded",
        "[Android_Smoke_Mod] FirstUpdate",
        "[Android_Smoke_Mod] FirstFixedUpdate",
        "[Android_Smoke_Mod] FirstLateUpdate")) {
        if (-not $latestLog.Contains($marker, [StringComparison]::Ordinal)) {
            throw "The lifecycle marker '$marker' was not found in '$latestLogPath'."
        }
    }
    $runtimeIdentityPattern =
        '(?m)^.*\[Android_Smoke_Mod\] RuntimeIdentityFile coreclr \S+ coreclr-host-api Hash True\s*$'
    if ($latestLog -notmatch $runtimeIdentityPattern) {
        throw "The same-process runtime identity marker was not found in '$latestLogPath'."
    }
}
if (-not [string]::IsNullOrWhiteSpace($HttpsProbeUrl) -and
    -not $latestLog.Contains("[Android_Smoke_Mod] HttpsRequest 200", [StringComparison]::Ordinal)) {
    throw "The managed HTTPS probe did not return HTTP 200. See '$latestLogPath'."
}

[ordered]@{
    capturedAtUtc = [DateTimeOffset]::UtcNow.ToString("O")
    deviceSerial = $Serial
    packageName = $PackageName
    processId = $processId
    bootstrapFlavor = $ExpectedBootstrapFlavor
    managedRuntimeBackend = $expectedManagedRuntimeBackend
    externalProcessMapsCaptured = $externalProcessMapsCaptured
    runtimeIdentityCaptured = $runtimeIdentityCaptured
    runtimeIdentity = $runtimeIdentity
} | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath (Join-Path $outputDirectory "smoke-metadata.json") -Encoding Utf8

Write-Host "Android startup smoke test passed:"
Write-Host "  Device: $Serial"
Write-Host "  Package: $PackageName"
Write-Host "  Managed runtime backend: $expectedManagedRuntimeBackend"
Write-Host "  Logs: $outputDirectory"
}
catch {
    $testError = $_
}
finally {
    if ($remoteRestores.Count -gt 0) {
        & $adb -s $Serial shell am force-stop $PackageName 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $cleanupErrors.Add("Could not stop '$PackageName' before restoring smoke-test files.")
        }

        for ($index = $remoteRestores.Count - 1; $index -ge 0; $index--) {
            $restore = $remoteRestores[$index]
            if ($restore.Existed) {
                & $adb -s $Serial push $restore.Backup $restore.Path 2>&1 | Out-Null
            }
            else {
                & $adb -s $Serial shell rm -f -- $restore.Path 2>&1 | Out-Null
            }
            if ($LASTEXITCODE -ne 0) {
                $cleanupErrors.Add("Could not restore smoke-test target '$($restore.Path)'.")
            }
        }
    }
    if (Test-Path -LiteralPath $restoreDirectory -PathType Container) {
        Remove-Item -LiteralPath $restoreDirectory -Recurse -Force
    }
}

if ($testError) {
    foreach ($cleanupError in $cleanupErrors) {
        Write-Warning $cleanupError
    }
    throw $testError
}
if ($cleanupErrors.Count -gt 0) {
    throw ($cleanupErrors -join [Environment]::NewLine)
}
