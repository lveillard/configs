$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'launch.ps1'
$pwsh = Join-Path $env:ProgramFiles 'PowerShell/7/pwsh.exe'
$settings = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'server.json') -Raw | ConvertFrom-Json
$shell = New-Object -ComObject WScript.Shell
foreach ($directory in @([Environment]::GetFolderPath('Desktop'),(Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs'))) {
    $path = Join-Path $directory 'Dev Sessions.lnk'
    if (Test-Path -LiteralPath $path) { throw "El acceso ya existe: $path" }
    $shortcut = $shell.CreateShortcut($path)
    $shortcut.TargetPath = $pwsh
    $shortcut.Arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -File "' + $scriptPath + '"'
    $shortcut.WorkingDirectory = $env:USERPROFILE
    $shortcut.IconLocation = $settings.weztermGui + ',0'
    $shortcut.Description = 'Terminales persistentes en dev-server-1: tmux, perfiles y zsh'
    $shortcut.Save()
    Write-Output $path
}
$command = Join-Path $env:USERPROFILE '.local/bin/dev-sessions.cmd'
if (Test-Path -LiteralPath $command) { throw "El comando ya existe: $command" }
@('@echo off', ('"' + $pwsh + '" -NoProfile -NonInteractive -WindowStyle Hidden -File "' + $scriptPath + '" %*')) | Set-Content -LiteralPath $command -Encoding ascii
Write-Output $command
