<#
.SYNOPSIS
    NodeDeploy PRO v4.0 - Deployment engine production-grade, unattended, snapshot-safe.

.DESCRIPTION
    Despliegue desatendido de 15 aplicaciones corporativas en orden estricto y resumible.
    Diseñado para:
      - Imagen base limpia Windows 11 Pro x64 (1809+).
      - Autopilot / Intune Win32App futura (todos los args son CLI-friendly).
      - VM con snapshot pre-deploy (resumable tras revert / reboot).

    Fix v4.0 vs v3.x:
      * Office C2R se espera ANTES de iManage stack (root cause -2147213312).
      * Outlook/Word/Excel/PPT/OfficeClickToRun procs killed antes Work Desktop.
      * MSI logging verbose forzado en wrappers InstallShield (/v"/qn /l*v ...").
      * Pending-reboot detection con auto-skip + flag reboot-required.
      * Cleanup pre-instalación: procesos iManage residuales + servicios.
      * Validación estricta multi-evidencia (registry + service + file + version).
      * Logging único, claro, sin ANSI gimmicks.
      * Sin self-elevation hack (lo hace el .bat con UAC).

.PARAMETER Source
    Carpeta con instaladores. Default: <script>\..\..\1.Node_Preparation

.PARAMETER StatePath
    Persistencia state + logs + reports. Default: <script>\..\state

.PARAMETER Phase
    full     -> todo el flujo (default)
    probe    -> sólo fingerprint, no instala
    install  -> sólo instalaciones (asume probe OK)
    validate -> sólo post-validation
    resume   -> reintenta lo pendiente
    cleanup  -> mata procesos / desinstalaciones parciales iManage

.PARAMETER SkipApps
    Lista nombres a saltar (por display name).

.PARAMETER MaxRetries
    Reintentos por app. Default: 2.

.PARAMETER NonInteractive
    Suprime cualquier pause/read-host (default true).

.NOTES
    Exit codes:
       0 -> todo OK
       1 -> fallos parciales (ver POSTVALIDATE_REPORT.md)
       2 -> source no existe / config inválida
       3 -> reboot requerido (relanzar tras reinicio)
       4 -> sin permisos admin
       5 -> dependencia critica ausente (.NET, PowerShell)
#>
[CmdletBinding()]
param(
    [string]$Source,
    [string]$StatePath,
    [ValidateSet('full','probe','install','validate','resume','cleanup')]
    [string]$Phase = 'full',
    [string[]]$SkipApps = @(),
    [int]$MaxRetries = 2,
    [switch]$NonInteractive = $true,
    [switch]$NoOffice,
    [switch]$ForceReinstall,
    [switch]$SequentialOffice
)

# ============================================================
#region BOOTSTRAP
# ============================================================
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

try {
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $OutputEncoding           = [Text.UTF8Encoding]::new($false)
} catch {}

$Script:Version       = '4.2.3'
$Script:SessionId     = [guid]::NewGuid().ToString('N').Substring(0,8)
$Script:StartTime     = Get-Date
$Script:ScriptDir     = Split-Path -Parent $PSCommandPath
$Script:DefaultSource = Resolve-Path (Join-Path $Script:ScriptDir '..\..\1.Node_Preparation') -ErrorAction SilentlyContinue
$Script:DefaultState  = Join-Path (Split-Path -Parent $Script:ScriptDir) 'state'

if (-not $Source)    { $Source    = $Script:DefaultSource }
if (-not $StatePath) { $StatePath = $Script:DefaultState }

# Admin check
$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '[FATAL] Requiere permisos de Administrador. Lanza desde Deploy.bat.' -ForegroundColor Red
    exit 4
}

# Source presence
if (-not (Test-Path $Source)) {
    Write-Host "[FATAL] Source no existe: $Source" -ForegroundColor Red
    exit 2
}
$Source = (Convert-Path $Source)

# State paths
foreach ($d in @($StatePath, (Join-Path $StatePath 'logs'), (Join-Path $StatePath 'reports'))) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
$Script:StatePath = (Convert-Path $StatePath)
$Script:LogDir    = Join-Path $Script:StatePath 'logs'
$Script:ReportDir = Join-Path $Script:StatePath 'reports'
$Script:StateFile = Join-Path $Script:StatePath 'nodedeploy_state.json'
$Script:LogFile   = Join-Path $Script:LogDir ('Deploy_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

# .NET / PSh version sanity
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "[FATAL] PowerShell 5.0+ requerido (actual: $($PSVersionTable.PSVersion))" -ForegroundColor Red
    exit 5
}
#endregion

# ============================================================
#region LOGGING
# ============================================================
$Script:LogLock = New-Object object
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','OK','WARN','ERROR','STEP','DEBUG')]
        [string]$Level = 'INFO'
    )
    $ts    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "$ts [$Level] $Message"
    [System.Threading.Monitor]::Enter($Script:LogLock)
    try { Add-Content -Path $Script:LogFile -Value $entry -ErrorAction SilentlyContinue }
    finally { [System.Threading.Monitor]::Exit($Script:LogLock) }

    $color = switch ($Level) {
        'OK'    { 'Green' }
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red' }
        'STEP'  { 'Cyan' }
        'DEBUG' { 'DarkGray' }
        default { 'Gray' }
    }
    if ($Level -ne 'DEBUG' -or $env:NODEDEPLOY_DEBUG -eq '1') {
        Write-Host $entry -ForegroundColor $color
    }
}

function Write-Step {
    param([string]$Title)
    $line = '-' * 70
    Write-Log $line 'STEP'
    Write-Log $Title 'STEP'
    Write-Log $line 'STEP'
}

function Write-Banner {
    $b = @"
============================================================
  NodeDeploy PRO v$($Script:Version)   session=$($Script:SessionId)
  Source : $Source
  State  : $($Script:StatePath)
  Log    : $($Script:LogFile)
  Phase  : $Phase
  Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
============================================================
"@
    foreach ($l in ($b -split "`n")) { Write-Log $l.TrimEnd() 'STEP' }
}
#endregion

# ============================================================
#region STATE
# ============================================================
function Get-State {
    if (Test-Path $Script:StateFile) {
        try {
            return Get-Content $Script:StateFile -Raw | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Log "State file corrupto, regenerando: $_" 'WARN'
        }
    }
    return [pscustomobject]@{
        session_id   = $Script:SessionId
        started      = (Get-Date -Format 'o')
        last_updated = (Get-Date -Format 'o')
        source       = $Source
        state_path   = $Script:StatePath
        version      = $Script:Version
        reboot_required = $false
        apps         = @{}
    }
}

function Save-State {
    param($State)
    $State.last_updated = (Get-Date -Format 'o')
    try {
        $json = $State | ConvertTo-Json -Depth 12
        Set-Content -Path $Script:StateFile -Value $json -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Log "Save-State error: $_" 'ERROR'
    }
}

function Get-AppRecord {
    param($State, [string]$Name)
    if ($State.apps -is [hashtable]) {
        if ($State.apps.ContainsKey($Name)) { return $State.apps[$Name] }
    } elseif ($State.apps.PSObject.Properties.Name -contains $Name) {
        return $State.apps.$Name
    }
    return $null
}

function Set-AppRecord {
    param($State, [string]$Name, $Record)
    if ($State.apps -is [hashtable]) {
        $State.apps[$Name] = $Record
    } else {
        if ($State.apps.PSObject.Properties.Name -contains $Name) {
            $State.apps.$Name = $Record
        } else {
            $State.apps | Add-Member -NotePropertyName $Name -NotePropertyValue $Record -Force
        }
    }
    Save-State $State
}
#endregion

# ============================================================
#region SYSTEM CHECKS
# ============================================================
function Test-PendingReboot {
    $signals = @()
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SOFTWARE\Microsoft\Updates\UpdateExeVolatile'
    )
    foreach ($p in $paths) { if (Test-Path $p) { $signals += $p } }
    try {
        $pf = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($pf -and $pf.PendingFileRenameOperations) { $signals += 'PendingFileRenameOperations' }
    } catch {}
    return @{ Pending = ($signals.Count -gt 0); Signals = $signals }
}

