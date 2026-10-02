$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $repositoryRoot 'scripts/common/AndroidDependencies.ps1')
$fixture = Join-Path $repositoryRoot "Output/Tests/SourceDependencies/$([Guid]::NewGuid().ToString('N'))"
[void][IO.Directory]::CreateDirectory($fixture)
function Assert-Equal($Expected, $Actual) {
    if ($Expected -cne $Actual) { throw "Expected '$Expected', got '$Actual'." }
}
function Assert-Rejected([scriptblock]$Action) {
    try { & $Action } catch { return }
    throw 'Expected source setup to reject the checkout.'
}
function Invoke-FixtureGit([string]$Path, [string[]]$Arguments) {
    & git -C $Path @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Fixture git failed: $Arguments" }
}
$origin = Join-Path $fixture 'origin'
[void][IO.Directory]::CreateDirectory($origin)
Invoke-FixtureGit $origin @('init', '--quiet')
Invoke-FixtureGit $origin @('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--quiet', '--allow-empty', '-m', 'first')
$first = (& git -C $origin rev-parse HEAD).Trim()
Invoke-FixtureGit $origin @('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--quiet', '--allow-empty', '-m', 'second')
$second = (& git -C $origin rev-parse HEAD).Trim()
$product = Join-Path $fixture 'Loader'
[void][IO.Directory]::CreateDirectory((Join-Path $product 'eng'))
[xml]$manifest = Get-Content -LiteralPath (Join-Path $repositoryRoot 'eng/AndroidDependencies.props') -Raw
$manifest.Project.PropertyGroup.AndroidIl2CppInteropRevision = $first
$manifest.Save((Join-Path $product 'eng/AndroidDependencies.props'))
$sibling = Join-Path $fixture 'Il2CppInterop'
Initialize-AndroidSourceCheckout -Path $sibling -Url $origin -Revision $first
Assert-Equal $sibling (Get-AndroidDependencySourceRoot -RepositoryRoot $product -Name Il2CppInterop)
Initialize-AndroidSourceCheckout -Path $sibling -Url 'https://invalid.example/never-fetch' -Revision $first
Invoke-FixtureGit $sibling @('checkout', '--quiet', '--detach', $second)
$cache = [IO.Path]::GetFullPath((Join-Path $product ".dependencies/Il2CppInterop/$first"))
Assert-Equal $cache (Get-AndroidDependencySourceRoot -RepositoryRoot $product -Name Il2CppInterop)
Initialize-AndroidSourceCheckout -Path $cache -Url $origin -Revision $first
Assert-Equal $second ((& git -C $sibling rev-parse HEAD).Trim())
Assert-Rejected { Initialize-AndroidSourceCheckout -Path $sibling -Url $origin -Revision $first }
[IO.File]::WriteAllText((Join-Path $cache 'local-work.txt'), 'keep')
Assert-Rejected { Initialize-AndroidSourceCheckout -Path $cache -Url $origin -Revision $first }
Assert-Equal 'keep' ([IO.File]::ReadAllText((Join-Path $cache 'local-work.txt')))
Assert-Equal $sibling (Get-AndroidDependencySourceRoot -RepositoryRoot $product -Name Il2CppInterop -SourceRoot $sibling)
$manifest.Project.PropertyGroup.AndroidIl2CppInteropRevision = $second
$manifest.Save((Join-Path $product 'eng/AndroidDependencies.props'))
Assert-Equal $sibling (Get-AndroidDependencySourceRoot -RepositoryRoot $product -Name Il2CppInterop)
$invalid = Join-Path $product '.dependencies/invalid'
Assert-Rejected { Initialize-AndroidSourceCheckout -Path $invalid -Url $origin -Revision ('0' * 40) }
if ((Test-Path -LiteralPath $invalid) -or @(Get-ChildItem -Path "$invalid.staging-*" -ErrorAction SilentlyContinue).Count) {
    throw 'Failed setup published or left staging output.'
}
$nestedOrigin = Join-Path $fixture 'nested-origin'
Initialize-AndroidSourceCheckout -Path $nestedOrigin -Url $origin -Revision $second
Invoke-FixtureGit $nestedOrigin @('-c', 'protocol.file.allow=always', 'submodule', 'add', '--quiet', $origin, 'nested')
Invoke-FixtureGit $nestedOrigin @('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--quiet', '-am', 'nested')
$nestedRevision = (& git -C $nestedOrigin rev-parse HEAD).Trim()
$incomplete = Join-Path $fixture 'incomplete'
Initialize-AndroidSourceCheckout -Path $incomplete -Url $nestedOrigin -Revision $nestedRevision
Assert-Rejected { Assert-AndroidSourceCheckout -Path $incomplete -Revision $nestedRevision -Recursive }
$priorProtocols = $env:GIT_ALLOW_PROTOCOL
try {
    $env:GIT_ALLOW_PROTOCOL = 'file'
    $complete = Join-Path $fixture 'complete'
    Initialize-AndroidSourceCheckout -Path $complete -Url $nestedOrigin -Revision $nestedRevision -Recursive
    Assert-AndroidSourceCheckout -Path $complete -Revision $nestedRevision -Recursive
} finally { $env:GIT_ALLOW_PROTOCOL = $priorProtocols }
Write-Host 'PASS independent Loader pins, matching/conflicting siblings, isolated caches, explicit roots and non-mutating setup'
