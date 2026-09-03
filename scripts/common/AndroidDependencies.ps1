function Get-AndroidDependencies {
    param(
        [string]$RepositoryRoot = [IO.Path]::GetFullPath(
            (Join-Path $PSScriptRoot "..\.."))
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
        "AndroidDotnetRuntimeArtifactUrl",
        "AndroidDotnetRuntimeArtifactSha256",
        "AndroidDobbyRevision",
        "AndroidIl2CppInteropVersion",
        "AndroidIl2CppInteropRevision",
        "AndroidHarmonyXVersion",
        "AndroidHarmonyXRevision",
        "AndroidMonoModVersion",
        "AndroidMonoModRevision")) {
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
        if ([string]$properties.$name -notmatch '^[0-9a-f]{40}$') {
            throw "Android dependency manifest property '$name' is not a Git revision."
        }
    }

    if ([string]$properties.AndroidDotnetRuntimeArtifactSha256 -notmatch '^[0-9a-f]{64}$') {
        throw "AndroidDotnetRuntimeArtifactSha256 is not a SHA-256 value."
    }
    $artifactUri = $null
    if (-not [Uri]::TryCreate(
        [string]$properties.AndroidDotnetRuntimeArtifactUrl,
        [UriKind]::Absolute,
        [ref]$artifactUri) -or
        $artifactUri.Scheme -ne "https") {
        throw "AndroidDotnetRuntimeArtifactUrl must be an absolute HTTPS URL."
    }

    return $properties
}
