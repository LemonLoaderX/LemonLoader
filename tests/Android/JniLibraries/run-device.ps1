param(
    [Parameter(Mandatory)][string]$Serial,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$Adb = 'adb',
    [string]$PackageName = 'jp.co.fanzagames.dotabyss_x_a',
    [string[]]$Candidates = @('baseline', 'java-interop', 'jnet')
)
$ErrorActionPreference = 'Stop'
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $OutputPath) { throw 'Evidence directory already exists.' }
[void][IO.Directory]::CreateDirectory($OutputPath)
$base = "/sdcard/Android/data/$PackageName/files/MelonLoader"
$remote = "$base/UserData/JniLibraries"
$probe = "$base/Mods/JniLibraryProbe.dll"
function Invoke-Adb([string[]]$Arguments) {
    $result = & $Adb -s $Serial @Arguments 2>&1
    if ($LASTEXITCODE) { throw "ADB failed: $($result -join ' ')" }
    return $result
}
foreach ($path in @($remote, $probe, "$base/.jni-evaluation-mods")) {
    & $Adb -s $Serial shell test -e $path 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { throw "Refusing to overwrite $path" }
}
$isolated = $false
$createdRemote = $false
try {
    # Let a preceding APK replacement finish deployment extraction before isolation.
    Invoke-Adb @('shell','am','force-stop',$PackageName) | Out-Null
    Invoke-Adb @('shell','monkey','-p',$PackageName,'-c','android.intent.category.LAUNCHER','1') | Out-Null
    Start-Sleep -Seconds 20
    Invoke-Adb @('shell','am','force-stop',$PackageName) | Out-Null
    Invoke-Adb @('shell','mv',"$base/Mods","$base/.jni-evaluation-mods") | Out-Null
    $isolated = $true
    Invoke-Adb @('shell','mkdir',"$base/Mods",$remote) | Out-Null
    $createdRemote = $true
    Invoke-Adb @('push',"$PSScriptRoot/bin/DeviceProbe/Release/net10.0/JniLibraryProbe.dll",$probe) | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath "$PSScriptRoot/bin/Host/Release/net10.0" -Filter '*.dll') {
        Invoke-Adb @('push',$file.FullName,"$remote/$($file.Name)") | Out-Null
    }
    $failures = @()
    foreach ($candidate in $Candidates) {
        $local = Join-Path $OutputPath $candidate
        [void][IO.Directory]::CreateDirectory($local)
        [IO.File]::WriteAllText("$local/candidate.txt",$candidate)
        Invoke-Adb @('shell','am','force-stop',$PackageName) | Out-Null
        Invoke-Adb @('push',"$local/candidate.txt","$remote/candidate.txt") | Out-Null
        $started = [long]((Invoke-Adb @('shell','date','+%s')) -join '').Trim()
        Invoke-Adb @('shell','monkey','-p',$PackageName,'-c','android.intent.category.LAUNCHER','1') | Out-Null
        $deadline = [DateTime]::UtcNow.AddSeconds(45)
        $text = ''
        do {
            Start-Sleep -Milliseconds 1000
            $modified = [long]((Invoke-Adb @('shell','stat','-c','%Y',"$base/MelonLoader/Latest.log")) -join '').Trim()
            if ($modified -lt $started) { continue }
            $text = (Invoke-Adb @('shell','cat',"$base/MelonLoader/Latest.log")) -join "`n"
        } until (($text.Contains("PASS ALL $candidate") -and $text.Contains('FRAME after evaluation')) -or $text.Contains('FAIL JNI evaluation') -or [DateTime]::UtcNow -gt $deadline)
        Invoke-Adb @('pull',"$base/MelonLoader/Latest.log","$local/Latest.log") | Out-Null
        Invoke-Adb @('logcat','-d','-t','2000') | Set-Content -LiteralPath "$local/logcat.txt" -Encoding utf8
        $pidText = & $Adb -s $Serial shell pidof $PackageName 2>&1
        if ($LASTEXITCODE -or -not $text.Contains("PASS ALL $candidate") -or -not $text.Contains('FRAME after evaluation')) {
            $failures += $candidate
            Write-Host "FAIL $candidate process=$pidText"
        } else { Write-Host "PASS $candidate process=$pidText" }
    }
    if ($failures.Count) { throw "Failed candidates: $($failures -join ', ')" }
}
finally {
    Invoke-Adb @('shell','am','force-stop',$PackageName) | Out-Null
    if ($isolated) {
        Invoke-Adb @('shell','rm','-f',$probe) | Out-Null
        & $Adb -s $Serial shell rmdir "$base/Mods" 2>&1 | Out-Null
        if ($LASTEXITCODE) {
            # Preserve any APK-policy regenerated inputs before restoring originals.
            $extra = "$base/.jni-regenerated-$([Guid]::NewGuid().ToString('N'))"
            Invoke-Adb @('shell','mv',"$base/Mods",$extra) | Out-Null
            Invoke-Adb @('pull',$extra,"$OutputPath/regenerated-mods") | Out-Null
            Invoke-Adb @('shell','rm','-rf',$extra) | Out-Null
        }
        Invoke-Adb @('shell','mv',"$base/.jni-evaluation-mods","$base/Mods") | Out-Null
    }
    # Only this script's new, preflight-checked evaluation directory is removed.
    if ($createdRemote) { Invoke-Adb @('shell','rm','-rf',$remote) | Out-Null }
}
