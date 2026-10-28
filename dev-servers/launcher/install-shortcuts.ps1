# Desktop and Start shortcuts plus a wezterm-rem-<label> command for every box in ../boxes.json.
$ErrorActionPreference = 'Stop'
$catalogue = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../boxes.json') -Raw | ConvertFrom-Json
$shell = New-Object -ComObject WScript.Shell
$scriptPath = Join-Path $PSScriptRoot 'launch.ps1'
$pwsh = Join-Path $env:ProgramFiles 'PowerShell/7/pwsh.exe'
$binDir = Join-Path $env:USERPROFILE '.local/bin'
$null = New-Item -ItemType Directory -Path $binDir -Force
foreach ($box in $catalogue.boxes) {
    $arguments = '-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $scriptPath + '" -Box ' + $box.name
    foreach ($location in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {
        $shortcut = $shell.CreateShortcut((Join-Path $location ($box.shortcut + '.lnk')))
        $shortcut.TargetPath = $pwsh
        $shortcut.Arguments = $arguments
        $shortcut.WorkingDirectory = $env:USERPROFILE
        $shortcut.IconLocation = (Join-Path $env:ProgramFiles 'WezTerm/wezterm-gui.exe') + ',0'
        $shortcut.Description = "Terminales persistentes en $($box.name) ($($box.description))"
        $shortcut.WindowStyle = 7
        $shortcut.Save()
    }
    $command = if ($box.name -eq 'dev-server-1') { 'wezterm-rem' } else { "wezterm-rem-$($box.label)" }
    Set-Content -LiteralPath (Join-Path $binDir "$command.cmd") -Encoding ascii -Value "@echo off`r`nstart `"`" `"$pwsh`" $arguments"
    Write-Output "$($box.shortcut) -> $command"
}
