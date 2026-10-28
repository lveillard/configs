param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
try {
    $remoteRoot = Split-Path -Parent $PSScriptRoot
    $settings = Get-Content -LiteralPath (Join-Path $remoteRoot 'server.json') -Raw | ConvertFrom-Json
    $pwsh = Join-Path $env:ProgramFiles 'PowerShell/7/pwsh.exe'
    $check = & $pwsh -NoProfile -NonInteractive -File (Join-Path $remoteRoot 'launch.ps1') -CheckOnly 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo conectar a la VM. Revisa WezTerm Remote/launch.log.' }
    $ssh = Join-Path $env:WINDIR 'System32/OpenSSH/ssh.exe'
    & $ssh -T -o BatchMode=yes -o ConnectTimeout=10 $settings.hostAlias 'test -x /home/devuser/.local/bin/dev'
    if ($LASTEXITCODE -ne 0) { throw 'El gestor dev no esta disponible en la VM.' }
    if ($CheckOnly) { Write-Output 'Dev Sessions: SSH y gestor disponibles.'; exit 0 }
    $start = [System.Diagnostics.ProcessStartInfo]::new($settings.weztermGui)
    $start.UseShellExecute = $false
    $start.WorkingDirectory = $env:USERPROFILE
    $start.Environment.Clear()
    foreach ($key in @('SystemRoot','WINDIR','PATH','USERPROFILE','HOMEDRIVE','HOMEPATH','APPDATA','LOCALAPPDATA','ProgramData','ProgramFiles','ProgramFiles(x86)','ProgramW6432','CommonProgramFiles','CommonProgramFiles(x86)','CommonProgramW6432','TEMP','TMP','USERNAME','USERDOMAIN','COMSPEC','NUMBER_OF_PROCESSORS','PROCESSOR_ARCHITECTURE','OS','SESSIONNAME')) {
        $value = [Environment]::GetEnvironmentVariable($key)
        if ($null -ne $value) { $start.Environment[$key] = $value }
    }
    foreach ($arg in @('--config-file',(Join-Path $PSScriptRoot 'wezterm.lua'),'start','--always-new-process','--class','org.wezfurlong.wezterm.devsessions')) { $start.ArgumentList.Add($arg) }
    [System.Diagnostics.Process]::Start($start) | Out-Null
} catch {
    if ($CheckOnly) { Write-Error 'No se pudo abrir Dev Sessions.' -ErrorAction Continue }
    else {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Dev Sessions','OK','Error') | Out-Null
    }
    exit 1
}