function Get-InstalledApps {
    @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    ) | ForEach-Object {
        Get-ItemProperty $_ -ErrorAction SilentlyContinue
    } | Where-Object { $_.DisplayName } | Select-Object DisplayName,DisplayVersion,Publisher,InstallDate
}

function Test-InstalledStrict {
    param(
        [string[]]$Keywords,
        [string[]]$ServiceNames,
        [string[]]$FilePaths,
        [string[]]$ExcludeDetect,
        [string]$MinVersion,
        [switch]$Refresh
    )
    if ($Refresh -or -not $Global:InstalledCache) {
        $Global:InstalledCache = Get-InstalledApps
    }
    $evidence = @()
    $version  = $null
    if ($Keywords) {
        foreach ($kw in $Keywords) {
            $cands = $Global:InstalledCache | Where-Object { $_.DisplayName -like "*$kw*" }
            # v4.2.3: ExcludeDetect filtra falsos positivos (e.g. 'iManage Drive' matchea 'iManage Drive Native')
            if ($ExcludeDetect) {
                foreach ($ex in $ExcludeDetect) {
                    $cands = $cands | Where-Object { $_.DisplayName -notlike "*$ex*" }
                }
            }
            $hit = $cands | Select-Object -First 1
            if ($hit) {
                $evidence += "registry:$($hit.DisplayName) v$($hit.DisplayVersion)"
                $version = $hit.DisplayVersion
                break
            }
        }
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
    $installed = $evidence.Count -gt 0
    if ($installed -and $MinVersion -and $version) {
        try {
            $cur = [version]($version -replace '[^0-9.]','')
            $min = [version]$MinVersion
            if ($cur -lt $min) {
                $evidence += "version_below_min:$version<$MinVersion"
                $installed = $false
            }
        } catch {}
    }
    return @{ Installed = $installed; Evidence = $evidence; Version = $version }
}

function Stop-ProcessSafe {
    param([string[]]$Names, [int]$WaitSec = 2)
    foreach ($n in $Names) {
        Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object {
            try { $_.Kill() } catch {}
        }
    }
    Start-Sleep -Seconds $WaitSec
}

function Wait-MsiQuiet {
    param([int]$Timeout = 180)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Seconds 3
    while ($sw.Elapsed.TotalSeconds -lt $Timeout) {
        $busy = Get-Process -Name 'msiexec' -ErrorAction SilentlyContinue |
                Where-Object { $_.SessionId -ne 0 }
        if (-not $busy) { return $true }
        Start-Sleep -Seconds 3
    }
    Write-Log "Wait-MsiQuiet TIMEOUT ${Timeout}s - msiexec child siguio activo" 'WARN'
    return $false
}
#endregion

# ============================================================
#region PROCESS LAUNCHER
# ============================================================
function Invoke-Installer {
    <#
    .SYNOPSIS
        Lanza un proceso instalador y captura exit code + stderr.
        No mata procesos arbitrarios; KillProcesses sólo en timeout o post-exit explícito.
    #>
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string]$Arguments = '',
        [int]$TimeoutSec   = 600,
        [string[]]$KillOnTimeout = @(),
        [string]$WorkingDirectory
    )
    Write-Log "CMD : `"$FilePath`" $Arguments" 'DEBUG'
    Write-Log "WAIT: ${TimeoutSec}s" 'DEBUG'

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $FilePath
    $psi.Arguments              = $Arguments
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    try { [void]$p.Start() } catch {
        return @{ ExitCode = -99; TimedOut = $false; Stderr = "$_"; Stdout = '' }
    }
    $errTask = $p.StandardError.ReadToEndAsync()
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $finished = $p.WaitForExit($TimeoutSec * 1000)
    if (-not $finished) {
        Write-Log "TIMEOUT ${TimeoutSec}s - matando PID $($p.Id) + hijos" 'WARN'
        try {
            Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.Id)" -ErrorAction SilentlyContinue | ForEach-Object {
                Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            }
        } catch {}
        try { $p.Kill() } catch {}
        Stop-ProcessSafe -Names $KillOnTimeout -WaitSec 2
        return @{ ExitCode = -1; TimedOut = $true; Stderr = ''; Stdout = '' }
    }
    $p.WaitForExit()
    $code = $p.ExitCode
    $err  = ''; $out = ''
    try { $err = $errTask.Result } catch {}
    try { $out = $outTask.Result } catch {}
    $p.Dispose()
    return @{ ExitCode = $code; TimedOut = $false; Stderr = $err; Stdout = $out }
}

function Invoke-MsiSilent {
    param(
        [string]$MsiPath,
        [string]$ExtraProps = '',
        [int]$TimeoutSec = 600,
        [string]$LogFile
    )
    if (-not $LogFile) {
        $LogFile = Join-Path $Script:LogDir ("msi_{0}.log" -f [IO.Path]::GetFileNameWithoutExtension($MsiPath))
    }
    $args = "/i `"$MsiPath`" /qn /norestart /l*v `"$LogFile`""
    if ($ExtraProps) { $args += " $ExtraProps" }
    $res = Invoke-Installer -FilePath 'msiexec.exe' -Arguments $args -TimeoutSec $TimeoutSec
    $res.LogFile = $LogFile
    $res.Command = "msiexec.exe $args"
    return $res
}

