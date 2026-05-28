<#
.SYNOPSIS
    N0DE_DEPL0Y v3.0 - Unified, Resumable, Autonomous Deployment Script
.DESCRIPTION
    Despliegue desatendido para 11 aplicaciones (apps_q_instalar) + 4 componentes iManage.
    Resumible tras revert de snapshot via state file + validacion contra registro real.

    Flujo:
      Phase -1 : Self-elevation (UAC silencioso si es admin local)
      Phase 0a : Probe + fingerprint de cada instalador (tech detection)
      Phase 0b : Office C2R en background (descarga ~2GB en paralelo)
      Phase 0c : Pre-cache paralelo (no aplica en source local, NOP)
      Phase 1  : Instalaciones silenciosas (MSI / EXE-Inno / EXE-NSIS / EXE-IS / Burn / MSIX)
      Phase 1b : iManage stack (InstallShield + WiX Burn, UI Automation fallback)
      Phase 2  : Validacion + post-install report
      Phase 3  : Sincronizar con Office + verificacion final

    Resume:
      State file en $StatePath persistira progreso. Si se revierte snapshot, en
      relanzamiento el script re-detecta estado real (registry+servicios+files)
      y reanuda en el primer app NO instalado.

.PARAMETER Source
    Carpeta con instaladores. Default: C:\testeo2.0\apps_q_instalar

.PARAMETER StatePath
    Carpeta para state file (debe sobrevivir snapshot revert si es posible).
    Default: C:\testeo2.0\state

.PARAMETER ResumeOnly
    Si se especifica, NO reintenta instalaciones fallidas, solo procesa pendientes.

.PARAMETER ProbeOnly
    Solo ejecuta Phase 0a (probe + report); no instala nada.

.PARAMETER MaxRetries
    Reintentos por app antes de marcar como fail definitivo. Default: 2.

.PARAMETER NonInteractive
    Suprime cualquier Read-Host residual; sale con exit code al final.

.NOTES
    v3.3 - 2026-05-12 - Performance + ESET fix:
                        - ESET install_config.ini parseado y propiedades pasadas inline
                          (MSI no auto-detecta INI, requiere passing manual)
                        - Pre-cache local UNC->C:\NodeDeploy_cache via robocopy MT=16
                          (~10-30s extra al inicio, ~2x speedup en installs)
                        - Office C2R launch en background al inicio de Phase 1
                          (descarga 600MB-2GB en paralelo con MSI/EXE/iManage)
                        - Flags -NoPreCache, -NoOfficeBackground para deshabilitar

    v3.2 - 2026-05-12 - Hotfix UNC:
                        - Convert-Path en vez de Resolve-Path (evita prefijo provider
                          que rompia msiexec con 1619 y CreateProcess con -99)
                        - configuration.xml busca primero junto al script (PSScriptRoot)
                          luego junto a installers ($Source)

    v3.1 - 2026-05-12 - Production:
                        - Source default UNC \\192.168.2.8\utilidades\1.Node_Preparation
                        - Phase 4 final: sysdm.cpl + lusrmgr.msc (domain/admin)
                        - -SkipFinalize switch para suprimir Phase 4

    v3.0 - 2026-05-12 - Refactor completo:
                        - Source local configurable
                        - State file con resume tras snapshot revert
                        - Probe dinamico de tech del instalador
                        - Informe tecnico per-app en Markdown
                        - Drop Phase 3 (Outlook addin cleanup, fuera de scope)
                        - 100% no interactivo (no Read-Host)
                        - Office configuration.xml auto-generado si falta
#>
[CmdletBinding()]
param(
    [string]$Source        = '\\192.168.2.8\utilidades\1.Node_Preparation',
    [string]$StatePath     = 'C:\testeo2.0\state',
    [string]$LocalCache    = 'C:\NodeDeploy_cache',
    [switch]$ResumeOnly,
    [switch]$ProbeOnly,
    [int]$MaxRetries       = 2,
    [switch]$NonInteractive = $true,
    [switch]$SkipFinalize,
    [switch]$NoPreCache,
    [switch]$NoOfficeBackground
)

$ErrorActionPreference = 'Continue'

# ====================================================================
#region  SELF-ELEVATION
# ====================================================================
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "  Elevando permisos (UAC)..." -ForegroundColor Yellow
    $scriptPath = $MyInvocation.MyCommand.Path
    $pass = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$scriptPath`"")
    foreach ($k in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$k]
        if ($v -is [switch]) {
            if ($v.IsPresent) { $pass += "-$k" }
        } else {
            $pass += "-$k"
            $pass += "`"$v`""
        }
    }
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $pass -Verb RunAs -ErrorAction Stop
    } catch {
        Write-Host "  No se pudo elevar: $_" -ForegroundColor Red
    }
    exit 0
}
#endregion SELF-ELEVATION

# ====================================================================
#region  CONFIGURATION
# ====================================================================

if (-not (Test-Path $Source)) {
    Write-Host "  [FATAL] Source no existe: $Source" -ForegroundColor Red
    exit 2
}
if (-not (Test-Path $StatePath)) {
    New-Item -Path $StatePath -ItemType Directory -Force | Out-Null
}

