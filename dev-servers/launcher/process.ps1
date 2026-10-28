function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [hashtable]$Environment = @{},
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = 15
    )
    $start = [System.Diagnostics.ProcessStartInfo]::new($FilePath)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    foreach ($name in $Environment.Keys) { $start.Environment[$name] = [string]$Environment[$name] }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        [void]$process.Start()
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) {
            # ConnectTimeout only covers connection setup, not a stalled SSH command.
            try { $process.Kill($true) } catch {
                if (-not $process.HasExited) { throw }
            }
            if (-not $process.WaitForExit(5000)) {
                throw 'No se pudo detener la comprobacion bloqueada.'
            }
        }
        [pscustomobject]@{
            ExitCode = if ($timedOut) { 124 } else { $process.ExitCode }
            TimedOut = $timedOut
            Stdout = $stdout.GetAwaiter().GetResult()
            Stderr = $stderr.GetAwaiter().GetResult()
        }
    } finally {
        $process.Dispose()
    }
}