function Invoke-InstallShieldSilent {
    <#
    .SYNOPSIS
        Wrapper InstallShield setup.exe con MSI verbose logging.
        /s = silent, /SMS = wait for child msiexec (no return early),
        /v"..." se pasa al MSI subyacente.
    #>
    param(
        [string]$ExePath,
        [string]$ExtraMsiProps = 'REBOOT=ReallySuppress',
        [int]$TimeoutSec = 900,
        [string]$LogFile
    )
    if (-not $LogFile) {
        $LogFile = Join-Path $Script:LogDir ("is_{0}.log" -f [IO.Path]::GetFileNameWithoutExtension($ExePath))
    }
    # IS wrapper /v pasa todo entre comillas al msiexec; escapamos comilla interna con \".
    $vArgs = "/qn /l*v \`"$LogFile\`" $ExtraMsiProps".Trim()
    $args  = "/s /SMS /v`"$vArgs`""
    $res = Invoke-Installer -FilePath $ExePath -Arguments $args -TimeoutSec $TimeoutSec
    # Wrapper retorna antes que msiexec en algunos installers — esperamos hijos.
    Wait-MsiQuiet -Timeout 180 | Out-Null
    $res.LogFile = $LogFile
    $res.Command = "`"$ExePath`" $args"
    return $res
}

function Invoke-BurnSilent {
    param(
        [string]$ExePath,
        [int]$TimeoutSec = 900,
        [string]$LogFile
    )
    if (-not $LogFile) {
        $LogFile = Join-Path $Script:LogDir ("burn_{0}.log" -f [IO.Path]::GetFileNameWithoutExtension($ExePath))
    }
    $args = "/quiet /norestart /log `"$LogFile`""
    $res = Invoke-Installer -FilePath $ExePath -Arguments $args -TimeoutSec $TimeoutSec
    Wait-MsiQuiet -Timeout 180 | Out-Null
    $res.LogFile = $LogFile
    $res.Command = "`"$ExePath`" $args"
    return $res
}

function Invoke-ExeSilent {
    param(
        [string]$ExePath,
        [string]$Arguments,
        [int]$TimeoutSec = 600,
        [string[]]$KillOnTimeout = @()
    )
    $res = Invoke-Installer -FilePath $ExePath -Arguments $Arguments `
                            -TimeoutSec $TimeoutSec -KillOnTimeout $KillOnTimeout
    $res.LogFile = ''
    $res.Command = "`"$ExePath`" $Arguments"
    return $res
}
#endregion

# ============================================================
#region APP CATALOG
# ============================================================
$Script:Apps = @(
    # ---------- GRUPO 1 : MSIs ----------
    [pscustomobject]@{
        Name='AnyDesk'; File='AnyDesk.msi'; Type='msi'; Group=1; Timeout=300
        Detect=@('AnyDesk'); ServiceNames=@('AnyDesk')
        FilePaths=@("${env:ProgramFiles(x86)}\AnyDesk\AnyDesk.exe","$env:ProgramFiles\AnyDesk\AnyDesk.exe")
    },
    [pscustomobject]@{
        Name='AqNet'; File='AqNetInstalacion.msi'; Type='msi'; Group=1; Timeout=300
        Detect=@('AqNet','Aqnet','Deposito Digital')
    },
    [pscustomobject]@{
        Name='Nebula CertAgent'; File='nebula-certAgent-winx64-5.0.0.msi'; Type='msi'; Group=1; Timeout=300
        Detect=@('Nebula','CertAgent','nebulaCERTagent')
        ServiceNames=@('nebulaCERTagent','nebulaCERT')
        FilePaths=@("$env:ProgramFiles\Vintegris\nebulaCERTagent\nebulaCERTagent.exe")
    },
    [pscustomobject]@{
        Name='ESET Management Agent'; File='eset_msi.msi'; Type='msi-eset'; Group=1; Timeout=600
        Detect=@('ESET Management Agent','ESET Remote Administrator Agent')
        ServiceNames=@('EraAgentSvc')
        FilePaths=@("$env:ProgramFiles\ESET\RemoteAdministrator\Agent\ERAAgent.exe")
        IniFile='install_config.ini'
    },

    # ---------- GRUPO 2 : EXE silent ----------
    [pscustomobject]@{
        Name='Google Chrome'; File='ChromeSetup.exe'; Type='exe'; Group=2; Timeout=600
        Args='/silent /install'
        Detect=@('Google Chrome')
        FilePaths=@("$env:ProgramFiles\Google\Chrome\Application\chrome.exe","${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe")
    },
    [pscustomobject]@{
        Name='Autofirma'; File='Autofirma_64_v1_9_installer.exe'; Type='exe'; Group=2; Timeout=300
        Args='/S'
        Detect=@('AutoFirma','Autofirma')
        FilePaths=@("$env:ProgramFiles\AutoFirma\AutoFirma.exe")
    },
    [pscustomobject]@{
        Name='Bit4id Middleware'; File='Bit4id_Middleware.exe'; Type='exe'; Group=2; Timeout=300
        Args='/S'
        Detect=@('Bit4id','Universal Middleware')
        FilePaths=@("$env:ProgramFiles\Bit4id\Universal MW\bin\bit4xpki.exe","${env:ProgramFiles(x86)}\Bit4id\Universal MW\bin\bit4xpki.exe")
    },

    # ---------- GRUPO 3 : Complex EXE ----------
    [pscustomobject]@{
        Name='PDFelement Business'; File='pdfelement_business-15066_10.1.5.exe'; Type='exe'; Group=3; Timeout=900
        Args='/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /NOCANCEL /NOCLOSEAPPLICATIONS /CLOSEAPPLICATIONS'
        Detect=@('PDFelement','Wondershare')
        FilePaths=@("$env:ProgramFiles\Wondershare\PDFelement\PDFelement.exe","${env:ProgramFiles(x86)}\Wondershare\PDFelement\PDFelement.exe")
        KillOnTimeout=@('PDFelement','Wondershare','wshelper','WsAppService','ElevationService')
    },
    [pscustomobject]@{
        Name='MitelConnect'; File='MitelConnect.exe'; Type='installshield'; Group=3; Timeout=900
        MsiExtra='REBOOT=ReallySuppress'
        Detect=@('Mitel','Mitel Connect','MiCollab')
        FilePaths=@("$env:ProgramFiles\Mitel\Connect Client\ConnectAgent.exe","${env:ProgramFiles(x86)}\Mitel\Connect Client\ConnectAgent.exe")
    },

    # ---------- GRUPO 4 : Office (BLOQUEANTE para iManage) ----------
    [pscustomobject]@{
        Name='Microsoft 365 Apps'; File='OfficeSetup.exe'; Type='office'; Group=4; Timeout=2400
        XmlFile='Sc3.0\configuration.xml'
        # Detect: WINWORD.EXE (proxy de Office completo). iManage Work Desktop necesita
        # Word ademas de Outlook; verificamos Word como signal mas fuerte que Outlook solo.
        # Para baseline parcial (Word presente, Outlook no) handler decide via Smart detection.
        Detect=@()
        FilePaths=@("$env:ProgramFiles\Microsoft Office\root\Office16\WINWORD.EXE")
    },

    # ---------- GRUPO 5 : iManage stack (POST Office) ----------
    [pscustomobject]@{
        Name='iManage Agent Services'
        Path='Imanage 2.0\iManage Work Desktop for Windows 10.9.4.39 (x64 Office)\iManageAgentServices.exe'
        Type='installshield'; Group=5; Timeout=600
        MsiExtra='REBOOT=ReallySuppress'
        Detect=@('iManage Agent','iManageAgent')
    },
    [pscustomobject]@{
        Name='iManage Drive'
        Path='Imanage 2.0\iManage Drive for Windows 10.10.0.410\iManage Drive for Windows 10.10.0.410\iManageDriveSetup.exe'
        Type='burn'; Group=5; Timeout=900
        Detect=@('iManage Drive')
        ExcludeDetect=@('Native')
        FilePaths=@("$env:ProgramFiles\iManage\iManage Drive\iManageDrive.exe")
    },
    [pscustomobject]@{
        Name='iManage Drive Native'
        Path='Imanage 2.0\iManage Drive for Windows 10.10.0.410\iManageDrive Native 10.6.1.15\iManageDriveNative.exe'
        Type='burn'; Group=5; Timeout=600
        Detect=@('iManage Drive Native','iManageDriveNative')
    },
    [pscustomobject]@{
        Name='iManage Work Desktop'
        Path='Imanage 2.0\iManage Work Desktop for Windows 10.9.4.39 (x64 Office)\iManageWorkDesktopforWindowsx64.exe'
        Type='installshield-imanage'; Group=5; Timeout=1200
        MsiExtra='REBOOT=ReallySuppress IACCEPTIMANAGEEULA=YES'
        Detect=@('iManage Work Desktop','iManage Work')
        RequiresOffice=$true
    },

    # ---------- GRUPO 6 : AV behavioral (post-iManage para evitar bloqueo InstallScript) ----------
    [pscustomobject]@{
        Name='MDR Cortex XDR'; File='MDR_Windows_Andersen_8_2_x64.msi'; Type='msi'; Group=6; Timeout=900
        Detect=@('Cortex XDR','Cortex','Palo Alto','Traps')
        ServiceNames=@('cyserver','CyveraService')
        MsiExtra='REBOOT=ReallySuppress'
    }
)
#endregion

# ============================================================
#region RESOLVE PATHS
# ============================================================
function Resolve-AppPath {
    param($App)
    $rel = if ($App.Path) { $App.Path } else { $App.File }
    return (Join-Path $Source $rel)
}

function Resolve-OfficeXml {
    $candidates = @(
        (Join-Path $Source 'Sc3.0\configuration.xml'),
        (Join-Path $Source 'configuration.xml'),
        (Join-Path $Script:ScriptDir 'configuration.xml')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return (Convert-Path $c) } }
    return $null
}

function Get-EsetIniProperties {
    param([string]$IniPath)
    if (-not (Test-Path $IniPath)) { return $null }
    $props = @()
    foreach ($line in (Get-Content $IniPath)) {
        $l = $line.Trim()
        if (-not $l -or $l -match '^[#;\[]') { continue }
        if ($l -match '^([A-Z_][A-Z0-9_]*)=(.*)$') {
            $k = $matches[1]; $v = $matches[2].Trim()
            $props += '{0}="{1}"' -f $k, $v
        }
    }
    if ($props.Count -eq 0) { return $null }
    return ($props -join ' ')
}
#endregion

# ============================================================
#region INSTALL ENGINE
# ============================================================
function Install-App {
    param($App, $State)

    $record = Get-AppRecord $State $App.Name
    if (-not $record) {
        $record = [pscustomobject]@{
            name=$App.Name; type=$App.Type; status='pending'
            attempts=0; exit_code=$null; elapsed_sec=0
            started=(Get-Date -Format 'o'); finished=$null
            args_used=''; install_log=''; evidence=@(); errors=@()
            validated=$false; timed_out=$false
        }
    }

    if ($SkipApps -contains $App.Name) {
        $record.status = 'skipped_by_user'
        Set-AppRecord $State $App.Name $record
        Write-Log "SKIP $($App.Name) (excluido via -SkipApps)" 'WARN'
        return $record
    }

    # v4.2.2: Office pre-check especial — skip SOLO si Word AND Outlook ambos presentes.
    # Word presente sin Outlook -> handler bootstrap. Word ausente -> handler full C2R.
    if ($App.Type -eq 'office' -and -not $ForceReinstall) {
        $office16 = "$env:ProgramFiles\Microsoft Office\root\Office16"
        $hasWord    = Test-Path (Join-Path $office16 'WINWORD.EXE')
        $hasOutlook = Test-Path (Join-Path $office16 'OUTLOOK.EXE')
        if ($hasWord -and $hasOutlook) {
            $record.status    = 'ok'
            $record.evidence  = @('file:WINWORD.EXE','file:OUTLOOK.EXE')
            $record.validated = $true
            $record.errors    = @()
            $record.finished  = (Get-Date -Format 'o')
            Set-AppRecord $State $App.Name $record
            Write-Log "SKIP $($App.Name) - Office completo (Word + Outlook ya presentes)" 'OK'
            return $record
        }
        # Word presente sin Outlook, o Office ausente: fall through al handler que decide.
    }

    # Pre-check generico (NO aplica a type=office, manejado arriba).
    # v4.2.1: NO -Refresh aqui (cache se invalida solo post-install). Acelera 15 apps x ~150ms = 2-3s ahorrados.
    # v4.2.3: reset record.errors al marcar ok (evita stale errors como 'reboot_pending' del run anterior).
    if (-not $ForceReinstall -and $App.Type -ne 'office') {
        $check = Test-InstalledStrict -Keywords $App.Detect -ServiceNames $App.ServiceNames -FilePaths $App.FilePaths -ExcludeDetect $App.ExcludeDetect
        if ($check.Installed) {
            $record.status   = 'ok'
            $record.evidence = $check.Evidence
            $record.validated= $true
            $record.errors   = @()
            $record.finished = (Get-Date -Format 'o')
            Set-AppRecord $State $App.Name $record
            Write-Log "SKIP $($App.Name) - ya instalado [$($check.Evidence -join ', ')]" 'OK'
            return $record
        }
    }

    # File exists?
    $file = Resolve-AppPath $App
    if (-not (Test-Path $file)) {
        $record.status = 'fail'
        $record.errors = @("file_not_found:$file")
        $record.finished = (Get-Date -Format 'o')
        Set-AppRecord $State $App.Name $record
        Write-Log "FAIL $($App.Name) - instalador no existe: $file" 'ERROR'
        return $record
    }

    # iManage Work Desktop: gating pre-requisitos
    # iManage Work Desktop 10.9.x exige Word + Outlook (verificado via log:
    # "Work Desktop install did not detect MS Office is installed" sin WINWORD.EXE).
    if ($App.RequiresOffice) {
        $office16 = "$env:ProgramFiles\Microsoft Office\root\Office16"
        $missing = @()
        if (-not (Test-Path (Join-Path $office16 'OUTLOOK.EXE')))  { $missing += 'OUTLOOK.EXE' }
        if (-not (Test-Path (Join-Path $office16 'WINWORD.EXE'))) { $missing += 'WINWORD.EXE' }
        if ($missing.Count -gt 0) {
            $record.status = 'fail'
            $record.errors = @("office_prereq_missing:$($missing -join ',')")
            $record.finished = (Get-Date -Format 'o')
            Set-AppRecord $State $App.Name $record
            Write-Log "FAIL $($App.Name) - requiere Office completo (faltan: $($missing -join ', '))" 'ERROR'
            return $record
        }
        # iManage Work Desktop tambien requiere Agent Services preinstalado
        $asCheck = Test-InstalledStrict -Keywords @('iManage Agent Services','iManageAgentServices') -Refresh
        if (-not $asCheck.Installed) {
            $record.status = 'fail'
            $record.errors = @('imanage_agent_services_missing')
            $record.finished = (Get-Date -Format 'o')
            Set-AppRecord $State $App.Name $record
            Write-Log "FAIL $($App.Name) - requiere iManage Agent Services preinstalado" 'ERROR'
            return $record
        }
        # Cerrar Outlook/Office para liberar locks COM
        Write-Log "Cerrando procesos Office antes de $($App.Name)..." 'INFO'
        Stop-ProcessSafe -Names @('OUTLOOK','WINWORD','EXCEL','POWERPNT','MSACCESS','ONENOTE','OfficeClickToRun','OfficeC2RClient','setup') -WaitSec 3
        Wait-MsiQuiet -Timeout 60 | Out-Null
    }

    # Reboot pendiente?
    $reb = Test-PendingReboot
    if ($reb.Pending) {
        Write-Log "WARN: Reboot pending antes de $($App.Name): $($reb.Signals -join ', ')" 'WARN'
        if (($App.RequiresOffice -or $App.Type -like '*imanage*') -and $env:NODEDEPLOY_FORCE_IMANAGE -ne '1') {
            $record.status = 'deferred_reboot'
            $record.errors = @("reboot_pending:$($reb.Signals -join '|')")
            $record.finished = (Get-Date -Format 'o')
            Set-AppRecord $State $App.Name $record
            $State.reboot_required = $true
            Save-State $State
            Write-Log "DEFERRED $($App.Name) - reboot pendiente. Reanuda con: Deploy.bat resume" 'WARN'
            return $record
        }
    }

    Write-Step "INSTALANDO: $($App.Name)  [$($App.Type)]  file=$(Split-Path $file -Leaf)"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $record.attempts++
    $record.started = (Get-Date -Format 'o')

    # Cleanup pre-instalación iManage Work Desktop
    if ($App.Type -eq 'installshield-imanage') {
        Write-Log "Limpieza pre-instalación iManage..." 'INFO'
        Stop-ProcessSafe -Names @('iManageStayExec','iManageDrive','iManageWorkDesktop','iManageEFS','iManageAgentSvc') -WaitSec 2
    }

    $result = $null
    switch ($App.Type) {
        'msi' {
            $result = Invoke-MsiSilent -MsiPath $file -ExtraProps $App.MsiExtra -TimeoutSec $App.Timeout
        }
        'msi-eset' {
            $iniPath  = Join-Path $Source 'install_config.ini'
            $iniProps = Get-EsetIniProperties $iniPath
            $extra = if ($iniProps) {
                Write-Log "ESET INI cargado: $iniPath ($($iniProps.Length) chars)" 'INFO'
                "P_INSTALL_MODE=1 P_INSTALL_MODE_EULA_ONLY=`"1`" $iniProps"
            } else {
                Write-Log "ESET install_config.ini AUSENTE - agente se instalará UNENROLLED" 'WARN'
                "P_INSTALL_MODE=1"
            }
            $result = Invoke-MsiSilent -MsiPath $file -ExtraProps $extra -TimeoutSec $App.Timeout
        }
        'exe' {
            $result = Invoke-ExeSilent -ExePath $file -Arguments $App.Args -TimeoutSec $App.Timeout -KillOnTimeout $App.KillOnTimeout
        }
        'installshield' {
            $extra = if ($App.MsiExtra) { $App.MsiExtra } else { 'REBOOT=ReallySuppress' }
            $result = Invoke-InstallShieldSilent -ExePath $file -ExtraMsiProps $extra -TimeoutSec $App.Timeout
        }
        'installshield-imanage' {
            # iManage Work Desktop = pure InstallScript Setup Launcher.
            # Sintaxis OFICIAL iManage 10.9.x docs: wrapper /s setup.iss (positional).
            # Path corto sin espacios. setup.iss respuesta default.
            # v4.2.1: si setup.iss YA esta junto al wrapper en source (pre-bundled),
            # se omite el extract step (~50s ahorrados).
            $extractDir = Join-Path $env:TEMP "imWork_$([guid]::NewGuid().ToString('N').Substring(0,6))"
            New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

            $shortExe = Join-Path $extractDir 'iManageWorkDesktopforWindowsx64.exe'
            Copy-Item -LiteralPath $file -Destination $shortExe -Force

            $cwdIss        = Join-Path $extractDir 'setup.iss'
            $preBundledIss = Join-Path (Split-Path -Parent $file) 'setup.iss'
            $isLog         = Join-Path $Script:LogDir ("is_iManageWorkDesktop_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

            if (Test-Path $preBundledIss) {
                Write-Log "setup.iss pre-bundled encontrado en source. Skip extract (~50s)." 'OK'
                Copy-Item -LiteralPath $preBundledIss -Destination $cwdIss -Force
            } else {
                $extPayload = Join-Path $extractDir 'ext'
                Write-Log "setup.iss no pre-bundled. Extrayendo payload de wrapper a $extPayload..." 'INFO'
                Invoke-Installer -FilePath $shortExe -Arguments "/s /extract_all:`"$extPayload`"" -TimeoutSec 300 | Out-Null
                Start-Sleep -Seconds 3
                $bundledIss = Join-Path $extPayload 'Disk1\setup.iss'
                if (Test-Path $bundledIss) {
                    Copy-Item -LiteralPath $bundledIss -Destination $cwdIss -Force
                }
            }

            if (-not (Test-Path $cwdIss)) {
                Write-Log "setup.iss no disponible en $cwdIss" 'ERROR'
                $result = @{ ExitCode = -12; TimedOut = $false; LogFile = ''; Command = '' }
            } else {
                # Per docs: wrapper /s setup.iss (positional). NO /f1, NO /v"/qn".
                Push-Location $extractDir
                try {
                    $result = Invoke-Installer -FilePath $shortExe -Arguments "/s setup.iss" -TimeoutSec $App.Timeout
                } finally {
                    Pop-Location
                }
                $result.LogFile = $isLog
                $result.Command = "`"$shortExe`" /s setup.iss"
                Wait-MsiQuiet -Timeout 60 | Out-Null
            }
            # NB: $extractDir conservado para forense. Limpieza manual si OK.
        }
        'burn' {
            $result = Invoke-BurnSilent -ExePath $file -TimeoutSec $App.Timeout
        }
        'office' {
            # Smart detection v4.1:
            # iManage Work Desktop requiere Word + Outlook minimum.
            # - Si Word presente AND Outlook ausente AND OutlookClassic.exe disponible
            #   -> bootstrap rapido OutlookClassic.exe (anade Outlook a baseline existente)
            # - Else -> Office C2R full configuration.xml (incluye Word/Excel/PPT/Outlook)
            $office16Root = "$env:ProgramFiles\Microsoft Office\root\Office16"
            $outlookClassic = Join-Path $office16Root 'OUTLOOK.EXE'
            $word   = Join-Path $office16Root 'WINWORD.EXE'
            $hasWord = Test-Path $word
            $outlookClassicBootstrap = Join-Path $Source 'OutlookClassic.exe'

            if ($hasWord -and -not (Test-Path $outlookClassic) -and (Test-Path $outlookClassicBootstrap)) {
                Write-Log "Word presente, Outlook ausente. Bootstrap OutlookClassic.exe..." 'INFO'
                Stop-ProcessSafe -Names @('OUTLOOK','OfficeClickToRun','OfficeC2RClient','setup') -WaitSec 3
                $result = Invoke-Installer -FilePath $outlookClassicBootstrap -Arguments '' -TimeoutSec $App.Timeout
                $result.LogFile = ''
                $result.Command = "`"$outlookClassicBootstrap`""
            } else {
                $xml = Resolve-OfficeXml
                if (-not $xml) {
                    Write-Log "Office configuration.xml AUSENTE; abortando Office" 'ERROR'
                    $result = @{ ExitCode = -10; TimedOut = $false; LogFile = ''; Command = '' }
                } else {
                    Stop-ProcessSafe -Names @('OUTLOOK','WINWORD','EXCEL','POWERPNT','OfficeClickToRun','OfficeC2RClient','setup') -WaitSec 3
                    $result = Invoke-Installer -FilePath $file -Arguments "/configure `"$xml`"" -TimeoutSec $App.Timeout
                    $result.LogFile = ''
                    $result.Command = "$file /configure `"$xml`""
                }
            }
        }
        default {
            Write-Log "Tipo desconocido: $($App.Type)" 'ERROR'
            $result = @{ ExitCode = -11; TimedOut = $false; LogFile = ''; Command = '' }
        }
    }

    $sw.Stop()
    $record.elapsed_sec = [int]$sw.Elapsed.TotalSeconds
    $record.exit_code   = $result.ExitCode
    $record.timed_out   = [bool]$result.TimedOut
    $record.args_used   = $result.Command
    $record.install_log = $result.LogFile

    # Post-install validation
    Start-Sleep -Seconds 3
    $check = Test-InstalledStrict -Keywords $App.Detect -ServiceNames $App.ServiceNames -FilePaths $App.FilePaths -ExcludeDetect $App.ExcludeDetect -Refresh
    $record.evidence  = $check.Evidence
    $record.validated = $check.Installed

    if ($check.Installed) {
        $record.status = 'ok'
        Write-Log "OK   $($App.Name)  [$($check.Evidence -join ', ')]  ($($record.elapsed_sec)s)" 'OK'
    } elseif ($result.ExitCode -in 3010,1641) {
        $record.status = 'ok_reboot'
        $record.errors += "reboot_required:$($result.ExitCode)"
        $State.reboot_required = $true
        Write-Log "OK*  $($App.Name) - reboot requerido (exit $($result.ExitCode))" 'WARN'
    } elseif ($result.ExitCode -eq 0) {
        $record.status = 'ok_unverified'
        $record.errors += 'exit_0_no_evidence'
        Write-Log "OK?  $($App.Name) - exit 0 pero sin evidencia en registry/service/file" 'WARN'
    } elseif ($result.TimedOut) {
        $record.status = 'fail_timeout'
        $record.errors += "timeout:$($App.Timeout)s"
        Write-Log "FAIL $($App.Name) - TIMEOUT $($App.Timeout)s" 'ERROR'
    } else {
        $record.status = 'fail'
        $record.errors += "exit_code:$($result.ExitCode)"
        $hex = if ($result.ExitCode -ne $null) {
            try { "0x{0:X8}" -f ([uint32]([int64]$result.ExitCode -band 0xFFFFFFFFL)) }
            catch { "0x?? (raw=$($result.ExitCode))" }
        } else { '' }
        Write-Log "FAIL $($App.Name) - exit $($result.ExitCode) ($hex)" 'ERROR'
        if ($result.Stderr) {
            $line = ($result.Stderr -split "`n" | Select-Object -First 1)
            Write-Log "STDERR: $line" 'ERROR'
        }
    }
    $record.finished = (Get-Date -Format 'o')
    Set-AppRecord $State $App.Name $record
    return $record
}

