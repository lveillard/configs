param([Parameter(Mandatory)][string]$Box, [switch]$CheckOnly, [switch]$Sessions, [string]$Workspace, [switch]$NewWindow)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# One launcher for every box in ../boxes.json; -Box picks the entry.
$catalogue = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../boxes.json') -Raw | ConvertFrom-Json
$entry = $catalogue.boxes | Where-Object name -eq $Box
if (-not $entry) { throw "Unknown box '$Box'. Known: $($catalogue.boxes.name -join ', ')" }
$settings = [pscustomobject]@{
    subscriptionId = $entry.subscriptionId; resourceGroup = $entry.resourceGroup; vmName = $entry.name
    hostAlias = $entry.name; weztermGui = $catalogue.weztermGui
}
$stateDirectory = Join-Path $env:USERPROFILE (Join-Path '.local/state' $entry.stateDir)
$null = New-Item -ItemType Directory -Path $stateDirectory -Force
$logPath = Join-Path $stateDirectory 'launch.log'
$lock = [System.Threading.Mutex]::new($false, "Local\WezTerm-Remote-$($entry.name)")
$acquired = $false
. (Join-Path $PSScriptRoot 'process.ps1')

function Write-LaunchLog {
    param([string]$Message)
    Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format o) [PID $PID] $Message"
}

function Invoke-Remote {
    param([string]$Command, [int]$TimeoutSeconds = 12)
    $traceRoot = Join-Path $stateDirectory 'ssh-traces'
    $null = New-Item -ItemType Directory -Path $traceRoot -Force
    $tracePath = Join-Path $traceRoot "ssh-$PID-$([guid]::NewGuid().ToString('N')).log"
    $result = Invoke-BoundedProcess -FilePath $ssh -TimeoutSeconds $TimeoutSeconds -Arguments @(
        '-n', '-T', '-v', '-E', $tracePath, '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5',
        '-o', 'ConnectionAttempts=1', '-o', 'ServerAliveInterval=3',
        '-o', 'ServerAliveCountMax=2',
        $settings.hostAlias, $Command
    )
    if ($result.TimedOut) { Write-LaunchLog "SSH probe timed out after $TimeoutSeconds seconds." }
    if ($result.ExitCode -ne 0) {
        Write-LaunchLog "SSH exit $($result.ExitCode); diagnostic trace: $tracePath"
    } elseif (Test-Path -LiteralPath $tracePath) {
        Remove-Item -LiteralPath $tracePath -ErrorAction SilentlyContinue
    }
    return $result
}

