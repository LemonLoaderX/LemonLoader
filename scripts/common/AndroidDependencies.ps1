function Get-AndroidDependencies {
    param(
        [string]$RepositoryRoot = [IO.Path]::GetFullPath(
            (Join-Path $PSScriptRoot "..\..")),
        [switch]$IncludeLegacyRuntime
    )

    $manifestPath = Join-Path $RepositoryRoot "eng\AndroidDependencies.props"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Android dependency manifest was not found at '$manifestPath'."
    }

    [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
    $properties = $manifest.Project.PropertyGroup
    foreach ($name in @(
        "AndroidNdkRevision",
        "AndroidApiLevel",
        "AndroidDotnetRuntimeVersion",
        "AndroidDotnetRuntimeRevision",
        "AndroidDotnetRuntimeRepositoryUrl",
        "AndroidDotnetRuntimeArtifactUrl",
        "AndroidDotnetRuntimeArtifactSha256",
        "AndroidDobbyRevision",
        "AndroidDobbyRepositoryUrl",
        "AndroidIl2CppInteropVersion",
        "AndroidIl2CppInteropRevision",
        "AndroidIl2CppInteropRepositoryUrl",
        "AndroidHarmonyXVersion",
        "AndroidHarmonyXRevision",
        "AndroidHarmonyXRepositoryUrl",
        "AndroidMonoModVersion",
        "AndroidMonoModRevision",
        "AndroidMonoModRepositoryUrl")) {
        if (!$IncludeLegacyRuntime -and $name.StartsWith('AndroidDotnetRuntime')) { continue }
        if ([string]::IsNullOrWhiteSpace([string]$properties.$name)) {
            throw "Android dependency manifest property '$name' is missing."
        }
    }

    foreach ($name in @(
        "AndroidDotnetRuntimeRevision",
        "AndroidDobbyRevision",
        "AndroidIl2CppInteropRevision",
        "AndroidHarmonyXRevision",
        "AndroidMonoModRevision")) {
        if (!$IncludeLegacyRuntime -and $name.StartsWith('AndroidDotnetRuntime')) { continue }
        if ([string]$properties.$name -notmatch '^[0-9a-f]{40}$') {
            throw "Android dependency manifest property '$name' is not a Git revision."
        }
    }

    if ($IncludeLegacyRuntime -and [string]$properties.AndroidDotnetRuntimeArtifactSha256 -notmatch '^[0-9a-f]{64}$') {
        throw "AndroidDotnetRuntimeArtifactSha256 is not a SHA-256 value."
    }
    foreach ($name in @(
        "AndroidDotnetRuntimeRepositoryUrl",
        "AndroidDotnetRuntimeArtifactUrl",
        "AndroidDobbyRepositoryUrl",
        "AndroidIl2CppInteropRepositoryUrl",
        "AndroidHarmonyXRepositoryUrl",
        "AndroidMonoModRepositoryUrl")) {
        if (!$IncludeLegacyRuntime -and $name.StartsWith('AndroidDotnetRuntime')) { continue }
        $uri = $null
        if (-not [Uri]::TryCreate(
            [string]$properties.$name,
            [UriKind]::Absolute,
            [ref]$uri) -or
            $uri.Scheme -ne "https") {
            throw "$name must be an absolute HTTPS URL."
        }
    }

    return $properties
}

function Get-AndroidDependencySourceRoot {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Dobby", "Il2CppInterop", "HarmonyX", "MonoMod", "runtime")]
        [string]$Name,

        [string]$RepositoryRoot = [IO.Path]::GetFullPath(
            (Join-Path $PSScriptRoot "..\.."))
    )

    return [IO.Path]::GetFullPath(
        (Join-Path $RepositoryRoot ".dependencies\$Name"))
}