function Install-Group2Parallel {
    <#
    .SYNOPSIS
        Instala apps Grupo 2 (Chrome / Autofirma / Bit4id) EN PARALELO.
        Seguro: todos son NSIS / EXE bootstrap. No comparten msiexec mutex.
        Ahorra ~2 min vs serial.
    .NOTES
        Disable via env var: NODEDEPLOY_NO_PARALLEL_G2=1
    #>
    param($Apps, $State)

    $handles = @()
    foreach ($app in ($Apps | Sort-Object Name)) {
        # Skip por usuario -> Install-App lo registra
        if ($SkipApps -contains $app.Name) {
            Install-App -App $app -State $State | Out-Null
            continue
        }
        # Pre-check installed -> Install-App lo detecta y skip
        if (-not $ForceReinstall) {
            $check = Test-InstalledStrict -Keywords $app.Detect -ServiceNames $app.ServiceNames -FilePaths $app.FilePaths
            if ($check.Installed) {
                Install-App -App $app -State $State | Out-Null
                continue
            }
        }
        $file = Resolve-AppPath $app
        if (-not (Test-Path $file)) {
            Install-App -App $app -State $State | Out-Null  # marca file_not_found
            continue
        }
        $record = Get-AppRecord $State $app.Name
        if (-not $record) {
            $record = [pscustomobject]@{
                name=$app.Name; type=$app.Type; status='running_parallel'
                attempts=1; exit_code=$null; elapsed_sec=0
                started=(Get-Date -Format 'o'); finished=$null
                args_used=''; install_log=''; evidence=@(); errors=@()
                validated=$false; timed_out=$false
            }
        } else {
            $record.status = 'running_parallel'
            $record.attempts++
            $record.started = (Get-Date -Format 'o')
        }
        $record.args_used = "`"$file`" $($app.Args)"
        Set-AppRecord $State $app.Name $record

        Write-Log "[PAR] Lanzando $($app.Name) (PID asignado)..." 'INFO'
        try {
            $proc = Start-Process -FilePath $file -ArgumentList $app.Args -PassThru -ErrorAction Stop
            $handles += @{ App=$app; Process=$proc; Record=$record; Started=(Get-Date) }
        } catch {
            $record.status = 'fail'
            $record.errors += "start_process:$_"
            $record.finished = (Get-Date -Format 'o')
            Set-AppRecord $State $app.Name $record
            Write-Log "[PAR] FAIL launch $($app.Name): $_" 'ERROR'
        }
    }

    if ($handles.Count -eq 0) { return }
    Write-Log "[PAR] Esperando $($handles.Count) procesos Grupo 2 en paralelo..." 'INFO'

    # Wait all with per-app timeout
    foreach ($h in $handles) {
        $timeout = [int]$h.App.Timeout
        if (-not $timeout) { $timeout = 600 }
        $finished = $h.Process.WaitForExit($timeout * 1000)
        $r = $h.Record
        if (-not $finished) {
            Write-Log "[PAR] TIMEOUT $($h.App.Name) (${timeout}s) - kill PID $($h.Process.Id)" 'WARN'
            try {
                Get-CimInstance Win32_Process -Filter "ParentProcessId=$($h.Process.Id)" -ErrorAction SilentlyContinue | ForEach-Object {
                    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
                }
                $h.Process.Kill()
            } catch {}
            Stop-ProcessSafe -Names $h.App.KillOnTimeout -WaitSec 1
            $r.status = 'fail_timeout'
            $r.timed_out = $true
            $r.errors += "timeout:${timeout}s"
        } else {
            $r.exit_code = $h.Process.ExitCode
        }
        $r.elapsed_sec = [int]((Get-Date) - $h.Started).TotalSeconds
        $r.finished = (Get-Date -Format 'o')
        Set-AppRecord $State $h.App.Name $r
    }

    # Post-validate cada app (cache refresh una sola vez)
    Start-Sleep -Seconds 3
    $Global:InstalledCache = $null  # force refresh next call
    foreach ($h in $handles) {
        $r = Get-AppRecord $State $h.App.Name
        if ($r.timed_out) { continue }
        $check = Test-InstalledStrict -Keywords $h.App.Detect -ServiceNames $h.App.ServiceNames -FilePaths $h.App.FilePaths
        $r.evidence = $check.Evidence
        $r.validated = $check.Installed
        if ($check.Installed) {
            $r.status = 'ok'
            Write-Log "[PAR] OK   $($h.App.Name)  [$($check.Evidence -join ', ')]  ($($r.elapsed_sec)s)" 'OK'
        } elseif ($r.exit_code -in 3010,1641) {
            $r.status = 'ok_reboot'
            $r.errors += "reboot_required:$($r.exit_code)"
            $State.reboot_required = $true
            Write-Log "[PAR] OK*  $($h.App.Name) reboot requerido" 'WARN'
        } elseif ($r.exit_code -eq 0) {
            $r.status = 'ok_unverified'
            $r.errors += 'exit_0_no_evidence'
            Write-Log "[PAR] OK?  $($h.App.Name) exit 0 sin evidencia" 'WARN'
        } else {
            $r.status = 'fail'
            $r.errors += "exit_code:$($r.exit_code)"
            Write-Log "[PAR] FAIL $($h.App.Name) exit $($r.exit_code)" 'ERROR'
        }
        Set-AppRecord $State $h.App.Name $r
    }
}

function Start-OfficeBackground {
    <#
    .SYNOPSIS
        Lanza Office C2R (o OutlookClassic bootstrap) en background.
        Retorna handle con Process + StartedAt para Complete-OfficeBackground.
    #>
    param($App, $State)

    $file = Resolve-AppPath $App
    if (-not (Test-Path $file)) {
        Write-Log "Office: instalador no existe: $file" 'ERROR'
        return $null
    }

    $record = Get-AppRecord $State $App.Name
    if (-not $record) {
        $record = [pscustomobject]@{
            name=$App.Name; type=$App.Type; status='running_bg'
            attempts=0; exit_code=$null; elapsed_sec=0
            started=(Get-Date -Format 'o'); finished=$null
            args_used=''; install_log=''; evidence=@(); errors=@()
            validated=$false; timed_out=$false
        }
    }
    $record.status   = 'running_bg'
    $record.attempts = ($record.attempts + 1)
    $record.started  = (Get-Date -Format 'o')

    $office16Root = "$env:ProgramFiles\Microsoft Office\root\Office16"
    $outlookClassic = Join-Path $office16Root 'OUTLOOK.EXE'
    $word   = Join-Path $office16Root 'WINWORD.EXE'
    $hasWord = Test-Path $word
    $outlookClassicBootstrap = Join-Path $Source 'OutlookClassic.exe'

    Stop-ProcessSafe -Names @('OUTLOOK','WINWORD','EXCEL','POWERPNT','OfficeClickToRun','OfficeC2RClient','setup') -WaitSec 3

    $proc = $null
    try {
        if ($hasWord -and -not (Test-Path $outlookClassic) -and (Test-Path $outlookClassicBootstrap)) {
            Write-Log "[BG] Word presente, Outlook ausente. Bootstrap OutlookClassic.exe..." 'INFO'
            $proc = Start-Process -FilePath $outlookClassicBootstrap -PassThru -ErrorAction Stop
            $record.args_used = "`"$outlookClassicBootstrap`""
        } else {
            $xml = Resolve-OfficeXml
            if (-not $xml) {
                Write-Log "Office configuration.xml AUSENTE; abortando Office" 'ERROR'
                $record.status = 'fail'
                $record.errors = @('config_xml_missing')
                $record.finished = (Get-Date -Format 'o')
                Set-AppRecord $State $App.Name $record
                return $null
            }
            Write-Log "[BG] Lanzando Office C2R: OfficeSetup.exe /configure `"$xml`"" 'INFO'
            $proc = Start-Process -FilePath $file -ArgumentList @('/configure', "`"$xml`"") -PassThru -ErrorAction Stop
            $record.args_used = "`"$file`" /configure `"$xml`""
        }
    } catch {
        Write-Log "Office Start-Process FAIL: $_" 'ERROR'
        $record.status = 'fail'
        $record.errors += "start_process:$_"
        $record.finished = (Get-Date -Format 'o')
        Set-AppRecord $State $App.Name $record
        return $null
    }

    Set-AppRecord $State $App.Name $record
    Write-Log "[BG] Office PID $($proc.Id) lanzado. Continuando con Grupos 1-3 en paralelo..." 'OK'

    return @{
        Process   = $proc
        StartedAt = Get-Date
        Mode      = if ($hasWord -and -not (Test-Path $outlookClassic) -and (Test-Path $outlookClassicBootstrap)) { 'bootstrap' } else { 'c2r' }
    }
}