function Invoke-Azure {
    param([string[]]$Arguments, [int]$TimeoutSeconds = 90)
    $azureCommand = (Get-Command az -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $azureArgs = @($Arguments) + @('--subscription', $settings.subscriptionId, '--only-show-errors')
    $azureEnvironment = @{}
    if ([System.IO.Path]::GetExtension($azureCommand) -eq '.cmd') {
        # Use the same interpreter and flags as the official MSI az.cmd wrapper.
        # ArgumentList avoids passing subscription data through cmd.exe quoting.
        $azureCommand = Join-Path (Split-Path -Parent $azureCommand) '../python.exe'
        if (-not (Test-Path -LiteralPath $azureCommand -PathType Leaf)) {
            throw 'No se encuentra el interprete de la instalacion de Azure CLI.'
        }
        $azureArgs = @('-IBm', 'azure.cli') + $azureArgs
        $azureEnvironment['AZ_INSTALLER'] = 'MSI'
    }
    $result = Invoke-BoundedProcess -FilePath $azureCommand -Arguments $azureArgs -Environment $azureEnvironment -TimeoutSeconds $TimeoutSeconds
    if ($result.TimedOut) {
        throw "Azure CLI no respondio en $TimeoutSeconds segundos. Vuelve a abrir el acceso directo; una operacion ya enviada a Azure puede seguir ejecutandose."
    }
    if ($result.ExitCode -ne 0) {
        throw "Azure CLI: $($result.Stderr.Trim()). Si la sesion ha caducado, ejecuta az login y vuelve a abrir el acceso directo."
    }
    return $result.Stdout
}

function Test-Remote {
    $result = Invoke-Remote -Command 'test -S ~/.local/state/wezterm/dev-server.sock'
    return ($result.ExitCode -eq 0)
}

try {
    try { $acquired = $lock.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $acquired = $true }
    if (-not $acquired) {
        Write-LaunchLog 'Another launch is already in progress.'
        if ($CheckOnly) {
            Write-Error 'Ya hay una apertura en curso; la comprobacion no se ha ejecutado.' -ErrorAction Continue
            exit 1
        }
        exit 0
    }
    Write-LaunchLog 'Checking SSH and the remote mux socket.'
    $ssh = Join-Path $env:WINDIR 'System32/OpenSSH/ssh.exe'
    if (-not (Test-Remote)) {
        Write-LaunchLog 'SSH unavailable; checking VM state.'
        $powerJson = Invoke-Azure -Arguments @('vm', 'get-instance-view', '--resource-group', $settings.resourceGroup, '--name', $settings.vmName, '--query', 'instanceView.statuses', '-o', 'json')
        $power = ($powerJson | ConvertFrom-Json | Where-Object code -like 'PowerState/*').code
        if ($power -in @('PowerState/deallocated', 'PowerState/stopped')) {
            Write-Output "Encendiendo $($settings.vmName)..."
            Write-LaunchLog 'Starting the VM.'
            $null = Invoke-Azure -Arguments @('vm', 'start', '--resource-group', $settings.resourceGroup, '--name', $settings.vmName, '-o', 'none') -TimeoutSeconds 180
        }
        Write-LaunchLog 'Retrying SSH over Tailscale.'
        $connected = $false
        for ($attempt = 0; $attempt -lt 12; $attempt++) {
            if (Test-Remote) { $connected = $true; break }
            Start-Sleep -Seconds 2
        }
        if (-not $connected) { throw "La VM no responde por SSH o su servicio WezTerm no esta disponible. Comprueba que Tailscale esta conectado, revisa launch.log y prueba ssh $($settings.hostAlias)." }
    }
    if ($CheckOnly) {
        $check = Invoke-Remote -Command 'hostname; uname -sr; systemctl is-active wezterm-mux.service; wezterm-mux-server --version'
        if ($check.ExitCode -ne 0) { throw 'La comprobacion remota fallo o agoto su tiempo de espera.' }
        Write-Output $check.Stdout.TrimEnd()
        Write-LaunchLog 'Remote check succeeded.'
        exit 0
    }
    Write-LaunchLog 'Reading remote sessions.'
    $paneResult = Invoke-Remote -Command 'timeout 10s env WEZTERM_UNIX_SOCKET="$HOME/.local/state/wezterm/dev-server.sock" wezterm cli --no-auto-start list --format json' -TimeoutSeconds 15
    if ($paneResult.ExitCode -ne 0) { throw 'No se pudo consultar la lista de sesiones del servidor dentro del tiempo de espera.' }
    $panes = @($paneResult.Stdout | ConvertFrom-Json)
    $workspaces = @($panes | ForEach-Object workspace | Sort-Object -Unique)
    $preferred = $Workspace
    $preferencePath = Join-Path $stateDirectory 'last-session.txt'
    if (-not $preferred -and (Test-Path -LiteralPath $preferencePath)) {
        $preferred = ([string](Get-Content -LiteralPath $preferencePath -Raw)).Trim()
    }
    $workspaceName = if ($preferred -and $preferred -in $workspaces) { $preferred }
        elseif ('default' -in $workspaces) { 'default' }
        elseif ($workspaces.Count -gt 0) { $workspaces[0] }
        else { 'default' }
    $gui = if ($settings.weztermGui) { $settings.weztermGui } else { Join-Path $env:ProgramFiles 'WezTerm/wezterm-gui.exe' }
    $gui = [System.IO.Path]::GetFullPath($gui)
    $configPath = Join-Path $PSScriptRoot 'wezterm.lua'
    if (-not $NewWindow -and -not $Workspace -and -not $Sessions) {
        $existing = Get-CimInstance Win32_Process -Filter "Name = 'wezterm-gui.exe'" |
            Where-Object { $_.ExecutablePath -eq $gui -and $_.CommandLine -match [regex]::Escape($configPath) -and $_.CommandLine -match ([regex]::Escape($settings.hostAlias) + '"?\s*$') } |
            Sort-Object CreationDate | Select-Object -First 1
        if ($existing) {
            $existingGui = Get-Process -Id $existing.ProcessId -ErrorAction SilentlyContinue
            if ($existingGui -and -not $existingGui.HasExited) {
                $handle = $existingGui.MainWindowHandle
                if ($handle -ne [IntPtr]::Zero) {
                    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WezTermRemoteWindow {
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr window, int command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
}
'@
                    if ([WezTermRemoteWindow]::IsIconic($handle)) { [void][WezTermRemoteWindow]::ShowWindowAsync($handle, 9) }
                    [void][WezTermRemoteWindow]::SetForegroundWindow($handle)
                }
                Write-LaunchLog "Reused existing WezTerm GUI PID $($existingGui.Id)."
                exit 0
            }
        }
    }
    $processInfo = [System.Diagnostics.ProcessStartInfo]::new($gui)
    $processInfo.UseShellExecute = $false
    $processInfo.WorkingDirectory = $env:USERPROFILE
    $processInfo.Environment.Clear()
    # A remote terminal needs Windows runtime paths, not API keys or agent state.
    foreach ($variable in @('SystemRoot', 'WINDIR', 'PATH', 'USERPROFILE', 'HOMEDRIVE', 'HOMEPATH', 'APPDATA', 'LOCALAPPDATA', 'ProgramData', 'ProgramFiles', 'ProgramFiles(x86)', 'ProgramW6432', 'CommonProgramFiles', 'CommonProgramFiles(x86)', 'CommonProgramW6432', 'TEMP', 'TMP', 'USERNAME', 'USERDOMAIN', 'COMSPEC', 'NUMBER_OF_PROCESSORS', 'PROCESSOR_ARCHITECTURE', 'OS', 'SESSIONNAME')) {
        $value = [Environment]::GetEnvironmentVariable($variable)
        if ($null -ne $value) { $processInfo.Environment[$variable] = $value }
    }
    $processInfo.Environment['WEZTERM_REMOTE_DOMAIN'] = $settings.hostAlias
    $processInfo.Environment['WEZTERM_REMOTE_LAUNCHER'] = $PSScriptRoot
    if ($Sessions -or $workspaces.Count -gt 1) {
        $processInfo.Environment['WEZTERM_REMOTE_SHOW_SESSIONS'] = '1'
    }
    foreach ($argument in @('--config-file', $configPath, 'connect', '--class', "org.wezfurlong.wezterm.remote-$($entry.label)", '--workspace', $workspaceName, $settings.hostAlias)) {
        $processInfo.ArgumentList.Add($argument)
    }
    $guiProcess = [System.Diagnostics.Process]::Start($processInfo)
    try {
        Write-LaunchLog "Started WezTerm GUI PID $($guiProcess.Id)."
        if ($guiProcess.WaitForExit(2000) -and $guiProcess.ExitCode -ne 0) {
            throw 'WezTerm se cerro durante el arranque. Consulta los registros de WezTerm y launch.log.'
        }
    } finally { $guiProcess.Dispose() }
} catch {
    $message = $_.Exception.Message
    # An error dialog can stay open indefinitely; it must not block another launch.
    if ($acquired) { $lock.ReleaseMutex(); $acquired = $false }
    Write-LaunchLog $message
    if ($CheckOnly) { Write-Error $message -ErrorAction Continue }
    else {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($message, 'WezTerm Remote', 'OK', 'Error') | Out-Null
    }
    exit 1
} finally {
    if ($acquired) { $lock.ReleaseMutex() }
    $lock.Dispose()
}
