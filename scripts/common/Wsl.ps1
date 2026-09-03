function Get-WslHome {
    param([Parameter(Mandatory)][string]$Distribution)

    $output = @(& wsl.exe -d $Distribution -- sh -lc 'printf %s "$HOME"' 2>&1)
    if ($LASTEXITCODE -ne 0 -or $output.Count -ne 1) {
        throw "Could not resolve the home directory for WSL distribution '$Distribution'."
    }

    $wslHome = $output[0].Trim()
    if ($wslHome -notmatch '^/[A-Za-z0-9._+/-]+$' -or $wslHome -eq "/") {
        throw "WSL returned an invalid home directory '$wslHome'."
    }
    return $wslHome.TrimEnd('/')
}