function Complete-OfficeBackground {
    <#
    .SYNOPSIS
        Espera al proceso Office bg y valida instalacion.
        Polla OUTLOOK.EXE adicional tras exit por si bootstrap salio rapido.
    #>
    param($Bg, $App, $State)
    if (-not $Bg) { return }

    $proc    = $Bg.Process
    $timeout = [int]$App.Timeout
    $record  = Get-AppRecord $State $App.Name

    Write-Log "Esperando Office background (PID $($proc.Id), timeout ${timeout}s)..." 'INFO'

    while (-not $proc.HasExited) {
        $elapsed = (Get-Date) - $Bg.StartedAt
        if ($elapsed.TotalSeconds -gt $timeout) {
            Write-Log "Office BG TIMEOUT (${timeout}s) -> matando PID $($proc.Id)" 'ERROR'
            try {
                Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc.Id)" -ErrorAction SilentlyContinue | ForEach-Object {
                    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
                }
                $proc.Kill()
            } catch {}
            $record.status      = 'fail_timeout'
            $record.timed_out   = $true
            $record.errors     += "timeout:${timeout}s"
            $record.finished    = (Get-Date -Format 'o')
            $record.elapsed_sec = [int]$elapsed.TotalSeconds
            Set-AppRecord $State $App.Name $record
            return
        }
        Start-Sleep -Seconds 30
        Write-Log "Office BG en progreso... $([int]$elapsed.TotalSeconds)s transcurridos" 'DEBUG'
    }

    $proc.WaitForExit()
    $exitCode = $proc.ExitCode
    Start-Sleep -Seconds 5

    $check = Test-InstalledStrict -Keywords $App.Detect -ServiceNames $App.ServiceNames -FilePaths $App.FilePaths -ExcludeDetect $App.ExcludeDetect -Refresh

    # Bootstrap o C2R wrapper pueden salir antes que C2R service termine.
    # Si exit 0 sin OUTLOOK.EXE, poll adicional hasta timeout restante.
    if (-not $check.Installed -and $exitCode -eq 0) {
        Write-Log "Office wrapper exit 0 sin evidencia OUTLOOK.EXE. Polling C2R service hasta ${timeout}s totales..." 'INFO'
        while (((Get-Date) - $Bg.StartedAt).TotalSeconds -lt $timeout) {
            Start-Sleep -Seconds 30
            $check = Test-InstalledStrict -Keywords $App.Detect -ServiceNames $App.ServiceNames -FilePaths $App.FilePaths -ExcludeDetect $App.ExcludeDetect -Refresh
            if ($check.Installed) { break }
            $c2r = Get-Process -Name 'OfficeClickToRun','OfficeC2RClient' -ErrorAction SilentlyContinue
            if (-not $c2r) {
                Write-Log "C2R service no activo y sin OUTLOOK.EXE - abandono poll" 'WARN'
                break
            }
        }
    }

    $record.exit_code   = $exitCode
    $record.elapsed_sec = [int]((Get-Date) - $Bg.StartedAt).TotalSeconds
    $record.finished    = (Get-Date -Format 'o')
    $record.evidence    = $check.Evidence
    $record.validated   = $check.Installed

    if ($check.Installed) {
        $record.status = 'ok'
        Write-Log "OK Office [BG] [$($check.Evidence -join ', ')] ($($record.elapsed_sec)s)" 'OK'
    } elseif ($exitCode -in 3010,1641) {
        $record.status = 'ok_reboot'
        $record.errors += "reboot_required:$exitCode"
        $State.reboot_required = $true
        Write-Log "OK* Office [BG] reboot requerido (exit $exitCode)" 'WARN'
    } elseif ($exitCode -eq 0) {
        $record.status = 'ok_unverified'
        $record.errors += 'exit_0_no_evidence'
        Write-Log "OK? Office [BG] exit 0 pero sin OUTLOOK.EXE" 'WARN'
    } else {
        $record.status = 'fail'
        $record.errors += "exit_code:$exitCode"
        Write-Log "FAIL Office [BG] exit $exitCode" 'ERROR'
    }

    Set-AppRecord $State $App.Name $record
}
#endregion

