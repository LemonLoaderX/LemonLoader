#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('android', 'bionic')][string]$RuntimeProfile = 'android',
    [string]$SourceRoot
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common/AndroidDependencies.ps1')
. (Join-Path $PSScriptRoot 'common/RuntimeProfiles.ps1')
$profile = Get-RuntimeProfile -Name $RuntimeProfile
$source = Get-RuntimeSourceRoot -Profile $profile -SourceRoot $SourceRoot
Initialize-AndroidSourceCheckout -Path $source -Url (Get-RuntimeRepositoryUrl) -Revision $profile.revision -AllowUntracked
Write-Host "Runtime source: $source"
