function Get-AndroidNdkHostTag {
    if ($IsWindows) { return "windows-x86_64" }
    if ($IsLinux) { return "linux-x86_64" }
    if ($IsMacOS) { return "darwin-x86_64" }
    throw "The current host OS is not supported by the Android NDK scripts."
}

function Get-HostExecutableName {
    param([Parameter(Mandatory)] [string]$Name)
    if ($IsWindows) { return "$Name.exe" }
    return $Name
}

function Get-AndroidNdkTool {
    param(
        [Parameter(Mandatory)] [string]$AndroidNdkRoot,
        [Parameter(Mandatory)] [string]$Name
    )

    $tool = Join-Path $AndroidNdkRoot (
        "toolchains/llvm/prebuilt/{0}/bin/{1}" -f `
            (Get-AndroidNdkHostTag),
            (Get-HostExecutableName $Name))
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
        throw "Required Android NDK tool '$Name' was not found at '$tool'."
    }
    return $tool
}

function Get-AndroidSdkTool {
    param(
        [Parameter(Mandatory)] [string]$AndroidSdkRoot,
        [Parameter(Mandatory)] [string]$RelativePath,
        [Parameter(Mandatory)] [string]$CommandName
    )

    $candidate = Join-Path $AndroidSdkRoot $RelativePath
    if ($IsWindows) {
        $candidate = "$candidate.exe"
    }
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return $candidate
    }

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    throw "'$CommandName' was not found under '$AndroidSdkRoot' or on PATH."
}

function Get-AndroidAdb {
    param([string]$AndroidSdkRoot = $env:ANDROID_SDK_ROOT)

    if (-not [string]::IsNullOrWhiteSpace($AndroidSdkRoot)) {
        return Get-AndroidSdkTool `
            -AndroidSdkRoot $AndroidSdkRoot `
            -RelativePath "platform-tools/adb" `
            -CommandName "adb"
    }

    $command = Get-Command adb -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    throw "adb was not found. Set ANDROID_SDK_ROOT or add platform-tools to PATH."
}

function Resolve-AndroidDeviceSerial {
    param(
        [Parameter(Mandatory)] [string]$Adb,
        [string]$Serial
    )

    $deviceLines = & $Adb devices 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb devices failed with exit code $LASTEXITCODE."
    }

    $devices = @($deviceLines | ForEach-Object {
        if ($_ -match '^(\S+)\s+device\s*$') {
            $Matches[1]
        }
    })

    if (-not [string]::IsNullOrWhiteSpace($Serial)) {
        if ($devices -notcontains $Serial) {
            throw "Android device '$Serial' is not connected and authorized."
        }
        return $Serial
    }
    if ($devices.Count -eq 0) {
        throw "No authorized Android device is connected."
    }
    if ($devices.Count -gt 1) {
        throw "Multiple Android devices are connected; select one with -Serial."
    }
    return $devices[0]
}