# ============================================================
#region REPORT
# ============================================================
function Write-FinalReport {
    param($State)
    $reportFile = Join-Path (Split-Path -Parent $Script:StatePath) 'POSTVALIDATE_REPORT.md'

    $apps = if ($State.apps -is [hashtable]) {
        $State.apps.GetEnumerator() | ForEach-Object { $_.Value }
    } else {
        $State.apps.PSObject.Properties | ForEach-Object { $_.Value }
    }

    $ok    = ($apps | Where-Object { $_.status -in 'ok','ok_reboot','ok_unverified' }).Count
    $fail  = ($apps | Where-Object { $_.status -like 'fail*' }).Count
    $defer = ($apps | Where-Object { $_.status -eq 'deferred_reboot' }).Count
    $skip  = ($apps | Where-Object { $_.status -eq 'skipped_by_user' }).Count
    $total = ($Script:Apps | Measure-Object).Count

    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine("# POSTVALIDATE REPORT - NodeDeploy PRO v$($Script:Version)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("- **Session:** $($Script:SessionId)")
    [void]$sb.AppendLine("- **Inicio:** $($Script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))")
    [void]$sb.AppendLine("- **Fin:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    [void]$sb.AppendLine("- **Duración:** $([int]((Get-Date) - $Script:StartTime).TotalSeconds)s")
    [void]$sb.AppendLine("- **Reboot requerido:** $($State.reboot_required)")
    [void]$sb.AppendLine("- **Source:** $Source")
    [void]$sb.AppendLine("- **Log:** $($Script:LogFile)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Resumen")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Métrica | Valor |")
    [void]$sb.AppendLine("|---|---|")
    [void]$sb.AppendLine("| Total apps | $total |")
    [void]$sb.AppendLine("| OK | $ok |")
    [void]$sb.AppendLine("| FAIL | $fail |")
    [void]$sb.AppendLine("| Deferred (reboot) | $defer |")
    [void]$sb.AppendLine("| Skipped (usuario) | $skip |")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Detalle por aplicación")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| App | Status | Exit | Duración | Evidencia | Errores |")
    [void]$sb.AppendLine("|---|---|---|---|---|---|")
    foreach ($a in $Script:Apps) {
        $r = $apps | Where-Object { $_.name -eq $a.Name } | Select-Object -First 1
        if (-not $r) {
            [void]$sb.AppendLine("| $($a.Name) | not_run | - | - | - | - |")
            continue
        }
        $ev = if ($r.evidence) { ($r.evidence -join '; ') } else { '-' }
        $er = if ($r.errors)   { ($r.errors -join '; ')   } else { '-' }
        [void]$sb.AppendLine("| $($r.name) | $($r.status) | $($r.exit_code) | $($r.elapsed_sec)s | $ev | $er |")
    }
    [void]$sb.AppendLine("")
    if ($fail -gt 0) {
        [void]$sb.AppendLine("## Apps con fallo")
        [void]$sb.AppendLine("")
        foreach ($a in ($apps | Where-Object { $_.status -like 'fail*' })) {
            [void]$sb.AppendLine("### $($a.name)")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("- Exit: ``$($a.exit_code)``")
            [void]$sb.AppendLine("- Args: ``$($a.args_used)``")
            [void]$sb.AppendLine("- Log: ``$($a.install_log)``")
            [void]$sb.AppendLine("- Errores: $($a.errors -join '; ')")
            [void]$sb.AppendLine("")
        }
    }
    Set-Content -Path $reportFile -Value $sb.ToString() -Encoding UTF8
    Write-Log "Report: $reportFile" 'OK'
    return $reportFile
}
#endregion

# ============================================================
#region MAIN
# ============================================================
Write-Banner
$State = Get-State

# Pre-checks
Write-Step "PRE-CHECKS"
Write-Log "OS: $((Get-CimInstance Win32_OperatingSystem).Caption)" 'INFO'
$drive = Get-PSDrive C
Write-Log "Disco C: libre $([math]::Round($drive.Free/1GB,1)) GB de $([math]::Round(($drive.Free+$drive.Used)/1GB,1)) GB" 'INFO'
if ($drive.Free -lt 8GB) {
    Write-Log "WARN: <8GB libres en C: - puede fallar Office (descarga ~3GB)" 'WARN'
}
$reb = Test-PendingReboot
if ($reb.Pending) {
    Write-Log "Pending-reboot detectado: $($reb.Signals -join ', ')" 'WARN'
    Write-Log "Se recomienda reiniciar antes de iniciar el deploy." 'WARN'
}

# Inventario presencia archivos
Write-Step "VERIFICANDO ARCHIVOS DE INSTALACIÓN"
$missingApps = @()
foreach ($a in $Script:Apps) {
    $p = Resolve-AppPath $a
    if (Test-Path $p) {
        Write-Log "  [OK] $($a.Name) -> $(Split-Path $p -Leaf)" 'INFO'
    } else {
        Write-Log "  [MISS] $($a.Name) -> $p" 'WARN'
        $missingApps += $a.Name
    }
}
$xmlPath = Resolve-OfficeXml
if (-not $xmlPath) {
    Write-Log "  [MISS] Office configuration.xml" 'WARN'
} else {
    Write-Log "  [OK] Office XML -> $xmlPath" 'INFO'
}

if ($Phase -eq 'probe') {
    Write-Log "Phase=probe: salida sin instalar" 'OK'
    exit 0
}

if ($Phase -eq 'validate') {
    Write-Step "VALIDATE ONLY"
    foreach ($a in $Script:Apps) {
        $c = Test-InstalledStrict -Keywords $a.Detect -ServiceNames $a.ServiceNames -FilePaths $a.FilePaths -Refresh
        $lvl = if ($c.Installed) { 'OK' } else { 'WARN' }
        Write-Log "[$lvl] $($a.Name): $($c.Evidence -join '; ')" $lvl
    }
    Write-FinalReport $State | Out-Null
    exit 0
}

if ($Phase -eq 'cleanup') {
    Write-Step "CLEANUP iManage residuales"
    Stop-ProcessSafe -Names @('iManageStayExec','iManageDrive','iManageWorkDesktop','iManageEFS','iManageAgentSvc') -WaitSec 3
    foreach ($svc in @('imUpdateManagerService','iManageWorkOfflineService')) {
        Get-Service -Name $svc -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Log "Stopping service $svc" 'INFO'
            try { $_.Stop() } catch {}
        }
    }
    Write-Log "Cleanup completo" 'OK'
    exit 0
}

