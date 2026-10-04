param(
    [Parameter(Mandatory)][string]$JavaInteropSource,
    [Parameter(Mandatory)][string]$MelonLoaderAssemblyPath
)
$ErrorActionPreference = 'Stop'
$JavaInteropSource = [IO.Path]::GetFullPath($JavaInteropSource)
$MelonLoaderAssemblyPath = [IO.Path]::GetFullPath($MelonLoaderAssemblyPath)
dotnet build "$PSScriptRoot/Host.csproj" -c Release "-p:JavaInteropSource=$JavaInteropSource"
if ($LASTEXITCODE) { throw 'Building JNI evaluation host failed.' }
dotnet build "$PSScriptRoot/DeviceProbe.csproj" -c Release "-p:MelonLoaderAssemblyPath=$MelonLoaderAssemblyPath"
if ($LASTEXITCODE) { throw 'Building JNI evaluation Mod failed.' }