# Convert-Path devuelve native path sin prefijo provider (Microsoft.PowerShell.Core\FileSystem::).
# Resolve-Path sobre UNC anade ese prefijo que msiexec/CreateProcess no aceptan -> exit 1619 / -99.
$Script:Source     = (Convert-Path $Source)
$Script:StatePath  = (Convert-Path $StatePath)
$Script:StateFile  = Join-Path $Script:StatePath 'nodedeploy_state.json'
$Script:LogDir     = Join-Path $Script:StatePath 'logs'
$Script:ReportDir  = Join-Path $Script:StatePath 'reports'
foreach ($p in @($Script:LogDir, $Script:ReportDir)) {
    if (-not (Test-Path $p)) { New-Item -Path $p -ItemType Directory -Force | Out-Null }
}
$Script:LogFile        = Join-Path $Script:LogDir ('NodeDeploy_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$Script:Desktop        = [Environment]::GetFolderPath('CommonDesktopDirectory')
$Script:DefaultTimeout = 300
$Script:MaxRetries     = $MaxRetries
$Script:SessionId      = [Guid]::NewGuid().ToString('N').Substring(0,8)

# configuration.xml puede vivir junto al script (Sc3.0\) o junto a OfficeSetup.exe ($Source).
# Buscar primero junto al script (mas portable), fallback a Source.
$Script:OfficeConfigXml = $null
$xmlCandidates = @(
    (Join-Path $PSScriptRoot 'configuration.xml'),
    (Join-Path $Script:Source 'configuration.xml')
)
foreach ($x in $xmlCandidates) {
    if ($x -and (Test-Path $x)) {
        $Script:OfficeConfigXml = (Convert-Path $x)
        break
    }
}
if (-not $Script:OfficeConfigXml) {
    # Default a junto al script aunque no exista (sera reportado luego).
    $Script:OfficeConfigXml = Join-Path $PSScriptRoot 'configuration.xml'
}

#endregion CONFIGURATION

# ====================================================================
#region  UI ENGINE
# ====================================================================
$Script:SpinIdx   = 0
$Script:SpinChars = @('/', '-', '\', '|')

function Show-Banner {
    $banner = @"

    `e[36m ___  ___  ________  ________  _______`e[0m
    `e[36m|\  \|\  \|\   __  \|\   ___ \|\  ___ \`e[0m
    `e[36m\ \  \\\  \ \  \|\  \ \  \_|\ \ \   __/|`e[0m
    `e[36m \ \   __  \ \  \\\  \ \  \ \\ \ \  \_|/__`e[0m
    `e[36m  \ \  \ \  \ \  \\\  \ \  \_\\ \ \  \_|\ \`e[0m
    `e[36m   \ \__\ \__\ \_______\ \_______\ \_______\`e[0m
    `e[36m    \|__|\|__|\|_______|\|_______|\|_______|`e[0m
    `e[35m ________  _______   ________  ___       ________  ___    ___`e[0m
    `e[35m|\   ___ \|\  ___ \ |\   __  \|\  \     |\   __  \|\  \  /  /|`e[0m
    `e[35m\ \  \_|\ \ \   __/|\ \  \|\  \ \  \    \ \  \|\  \ \  \/  / /`e[0m
    `e[35m \ \  \ \\ \ \  \_|/_\ \   ____\ \  \    \ \  \\\  \ \    / /`e[0m
    `e[35m  \ \  \_\\ \ \  \_|\ \ \  \___|\ \  \____\ \  \\\  \ \  / /`e[0m
    `e[35m   \ \_______\ \_______\ \__\    \ \_______\ \_______\ \__/ /`e[0m
    `e[35m    \|_______|\|_______|\|__|     \|_______|\|_______|\|__|/`e[0m

"@
    Write-Host $banner
    Write-Host ('  =' + ('=' * 65)) -ForegroundColor Cyan
    Write-Host "  N0DE_DEPL0Y  v3.3   //   $(Get-Date -Format 'yyyy.MM.dd')   //   session=$($Script:SessionId)" -ForegroundColor Magenta
    Write-Host "  Resumable, Autonomous, Snapshot-Safe Deployment Engine" -ForegroundColor DarkGray
    Write-Host ('  =' + ('=' * 65)) -ForegroundColor Cyan
    Write-Host ''
}

function Show-PhaseHeader {
    param([string]$Phase, [string]$Title, [string]$Subtitle)
    Write-Host ''
    Write-Host ('  +' + ('-' * 64) + '+') -ForegroundColor Cyan
    $h = "  |  PHASE $Phase :: $Title"
    Write-Host $h.PadRight(66) -ForegroundColor Magenta -NoNewline; Write-Host '|' -ForegroundColor Cyan
    if ($Subtitle) {
        $s = "  |  $Subtitle"
        Write-Host $s.PadRight(66) -ForegroundColor DarkGray -NoNewline; Write-Host '|' -ForegroundColor Cyan
    }
    Write-Host ('  +' + ('-' * 64) + '+') -ForegroundColor Cyan
    Write-Host ''
}

function Show-AppResult {
    param([string]$AppName, [string]$Result, [string]$Detail = '')
    $tag = switch ($Result) {
        'ok'   { @{ T='OK';   C='Green'  } }
        'skip' { @{ T='SKIP'; C='Yellow' } }
        'fail' { @{ T='FAIL'; C='Red'    } }
        'retry'{ @{ T='RETRY';C='Yellow' } }
        default{ @{ T=$Result.ToUpper(); C='Gray' } }
    }
    Write-Host '  [' -NoNewline -ForegroundColor DarkGray
    Write-Host $tag.T -NoNewline -ForegroundColor $tag.C
    Write-Host '] ' -NoNewline -ForegroundColor DarkGray
    Write-Host $AppName -NoNewline -ForegroundColor White
    if ($Detail) { Write-Host " $Detail" -ForegroundColor DarkGray } else { Write-Host '' }
}

function Show-AppProgress {
    param([string]$AppName, [string]$Status)
    $spin = $Script:SpinChars[$Script:SpinIdx % 4]; $Script:SpinIdx++
    Write-Host "  [$spin] " -NoNewline -ForegroundColor Cyan
    Write-Host "$Status " -NoNewline -ForegroundColor Yellow
    Write-Host $AppName -ForegroundColor White
}
#endregion UI ENGINE

# ====================================================================
#region  CORE UTILITIES
# ====================================================================
function Write-Log {
    param([string]$Msg, [string]$Level = 'INFO')
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Msg"
    Add-Content -Path $Script:LogFile -Value $entry -ErrorAction SilentlyContinue
}

function Write-LogHost {
    param([string]$Msg, [string]$Level = 'INFO')
    Write-Log -Msg $Msg -Level $Level
    $color = switch ($Level) {
        'ERROR' { 'Red' }
        'WARN'  { 'Yellow' }
        'OK'    { 'Green' }
        default { 'DarkGray' }
    }
    Write-Host "  $Msg" -ForegroundColor $color
}

function Get-InstalledApps {
    @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    ) | ForEach-Object {
        Get-ItemProperty $_ -ErrorAction SilentlyContinue
    } | Where-Object { $_.DisplayName } | Select-Object -ExpandProperty DisplayName
}

function Test-InstalledStrict {
    param(
        [string[]]$Keywords,
        [string]$AppxName,
        [string[]]$ServiceNames,
        [string[]]$FilePaths,
        [switch]$Refresh
    )
    if ($Refresh -or -not $Global:InstalledCache) {
        $Global:InstalledCache = Get-InstalledApps
    }
    $evidence = @()
    if ($Keywords) {
        foreach ($kw in $Keywords) {
            if ($Global:InstalledCache | Where-Object { $_ -like "*$kw*" }) {
                $evidence += "registry:$kw"
                break
            }
        }
    }
    if ($AppxName -and (Get-AppxPackage -Name "*$AppxName*" -ErrorAction SilentlyContinue)) {
        $evidence += "appx:$AppxName"
    }
    if ($ServiceNames) {
        foreach ($svc in $ServiceNames) {
            $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($s) { $evidence += "service:$svc($($s.Status))" }
        }
    }
    if ($FilePaths) {
        foreach ($fp in $FilePaths) {
            if ($fp -and (Test-Path $fp)) {
                $evidence += "file:$(Split-Path $fp -Leaf)"
                break
            }
        }
    }
    return @{ Installed = ($evidence.Count -gt 0); Evidence = $evidence }
}

function Start-InstallProcess {
    param(
        [string]$FilePath,
        [string]$Arguments,
        [int]$Timeout = $Script:DefaultTimeout,
        [string[]]$KillProcesses = @(),
        [string]$WorkingDirectory = ''
    )
    Write-Log "  CMD: `"$FilePath`" $Arguments"
    Write-Log "  Timeout: ${Timeout}s"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $FilePath
    $psi.Arguments              = $Arguments
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    try { [void]$proc.Start() } catch {
        Write-Log "  Launch failed: $_" 'ERROR'
        return @{ ExitCode = -99; TimedOut = $false; Error = "$_" }
    }

    $stderrTask = $proc.StandardError.ReadToEndAsync()
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $finished = $proc.WaitForExit($Timeout * 1000)

    if (-not $finished) {
        Write-Log "  TIMEOUT ${Timeout}s - killing PID $($proc.Id)" 'WARN'
        try {
            $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc.Id)" -ErrorAction SilentlyContinue
            foreach ($child in $children) {
                Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue
            }
        } catch {}
        try { $proc.Kill() } catch {}
        foreach ($pn in $KillProcesses) {
            Get-Process -Name $pn -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        return @{ ExitCode = -1; TimedOut = $true; Error = 'TIMEOUT' }
    }
    $proc.WaitForExit()
    $code = $proc.ExitCode
    $stderr = ''
    $stdout = ''
    try { $stderr = $stderrTask.Result } catch {}
    try { $stdout = $stdoutTask.Result } catch {}
    if ($stderr -and $stderr.Trim()) {
        $lines = ($stderr.Trim() -split "`n" | Select-Object -First 3) -join ' | '
        Write-Log "  STDERR: $lines" 'WARN'
    }
    Start-Sleep -Milliseconds 800
    foreach ($pn in $KillProcesses) {
        Get-Process -Name $pn -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    $proc.Dispose()
    return @{ ExitCode = $code; TimedOut = $false; Stdout = $stdout; Stderr = $stderr }
}

function Wait-ChildMsi {
    param([int]$Timeout = 120)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Seconds 5
    while ($sw.Elapsed.TotalSeconds -lt $Timeout) {
        $userMsi = Get-Process -Name 'msiexec' -ErrorAction SilentlyContinue |
                   Where-Object { $_.SessionId -ne 0 }
        if (-not $userMsi) { break }
        Start-Sleep -Seconds 3
    }
    $sw.Stop()
    Write-Log "  msiexec children finished ($([int]$sw.Elapsed.TotalSeconds)s)"
}

function New-Shortcut {
    param([string]$Name, [string]$TargetPath)
    if (-not $TargetPath -or -not (Test-Path $TargetPath)) { return }
    $lnk = Join-Path $Script:Desktop "$Name.lnk"
    if (Test-Path $lnk) { return }
    try {
        $ws = New-Object -ComObject WScript.Shell
        $sc = $ws.CreateShortcut($lnk)
        $sc.TargetPath = $TargetPath
        $sc.Save()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ws) | Out-Null
        Write-Log "  Shortcut created: $Name" 'OK'
    } catch {
        Write-Log "  Shortcut failed: $Name - $_" 'WARN'
    }
}

function Resolve-ExePath {
    param([string[]]$Candidates)
    foreach ($c in $Candidates) {
        if (-not $c) { continue }
        if (Test-Path $c) { return $c }
        $res = Resolve-Path $c -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($res) { return $res.Path }
    }
    return $null
}

function Get-EsetIniProperties {
    <#
    .SYNOPSIS
        Parsea install_config.ini de ESET y devuelve cadena de propiedades MSI.
        Cada linea KEY=VALUE se convierte en KEY="VALUE" para pasar a msiexec.
    .NOTES
        El MSI de ESET Management Agent NO auto-detecta el INI. Hay que parsearlo
        y pasar cada propiedad como argumento de msiexec. Valor sin espacios
        (base64) se pasa entrecomillado por seguridad.
    #>
    param([string]$IniPath)
    if (-not (Test-Path $IniPath)) { return $null }
    $props = @()
    foreach ($line in (Get-Content $IniPath -ErrorAction SilentlyContinue)) {
        $l = $line.Trim()
        if (-not $l) { continue }
        if ($l -match '^[#;]') { continue }
        if ($l -match '^\[') { continue }
        if ($l -match '^([A-Z_][A-Z0-9_]*)=(.*)$') {
            $k = $matches[1]
            $v = $matches[2].Trim()
            # MSI props: PROPERTY="value" - escapes embedded quote as "" but base64 no tiene
            $props += '{0}="{1}"' -f $k, $v
        }
    }
    if ($props.Count -eq 0) { return $null }
    return ($props -join ' ')
}

function Invoke-PreCache {
    <#
    .SYNOPSIS
        Copia $Source UNC a $LocalCache via robocopy multi-threaded.
        Tras la copia retorna nueva ruta para usar como $Source.
    .NOTES
        Acelera installs sobre LAN gigabit: ~1.1GB en ~10-30s.
        Si Source ya es local o LocalCache fallo, retorna $Source original.
    #>
    param([string]$SourcePath, [string]$CachePath)
    if (-not $SourcePath -or -not $SourcePath.StartsWith('\\')) {
        Write-Log '  Pre-cache: source no es UNC, skip'
        return $SourcePath
    }
    if (-not (Test-Path $CachePath)) {
        New-Item -ItemType Directory -Path $CachePath -Force | Out-Null
    }
    Write-LogHost "  Pre-cache: robocopy $SourcePath -> $CachePath (MT=16)..."
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $rcArgs = @($SourcePath, $CachePath, '/E', '/MT:16', '/R:2', '/W:3',
                '/NP', '/NJH', '/NJS', '/NDL', '/NFL', '/XO')
    $rc = Start-Process -FilePath 'robocopy.exe' -ArgumentList $rcArgs `
                        -Wait -NoNewWindow -PassThru
    $sw.Stop()
    # Robocopy: 0=no copy, 1=ok, 2-7=mixed but functional, 8+=error
    if ($rc.ExitCode -ge 8) {
        Write-LogHost "  Pre-cache FAIL rc=$($rc.ExitCode), usando UNC" 'WARN'
        return $SourcePath
    }
    Write-LogHost "  Pre-cache OK ($([int]$sw.Elapsed.TotalSeconds)s, rc=$($rc.ExitCode))" 'OK'
    return (Convert-Path $CachePath)
}

function Start-OfficeBackground {
    <#
    .SYNOPSIS
        Lanza OfficeSetup.exe /configure XML en background no-bloqueante.
        Permite que MSIs/EXEs instalen mientras Office descarga 2GB en paralelo.
    .OUTPUTS
        Hashtable { Process, StartTime, Status, TargetApp }
    #>
    param([hashtable]$OfficeApp, [string]$XmlPath)
    $exe = if ($OfficeApp.Path) { Join-Path $Script:Source $OfficeApp.Path } else { Join-Path $Script:Source $OfficeApp.File }
    if (-not (Test-Path $exe) -or -not (Test-Path $XmlPath)) {
        Write-Log "  Office bg: file missing exe=$exe xml=$XmlPath" 'WARN'
        return $null
    }
    # Kill stale Office procs
    @('OUTLOOK','WINWORD','EXCEL','POWERPNT','OfficeClickToRun','OfficeC2RClient') | ForEach-Object {
        Get-Process -Name $_ -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2

    Write-LogHost "  Office background: launching $exe /configure $XmlPath" 'OK'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $exe
    $psi.Arguments              = "/configure `"$XmlPath`""
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError  = $false
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    try { [void]$proc.Start() } catch {
        Write-Log "  Office bg launch failed: $_" 'ERROR'
        return $null
    }
    Write-LogHost "  Office bg PID=$($proc.Id) corriendo (descarga ~600MB Outlook-only)" 'OK'
    return @{
        Process   = $proc
        StartTime = [Diagnostics.Stopwatch]::StartNew()
        Status    = 'running'
        TargetApp = $OfficeApp
    }
}

function Wait-OfficeBackground {
    param([hashtable]$Job, [int]$Timeout = 1800)
    if (-not $Job -or $Job.Status -ne 'running') { return $null }
    $proc = $Job.Process
    $sw   = $Job.StartTime
    if (-not $proc.HasExited) {
        Write-LogHost "  Esperando Office bg (timeout ${Timeout}s)..."
        while (-not $proc.HasExited -and $sw.Elapsed.TotalSeconds -lt $Timeout) {
            Start-Sleep -Seconds 5
        }
    }
    if (-not $proc.HasExited) {
        Write-LogHost "  Office bg TIMEOUT ${Timeout}s - killing" 'WARN'
        @('OfficeClickToRun','OfficeC2RClient','setup') | ForEach-Object {
            Get-Process -Name $_ -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        try { $proc.Kill() } catch {}
    }
    $proc.WaitForExit()
    $code = $proc.ExitCode
    $secs = [int]$sw.Elapsed.TotalSeconds
    Write-Log "  Office bg finished: exit=$code (${secs}s)"
    $proc.Dispose()
    return @{ ExitCode = $code; ElapsedSec = $secs }
}
#endregion CORE UTILITIES

# ====================================================================
#region  STATE MANAGEMENT (resumable across reboots & snapshot reverts)
# ====================================================================
function Load-State {
    if (Test-Path $Script:StateFile) {
        try {
            $raw = Get-Content $Script:StateFile -Raw -ErrorAction Stop
            return ($raw | ConvertFrom-Json -ErrorAction Stop)
        } catch {
            Write-Log "  State file corrupto, ignorando: $_" 'WARN'
        }
    }
    return $null
}

function New-State {
    return [pscustomobject]@{
        session_id   = $Script:SessionId
        started      = (Get-Date -Format 'o')
        last_updated = (Get-Date -Format 'o')
        source       = $Script:Source
        state_path   = $Script:StatePath
        current_phase = '0a'
        apps         = @{}
    }
}

function Save-State {
    param($State)
    $State.last_updated = (Get-Date -Format 'o')
    try {
        ($State | ConvertTo-Json -Depth 10) | Set-Content -Path $Script:StateFile -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Log "  Save-State error: $_" 'ERROR'
    }
}

function Get-AppState {
    param($State, [string]$Key)
    if ($State.apps -is [hashtable]) {
        if ($State.apps.ContainsKey($Key)) { return $State.apps[$Key] }
    } elseif ($State.apps.PSObject.Properties.Name -contains $Key) {
        return $State.apps.$Key
    }
    return $null
}

function Set-AppState {
    param($State, [string]$Key, $Data)
    if ($State.apps -is [hashtable]) {
        $State.apps[$Key] = $Data
    } else {
        if ($State.apps.PSObject.Properties.Name -contains $Key) {
            $State.apps.$Key = $Data
        } else {
            $State.apps | Add-Member -NotePropertyName $Key -NotePropertyValue $Data -Force
        }
    }
    Save-State -State $State
}
#endregion STATE MANAGEMENT

# ====================================================================
#region  PROBE / FINGERPRINT ENGINE
# ====================================================================
function Get-MsiMetadata {
    param([string]$MsiPath)
    $meta = @{ ProductName=''; ProductVersion=''; Manufacturer=''; ProductCode=''; UpgradeCode='' }
    try {
        $wi = New-Object -ComObject WindowsInstaller.Installer
        $db = $wi.GetType().InvokeMember('OpenDatabase','InvokeMethod',$null,$wi,@($MsiPath,0))
        $sql = "SELECT Property,Value FROM Property WHERE Property='ProductName' OR Property='ProductVersion' OR Property='Manufacturer' OR Property='ProductCode' OR Property='UpgradeCode'"
        $v = $db.GetType().InvokeMember('OpenView','InvokeMethod',$null,$db,@($sql))
        $v.GetType().InvokeMember('Execute','InvokeMethod',$null,$v,$null) | Out-Null
        while ($true) {
            $r = $v.GetType().InvokeMember('Fetch','InvokeMethod',$null,$v,$null)
            if (-not $r) { break }
            $p = $r.GetType().InvokeMember('StringData','GetProperty',$null,$r,@(1))
            $val = $r.GetType().InvokeMember('StringData','GetProperty',$null,$r,@(2))
            if ($meta.ContainsKey($p)) { $meta[$p] = $val }
        }
        $v.GetType().InvokeMember('Close','InvokeMethod',$null,$v,$null) | Out-Null
    } catch {
        Write-Log "  Get-MsiMetadata error ${MsiPath}: $_" 'WARN'
    }
    return $meta
}

function Get-ExeFingerprint {
    param([string]$ExePath)
    # Read up to 16MB tail looking for known installer signatures.
    # Most installer signatures are in the first few MB but Inno/NSIS bury
    # markers near the entrypoint. We read in chunks for efficiency.
    $fp = @{
        Tech       = 'unknown'
        Confidence = 'low'
        Markers    = @()
        Signature  = $null
    }
    try {
        $fs = [IO.File]::OpenRead($ExePath)
        try {
            $len = [int][Math]::Min($fs.Length, 8MB)
            $buf = New-Object byte[] $len
            [void]$fs.Read($buf, 0, $len)
            $ascii = [Text.Encoding]::ASCII.GetString($buf)
            $unicode = [Text.Encoding]::Unicode.GetString($buf)

            $checks = @(
                @{ Pattern = 'Inno Setup Setup Data';        Tech='inno';          Conf='high'  },
                @{ Pattern = 'Inno Setup';                   Tech='inno';          Conf='medium'},
                @{ Pattern = 'Nullsoft.NSIS.exehead';        Tech='nsis';          Conf='high'  },
                @{ Pattern = 'Nullsoft Install System';      Tech='nsis';          Conf='high'  },
                @{ Pattern = 'NSIS Error';                   Tech='nsis';          Conf='medium'},
                @{ Pattern = 'InstallShield';                Tech='installshield'; Conf='high'  },
                @{ Pattern = 'ISBEW64';                      Tech='installshield'; Conf='high'  },
                @{ Pattern = 'InstallScript';                Tech='installshield'; Conf='medium'},
                @{ Pattern = 'wixburn';                      Tech='burn';          Conf='high'  },
                @{ Pattern = 'BurnExecutable';               Tech='burn';          Conf='high'  },
                @{ Pattern = 'WixBundleManifest';            Tech='burn';          Conf='high'  },
                @{ Pattern = 'Squirrel.Windows';             Tech='squirrel';      Conf='high'  },
                @{ Pattern = 'Microsoft Click-to-Run';       Tech='office_c2r';    Conf='high'  },
                @{ Pattern = 'Click-to-Run';                 Tech='office_c2r';    Conf='medium'},
                @{ Pattern = 'OfficeClickToRun';             Tech='office_c2r';    Conf='high'  },
                @{ Pattern = '7-Zip SFX';                    Tech='7zsfx';         Conf='high'  },
                @{ Pattern = 'WinRAR SFX';                   Tech='winrar_sfx';    Conf='high'  },
                @{ Pattern = 'Chrome';                       Tech='chrome_setup';  Conf='low'   }
            )
            foreach ($c in $checks) {
                if ($ascii -match [regex]::Escape($c.Pattern) -or $unicode -match [regex]::Escape($c.Pattern)) {
                    $fp.Markers += $c.Pattern
                    # Promote first high-confidence match; medium upgrades from unknown only.
                    if ($fp.Tech -eq 'unknown' -or ($c.Conf -eq 'high' -and $fp.Confidence -ne 'high')) {
                        $fp.Tech = $c.Tech
                        $fp.Confidence = $c.Conf
                    }
                }
            }
        } finally { $fs.Close() }
    } catch {
        Write-Log "  Get-ExeFingerprint error ${ExePath}: $_" 'WARN'
    }
    try {
        $sig = Get-AuthenticodeSignature -FilePath $ExePath -ErrorAction SilentlyContinue
        if ($sig -and $sig.SignerCertificate) {
            $fp.Signature = $sig.SignerCertificate.Subject
        }
    } catch {}
    return $fp
}

function Invoke-ProbeAll {
    param([array]$Apps)
    Show-PhaseHeader -Phase '0a' -Title 'INSTALLER PROBE' -Subtitle 'Fingerprint + metadata extraction'
    $results = @()
    foreach ($app in $Apps) {
        $file = if ($app.Path) { Join-Path $Script:Source $app.Path } else { Join-Path $Script:Source $app.File }
        if (-not (Test-Path $file)) {
            Write-LogHost "  [MISS] $($app.Name) -> $file" 'WARN'
            $results += @{ App=$app; File=$file; Status='missing' }
            continue
        }
        $ext = [IO.Path]::GetExtension($file).ToLower()
        $probe = @{ App=$app; File=$file; Ext=$ext; Size=(Get-Item $file).Length }
        switch ($ext) {
            '.msi' {
                $probe.Tech = 'msi'
                $probe.Meta = Get-MsiMetadata -MsiPath $file
                Write-Log "  PROBE [$($app.Name)] MSI: $($probe.Meta.ProductName) v$($probe.Meta.ProductVersion) / $($probe.Meta.Manufacturer)"
            }
            '.msixbundle' {
                $probe.Tech = 'msixbundle'
                Write-Log "  PROBE [$($app.Name)] MSIXBUNDLE"
            }
            '.exe' {
                $fp = Get-ExeFingerprint -ExePath $file
                $probe.Tech = $fp.Tech
                $probe.Markers = $fp.Markers
                $probe.Signature = $fp.Signature
                Write-Log "  PROBE [$($app.Name)] EXE -> $($fp.Tech) (conf=$($fp.Confidence)) sig=$($fp.Signature)"
            }
            default {
                $probe.Tech = 'unknown'
            }
        }
        Show-AppResult -AppName $app.Name -Result 'ok' -Detail "($($probe.Tech))"
        $results += $probe
    }
    return $results
}
#endregion PROBE ENGINE

# ====================================================================
#region  APP REGISTRY
# ====================================================================
# Schema:
#   Name          : display name (also used as state key)
#   File / Path   : relative path under $Source
#   Type          : msi | exe | msixbundle | inno | nsis | installshield | burn | office | chrome
#   Args          : argument template (only for non-MSI)
#   MsiExtra      : extra MSI properties appended to /qn /norestart
#   Detect        : registry DisplayName keywords (Test-InstalledStrict)
#   AppxDetect    : Appx package name pattern
#   ServiceNames  : Windows services that prove install
#   FilePaths     : disk paths that prove install
#   Group         : 1=MSI, 2=EXE silent, 3=Complex (UI-automation candidates)
#   Timeout       : seconds, default $DefaultTimeout
#   KillGUI       : process names to kill post-install
#   Shortcut      : { Exe, Alt } for desktop shortcut
#   RequiresXml   : (office) requires configuration.xml present
#   FallbackUI    : (bool) try UI Automation if silent install fails

$Script:Apps = @(
    # ---- GROUP 1 : MSIs ----
    @{
        Name         = 'AnyDesk'
        File         = 'AnyDesk.msi'
        Type         = 'msi'
        Detect       = @('AnyDesk')
        FilePaths    = @("${env:ProgramFiles(x86)}\AnyDesk\AnyDesk.exe","$env:ProgramFiles\AnyDesk\AnyDesk.exe")
        ServiceNames = @('AnyDesk')
        Group        = 1
        Shortcut     = @{ Exe = "${env:ProgramFiles(x86)}\AnyDesk\AnyDesk.exe"; Alt = "$env:ProgramFiles\AnyDesk\AnyDesk.exe" }
    },
    @{
        Name   = 'AqNet'
        File   = 'AqNetInstalacion.msi'
        Type   = 'msi'
        Detect = @('AqNet','Aqnet','Deposito Digital','AQNET')
        Group  = 1
    },
    @{
        Name         = 'Nebula CertAgent'
        File         = 'nebula-certAgent-winx64-5.0.0.msi'
        Type         = 'msi'
        Detect       = @('Nebula','CertAgent','certAgent','nebulaCERTagent')
        FilePaths    = @("$env:ProgramFiles\Vintegris\nebulaCERTagent\nebulaCERTagent.exe")
        ServiceNames = @('nebulaCERTagent','nebulaCERT')
        Group        = 1
    },
    @{
        Name         = 'MDR / Cortex XDR'
        File         = 'MDR_Windows_Andersen_8_2_x64.msi'
        Type         = 'msi'
        Detect       = @('Cortex XDR','Cortex','Palo Alto','Traps')
        ServiceNames = @('cyserver','CyveraService')
        MsiExtra     = 'REBOOT=ReallySuppress'
        Timeout      = 600
        Group        = 1
    },
    @{
        Name         = 'ESET Management Agent'
        File         = 'eset_msi.msi'
        Type         = 'msi'
        Detect       = @('ESET Management Agent','ESET Remote Administrator Agent','ERA Agent')
        ServiceNames = @('EraAgentSvc','ekrn')
        FilePaths    = @("$env:ProgramFiles\ESET\RemoteAdministrator\Agent\ERAAgent.exe")
        # Without install_config.ini next to MSI, the agent installs unenrolled.
        # Try with P_PRODUCT_TYPE override; gracefully fail if not pre-configured.
        MsiExtra     = 'P_INSTALL_MODE=1'
        Timeout      = 600
        Group        = 1
    },

    # ---- GROUP 2 : EXE silent  ----
    @{
        Name      = 'Google Chrome'
        File      = 'ChromeSetup.exe'
        Type      = 'chrome'
        Args      = '/silent /install'
        Detect    = @('Google Chrome')
        FilePaths = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
                      "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe")
        Group     = 2
        Timeout   = 300
        Shortcut  = @{ Exe = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"; Alt = "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe" }
    },
    @{
        Name      = 'Autofirma'
        File      = 'Autofirma_64_v1_9_installer.exe'
        Type      = 'nsis'
        Args      = '/S'
        Detect    = @('AutoFirma','Autofirma')
        FilePaths = @("$env:ProgramFiles\AutoFirma\AutoFirma.exe")
        Group     = 2
        Timeout   = 240
        Shortcut  = @{ Exe = "$env:ProgramFiles\AutoFirma\AutoFirma.exe" }
    },
    @{
        Name      = 'Bit4id Middleware'
        File      = 'Bit4id_Middleware.exe'
        Type      = 'nsis'
        Args      = '/S'
        Detect    = @('Bit4id','bit4id','Universal Middleware')
        FilePaths = @("$env:ProgramFiles\Bit4id\Universal MW\bin\bit4xpki.exe","${env:ProgramFiles(x86)}\Bit4id\Universal MW\bin\bit4xpki.exe")
        Group     = 2
        Timeout   = 300
        KillGUI   = @('Bit4id*','universal*','bit4xpki*')
    },

    # ---- GROUP 3 : Complex (Inno + IS) ----
    @{
        Name        = 'PDFelement Business'
        File        = 'pdfelement_business-15066_10.1.5.exe'
        Type        = 'inno'
        Args        = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /NOCANCEL /NOCLOSEAPPLICATIONS /CLOSEAPPLICATIONS'
        Detect      = @('PDFelement','Wondershare','PDFelement Business')
        FilePaths   = @("$env:ProgramFiles\Wondershare\PDFelement\PDFelement.exe","${env:ProgramFiles(x86)}\Wondershare\PDFelement\PDFelement.exe")
        Group       = 3
        Timeout     = 900
        KillGUI     = @('PDFelement*','Wondershare*','wshelper*','WsAppService*','ElevationService*')
        FallbackUI  = $true
        UIPattern   = 'PDFelement|Wondershare|Setup|Instalar'
    },
    @{
        Name        = 'MitelConnect'
        File        = 'MitelConnect.exe'
        Type        = 'installshield'
        Args        = '/s /v"/qn REBOOT=ReallySuppress"'
        Detect      = @('Mitel','MiCollab','Mitel Connect')
        FilePaths   = @("$env:ProgramFiles\Mitel\Connect Client\ConnectAgent.exe","${env:ProgramFiles(x86)}\Mitel\Connect Client\ConnectAgent.exe")
        Group       = 3
        Timeout     = 600
        KillGUI     = @('MitelConnect*','Mitel*')
    },

    # ---- GROUP 4 : Office Click-to-Run (background-eligible) ----
    @{
        Name        = 'Microsoft 365 Apps (Outlook+core)'
        File        = 'OfficeSetup.exe'
        Type        = 'office'
        Args        = '/configure "{XML}"'
        Detect      = @('Microsoft 365 Apps','Microsoft Office','Microsoft Outlook')
        FilePaths   = @("$env:ProgramFiles\Microsoft Office\root\Office16\OUTLOOK.EXE")
        Group       = 4
        Timeout     = 1800
        RequiresXml = $true
    },

    # ---- GROUP 5 : iManage stack ----
    @{
        Name        = 'iManage Agent Services'
        Path        = 'Imanage 2.0\iManage Work Desktop for Windows 10.9.4.39 (x64 Office)\iManageAgentServices.exe'
        Type        = 'installshield'
        Args        = '/s /SMS /v"/qn REBOOT=ReallySuppress"'
        Detect      = @('iManage Agent','iManageAgent')
        Group       = 5
        Timeout     = 600
    },
    @{
        Name        = 'iManage Drive'
        Path        = 'Imanage 2.0\iManage Drive for Windows 10.10.0.410\iManage Drive for Windows 10.10.0.410\iManageDriveSetup.exe'
        Type        = 'burn'
        Args        = '/quiet /norestart'
        Detect      = @('iManage Drive')
        FilePaths   = @("$env:ProgramFiles\iManage\iManage Drive\iManageDrive.exe")
        Group       = 5
        Timeout     = 900
        Shortcut    = @{ Exe = "$env:ProgramFiles\iManage\iManage Drive\iManageDrive.exe" }
    },
    @{
        Name        = 'iManage Drive Native'
        Path        = 'Imanage 2.0\iManage Drive for Windows 10.10.0.410\iManageDrive Native 10.6.1.15\iManageDriveNative.exe'
        Type        = 'burn'
        Args        = '/quiet /norestart'
        Detect      = @('iManage Drive Native','iManageDriveNative')
        Group       = 5
        Timeout     = 600
    },
    @{
        Name        = 'iManage Work Desktop'
        Path        = 'Imanage 2.0\iManage Work Desktop for Windows 10.9.4.39 (x64 Office)\iManageWorkDesktopforWindowsx64.exe'
        Type        = 'installshield'
        Args        = '/s /SMS /v"/qn REBOOT=ReallySuppress"'
        Detect      = @('iManage Work Desktop','iManage Work')
        Group       = 5
        Timeout     = 900
        FallbackUI  = $true
        UIPattern   = 'iManage|InstallShield|Work Desktop'
    }
)
#endregion APP REGISTRY

# ====================================================================
#region  INSTALL ENGINES
# ====================================================================
function Invoke-Install {
    param([hashtable]$App)

    $name    = $App.Name
    $timeout = if ($App.Timeout) { $App.Timeout } else { $Script:DefaultTimeout }
    $filePath = if ($App.Path) { Join-Path $Script:Source $App.Path } else { Join-Path $Script:Source $App.File }

    $record = @{
        name         = $name
        file         = $App.File
        path         = $App.Path
        type         = $App.Type
        full_path    = $filePath
        status       = 'pending'
        attempts     = 0
        exit_code    = $null
        elapsed_sec  = 0
        evidence     = @()
        args_used    = ''
        install_log  = ''
        errors       = @()
        started      = (Get-Date -Format 'o')
        finished     = $null
        timed_out    = $false
        validated    = $false
    }

    if (-not (Test-Path $filePath)) {
        $record.status = 'fail'
        $record.errors += "file_not_found:$filePath"
        $record.finished = (Get-Date -Format 'o')
        Show-AppResult -AppName $name -Result 'fail' -Detail '(file not found)'
        Write-Log "  $name - FILE NOT FOUND: $filePath" 'ERROR'
        return $record
    }

    # Pre-check: already installed?
    $strict = Test-InstalledStrict `
        -Keywords $App.Detect `
        -AppxName $App.AppxDetect `
        -ServiceNames $App.ServiceNames `
        -FilePaths $App.FilePaths `
        -Refresh
    if ($strict.Installed) {
        $record.status = 'skip'
        $record.evidence = $strict.Evidence
        $record.validated = $true
        $record.finished = (Get-Date -Format 'o')
        Show-AppResult -AppName $name -Result 'skip'
        Write-Log "  SKIP $name - already installed (evidence: $($strict.Evidence -join ', '))" 'OK'
        return $record
    }

    $record.attempts++
    Write-Log "--- $name [$($App.Type)] attempt $($record.attempts) ---"
    Show-AppProgress -AppName $name -Status 'Installing'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $killList = if ($App.KillGUI) { $App.KillGUI } else { @() }

    $result = $null
    switch ($App.Type) {

        'msi' {
            $logName = "msi_$([IO.Path]::GetFileNameWithoutExtension($filePath)).log"
            $msiLog  = Join-Path $Script:LogDir $logName
            $extra   = if ($App.MsiExtra) { " $($App.MsiExtra)" } else { '' }

            # ESET Management Agent: parsea install_config.ini y anade props inline
            if ($App.Name -like '*ESET*') {
                $iniPath = Join-Path $Script:Source 'install_config.ini'
                $iniProps = Get-EsetIniProperties -IniPath $iniPath
                if ($iniProps) {
                    $extra += " $iniProps"
                    Write-Log "  ESET INI cargado: $iniPath ($($iniProps.Length) chars)"
                } else {
                    $record.errors += "eset_ini_missing:$iniPath"
                    Write-Log "  ESET install_config.ini no encontrado en $iniPath" 'WARN'
                }
            }

            $argLine = "/i `"$filePath`" /qn /norestart /l*v `"$msiLog`"$extra"
            $record.args_used   = "msiexec.exe $argLine"
            $record.install_log = $msiLog
            $result = Start-InstallProcess -FilePath 'msiexec.exe' -Arguments $argLine -Timeout $timeout
        }

        'msixbundle' {
            $record.args_used = "Add-AppxPackage -Path `"$filePath`""
            try {
                Add-AppxPackage -Path $filePath -ErrorAction Stop
                $result = @{ ExitCode = 0; TimedOut = $false }
            } catch {
                $errMsg = "$_"
                if ($errMsg -match 'higher version|ya instalada|already installed') {
                    $result = @{ ExitCode = 0; TimedOut = $false }
                } else {
                    $record.errors += "msix_error:$errMsg"
                    $result = @{ ExitCode = -3; TimedOut = $false }
                }
            }
        }

        { @('exe','nsis','inno','chrome') -contains $_ } {
            $record.args_used = "$filePath $($App.Args)"
            $result = Start-InstallProcess `
                -FilePath $filePath -Arguments $App.Args `
                -Timeout $timeout -KillProcesses $killList
        }

        'installshield' {
            $record.args_used = "$filePath $($App.Args)"
            $result = Start-InstallProcess `
                -FilePath $filePath -Arguments $App.Args `
                -Timeout $timeout -KillProcesses $killList
            if (-not $result.TimedOut) { Wait-ChildMsi -Timeout 180 }
        }

        'burn' {
            $burnLog = Join-Path $Script:LogDir ("burn_{0}.log" -f [IO.Path]::GetFileNameWithoutExtension($filePath))
            $argLine = "$($App.Args) /log `"$burnLog`""
            $record.args_used   = "$filePath $argLine"
            $record.install_log = $burnLog
            $result = Start-InstallProcess `
                -FilePath $filePath -Arguments $argLine `
                -Timeout $timeout -KillProcesses $killList
            if (-not $result.TimedOut) { Wait-ChildMsi -Timeout 180 }
        }

        'office' {
            if (-not (Test-Path $Script:OfficeConfigXml)) {
                $record.errors += "office_xml_missing:$($Script:OfficeConfigXml)"
                $result = @{ ExitCode = -4; TimedOut = $false }
            } else {
                'OUTLOOK','WINWORD','EXCEL','POWERPNT','OfficeClickToRun','OfficeC2RClient' | ForEach-Object {
                    Get-Process -Name $_ -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                }
                Start-Sleep -Seconds 2
                $argLine = "/configure `"$($Script:OfficeConfigXml)`""
                $record.args_used = "$filePath $argLine"
                $record.install_log = "$env:TEMP\OfficeSetup_NodeDeploy"
                $result = Start-InstallProcess `
                    -FilePath $filePath -Arguments $argLine `
                    -Timeout $timeout -KillProcesses $killList
            }
        }

        default {
            $record.errors += "unknown_type:$($App.Type)"
            $result = @{ ExitCode = -5; TimedOut = $false }
        }
    }

    $sw.Stop()
    $record.elapsed_sec = [int]$sw.Elapsed.TotalSeconds
    $record.exit_code   = $result.ExitCode
    $record.timed_out   = [bool]$result.TimedOut

    # Post-install validation
    Start-Sleep -Seconds 2
    $strict = Test-InstalledStrict `
        -Keywords $App.Detect `
        -AppxName $App.AppxDetect `
        -ServiceNames $App.ServiceNames `
        -FilePaths $App.FilePaths `
        -Refresh
    $record.evidence  = $strict.Evidence
    $record.validated = $strict.Installed

    if ($strict.Installed) {
        $record.status = 'ok'
        Show-AppResult -AppName $name -Result 'ok' -Detail "($($record.elapsed_sec)s)"
        Write-Log "  OK $name evidence=[$($strict.Evidence -join ', ')]" 'OK'
    } elseif ($record.exit_code -eq 0) {
        $record.status = 'ok'
        Show-AppResult -AppName $name -Result 'ok' -Detail "($($record.elapsed_sec)s, code=0)"
        Write-Log "  OK? $name code=0 no-evidence ($($record.elapsed_sec)s)" 'WARN'
    } elseif ($record.exit_code -in @(3010, 1641)) {
        $record.status = 'ok'
        $record.errors += "reboot_pending:$($record.exit_code)"
        Show-AppResult -AppName $name -Result 'ok' -Detail '(reboot pending)'
        Write-Log "  OK $name reboot pending" 'WARN'
    } elseif ($record.timed_out) {
        $record.status = 'fail'
        $record.errors += "timeout:${timeout}s"
        Show-AppResult -AppName $name -Result 'fail' -Detail "(TIMEOUT ${timeout}s)"
    } else {
        $record.status = 'fail'
        $record.errors += "exit_code:$($record.exit_code)"
        Show-AppResult -AppName $name -Result 'fail' -Detail "(code=$($record.exit_code))"
    }

    $record.finished = (Get-Date -Format 'o')
    if ($record.status -eq 'ok' -and $App.Shortcut) {
        $shortcuts = @($App.Shortcut.Exe, $App.Shortcut.Alt) | Where-Object { $_ }
        $exe = Resolve-ExePath -Candidates $shortcuts
        if ($exe) { New-Shortcut -Name $name -TargetPath $exe }
    }
    return $record
}
#endregion INSTALL ENGINES

# ====================================================================
#region  REPORT GENERATOR (Markdown per-app + master)
# ====================================================================
function Write-AppReport {
    param([hashtable]$App, $Probe, $Record)
    $safeName = ($App.Name -replace '[\\/:*?"<>|]','_')
    $reportFile = Join-Path $Script:ReportDir "$safeName.md"
    $md = New-Object Text.StringBuilder

    [void]$md.AppendLine("# $($App.Name)")
    [void]$md.AppendLine('')
    $relFile = if ($App.File) { $App.File } else { $App.Path }
    [void]$md.AppendLine("- **Archivo:** ``$relFile``")
    [void]$md.AppendLine("- **Tipo declarado:** $($App.Type)")
    if ($Probe) {
        [void]$md.AppendLine("- **Tecnologia detectada:** $($Probe.Tech)")
        if ($Probe.Meta) {
            [void]$md.AppendLine("- **ProductName:** $($Probe.Meta.ProductName)")
            [void]$md.AppendLine("- **ProductVersion:** $($Probe.Meta.ProductVersion)")
            [void]$md.AppendLine("- **Manufacturer:** $($Probe.Meta.Manufacturer)")
            [void]$md.AppendLine("- **ProductCode:** $($Probe.Meta.ProductCode)")
            [void]$md.AppendLine("- **UpgradeCode:** $($Probe.Meta.UpgradeCode)")
        }
        if ($Probe.Signature) {
            [void]$md.AppendLine("- **Firma digital:** ``$($Probe.Signature)``")
        }
        if ($Probe.Markers) {
            [void]$md.AppendLine("- **Markers PE:** $($Probe.Markers -join ', ')")
        }
        if ($Probe.Size) {
            [void]$md.AppendLine("- **Tamano:** $([Math]::Round($Probe.Size/1MB,1)) MB")
        }
    }
    [void]$md.AppendLine('')
    [void]$md.AppendLine('## Parametros silenciosos')
    [void]$md.AppendLine('')
    [void]$md.AppendLine('```')
    [void]$md.AppendLine($Record.args_used)
    [void]$md.AppendLine('```')
    [void]$md.AppendLine('')
    [void]$md.AppendLine('## Resultado')
    [void]$md.AppendLine('')
    [void]$md.AppendLine("- **Estado:** $($Record.status)")
    [void]$md.AppendLine("- **Exit code:** $($Record.exit_code)")
    [void]$md.AppendLine("- **Duracion:** $($Record.elapsed_sec)s")
    [void]$md.AppendLine("- **Timeout:** $([bool]$Record.timed_out)")
    [void]$md.AppendLine("- **Intentos:** $($Record.attempts)")
    [void]$md.AppendLine('')
    [void]$md.AppendLine('## Validacion post-instalacion')
    [void]$md.AppendLine('')
    if ($Record.evidence -and $Record.evidence.Count -gt 0) {
        foreach ($e in $Record.evidence) { [void]$md.AppendLine("- $e") }
    } else {
        [void]$md.AppendLine('- (sin evidencias en registro/servicios/disco)')
    }
    [void]$md.AppendLine('')
    [void]$md.AppendLine("**Validado:** $([bool]$Record.validated)")
    [void]$md.AppendLine('')
    if ($Record.install_log) {
        [void]$md.AppendLine('## Log del instalador')
        [void]$md.AppendLine('')
        [void]$md.AppendLine("``$($Record.install_log)``")
        [void]$md.AppendLine('')
    }
    if ($Record.errors -and $Record.errors.Count -gt 0) {
        [void]$md.AppendLine('## Errores / incidencias')
        [void]$md.AppendLine('')
        foreach ($e in $Record.errors) { [void]$md.AppendLine("- ``$e``") }
        [void]$md.AppendLine('')
    }
    [void]$md.AppendLine('## Recomendaciones')
    [void]$md.AppendLine('')
    $recs = @()
    switch ($App.Type) {
        'msi' {
            $recs += 'Usar siempre msiexec /qn /norestart con /l*v para log verboso reproducible.'
            $recs += 'Para Cortex/MDR/AV: anadir REBOOT=ReallySuppress.'
        }
        'inno' {
            $recs += 'Inno Setup: usar /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- y CLOSEAPPLICATIONS para evitar prompt si hay procesos abiertos.'
            $recs += 'Anadir /LOG=path para captura de log persistente.'
        }
        'nsis' {
            $recs += 'NSIS: /S (mayuscula) es estandar. Sin log nativo: validar por registro/servicios.'
        }
        'installshield' {
            $recs += 'InstallShield wrapper: usar /s /SMS /v"/qn REBOOT=ReallySuppress". /SMS evita que el wrapper retorne antes que msiexec.'
        }
        'burn' {
            $recs += 'WiX Burn: /quiet /norestart /log <path>. /passive si quieres barra de progreso.'
        }
        'office' {
            $recs += 'Office C2R: Display Level=None + AcceptEULA=TRUE en configuration.xml. ForceUpgrade=TRUE para entornos pre-existentes.'
            $recs += 'Compatible Autopilot via Intune en setting Office Apps.'
        }
        'chrome' {
            $recs += 'ChromeSetup.exe: /silent /install. Para entorno empresarial preferir el MSI (.msi) corporativo.'
        }
    }
    if ($Record.status -eq 'fail') {
        $recs += 'Reintentar con flag FallbackUI si esta disponible.'
        $recs += "Revisar log: $($Record.install_log)"
    }
    foreach ($r in $recs) { [void]$md.AppendLine("- $r") }
    [void]$md.AppendLine('')
    [void]$md.AppendLine("_Generado: $(Get-Date -Format 'o') / session $($Script:SessionId)_")

    Set-Content -Path $reportFile -Value $md.ToString() -Encoding UTF8
    Write-Log "  Report: $reportFile"
}

function Write-MasterReport {
    param([array]$Records)
    $file = Join-Path $Script:ReportDir 'INDEX.md'
    $md = New-Object Text.StringBuilder
    [void]$md.AppendLine('# NodeDeploy - Informe maestro')
    [void]$md.AppendLine('')
    [void]$md.AppendLine("- **Session:** ``$($Script:SessionId)``")
    [void]$md.AppendLine("- **Fecha:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    [void]$md.AppendLine("- **Source:** ``$($Script:Source)``")
    [void]$md.AppendLine("- **State file:** ``$($Script:StateFile)``")
    [void]$md.AppendLine('')
    [void]$md.AppendLine('| App | Tipo | Estado | Exit | Tiempo | Evidencias | Reporte |')
    [void]$md.AppendLine('|-----|------|--------|------|--------|------------|---------|')
    foreach ($r in $Records) {
        $safeName = ($r.name -replace '[\\/:*?"<>|]','_')
        $ev = if ($r.evidence) { ($r.evidence -join '; ') } else { '-' }
        [void]$md.AppendLine(("| {0} | {1} | {2} | {3} | {4}s | {5} | [{6}]({6}.md) |" -f `
            $r.name, $r.type, $r.status, $r.exit_code, $r.elapsed_sec, $ev, $safeName))
    }
    [void]$md.AppendLine('')
    Set-Content -Path $file -Value $md.ToString() -Encoding UTF8
    Write-Log "  Master report: $file"
}
#endregion REPORT GENERATOR

# ====================================================================
#region  RESUME-AWARE ORCHESTRATION
# ====================================================================
function Get-PrevRecord {
    param($State, [string]$Key)
    $r = Get-AppState -State $State -Key $Key
    if (-not $r) { return $null }
    # Convert PSCustomObject -> hashtable for in-place updates
    $h = @{}
    foreach ($p in $r.PSObject.Properties) { $h[$p.Name] = $p.Value }
    return $h
}

function Invoke-Phase1 {
    param($State, $Probes, $OfficeBgJob)
    Show-PhaseHeader -Phase '1' -Title 'SILENT INSTALLATIONS' -Subtitle 'MSI / EXE / Inno / NSIS / IS / Burn (Office en background si aplica)'

    $records = @()
    $groups = $Script:Apps | Group-Object { $_.Group } | Sort-Object Name
    foreach ($grp in $groups) {
        $apps = @($grp.Group)

        # Si Office esta en background, skip su grupo en serial
        if ($OfficeBgJob -and $grp.Name -eq '4') {
            Write-Host ''
            Write-Host '  >> Office C2R (background, se valida al final)' -ForegroundColor Cyan
            continue
        }
        $label = switch ($grp.Name) {
            '1' { 'MSI Packages' }
            '2' { 'EXE silent (NSIS/Chrome)' }
            '3' { 'Complex (Inno + IS)' }
            '4' { 'Office C2R' }
            '5' { 'iManage stack' }
            default { "Group $($grp.Name)" }
        }
        Write-Host ''
        Write-Host "  >> $label ($($apps.Count) apps)" -ForegroundColor Cyan
        Write-Host ('  ' + ('-' * 60)) -ForegroundColor DarkGray

        foreach ($app in $apps) {
            $prev = Get-PrevRecord -State $State -Key $app.Name

            # Resume policy: if previous run says ok+validated AND current state matches, skip.
            if ($prev -and $prev.status -in @('ok','skip')) {
                # Re-validate against current OS state (handles snapshot revert)
                $strict = Test-InstalledStrict `
                    -Keywords $app.Detect -AppxName $app.AppxDetect `
                    -ServiceNames $app.ServiceNames -FilePaths $app.FilePaths -Refresh
                if ($strict.Installed) {
                    Show-AppResult -AppName $app.Name -Result 'skip' -Detail '(state+validated)'
                    Write-Log "  SKIP $($app.Name) - state file says ok and validated against current OS"
                    $records += $prev
                    continue
                } else {
                    Write-Log "  $($app.Name) state=ok pero NO instalada en OS (revert?) - reinstalando" 'WARN'
                }
            }
            if ($prev -and $prev.status -eq 'fail' -and $ResumeOnly) {
                Show-AppResult -AppName $app.Name -Result 'skip' -Detail '(prev=fail, ResumeOnly)'
                $records += $prev
                continue
            }

            $rec = Invoke-Install -App $app
            $probe = $Probes | Where-Object { $_.App.Name -eq $app.Name } | Select-Object -First 1
            if ($prev) { $rec.attempts += [int]$prev.attempts }
            Write-AppReport -App $app -Probe $probe -Record $rec
            Set-AppState -State $State -Key $app.Name -Data $rec
            $records += $rec

            # Retry logic
            if ($rec.status -eq 'fail' -and $rec.attempts -lt $Script:MaxRetries) {
                $nextAttempt = $rec.attempts + 1
                Write-LogHost "  Reintento $nextAttempt/$($Script:MaxRetries) para $($app.Name)" 'WARN'
                Start-Sleep -Seconds 3
                $rec2 = Invoke-Install -App $app
                $rec2.attempts += $rec.attempts
                Write-AppReport -App $app -Probe $probe -Record $rec2
                Set-AppState -State $State -Key $app.Name -Data $rec2
                $records[-1] = $rec2
            }
        }
    }
    return $records
}
#endregion ORCHESTRATION

# ====================================================================
#region  MAIN
# ====================================================================
$totalSW = [Diagnostics.Stopwatch]::StartNew()
try {
    try { Clear-Host } catch {}
    Show-Banner

    Write-Log '============================================'
    Write-Log " N0DE_DEPL0Y v3.0  session=$($Script:SessionId)"
    Write-Log " Source:    $Script:Source"
    Write-Log " StatePath: $Script:StatePath"
    Write-Log " Log:       $Script:LogFile"
    Write-Log '============================================'

    Write-Host "  Source:     " -NoNewline -ForegroundColor DarkGray
    Write-Host  $Script:Source     -ForegroundColor Cyan
    Write-Host "  State file: " -NoNewline -ForegroundColor DarkGray
    Write-Host  $Script:StateFile  -ForegroundColor Cyan
    Write-Host "  Log:        " -NoNewline -ForegroundColor DarkGray
    Write-Host  $Script:LogFile    -ForegroundColor Cyan
    Write-Host  ''

    # Load or initialize state
    $state = Load-State
    if ($state) {
        Write-LogHost "Sesion previa detectada: $($state.session_id) ($($state.last_updated)). Reanudando..." 'WARN'
    } else {
        $state = New-State
        Save-State -State $state
        Write-Log 'Nueva sesion creada (no hay state file previo).'
    }

    # Registry cache
    Write-LogHost 'Escaneando aplicaciones instaladas en el sistema...'
    $Global:InstalledCache = Get-InstalledApps
    Write-LogHost "  -> $($Global:InstalledCache.Count) productos en registro."

    # Validate Office XML
    if (-not (Test-Path $Script:OfficeConfigXml)) {
        Write-LogHost "Office configuration.xml NO encontrado: $Script:OfficeConfigXml" 'WARN'
        Write-LogHost 'Office se marcara como fail si esta listado. Genera el XML o desactiva Office.' 'WARN'
    }

    # ---- Phase 0a : Probe ----
    $probes = Invoke-ProbeAll -Apps $Script:Apps
    $state.current_phase = '0a-probe-done'
    Save-State -State $state

    # ---- Phase 0b : Pre-cache (UNC -> local via robocopy MT=16) ----
    if (-not $ProbeOnly -and -not $NoPreCache -and $Script:Source -like '\\*') {
        Show-PhaseHeader -Phase '0b' -Title 'PRE-CACHE LOCAL' -Subtitle 'Robocopy UNC->local multi-threaded para acelerar installs'
        $newSrc = Invoke-PreCache -SourcePath $Script:Source -CachePath $LocalCache
        if ($newSrc -ne $Script:Source) {
            $Script:Source = $newSrc
            # Re-evaluar XML path tras switch a local
            $localXml = Join-Path $Script:Source 'configuration.xml'
            if (Test-Path $localXml) {
                $Script:OfficeConfigXml = (Convert-Path $localXml)
                Write-LogHost "  XML local: $Script:OfficeConfigXml"
            }
            Write-LogHost "  Source switched to: $Script:Source" 'OK'
        }
    }

    # ---- Phase 0c : Office background launch ----
    $officeJob = $null
    if (-not $ProbeOnly -and -not $NoOfficeBackground) {
        $officeApp = $Script:Apps | Where-Object { $_.Type -eq 'office' } | Select-Object -First 1
        if ($officeApp) {
            # Skip si ya instalado
            $strict = Test-InstalledStrict -Keywords $officeApp.Detect -FilePaths $officeApp.FilePaths -Refresh
            if (-not $strict.Installed -and (Test-Path $Script:OfficeConfigXml)) {
                Show-PhaseHeader -Phase '0c' -Title 'OFFICE BACKGROUND' -Subtitle 'Outlook Classic descarga en paralelo mientras instalan MSIs/EXEs'
                $officeJob = Start-OfficeBackground -OfficeApp $officeApp -XmlPath $Script:OfficeConfigXml
            } else {
                Write-LogHost "Office: ya instalado o sin XML, no se lanza background"
            }
        }
    }

    if ($ProbeOnly) {
        Write-LogHost 'ProbeOnly activo. Generando informe inicial sin instalar.' 'OK'
        $stubRecords = @()
        foreach ($p in $probes) {
            $stubFile = if ($p.App.File) { $p.App.File } else { $p.App.Path }
            $argsPreview = ''
            switch ($p.App.Type) {
                'msi' {
                    $logName = "msi_$([IO.Path]::GetFileNameWithoutExtension($stubFile)).log"
                    $extra = if ($p.App.MsiExtra) { " $($p.App.MsiExtra)" } else { '' }
                    $argsPreview = "msiexec.exe /i `"$stubFile`" /qn /norestart /l*v `"$logName`"$extra"
                }
                'office'  { $argsPreview = "$stubFile /configure `"$($Script:OfficeConfigXml)`"" }
                'burn'    { $argsPreview = "$stubFile $($p.App.Args) /log <path>" }
                default   { $argsPreview = "$stubFile $($p.App.Args)" }
            }
            $rec = @{
                name = $p.App.Name
                file = $stubFile
                type = $p.App.Type
                status = 'probed'
                exit_code = $null
                elapsed_sec = 0
                evidence = @()
                args_used = $argsPreview
                install_log = '(none, probe-only)'
                errors = @()
                attempts = 0
                timed_out = $false
                validated = $false
            }
            # Flag tech mismatch between declared Type and probed Tech (after normalization)
            $aliases = @{
                'office_c2r' = 'office'
                'chrome_setup' = 'chrome'
            }
            $probedNorm = if ($aliases.ContainsKey($p.Tech)) { $aliases[$p.Tech] } else { $p.Tech }
            if ($probedNorm -and $p.App.Type -and $probedNorm -ne $p.App.Type -and $probedNorm -ne 'unknown') {
                $rec.errors += "tech_mismatch:declared=$($p.App.Type),probed=$($p.Tech)"
            }
            Write-AppReport -App $p.App -Probe $p -Record $rec
            $stubRecords += $rec
        }
        Write-MasterReport -Records $stubRecords
        Write-Host ''
        Write-Host '  PROBE-ONLY completado. Revisa: ' -NoNewline -ForegroundColor Green
        Write-Host $Script:ReportDir -ForegroundColor Cyan
        exit 0
    }

    # ---- Phase 1 ----
    $state.current_phase = 'phase1'
    Save-State -State $state
    $records = Invoke-Phase1 -State $state -Probes $probes -OfficeBgJob $officeJob

    # ---- Phase 1b : Wait Office background + validar ----
    if ($officeJob) {
        Show-PhaseHeader -Phase '1b' -Title 'WAIT OFFICE BACKGROUND' -Subtitle 'Sincronizando con instalacion Office C2R en paralelo'
        $officeRes = Wait-OfficeBackground -Job $officeJob -Timeout 1800
        $officeApp = $Script:Apps | Where-Object { $_.Type -eq 'office' } | Select-Object -First 1
        $strict = Test-InstalledStrict -Keywords $officeApp.Detect -FilePaths $officeApp.FilePaths -Refresh
        $rec = @{
            name        = $officeApp.Name
            file        = $officeApp.File
            type        = $officeApp.Type
            full_path   = (Join-Path $Script:Source $officeApp.File)
            args_used   = "OfficeSetup.exe /configure `"$Script:OfficeConfigXml`" (background)"
            install_log = "$env:TEMP\OfficeSetup_NodeDeploy"
            exit_code   = $officeRes.ExitCode
            elapsed_sec = $officeRes.ElapsedSec
            evidence    = $strict.Evidence
            errors      = @()
            attempts    = 1
            timed_out   = $false
            validated   = $strict.Installed
            status      = if ($strict.Installed -or $officeRes.ExitCode -eq 0) { 'ok' } else { 'fail' }
            started     = (Get-Date).AddSeconds(-$officeRes.ElapsedSec).ToString('o')
            finished    = (Get-Date -Format 'o')
        }
        $probe = $probes | Where-Object { $_.App.Name -eq $officeApp.Name } | Select-Object -First 1
        Write-AppReport -App $officeApp -Probe $probe -Record $rec
        Set-AppState -State $state -Key $officeApp.Name -Data $rec
        $records += $rec
        Show-AppResult -AppName $officeApp.Name -Result $rec.status -Detail "($($rec.elapsed_sec)s, background)"
    }

    # ---- Phase 2 : Final validation + master report ----
    Show-PhaseHeader -Phase '2' -Title 'FINAL VALIDATION & REPORT'
    Write-MasterReport -Records $records

    $ok   = ($records | Where-Object { $_.status -eq 'ok'   }).Count
    $skp  = ($records | Where-Object { $_.status -eq 'skip' }).Count
    $fl   = ($records | Where-Object { $_.status -eq 'fail' }).Count

    $totalSW.Stop()
    $elapsed = $totalSW.Elapsed.ToString('hh\:mm\:ss')

    Write-Host ''
    Write-Host ('  +' + ('=' * 50) + '+') -ForegroundColor Cyan
    Write-Host '  |          DEPLOYMENT COMPLETE                    |' -ForegroundColor Magenta
    Write-Host ('  +' + ('-' * 50) + '+') -ForegroundColor Cyan
    Write-Host ("   Installed  : $ok").PadRight(54) -ForegroundColor Green
    Write-Host ("   Skipped    : $skp").PadRight(54) -ForegroundColor Yellow
    Write-Host ("   Failed     : $fl").PadRight(54) -ForegroundColor $(if($fl){'Red'}else{'DarkGray'})
    Write-Host ("   Duration   : $elapsed").PadRight(54) -ForegroundColor DarkGray
    Write-Host ("   Reports    : $Script:ReportDir").PadRight(54) -ForegroundColor DarkGray
    Write-Host ("   State      : $Script:StateFile").PadRight(54) -ForegroundColor DarkGray
    Write-Host ('  +' + ('=' * 50) + '+') -ForegroundColor Cyan
    Write-Host ''

    Write-Log "SUMMARY: OK=$ok SKIP=$skp FAIL=$fl Duration=$elapsed"

    $state.current_phase = 'done'
    Save-State -State $state

    # ---- Phase 4 : Post-deploy utilities (interactive consoles for tech) ----
    if (-not $SkipFinalize -and -not $ProbeOnly) {
        Show-PhaseHeader -Phase '4' -Title 'POST-DEPLOY UTILITIES' -Subtitle 'sysdm.cpl + lusrmgr.msc para domain join + admin local'
        try {
            Start-Process -FilePath 'control.exe' -ArgumentList 'sysdm.cpl' -ErrorAction Stop
            Write-Log '  Lanzado sysdm.cpl (System Properties)' 'OK'
            Write-Host '  [OK] sysdm.cpl  -> Computer Name + Domain Join' -ForegroundColor Green
        } catch {
            Write-Log "  sysdm.cpl error: $_" 'WARN'
        }
        try {
            Start-Process -FilePath 'mmc.exe' -ArgumentList 'lusrmgr.msc' -ErrorAction Stop
            Write-Log '  Lanzado lusrmgr.msc (Local Users and Groups)' 'OK'
            Write-Host '  [OK] lusrmgr.msc -> Habilitar admin local + cuentas' -ForegroundColor Green
        } catch {
            Write-Log "  lusrmgr.msc error: $_" 'WARN'
        }
        Write-Host ''
        Write-Host '  Consolas abiertas. Continua manualmente:' -ForegroundColor Cyan
        Write-Host '    1) sysdm.cpl  -> Cambiar nombre + Join al dominio' -ForegroundColor DarkGray
        Write-Host '    2) lusrmgr.msc -> Habilitar / agregar admin local' -ForegroundColor DarkGray
    }

    if ($fl -gt 0) { exit 1 } else { exit 0 }
}
catch {
    Write-Log "EXCEPCION NO CONTROLADA: $_" 'ERROR'
    Write-Log "  StackTrace: $($_.ScriptStackTrace)" 'ERROR'
    Write-Host ''
    Write-Host "  [ERROR CRITICO] $_" -ForegroundColor Red
    Write-Host "  Log: $Script:LogFile" -ForegroundColor Yellow
    exit 99
}
#endregion MAIN