# Phase=full|install|resume → procesa apps
Write-Step "INSTALACIONES (Phase=$Phase)"

# v4.2.3: reset state stale del run anterior antes de procesar:
# - reboot_required = false (lo recalcula cualquier app deferred este run)
# - InstalledCache forzado a refresh para reflejar registry actual (sin esto, app instalada
#   en sesion previa puede no detectarse si cache global stale)
$State.reboot_required = $false
$Global:InstalledCache = Get-InstalledApps
Save-State $State

# v4.1: Office (grupo 4) se arranca en BACKGROUND al inicio.
# Grupos 1-3 corren en foreground en paralelo con Office download/install.
# Antes de Grupo 5 (iManage requiere Outlook) -> Wait Office bg.
# -SequentialOffice fuerza el modo viejo (Office bloqueante en su turno).
$officeApp = $Script:Apps | Where-Object { $_.Group -eq 4 } | Select-Object -First 1
$officeBg  = $null

$canBgOffice = ($officeApp -ne $null) -and (-not $NoOffice) -and (-not $SequentialOffice) -and ($SkipApps -notcontains $officeApp.Name)
if ($canBgOffice -and -not $ForceReinstall) {
    # v4.2.2: Office bg solo se LANZA si Word AND Outlook ambos presentes ya = SKIP bg.
    # Si Word presente sin Outlook -> bg lanza bootstrap (rapido).
    # Si Office ausente -> bg lanza C2R full.
    $office16 = "$env:ProgramFiles\Microsoft Office\root\Office16"
    $hasWord    = Test-Path (Join-Path $office16 'WINWORD.EXE')
    $hasOutlook = Test-Path (Join-Path $office16 'OUTLOOK.EXE')
    if ($hasWord -and $hasOutlook) {
        Write-Log "Office completo ya instalado (Word + Outlook) - sin background launch" 'OK'
        $canBgOffice = $false
    }
}

