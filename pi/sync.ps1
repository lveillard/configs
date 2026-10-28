#Requires -Version 7.0
<#
.SYNOPSIS
    Sincroniza la configuración de Pi entre este repo y los perfiles locales (~/.pi/agent*).

.DESCRIPTION
    Versiona solo lo que el usuario posee y no contiene credenciales:

        models.json     providers y modelos custom (pi no lo reescribe)
        settings.json   preferencias (pi SÍ lo reescribe: lastChangelogVersion, theme...)

    Nunca toca auth.json (contiene API keys), sessions/, bin/, npm/,
    models-store.json ni mcp-cache.json: esos son estado gestionado por Pi.

    Al comparar e instalar se ignora la clave lastChangelogVersion, que Pi
    actualiza en cada upgrade y generaría ruido constante.

.PARAMETER Push
    Repo -> perfil local. Conserva el lastChangelogVersion que ya tenga el perfil.

.PARAMETER Pull
    Perfil local -> repo. Úsalo para capturar cambios hechos desde dentro de pi
    (p. ej. /model, /login de un provider nuevo) antes de commitear.

.PARAMETER Target
    Directorio de perfil destino. Por defecto: $env:PI_CODING_AGENT_DIR
    o ~/.pi/agent-plus.

.PARAMETER AllProfiles
    Aplica a los perfiles comunes ~/.pi/agent y ~/.pi/agent-plus.

.EXAMPLE
    pwsh -File pi/sync.ps1
    Muestra drift entre el repo y el perfil activo. Exit code 1 si hay diferencias.

.EXAMPLE
    pwsh -File pi/sync.ps1 -Push
    Instala la config del repo en el perfil activo.

.EXAMPLE
    pwsh -File pi/sync.ps1 -Pull -Target ~/.pi/agent-plus
    Captura el estado de un perfil en el repo.
#>
[CmdletBinding(DefaultParameterSetName = 'Status')]
param(
    [Parameter(ParameterSetName = 'Push', Mandatory)]
    [switch]$Push,

    [Parameter(ParameterSetName = 'Pull', Mandatory)]
    [switch]$Pull,

    [string]$Target,

    [switch]$AllProfiles
)

$ErrorActionPreference = 'Stop'

$repoDir = $PSScriptRoot
$tracked = @('models.json', 'settings.json')
$ignoreKeys = @('lastChangelogVersion')

# Heuristic detection of common credential forms; review the diff before committing.
$secretPattern = 'sk-[A-Za-z0-9]{16,}|tp-[A-Za-z0-9]{16,}|gho_[A-Za-z0-9]+|"apiKey"\s*:\s*"[^$]'
function Assert-ConfigSource {
    param([string]$Path)
    $raw = Get-Content -LiteralPath $Path -Raw
    $null = $raw | ConvertFrom-Json
    if ($raw -match $secretPattern) {
        throw "Config source appears to contain a credential: $Path"
    }
}

function Get-NormalizedJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $obj = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($k in $ignoreKeys) {
        if ($obj.PSObject.Properties.Name -contains $k) { $obj.PSObject.Properties.Remove($k) }
    }
    return ($obj | ConvertTo-Json -Depth 100 -Compress)
}

function Resolve-Targets {
    if ($Target -and $AllProfiles) { throw 'Use either -Target or -AllProfiles.' }
    if ($Pull -and $AllProfiles) { throw 'Pull requires a single profile; use -Target.' }
    if ($Target) { return @((Resolve-Path -LiteralPath $Target).Path) }
    if ($AllProfiles) {
        $root = Join-Path $HOME '.pi'
        $dirs = Get-ChildItem -LiteralPath $root -Directory -Filter 'agent*' |
            Where-Object { $_.Name -in @('agent', 'agent-plus') }
        if (-not $dirs) { throw "No hay perfiles ~/.pi/agent* en $root" }
        return @($dirs | Select-Object -ExpandProperty FullName)
    }
    if ($env:PI_CODING_AGENT_DIR) { return @($env:PI_CODING_AGENT_DIR) }
    return @((Join-Path (Join-Path $HOME '.pi') 'agent-plus'))
}

$targets = @(Resolve-Targets)
$mode = $PSCmdlet.ParameterSetName
$drifted = 0

# Validate every source before writing any file, including profile-to-repo pulls.
foreach ($f in $tracked) {
    $source = if ($Pull) { Join-Path $targets[0] $f } else { Join-Path $repoDir $f }
    Assert-ConfigSource $source
}

Write-Host "modo: $mode" -ForegroundColor Cyan
Write-Host "repo: $repoDir"
Write-Host "tracked: $($tracked -join ', ')"

foreach ($t in $targets) {
    Write-Host "`n== $t ==" -ForegroundColor Cyan
    if (-not (Test-Path -LiteralPath $t)) { throw "Profile does not exist: $t" }

    foreach ($f in $tracked) {
        $repoPath = Join-Path $repoDir $f
        $livePath = Join-Path $t $f

        switch ($mode) {
            'Status' {
                $repoNorm = Get-NormalizedJson $repoPath
                $liveNorm = Get-NormalizedJson $livePath
                if ($null -eq $liveNorm) {
                    Write-Host "  [falta]  $f" -ForegroundColor Yellow
                    $drifted++
                }
                elseif ($repoNorm -ne $liveNorm) {
                    Write-Host "  [drift]  $f" -ForegroundColor Yellow
                    $drifted++
                }
                else {
                    Write-Host "  [ok]     $f" -ForegroundColor Green
                }
            }
            'Push' {
                $newObj = Get-Content -LiteralPath $repoPath -Raw | ConvertFrom-Json
                if (Test-Path -LiteralPath $livePath) {
                    $liveObj = Get-Content -LiteralPath $livePath -Raw | ConvertFrom-Json
                    foreach ($k in $ignoreKeys) {
                        $liveVal = $null
                        if ($liveObj.PSObject.Properties.Name -contains $k) { $liveVal = $liveObj.$k }
                        if ($null -ne $liveVal) {
                            if ($newObj.PSObject.Properties.Name -contains $k) { $newObj.$k = $liveVal }
                            else { $newObj | Add-Member -NotePropertyName $k -NotePropertyValue $liveVal }
                        }
                    }
                }
                ConvertTo-Json -InputObject $newObj -Depth 100 | Set-Content -LiteralPath $livePath -Encoding utf8NoBOM
                Write-Host "  [push]   $f" -ForegroundColor Green
            }
            'Pull' {
                if (-not (Test-Path -LiteralPath $livePath)) {
                    Write-Warning "  [skip]   $f (no existe en el perfil)"
                    continue
                }
                Copy-Item -LiteralPath $livePath -Destination $repoPath -Force
                Write-Host "  [pull]   $f" -ForegroundColor Green
            }
        }
    }
}

if ($mode -eq 'Status') {
    Write-Host ''
    if ($drifted -gt 0) {
        Write-Host "$drifted archivo(s) con diferencias. Instala con: pwsh -File pi/sync.ps1 -Push" -ForegroundColor Yellow
        exit 1
    }
    Write-Host 'Todo en sync.' -ForegroundColor Green
}
elseif ($mode -eq 'Pull') {
    Write-Host "`nRevisa con 'git -C $repoDir diff`' antes de commitear." -ForegroundColor Cyan
}
