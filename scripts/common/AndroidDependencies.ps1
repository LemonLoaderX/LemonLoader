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
            (Join-Path $PSScriptRoot "..\..")),
        [string]$SourceRoot
    )

    if ($SourceRoot) { return [IO.Path]::GetFullPath($SourceRoot) }
    $dependencies = Get-AndroidDependencies -RepositoryRoot $RepositoryRoot -IncludeLegacyRuntime:($Name -eq 'runtime')
    $revisionProperty = if ($Name -eq 'runtime') { 'AndroidDotnetRuntimeRevision' } else { "Android${Name}Revision" }
    $revision = [string]$dependencies.$revisionProperty
    $directoryName = if ($Name -eq 'runtime') { 'dotnet-runtime' } else { $Name }
    $sibling = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot "../$directoryName"))
    if (Test-Path -LiteralPath (Join-Path $sibling '.git')) {
        $head = @(& git -C $sibling rev-parse HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and $head.Count -eq 1 -and $head[0].Trim() -ceq $revision) {
            return $sibling
        }
    }
    return [IO.Path]::GetFullPath((Join-Path $RepositoryRoot ".dependencies/$directoryName/$revision"))
}

function Assert-AndroidSourceCheckout {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Revision,
          [switch]$Recursive)
    if (!(Test-Path -LiteralPath (Join-Path $Path '.git'))) { throw "Source is not a Git checkout: '$Path'." }
    $head = @(& git -C $Path rev-parse HEAD)
    if ($LASTEXITCODE -ne 0 -or $head.Count -ne 1 -or $head[0].Trim() -cne $Revision) {
        throw "Source '$Path' does not match pinned revision '$Revision'; use a separate checkout."
    }
    $changes = @(& git -C $Path status --porcelain)
    if ($LASTEXITCODE -ne 0 -or $changes.Count) { throw "Source '$Path' has local changes; setup will not modify it." }
    if ($Recursive) {
        $submodules = @(& git -C $Path submodule status --recursive)
        if ($LASTEXITCODE -ne 0 -or @($submodules | Where-Object { $_ -notmatch '^ ' }).Count) {
            throw "Source '$Path' has missing or mismatched submodules; initialize them explicitly or use a private cache."
        }
    }
}

function Initialize-AndroidSourceCheckout {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Url,
          [Parameter(Mandatory)][string]$Revision, [switch]$Recursive)
    if (Test-Path -LiteralPath $Path) {
        Assert-AndroidSourceCheckout -Path $Path -Revision $Revision -Recursive:$Recursive
        return
    }
    $Path = [IO.Path]::GetFullPath($Path)
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    $staging = "$Path.staging-$([Guid]::NewGuid().ToString('N'))"
    try {
        & git -c core.longpaths=true clone --config core.longpaths=true --filter=blob:none --no-checkout $Url $staging
        if ($LASTEXITCODE -ne 0) { throw "Could not clone source '$Url'." }
        & git -C $staging cat-file -e "$Revision^{commit}" 2>$null
        if ($LASTEXITCODE -ne 0) {
            & git -C $staging fetch --no-tags origin $Revision
            if ($LASTEXITCODE -ne 0) { throw "Pinned revision '$Revision' is unavailable from '$Url'." }
        }
        & git -C $staging checkout --detach $Revision
        if ($LASTEXITCODE -ne 0) { throw "Could not check out pinned revision '$Revision'." }
        if ($Recursive) {
            & git -c core.longpaths=true -C $staging submodule update --init --recursive
            if ($LASTEXITCODE -ne 0) { throw "Could not initialize source submodules." }
            & git -C $staging submodule foreach --recursive 'git config core.longpaths true'
            if ($LASTEXITCODE -ne 0) { throw "Could not configure source submodule paths." }
        }
        Assert-AndroidSourceCheckout -Path $staging -Revision $Revision -Recursive:$Recursive
        [IO.Directory]::Move($staging, $Path)
    }
    finally {
        if (Test-Path -LiteralPath $staging) {
            $expected = [IO.Path]::GetFullPath("$Path.staging-")
            if (![IO.Path]::GetFullPath($staging).StartsWith($expected, [StringComparison]::Ordinal)) {
                throw "Refusing to clean an unexpected source staging path."
            }
            Remove-Item -LiteralPath $staging -Recurse -Force
        }
    }
}