if ($canBgOffice) {
    Write-Step "=== GRUPO 4 (BACKGROUND) === Office C2R en paralelo con Grupos 1-3"
    $officeBg = Start-OfficeBackground -App $officeApp -State $State
}

$excludeGroup4 = ($officeBg -ne $null)
$groups = $Script:Apps |
    Where-Object { -not ($excludeGroup4 -and $_.Group -eq 4) } |
    Group-Object Group |
    Sort-Object { [int]$_.Name }

foreach ($g in $groups) {
    # Gate antes de Grupo 5: esperar Office bg (iManage requiere OUTLOOK.EXE)
    if ([int]$g.Name -eq 5 -and $officeBg) {
        Write-Step "Esperando Office background antes de Grupo 5 (iManage)..."
        Complete-OfficeBackground -Bg $officeBg -App $officeApp -State $State
        $officeBg = $null
    }

    # v4.2.1: Grupo 2 (NSIS EXEs sin lock MSI) en PARALELO. Override via env var.
    if ([int]$g.Name -eq 2 -and $env:NODEDEPLOY_NO_PARALLEL_G2 -ne '1') {
        Write-Step "=== GRUPO 2 (PARALELO) === Chrome / Autofirma / Bit4id"
        Install-Group2Parallel -Apps $g.Group -State $State
        continue
    }

    Write-Step "=== GRUPO $($g.Name) ==="
    foreach ($app in ($g.Group | Sort-Object Name)) {
        if ($NoOffice -and $app.Type -eq 'office') {
            Write-Log "SKIP $($app.Name) (-NoOffice)" 'WARN'
            continue
        }
        Install-App -App $app -State $State | Out-Null
    }
}

# Si Office bg sigue activo (caso: Grupo 5 fue saltado completo), esperar al final
if ($officeBg) {
    Write-Step "Esperando Office background (final)..."
    Complete-OfficeBackground -Bg $officeBg -App $officeApp -State $State
    $officeBg = $null
}

# Reporte final
Write-Step "REPORT FINAL"
$reportFile = Write-FinalReport $State
$apps = if ($State.apps -is [hashtable]) {
    $State.apps.GetEnumerator() | ForEach-Object { $_.Value }
} else {
    $State.apps.PSObject.Properties | ForEach-Object { $_.Value }
}
$failures = $apps | Where-Object { $_.status -like 'fail*' }
$reboots  = $apps | Where-Object { $_.status -eq 'deferred_reboot' }

Write-Step "RESUMEN"
Write-Log "Total apps procesadas: $($apps.Count)" 'INFO'
Write-Log "OK: $(($apps | Where-Object { $_.status -like 'ok*' }).Count)" 'OK'
Write-Log "FAIL: $($failures.Count)" $(if ($failures.Count -gt 0) { 'ERROR' } else { 'INFO' })
Write-Log "DEFERRED (reboot): $($reboots.Count)" $(if ($reboots.Count -gt 0) { 'WARN' } else { 'INFO' })
Write-Log "Report: $reportFile" 'INFO'

if ($State.reboot_required) {
    Write-Log "=== REBOOT REQUERIDO ===" 'WARN'
    Write-Log "Reinicia el equipo y ejecuta Deploy.bat resume" 'WARN'
    exit 3
}
if ($failures.Count -gt 0) { exit 1 }
exit 0
#endregion
