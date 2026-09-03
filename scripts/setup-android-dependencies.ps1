[CmdletBinding()]
param(
    [string]$SourceRoot,

    [switch]$IncludeRuntime
)

$ErrorActionPreference = "Stop"
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
. (Join-Path $PSScriptRoot "common\AndroidDependencies.ps1")
$dependencies = Get-AndroidDependencies -RepositoryRoot $repositoryRoot
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Join-Path $repositoryRoot ".dependencies"
}
$sourceRoot = [IO.Path]::GetFullPath($SourceRoot)
[void][IO.Directory]::CreateDirectory($sourceRoot)

$sources = @(
    [pscustomobject]@{
        Name = "Dobby"
        Url = [string]$dependencies.AndroidDobbyRepositoryUrl
        Revision = [string]$dependencies.AndroidDobbyRevision
        Recursive = $false
    },
    [pscustomobject]@{
        Name = "Il2CppInterop"
        Url = [string]$dependencies.AndroidIl2CppInteropRepositoryUrl
        Revision = [string]$dependencies.AndroidIl2CppInteropRevision
        Recursive = $false
    },
    [pscustomobject]@{
        Name = "HarmonyX"
        Url = [string]$dependencies.AndroidHarmonyXRepositoryUrl
        Revision = [string]$dependencies.AndroidHarmonyXRevision
        Recursive = $false
    },
    [pscustomobject]@{
        Name = "MonoMod"
        Url = [string]$dependencies.AndroidMonoModRepositoryUrl
        Revision = [string]$dependencies.AndroidMonoModRevision
        Recursive = $true
    }
)
if ($IncludeRuntime) {
    $sources += [pscustomobject]@{
        Name = "runtime"
        Url = [string]$dependencies.AndroidDotnetRuntimeRepositoryUrl
        Revision = [string]$dependencies.AndroidDotnetRuntimeRevision
        Recursive = $false
    }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory)] [string]$WorkingDirectory,
        [Parameter(Mandatory)] [string[]]$Arguments
    )

    & git -C $WorkingDirectory @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed in '$WorkingDirectory'."
    }
}

foreach ($source in $sources) {
    $destination = [IO.Path]::GetFullPath((Join-Path $sourceRoot $source.Name))
    if (Test-Path -LiteralPath $destination) {
        if (-not (Test-Path -LiteralPath (Join-Path $destination ".git"))) {
            throw "Dependency path '$destination' is not a Git repository."
        }
        $changes = @(& git -C $destination status --porcelain)
        if ($LASTEXITCODE -ne 0 -or $changes.Count -gt 0) {
            throw "Dependency '$($source.Name)' has local changes; refusing to update it."
        }
        Invoke-Git -WorkingDirectory $destination -Arguments @(
            "fetch", "--no-tags", "origin", "main")
    }
    else {
        $staging = "$destination.staging-$([Guid]::NewGuid().ToString('N'))"
        try {
            & git clone --filter=blob:none --no-checkout --single-branch `
                --branch main $source.Url $staging
            if ($LASTEXITCODE -ne 0) {
                throw "Could not clone '$($source.Url)'."
            }
            [IO.Directory]::Move($staging, $destination)
        }
        finally {
            if (Test-Path -LiteralPath $staging) {
                $resolvedStaging = [IO.Path]::GetFullPath($staging)
                $sourcePrefix = $sourceRoot.TrimEnd('\', '/') +
                    [IO.Path]::DirectorySeparatorChar
                if (-not $resolvedStaging.StartsWith(
                        $sourcePrefix,
                        [StringComparison]::OrdinalIgnoreCase) -or
                    -not [IO.Path]::GetFileName($resolvedStaging).Contains(
                        ".staging-",
                        [StringComparison]::Ordinal)) {
                    throw "Refusing to clean unexpected staging path '$resolvedStaging'."
                }
                Remove-Item -LiteralPath $resolvedStaging -Recurse -Force
            }
        }
    }

    & git -C $destination cat-file -e "$($source.Revision)^{commit}"
    if ($LASTEXITCODE -ne 0) {
        throw "Revision '$($source.Revision)' is unavailable for '$($source.Name)'."
    }
    Invoke-Git -WorkingDirectory $destination -Arguments @(
        "checkout", "--detach", $source.Revision)
    if ($source.Recursive) {
        Invoke-Git -WorkingDirectory $destination -Arguments @(
            "submodule", "sync", "--recursive")
        Invoke-Git -WorkingDirectory $destination -Arguments @(
            "submodule", "update", "--init", "--recursive")
    }
    Write-Host "$($source.Name) @ $($source.Revision.Substring(0, 12))"
}

Write-Host "Android source dependencies are ready under '$sourceRoot'."
