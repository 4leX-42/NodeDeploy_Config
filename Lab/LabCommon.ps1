<#
.SYNOPSIS
    Funciones comunes del laboratorio NodeDeploy (VM VMware Workstation controlada por vmrun).
.NOTES
    Todo lo que instala software se ejecuta DENTRO de la VM via vmrun. Nada de este modulo
    lanza instaladores en el host.
    Compatible con Windows PowerShell 5.1 y PowerShell 7.
#>

$ErrorActionPreference = 'Stop'

$Script:LabRoot     = $PSScriptRoot
$Script:RepoRoot    = Split-Path -Parent $PSScriptRoot
$Script:LabLocalCfg = Join-Path $Script:LabRoot 'lab.local.json'
$Script:VmrunExe    = @(
    "${env:ProgramFiles(x86)}\VMware\VMware Workstation\vmrun.exe",
    "$env:ProgramFiles\VMware\VMware Workstation\vmrun.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

function Get-LabConfig {
    if (-not (Test-Path $Script:LabLocalCfg)) {
        throw "No existe $($Script:LabLocalCfg). Ejecuta primero New-NodeDeployLab.ps1."
    }
    $cfg = Get-Content $Script:LabLocalCfg -Raw | ConvertFrom-Json
    if (-not (Test-Path $cfg.VmxPath)) { throw "VM no encontrada: $($cfg.VmxPath)" }
    return $cfg
}

function Write-LabLog {
    param([string]$Message, [ValidateSet('INFO','OK','WARN','ERROR','STEP')][string]$Level = 'INFO')
    $color = @{ INFO='Gray'; OK='Green'; WARN='Yellow'; ERROR='Red'; STEP='Cyan' }[$Level]
    Write-Host ("{0} [{1}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message) -ForegroundColor $color
}

function Invoke-Vmrun {
    <#
        Wrapper de vmrun. -Guest anade credenciales del invitado. Devuelve @{ExitCode; Output}.
        -AllowFail evita throw cuando vmrun devuelve error.
    #>
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$Guest,
        [switch]$AllowFail,
        $Config
    )
    if (-not $Script:VmrunExe) { throw 'vmrun.exe no encontrado (VMware Workstation instalado?)' }
    $all = @('-T', 'ws')
    if ($Guest) {
        if (-not $Config) { $Config = Get-LabConfig }
        $all += @('-gu', $Config.GuestUser, '-gp', $Config.GuestPassword)
    }
    $all += $Arguments
    $out = & $Script:VmrunExe @all 2>&1 | Out-String
    $code = $LASTEXITCODE
    if ($code -ne 0 -and -not $AllowFail) {
        throw "vmrun $($Arguments[0]) fallo (exit $code): $($out.Trim())"
    }
    return @{ ExitCode = $code; Output = $out.Trim() }
}

function Test-LabRunning {
    param($Config)
    $r = Invoke-Vmrun -Arguments @('list') -AllowFail
    return ($r.Output -split "`r?`n" | Where-Object { $_.Trim() -ieq $Config.VmxPath }).Count -gt 0
}

function Wait-LabTools {
    <# Espera a que VMware Tools responda y el invitado acepte operaciones con credenciales. #>
    param($Config, [int]$TimeoutMin = 90)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalMinutes -lt $TimeoutMin) {
        $t = Invoke-Vmrun -Arguments @('checkToolsState', $Config.VmxPath) -AllowFail
        # Tools 12.x a veces reporta "installed" aunque el servicio responda: la prueba real es la operacion en el invitado.
        if ($t.Output -match 'running|installed') {
            $probe = Invoke-Vmrun -Guest -Config $Config -AllowFail -Arguments @('directoryExistsInGuest', $Config.VmxPath, 'C:\Windows')
            if ($probe.Output -match 'exists') { return $true }
        }
        Start-Sleep -Seconds 15
    }
    throw "Timeout ${TimeoutMin} min esperando VMware Tools en el invitado"
}

function Copy-ToLabGuest {
    param($Config, [string]$HostPath, [string]$GuestPath)
    Invoke-Vmrun -Guest -Config $Config -Arguments @('copyFileFromHostToGuest', $Config.VmxPath, $HostPath, $GuestPath) | Out-Null
}

function Copy-FromLabGuest {
    param($Config, [string]$GuestPath, [string]$HostPath)
    Invoke-Vmrun -Guest -Config $Config -AllowFail -Arguments @('copyFileFromGuestToHost', $Config.VmxPath, $GuestPath, $HostPath)
}

function Invoke-LabGuestScript {
    <#
        Copia un .ps1 del host al invitado y lo ejecuta con powershell.exe (5.1) como el usuario
        del laboratorio. -Interactive lo lanza en la sesion con escritorio (autologon), igual que
        un tecnico haciendo doble clic. Devuelve el exit code del script.
    #>
    param(
        $Config,
        [Parameter(Mandatory)][string]$ScriptPath,
        [string]$ScriptArgs = '',
        [switch]$Interactive,
        [switch]$NoWait
    )
    $guestDir = 'C:\LabRun'
    Invoke-Vmrun -Guest -Config $Config -AllowFail -Arguments @('createDirectoryInGuest', $Config.VmxPath, $guestDir) | Out-Null
    $guestScript = Join-Path $guestDir (Split-Path $ScriptPath -Leaf)
    Copy-ToLabGuest -Config $Config -HostPath $ScriptPath -GuestPath $guestScript
    $runArgs = @('runProgramInGuest', $Config.VmxPath)
    if ($NoWait)      { $runArgs += '-noWait' }
    if ($Interactive) { $runArgs += @('-activeWindow', '-interactive') }
    # Sin comillas incrustadas: PowerShell 5.1 las rompe al pasarlas a vmrun.exe (el script no
    # llegaba a arrancar -> exit 1). Rutas de C:\LabRun sin espacios; salida a <script>.out.log.
    if ($ScriptArgs -match '"') { throw 'ScriptArgs no puede contener comillas (usar base64)' }
    $outLog = Join-Path $guestDir ([IO.Path]::GetFileNameWithoutExtension($ScriptPath) + '.out.log')
    # Ojo: sin espacio sobrante si no hay argumentos (PowerShell lo tomaria como argumento " ").
    $psLine = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File $guestScript"
    if ($ScriptArgs) { $psLine += " $($ScriptArgs.Trim())" }
    $runArgs += @('C:\Windows\System32\cmd.exe', "/c $psLine> $outLog 2>&1")
    $r = Invoke-Vmrun -Guest -Config $Config -AllowFail -Arguments $runArgs
    $code = 0
    if ($r.Output -match 'exit code:\s*(-?\d+)') { $code = [int]$matches[1] }
    elseif ($r.ExitCode -ne 0) { $code = $r.ExitCode }
    return @{ ExitCode = $code; Output = $r.Output }
}

function Set-LabShareToRepo {
    # La carpeta compartida sigue a la copia del repo desde la que se ejecuta el lab
    # (p.ej. C:\NodeDeployLabSrc si el M.2 no esta conectado). Requiere VMware Tools.
    param($Config)
    Invoke-Vmrun -Arguments @('setSharedFolderState', $Config.VmxPath, $Config.SharedFolder, $Script:RepoRoot, 'readonly') -AllowFail | Out-Null
}

function Get-LabSnapshots {
    param($Config)
    $r = Invoke-Vmrun -Arguments @('listSnapshots', $Config.VmxPath) -AllowFail
    return @($r.Output -split "`r?`n" | Select-Object -Skip 1 | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
