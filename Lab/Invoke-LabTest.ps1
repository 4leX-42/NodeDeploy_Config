<#
.SYNOPSIS
    Ejecuta una prueba completa de NodeDeploy en la VM de laboratorio y trae los resultados.

.DESCRIPTION
    1. Revierte la VM al snapshot (por defecto '01-lenovo-baseline': Microsoft 365 for business de
       fabrica SIN Outlook clasico, como un Lenovo nuevo).
    2. Sincroniza el repo dentro de la VM (sin instaladores de antivirus).
    3. Lanza Deploy (v5 actual, o v4 de referencia sacado de git) con -SkipAV SIEMPRE.
    4. Copia informes, logs y traza de procesos a Lab\results\<fecha>_<etiqueta>\.
    Nada se instala en el host.

.EXAMPLE
    .\Invoke-LabTest.ps1                          # v5, snapshot baseline
    .\Invoke-LabTest.ps1 -Version v4 -Label antes # referencia v4.2.11 para comparar tiempos
    .\Invoke-LabTest.ps1 -ExtraArgs '-Serial'     # v5 sin carriles paralelos
#>
[CmdletBinding()]
param(
    [ValidateSet('v5','v4')][string]$Version = 'v5',
    [string]$Snapshot = '01-lenovo-baseline',
    [string]$ExtraArgs = '',
    [string]$Label,
    [switch]$Profile = $true,
    [switch]$KeepRunning,
    [switch]$NoRevert,
    [int]$HoldMsiSeconds = 0     # simula Windows Update reteniendo el mutex MSI N segundos al empezar
)

. (Join-Path $PSScriptRoot 'LabCommon.ps1')
$cfg = Get-LabConfig
if (-not $Label) { $Label = $Version }
$resDir = Join-Path $Script:LabRoot ("results\{0}_{1}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'), $Label)
New-Item -ItemType Directory -Force -Path $resDir | Out-Null
$t0 = Get-Date

if (-not $NoRevert) {
    if ((Get-LabSnapshots $cfg) -notcontains $Snapshot) { throw "Snapshot '$Snapshot' no existe. Ejecuta New-NodeDeployLab.ps1." }
    Write-LabLog "Revirtiendo a '$Snapshot'..." 'STEP'
    Invoke-Vmrun -Arguments @('revertToSnapshot', $cfg.VmxPath, $Snapshot) | Out-Null
}
if (-not (Test-LabRunning $cfg)) { Invoke-Vmrun -Arguments @('start', $cfg.VmxPath, 'nogui') | Out-Null }
Wait-LabTools -Config $cfg -TimeoutMin 15 | Out-Null
Set-LabShareToRepo -Config $cfg
Write-LabLog "VM lista (carpeta compartida -> $($Script:RepoRoot))" 'OK'

$sync = Invoke-LabGuestScript -Config $cfg -ScriptPath (Join-Path $Script:LabRoot 'guest\Sync-NodeDeploy.ps1')
if ($sync.ExitCode -ne 0) { throw "Sync fallo (exit $($sync.ExitCode))" }
Write-LabLog 'Repo sincronizado en C:\nodedeploy (sin instaladores AV)' 'OK'

if ($Version -eq 'v4') {
    # Referencia: Deploy.ps1 de v4.2.11 tal y como esta en git (HEAD antes de v5).
    $v4 = Join-Path $Script:LabRoot '_build\Deploy_v4.ps1'
    # cmd > fichero: bytes tal cual (evita que PowerShell recodifique los acentos UTF-8).
    & cmd.exe /c "git -C `"$($Script:RepoRoot)`" show b1594b0:NodeDeploy_Run/PRO/Deploy.ps1 > `"$v4`""
    if (-not (Test-Path $v4) -or (Get-Item $v4).Length -lt 10000) { throw 'No se pudo extraer Deploy.ps1 v4 de git (commit b1594b0)' }
    Copy-ToLabGuest -Config $cfg -HostPath $v4 -GuestPath 'C:\nodedeploy\NodeDeploy_Run\PRO\Deploy_v4.ps1'
}
Copy-ToLabGuest -Config $cfg -HostPath (Join-Path $Script:LabRoot 'guest\Watch-Processes.ps1') -GuestPath 'C:\LabRun\Watch-Processes.ps1'
Copy-ToLabGuest -Config $cfg -HostPath (Join-Path $Script:LabRoot 'guest\Hold-MsiMutex.ps1') -GuestPath 'C:\LabRun\Hold-MsiMutex.ps1'

$argLine = "-Version $Version"
if ($ExtraArgs) { $argLine += ' -ExtraArgsB64 ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($ExtraArgs)) }
if ($Profile)   { $argLine += ' -Profile' }
if ($HoldMsiSeconds -gt 0) { $argLine += " -HoldMsiSeconds $HoldMsiSeconds" }
Write-LabLog "Lanzando Deploy $Version $ExtraArgs dentro de la VM (sesion interactiva)..." 'STEP'
$run = Invoke-LabGuestScript -Config $cfg -ScriptPath (Join-Path $Script:LabRoot 'guest\Run-Deploy.ps1') -ScriptArgs $argLine -Interactive
Write-LabLog "Deploy termino exit=$($run.ExitCode)" $(if ($run.ExitCode -eq 0) { 'OK' } else { 'WARN' })

$zip = Join-Path $resDir 'artifacts.zip'
Copy-FromLabGuest -Config $cfg -GuestPath 'C:\LabRun\artifacts.zip' -HostPath $zip | Out-Null
if (Test-Path $zip) {
    Expand-Archive -Path $zip -DestinationPath $resDir -Force
    Remove-Item $zip -Force
}
$res = Get-ChildItem $resDir -Recurse -Filter 'result.json' | Select-Object -First 1
if ($res) {
    $r = Get-Content $res.FullName -Raw | ConvertFrom-Json
    Write-LabLog ("RESULTADO {0}: exit={1} duracion={2}s ({3:N1} min)" -f $r.version, $r.exit, $r.seconds, ($r.seconds / 60)) 'OK'
}
$report = Get-ChildItem $resDir -Recurse -Filter 'POSTVALIDATE_REPORT.md' | Select-Object -First 1
if ($report) { Write-LabLog "Informe: $($report.FullName)" 'INFO' }

if (-not $KeepRunning) { Invoke-Vmrun -Arguments @('stop', $cfg.VmxPath, 'hard') -AllowFail | Out-Null }
Write-LabLog ("Prueba completa en {0:N1} min. Resultados: {1}" -f ((Get-Date) - $t0).TotalMinutes, $resDir) 'OK'
