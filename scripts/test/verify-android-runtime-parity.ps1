[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$LatestLog,

    [string]$RuntimeRoot,

    [string]$RequiredPreferenceFile,

    [string[]]$RequiredPreferenceSections = @(),

    [string[]]$ForbiddenLogPattern = @(),

    [switch]$RequireUnityLogs
)

$ErrorActionPreference = "Stop"
$logPath = [IO.Path]::GetFullPath($LatestLog)
if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) {
    throw "Latest.log was not found: $logPath"
}

$log = Get-Content -LiteralPath $logPath -Raw
$failures = [Collections.Generic.List[string]]::new()
$requiredSections = @(
    $RequiredPreferenceSections |
        ForEach-Object { $_ -split ',' } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.Trim() }
)

if ($log -match '\[DEBUG-[^]]+\]') {
    $failures.Add("Latest.log contains temporary [DEBUG-*] instrumentation.")
}
if ($log -match 'Transform::SetAsLastSibling|Melon Events might run before some MonoBehaviour Events') {
    $failures.Add("Latest.log contains the obsolete Android component sibling warning.")
}
if ($log -match 'Configured RuntimeDetour for Android CoreCLR|Initialized the source-built Android CoreCLR crypto bridge') {
    $failures.Add("Latest.log contains a low-value Android initialization message.")
}
if ($RequireUnityLogs -and $log -notmatch '(?m)\[UNITY\] ') {
    $failures.Add("Latest.log contains no captured Unity player log lines.")
}
if ($log -match '(?m)^\[[0-9:]+\] \[UNITY\].*\r?\n\r?\n') {
    $failures.Add("A captured Unity player log has an extra trailing blank line.")
}
if ($log -match '(?m)^\[[0-9:]+\] \[UNITY\].*This Game has been MODIFIED using MelonLoader') {
    $failures.Add("Latest.log recaptured MelonLoader's own Unity warning banner.")
}
foreach ($pattern in $ForbiddenLogPattern) {
    if ($log -match $pattern) {
        $failures.Add("Latest.log contains forbidden pattern: $pattern")
    }
}

if (-not [string]::IsNullOrWhiteSpace($RuntimeRoot)) {
    $root = [IO.Path]::GetFullPath($RuntimeRoot)
    $loaderConfig = Join-Path $root "UserData\Loader.cfg"
    $logsDirectory = Join-Path $root "MelonLoader\Logs"
    if (-not (Test-Path -LiteralPath $loaderConfig -PathType Leaf)) {
        $failures.Add("Loader configuration is missing: $loaderConfig")
    }
    else {
        $loaderConfigText = Get-Content -LiteralPath $loaderConfig -Raw
        foreach ($unsupported in @(
            '(?m)^\[console\]\s*$',
            '(?m)^\[mono_debug_server\]\s*$',
            '(?m)^disable\s*=',
            '(?m)^hostfxr_path_override\s*=',
            '(?m)^mono_search_path_override\s*=',
            '(?m)^mono_bleeding_edge_environment_patches\s*=',
            '(?m)^force_(offline_generation|generator_regex|il2cpp_dumper_version|regeneration)\s*=',
            '(?m)^enable_cpp2il_(call_analyzer|native_method_detector)\s*='
        )) {
            if ($loaderConfigText -match $unsupported) {
                $failures.Add("Loader.cfg contains an Android-inapplicable field or section: $unsupported")
            }
        }
    }
    if (-not (Test-Path -LiteralPath $logsDirectory -PathType Container)) {
        $failures.Add("Historical log directory is missing: $logsDirectory")
    }
    elseif (@(Get-ChildItem -LiteralPath $logsDirectory -Filter "*.log" -File).Count -eq 0) {
        $failures.Add("Historical log directory contains no log files: $logsDirectory")
    }

    if (-not [string]::IsNullOrWhiteSpace($RequiredPreferenceFile)) {
        $preferencePath = Join-Path $root "UserData\$RequiredPreferenceFile"
        if (-not (Test-Path -LiteralPath $preferencePath -PathType Leaf)) {
            $failures.Add("Required preference file is missing: $preferencePath")
        }
        else {
            $preferenceText = Get-Content -LiteralPath $preferencePath -Raw
            foreach ($section in $requiredSections) {
                if ($preferenceText -notmatch "(?m)^\[$([regex]::Escape($section))\]\s*$") {
                    $failures.Add("Required preference section is missing: [$section]")
                }
            }
        }
    }
}

if ($failures.Count -ne 0) {
    $failures | ForEach-Object { Write-Host "FAIL: $_" -ForegroundColor Red }
    exit 1
}

Write-Host "Android runtime parity log contract passed: $logPath"
