<#
.SYNOPSIS
    NodeDeploy PRO v5 - Despliegue desatendido de las apps corporativas en portatiles Lenovo.

.DESCRIPTION
    Motor de instalacion resumible con planificador de dos carriles en paralelo:

      Carril MSI  : instaladores que usan Windows Installer (MSI, InstallShield+MSI, WiX Burn).
                    Se serializan y esperan el mutex global _MSIExecute (evita 1618 por
                    Windows Update / Lenovo Vantage / otro MSI en curso).
      Carril EXE  : instaladores NSIS / Inno Setup que no usan Windows Installer. Corren a la
                    vez que el carril MSI.
      Outlook     : Outlook clasico (C2R) se lanza en segundo plano en t=0. Los portatiles
                    Lenovo ya traen Microsoft 365 (Word/Excel/PPT); solo falta Outlook clasico.
                    Solo iManage Work Desktop espera a Outlook.

    Cambios v5 frente a v4.2.x:
      * Reintentos reales (-MaxRetries ya se aplica). 1618 = MSI ocupado -> espera y reintenta.
      * Dependencias explicitas (Autofirma tras Chrome, WD tras Agent Services + Outlook,
        Cortex XDR siempre el ultimo).
      * Outlook clasico en t=0 con el instalador oficial de Microsoft (OutlookClassic.exe); ODT
        (producto OutlookRetail, Version=MatchInstalled) como plan B (-OutlookMethod odt lo invierte).
        Office completo solo con -InstallFullOffice (1.Node_Preparation\configuration.xml).
      * iManage 3.0 (Drive 10.13.0.416, Work Desktop 10.10.2.62, Drive Native 10.6.1.15).
        Drive y Work Desktop son InstallShield InstallScript: /s con el setup.iss junto al exe.
      * QuickEdit de la consola desactivado al arrancar (un clic en la ventana congelaba el script).
      * Chrome Enterprise MSI offline (fallback al stub online ChromeSetup.exe).
      * PDFelement con /NOPAGE (obligatorio en silencioso segun Wondershare) y log Inno.
      * Exclusiones temporales de Defender acotadas (procesos instaladores + carpetas destino),
        registradas en el state y retiradas siempre (tambien tras un run abortado).
      * Secretos del agente ESET enmascarados en log y state.
      * -DryRun: simula instaladores (no instala nada) para probar el planificador.

.PARAMETER Phase
    full | install | resume -> instala lo pendiente (resume re-detecta y reintenta)
    probe    -> solo inventario de ficheros
    validate -> solo post-validacion
    cleanup  -> mata procesos iManage residuales

.NOTES
    Exit codes: 0 OK | 1 fallos parciales | 2 source/config invalida | 3 reboot requerido
                4 sin admin | 5 prerequisito ausente
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
    [switch]$SequentialOffice,
    [switch]$SkipAV,
    [switch]$InstallFullOffice,
    [switch]$NoDefenderBoost,
    [switch]$Serial,
    [switch]$DryRun,
    [ValidateSet('bootstrap','odt')]
    [string]$OutlookMethod = 'bootstrap'
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

$Script:Version       = '5.0.1'
$Script:SessionId     = [guid]::NewGuid().ToString('N').Substring(0,8)
$Script:StartTime     = Get-Date
$Script:ScriptDir     = Split-Path -Parent $PSCommandPath
$Script:DefaultSource = Resolve-Path (Join-Path $Script:ScriptDir '..\..\1.Node_Preparation') -ErrorAction SilentlyContinue
$Script:DefaultState  = Join-Path (Split-Path -Parent $Script:ScriptDir) 'state'
$Script:OfficeAppName = 'Outlook clasico'
$Script:MsiExec       = Join-Path $env:SystemRoot 'System32\msiexec.exe'
$Script:AVApps        = @('ESET Management Agent','MDR Cortex XDR')
if ($env:NODEDEPLOY_SERIAL -eq '1') { $Serial = $true }

if (-not $Source)    { $Source    = $Script:DefaultSource }
if (-not $StatePath) { $StatePath = $Script:DefaultState }
# powershell -File pasa "A,B" como UNA cadena: se separa por comas aqui.
$SkipApps = @($SkipApps | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim(" '`"") } | Where-Object { $_ })
if ($SkipAV)         { $SkipApps  = @($SkipApps) + $Script:AVApps | Select-Object -Unique }

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $DryRun -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '[FATAL] Requiere permisos de Administrador. Lanza desde Deploy.bat.' -ForegroundColor Red
    exit 4
}
if (-not $Source -or -not (Test-Path $Source)) {
    Write-Host "[FATAL] Source no existe: $Source" -ForegroundColor Red
    exit 2
}
$Source = (Convert-Path $Source)

foreach ($d in @($StatePath, (Join-Path $StatePath 'logs'), (Join-Path $StatePath 'reports'))) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
$Script:StatePath = (Convert-Path $StatePath)
$Script:LogDir    = Join-Path $Script:StatePath 'logs'
$Script:ReportDir = Join-Path $Script:StatePath 'reports'
$Script:StateFile = Join-Path $Script:StatePath 'nodedeploy_state.json'
$Script:LogFile   = Join-Path $Script:LogDir ('Deploy_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "[FATAL] PowerShell 5.0+ requerido (actual: $($PSVersionTable.PSVersion))" -ForegroundColor Red
    exit 5
}
#endregion

# ============================================================
#region LOGGING
# ============================================================
function Protect-Secret {
    # Enmascara certificados/passwords del agente ESET y cualquier PASSWORD=... en log/state.
    param([string]$Text)
    if (-not $Text) { return $Text }
    return [regex]::Replace($Text, '(?i)\b(P_CERT_CONTENT|P_CERT_AUTH_CONTENT|P_CERT_PASSWORD|P_LOGIN_PASSWORD|P_PASSWORD|[A-Z_]*PASSWORD|P_REGCODE)=("[^"]*"|\S+)', '$1="***"')
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','OK','WARN','ERROR','STEP','DEBUG')]
        [string]$Level = 'INFO'
    )
    $entry = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, (Protect-Secret $Message)
    Add-Content -Path $Script:LogFile -Value $entry -ErrorAction SilentlyContinue
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

function Get-Elapsed { [int]((Get-Date) - $Script:StartTime).TotalSeconds }

function Format-Duration {
    # 737 -> "12 min 17 s" ; 45 -> "45 s"
    param([int]$Seconds)
    $m = [int][math]::Floor($Seconds / 60); $s = [int]($Seconds % 60)
    if ($m -gt 0) { return ('{0} min {1:D2} s' -f $m, $s) }
    return ('{0} s' -f $s)
}

function Format-Clock {
    # 125 -> "02:05"
    param([int]$Seconds)
    return ('{0:D2}:{1:D2}' -f [int][math]::Floor($Seconds / 60), [int]($Seconds % 60))
}

function Disable-ConsoleQuickEdit {
    # Con QuickEdit activo, un clic en la ventana de consola la deja en modo "Seleccionar" y
    # CONGELA el script (Write-Host bloquea) hasta pulsar una tecla: en el primer Lenovo real hubo
    # que pulsar Enter para que siguiera. Se desactiva para esta consola (sin consola: no hace nada).
    try {
        if (-not ('NodeDeploy.ConsoleMode' -as [type])) {
            Add-Type -Namespace NodeDeploy -Name ConsoleMode -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
        }
        $h = [NodeDeploy.ConsoleMode]::GetStdHandle(-10)   # STD_INPUT_HANDLE
        $mode = [uint32]0
        if ([NodeDeploy.ConsoleMode]::GetConsoleMode($h, [ref]$mode)) {
            # quita ENABLE_QUICK_EDIT_MODE (0x40) y fija ENABLE_EXTENDED_FLAGS (0x80)
            [void][NodeDeploy.ConsoleMode]::SetConsoleMode($h, [uint32](($mode -band 0xFFFFFFBF) -bor 0x80))
            return $true
        }
    } catch {}
    return $false
}
#endregion

# ============================================================
#region STATE
# ============================================================
function Get-State {
    if (Test-Path $Script:StateFile) {
        try {
            $s = Get-Content $Script:StateFile -Raw | ConvertFrom-Json -ErrorAction Stop
            foreach ($p in 'apps','defender_boost','reboot_required') {
                if (-not ($s.PSObject.Properties.Name -contains $p)) {
                    $default = switch ($p) { 'apps' { [pscustomobject]@{} } 'defender_boost' { $null } default { $false } }
                    $s | Add-Member -NotePropertyName $p -NotePropertyValue $default -Force
                }
            }
            return $s
        } catch {
            Write-Log "State file corrupto, regenerando: $_" 'WARN'
        }
    }
    return [pscustomobject]@{
        session_id      = $Script:SessionId
        started         = (Get-Date -Format 'o')
        last_updated    = (Get-Date -Format 'o')
        source          = $Source
        state_path      = $Script:StatePath
        version         = $Script:Version
        reboot_required = $false
        defender_boost  = $null
        apps            = [pscustomobject]@{}
    }
}

function Save-State {
    param($State)
    $State.last_updated = (Get-Date -Format 'o')
    $State.version      = $Script:Version
    try {
        Set-Content -Path $Script:StateFile -Value ($State | ConvertTo-Json -Depth 12) -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Log "Save-State error: $_" 'ERROR'
    }
}

function Get-AppRecord {
    param($State, [string]$Name)
    if ($State.apps.PSObject.Properties.Name -contains $Name) { return $State.apps.$Name }
    return $null
}

function Set-AppRecord {
    param($State, [string]$Name, $Record)
    $State.apps | Add-Member -NotePropertyName $Name -NotePropertyValue $Record -Force
    Save-State $State
}

function New-AppRecord {
    param($App)
    return [pscustomobject]@{
        name = $App.Name; type = $App.Type; lane = $App.Lane; status = 'pending'
        attempts = 0; exit_code = $null; elapsed_sec = 0; start_offset_sec = $null
        started = $null; finished = $null
        args_used = ''; install_log = ''; evidence = @(); errors = @(); history = @()
        validated = $false; timed_out = $false
    }
}

function Get-OrNewRecord {
    param($State, $App)
    $r = Get-AppRecord $State $App.Name
    if (-not $r) { return (New-AppRecord $App) }
    foreach ($p in 'lane','history','start_offset_sec') {
        if (-not ($r.PSObject.Properties.Name -contains $p)) { $r | Add-Member -NotePropertyName $p -NotePropertyValue $null -Force }
    }
    if (-not $r.history) { $r.history = @() }
    return $r
}
#endregion

# ============================================================
#region SYSTEM CHECKS
# ============================================================
function Test-PendingReboot {
    # HARD (CBS / WU / UpdateExeVolatile) vs SOFT (PendingFileRenameOperations). Ninguna bloquea
    # (probado en campo); solo se informa. NODEDEPLOY_DEFER_ON_REBOOT=1 recupera el defer historico.
    $hard = @(); $soft = @()
    foreach ($p in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SOFTWARE\Microsoft\Updates\UpdateExeVolatile')) {
        if (Test-Path $p) { $hard += $p }
    }
    try {
        $pf = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($pf -and $pf.PendingFileRenameOperations) { $soft += 'PendingFileRenameOperations' }
    } catch {}
    return @{ HardPending = ($hard.Count -gt 0); HardSignals = $hard; SoftSignals = $soft }
}

function Get-InstalledApps {
    @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    ) | ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, PSChildName
}

function Test-InstalledStrict {
    param(
        [string[]]$Keywords,
        [string[]]$ServiceNames,
        [string[]]$FilePaths,
        [string[]]$ExcludeDetect,
        [switch]$Refresh
    )
    if ($Refresh -or -not $Script:InstalledCache) { $Script:InstalledCache = Get-InstalledApps }
    $evidence = @(); $version = $null
    foreach ($kw in @($Keywords)) {
        if (-not $kw) { continue }
        $cands = $Script:InstalledCache | Where-Object { $_.DisplayName -like "*$kw*" }
        foreach ($ex in @($ExcludeDetect)) {
            if ($ex) { $cands = $cands | Where-Object { $_.DisplayName -notlike "*$ex*" } }
        }
        $hit = $cands | Select-Object -First 1
        if ($hit) {
            $evidence += "registry:$($hit.DisplayName) v$($hit.DisplayVersion)"
            $version = $hit.DisplayVersion
            break
        }
    }
    foreach ($svc in @($ServiceNames)) {
        if (-not $svc) { continue }
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) { $evidence += "service:$svc($($s.Status))" }
    }
    foreach ($fp in @($FilePaths)) {
        if ($fp -and (Test-Path $fp)) { $evidence += "file:$(Split-Path $fp -Leaf)"; break }
    }
    return @{ Installed = ($evidence.Count -gt 0); Evidence = $evidence; Version = $version }
}

function Test-AppInstalled {
    param($App, [switch]$Refresh)
    if ($App.Type -eq 'office') {
        $os = Get-OfficeState
        $ok = $os.Word -and $os.Outlook
        return @{ Installed = $ok; Evidence = @($(if ($os.Word) { "file:WINWORD.EXE($($os.Arch))" }), $(if ($os.Outlook) { "file:OUTLOOK.EXE($($os.Arch))" }) | Where-Object { $_ }); Version = $null }
    }
    return Test-InstalledStrict -Keywords $App.Detect -ServiceNames $App.ServiceNames -FilePaths $App.FilePaths -ExcludeDetect $App.ExcludeDetect -Refresh:$Refresh
}

function Stop-ProcessSafe {
    param([string[]]$Names, [int]$WaitSec = 2)
    $killed = 0
    foreach ($n in @($Names)) {
        if (-not $n) { continue }
        Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object {
            try { $_.Kill(); $killed++ } catch {}
        }
    }
    if ($killed -and $WaitSec) { Start-Sleep -Seconds $WaitSec }
}

function Stop-ProcessTree {
    param([int]$ProcessId)
    try {
        Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue | ForEach-Object {
            Stop-ProcessTree -ProcessId $_.ProcessId
        }
    } catch {}
    try { Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue } catch {}
}

function Test-MsiBusy {
    <#
        $true si otro proceso tiene el mutex global de Windows Installer (_MSIExecute):
        Windows Update, Lenovo Vantage/System Update, Store, otro MSI... En ese caso lanzar un MSI
        devuelve 1618 al instante (causa tipica de "falla a veces y a la segunda va").
    #>
    if ($DryRun) { return $false }
    $m = $null
    try {
        if (-not [System.Threading.Mutex]::TryOpenExisting('Global\_MSIExecute', [ref]$m)) { return $false }
        try {
            if ($m.WaitOne(0)) { $m.ReleaseMutex(); return $false }
            return $true
        } catch [System.Threading.AbandonedMutexException] {
            try { $m.ReleaseMutex() } catch {}
            return $false
        }
    } catch [System.UnauthorizedAccessException] {
        return $true
    } catch {
        return $false
    } finally {
        if ($m) { $m.Dispose() }
    }
}

function Wait-InstallScriptChildren {
    # Hijos async de InstallScript (registro iwl://, addins COM) siguen vivos tras el exit del wrapper.
    param([string[]]$Names, [int]$Timeout = 60, [int]$StableChecks = 2)
    $sw = [Diagnostics.Stopwatch]::StartNew(); $stable = 0
    while ($sw.Elapsed.TotalSeconds -lt $Timeout) {
        if (-not (Get-Process -Name $Names -ErrorAction SilentlyContinue)) {
            $stable++
            if ($stable -ge $StableChecks) { return $true }
        } else { $stable = 0 }
        Start-Sleep -Seconds 1
    }
    Write-Log "Wait-InstallScriptChildren TIMEOUT ${Timeout}s" 'WARN'
    return $false
}
#endregion

# ============================================================
#region DEFENDER BOOST (exclusiones temporales, acotadas y trazadas)
# ============================================================
# Motivo: Defender RTP escanea cada fichero que escriben los instaladores pesados. Medido:
# iManage Work Desktop 46s -> 398s y PDFelement 53s -> 306s con RTP activo. Se excluyen SOLO
# los procesos instaladores concretos y sus carpetas destino, SOLO durante el despliegue.
# Lo anadido se guarda en state.defender_boost -> se retira aunque el run anterior muriera.
$Script:BoostAdded = @{ Paths = @(); Processes = @() }

function Test-DefenderRtp {
    try { return [bool](Get-MpComputerStatus -ErrorAction Stop).RealTimeProtectionEnabled } catch { return $false }
}

function Save-BoostState {
    param($State)
    $State.defender_boost = [pscustomobject]@{ paths = @($Script:BoostAdded.Paths); processes = @($Script:BoostAdded.Processes) }
    Save-State $State
}

function Add-DefenderBoost {
    param($State, [string[]]$Paths = @(), [string[]]$Processes = @())
    if ($DryRun -or $NoDefenderBoost) { return }
    if (-not (Test-DefenderRtp)) { return }
    $pref = Get-MpPreference -ErrorAction SilentlyContinue
    $havePaths = @($pref.ExclusionPath); $haveProcs = @($pref.ExclusionProcess)
    $nP = 0; $nX = 0
    foreach ($p in @($Paths)) {
        if (-not $p -or ($havePaths -contains $p) -or ($Script:BoostAdded.Paths -contains $p)) { continue }
        try { Add-MpPreference -ExclusionPath $p -ErrorAction Stop; $Script:BoostAdded.Paths += $p; $nP++ } catch {}
    }
    foreach ($x in @($Processes)) {
        if (-not $x -or ($haveProcs -contains $x) -or ($Script:BoostAdded.Processes -contains $x)) { continue }
        try { Add-MpPreference -ExclusionProcess $x -ErrorAction Stop; $Script:BoostAdded.Processes += $x; $nX++ } catch {}
    }
    if ($nP -or $nX) {
        Save-BoostState $State
        Write-Log "Defender boost: +$nP carpetas, +$nX procesos (temporal, se retira al final)" 'INFO'
    }
}

function Remove-DefenderBoost {
    param($State, [switch]$Quiet)
    if ($DryRun) { return }
    $paths = @($Script:BoostAdded.Paths); $procs = @($Script:BoostAdded.Processes)
    foreach ($p in $paths) { try { Remove-MpPreference -ExclusionPath $p -ErrorAction SilentlyContinue } catch {} }
    foreach ($x in $procs) { try { Remove-MpPreference -ExclusionProcess $x -ErrorAction SilentlyContinue } catch {} }
    if (($paths.Count + $procs.Count) -and -not $Quiet) {
        Write-Log "Defender boost retirado ($($paths.Count) carpetas, $($procs.Count) procesos). Estado original restaurado." 'OK'
    }
    $Script:BoostAdded = @{ Paths = @(); Processes = @() }
    if ($State) { $State.defender_boost = $null; Save-State $State }
}

function Clear-StaleDefenderBoost {
    # Exclusiones de un run anterior que murio antes de retirarlas (kill/reboot/timeout).
    param($State)
    if ($DryRun) { return }
    $b = $State.defender_boost
    if ($b -and ((@($b.paths).Count + @($b.processes).Count) -gt 0)) {
        $Script:BoostAdded = @{ Paths = @($b.paths | Where-Object { $_ }); Processes = @($b.processes | Where-Object { $_ }) }
        Write-Log "Defender: retirando exclusiones que dejo un run anterior abortado" 'WARN'
        Remove-DefenderBoost -State $State
    }
    # Legado v4.2.x (iManage WD): nombres exactos que v4 anadia y podia dejar huerfanos.
    try {
        $pref = Get-MpPreference -ErrorAction Stop
        foreach ($x in @('iManageWorkDesktopforWindowsx64.exe','ISBEW64.exe','ISSetup.dll')) {
            if (@($pref.ExclusionProcess) -contains $x) { Remove-MpPreference -ExclusionProcess $x -ErrorAction SilentlyContinue }
        }
    } catch {}
}
#endregion

# ============================================================
#region APP CATALOG
# ============================================================
# Lane : msi (Windows Installer, serializado) | exe (NSIS/Inno, paralelo) | office (background)
# Order: orden dentro del carril. After: espera a que terminen (cualquier resultado).
# Requires: deben terminar OK (si fallan -> 'blocked'). '@office' = Outlook clasico + Word listos.
# Boost: exclusiones Defender temporales (procesos instaladores + carpetas destino).
$imDrive  = 'Imanage 3.0\(1)iManage Drive for Windows 10.13.0.416'
$imWork   = 'Imanage 3.0\(2)iManage Work Desktop for Windows 10.10.2.62 (x64 Office)'
$imNative = 'Imanage 3.0\(3)iManageDrive Native 10.6.1.15'
$pdfExe   = 'pdfelement_business-15066_10.1.5.exe'

$Script:Apps = @(
    # ---------- Outlook clasico (background desde t=0) ----------
    [pscustomobject]@{
        Name=$Script:OfficeAppName; File='OfficeSetup.exe'; Type='office'; Lane='office'; Order=0; Timeout=1800
        Detect=@(); FilePaths=@()
    },

    # ---------- Carril MSI ----------
    [pscustomobject]@{
        Name='AnyDesk'; File='AnyDesk.msi'; Type='msi'; Lane='msi'; Order=10; Timeout=300
        Detect=@('AnyDesk'); ServiceNames=@('AnyDesk')
        FilePaths=@("${env:ProgramFiles(x86)}\AnyDesk\AnyDesk.exe","$env:ProgramFiles\AnyDesk\AnyDesk.exe")
    },
    [pscustomobject]@{
        Name='AqNet'; File='AqNetInstalacion.msi'; Type='msi'; Lane='msi'; Order=20; Timeout=300
        Detect=@('AqNet','Aqnet','Deposito Digital')
    },
    [pscustomobject]@{
        Name='Nebula CertAgent'; File='nebula-certAgent-winx64-5.0.0.msi'; Type='msi'; Lane='msi'; Order=30; Timeout=300
        Detect=@('Nebula','CertAgent','nebulaCERTagent'); ServiceNames=@('nebulaCERTagent','nebulaCERT')
        FilePaths=@("$env:ProgramFiles\Vintegris\nebulaCERTagent\nebulaCERTagent.exe")
    },
    [pscustomobject]@{
        Name='ESET Management Agent'; File='eset_msi.msi'; Type='msi-eset'; Lane='msi'; Order=40; Timeout=600
        Detect=@('ESET Management Agent','ESET Remote Administrator Agent'); ServiceNames=@('EraAgentSvc')
        FilePaths=@("$env:ProgramFiles\ESET\RemoteAdministrator\Agent\ERAAgent.exe")
    },
    [pscustomobject]@{
        # Enterprise MSI offline (~160 MB): sin descarga en el momento, exit codes MSI fiables.
        Name='Google Chrome'; File='GoogleChromeStandaloneEnterprise64.msi'; Type='msi'; Lane='msi'; Order=50; Timeout=600
        Detect=@('Google Chrome')
        FilePaths=@("$env:ProgramFiles\Google\Chrome\Application\chrome.exe","${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe")
        Fallback=[pscustomobject]@{ File='ChromeSetup.exe'; Type='exe'; Lane='exe'; Args='/silent /install' }
    },
    [pscustomobject]@{
        Name='MitelConnect'; File='MitelConnect.exe'; Type='installshield'; Lane='msi'; Order=60; Timeout=900
        MsiExtra='REBOOT=ReallySuppress'
        Detect=@('Mitel Connect','Mitel','MiCollab')
        FilePaths=@("$env:ProgramFiles\Mitel\Connect Client\ConnectAgent.exe","${env:ProgramFiles(x86)}\Mitel\Connect Client\ConnectAgent.exe")
        Boost=@{ Paths=@("${env:ProgramFiles(x86)}\Mitel","$env:ProgramFiles\Mitel") }
    },
    [pscustomobject]@{
        Name='iManage Agent Services'; Path="$imWork\iManageAgentServices.exe"; Type='installshield'; Lane='msi'; Order=70; Timeout=600
        MsiExtra='REBOOT=ReallySuppress'
        Detect=@('iManage Agent Services','iManage Agent','iManageAgent')
    },
    [pscustomobject]@{
        # 10.13 ya NO es WiX Burn (10.10 lo era): es InstallShield InstallScript puro y /quiet
        # abria la GUI. Silencioso = "setup.exe /s" + setup.iss (el que trae el paquete, junto al exe).
        Name='iManage Drive'; Path="$imDrive\iManageDriveSetup.exe"; Type='installshield-imanage'; Lane='msi'; Order=80; Timeout=900
        Detect=@('iManage Drive'); ExcludeDetect=@('Native')
        FilePaths=@("$env:ProgramFiles\iManage\iManage Drive\iManageDrive.exe")
        Boost=@{ Processes=@('iManageDriveSetup.exe','ISBEW64.exe'); Paths=@("$env:ProgramFiles\iManage") }
    },
    [pscustomobject]@{
        Name='iManage Drive Native'; Path="$imNative\iManageDriveNative.exe"; Type='burn'; Lane='msi'; Order=90; Timeout=600
        Requires=@('iManage Drive')
        Detect=@('iManage Drive Native','iManageDriveNative')
    },
    [pscustomobject]@{
        # InstallScript puro. Prerequisitos HARD (log iManage): Agent Services + Office con Word y Outlook.
        Name='iManage Work Desktop'; Path="$imWork\iManageWorkDesktopforWindowsx64.exe"; Type='installshield-imanage'; Lane='msi'; Order=100; Timeout=1200
        Requires=@('iManage Agent Services','@office'); RequiresOffice=$true
        Detect=@('iManage Work Desktop','iManage Work')
        Boost=@{ Processes=@('iManageWorkDesktopforWindowsx64.exe','ISBEW64.exe'); Paths=@("$env:ProgramFiles\iManage","${env:ProgramFiles(x86)}\iManage") }
    },
    [pscustomobject]@{
        # Siempre el ultimo: su monitor de comportamiento bloquea el runtime InstallScript de iManage.
        Name='MDR Cortex XDR'; File='MDR_Windows_Andersen_8_2_x64.msi'; Type='msi'; Lane='msi'; Order=999; Timeout=900
        AfterAll=$true; MsiExtra='REBOOT=ReallySuppress'
        Detect=@('Cortex XDR','Palo Alto','Traps'); ServiceNames=@('cyserver','CyveraService')
    },

    # ---------- Carril EXE (sin Windows Installer, en paralelo al carril MSI) ----------
    [pscustomobject]@{
        Name='Bit4id Middleware'; File='Bit4id_Middleware.exe'; Type='exe'; Lane='exe'; Order=10; Timeout=300
        Args='/S'
        Detect=@('Bit4id','Universal Middleware')
        FilePaths=@("$env:ProgramFiles\Bit4id\Universal MW\bin\bit4xpki.exe","${env:ProgramFiles(x86)}\Bit4id\Universal MW\bin\bit4xpki.exe")
        Boost=@{ Processes=@('Bit4id_Middleware.exe'); Paths=@("$env:ProgramFiles\Bit4id","${env:ProgramFiles(x86)}\Bit4id") }
    },
    [pscustomobject]@{
        # Inno Setup 571 MB. /NOPAGE es obligatorio en silencioso segun la guia de despliegue de
        # Wondershare (sin el, el instalador espera en la pagina final). /LOG deja traza propia.
        Name='PDFelement Business'; File=$pdfExe; Type='inno'; Lane='exe'; Order=20; Timeout=900
        Args='/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /NOPAGE /NOCANCEL /CLOSEAPPLICATIONS'
        Detect=@('PDFelement','Wondershare PDFelement')
        FilePaths=@("$env:ProgramFiles\Wondershare\PDFelement\PDFelement.exe","${env:ProgramFiles(x86)}\Wondershare\PDFelement\PDFelement.exe")
        KillOnTimeout=@('PDFelement','wshelper','WsAppService')
        Boost=@{ Processes=@($pdfExe, [IO.Path]::ChangeExtension($pdfExe, '.tmp')); Paths=@("$env:ProgramFiles\Wondershare","${env:ProgramFiles(x86)}\Wondershare") }
    },
    [pscustomobject]@{
        # Configura Chrome (y Firefox) al instalarse -> debe ir DESPUES de Chrome.
        Name='Autofirma'; File='Autofirma_64_v1_9_installer.exe'; Type='exe'; Lane='exe'; Order=30; Timeout=300
        Args='/S'; After=@('Google Chrome')
        Detect=@('Autofirma','AutoFirma')
        FilePaths=@("$env:ProgramFiles\Autofirma\Autofirma\Autofirma.exe","$env:ProgramFiles\AutoFirma\AutoFirma.exe")
        Boost=@{ Processes=@('Autofirma_64_v1_9_installer.exe'); Paths=@("$env:ProgramFiles\Autofirma") }
    }
)

# Duraciones de referencia (s) para -DryRun (medidas en campo, Defender off, jul-2026).
$Script:DryRunSeconds = @{
    'Outlook clasico'=240; 'AnyDesk'=3; 'AqNet'=7; 'Nebula CertAgent'=6; 'ESET Management Agent'=17
    'Google Chrome'=30; 'MitelConnect'=61; 'iManage Agent Services'=9; 'iManage Drive'=53
    'iManage Drive Native'=5; 'iManage Work Desktop'=45; 'MDR Cortex XDR'=23
    'Bit4id Middleware'=35; 'PDFelement Business'=53; 'Autofirma'=36
}
#endregion

# ============================================================
#region PATHS / OFFICE HELPERS
# ============================================================
function Resolve-AppPath {
    param($App)
    $rel = if ($App.Path) { $App.Path } else { $App.File }
    return (Join-Path $Source $rel)
}

function Resolve-AppDefinition {
    # Si el instalador principal no existe y hay Fallback (p.ej. Chrome MSI -> stub EXE), lo usa.
    param($App)
    $file = Resolve-AppPath $App
    if ((Test-Path $file) -or -not $App.Fallback) { return $App }
    $fb = $App.Fallback
    $clone = $App.PSObject.Copy()
    foreach ($p in $fb.PSObject.Properties) { $clone | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
    $clone | Add-Member -NotePropertyName 'Path' -NotePropertyValue $null -Force
    $clone | Add-Member -NotePropertyName 'UsingFallback' -NotePropertyValue $true -Force
    return $clone
}

function Get-OfficeState {
    if ($DryRun) {
        $sim = $Script:DryRunOffice
        return @{ Word = $sim.Word; Outlook = $sim.Outlook; WordPath = ''; OutlookPath = ''; Arch = 'x64' }
    }
    $state = @{ Word = $false; Outlook = $false; WordPath = ''; OutlookPath = ''; Arch = 'none' }
    foreach ($r in @(
        @{ Path = "$env:ProgramFiles\Microsoft Office\root\Office16"; Arch = 'x64' },
        @{ Path = "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16"; Arch = 'x86' })) {
        if (-not $state.Word) {
            $w = Join-Path $r.Path 'WINWORD.EXE'
            if (Test-Path $w) { $state.Word = $true; $state.WordPath = $w; $state.Arch = $r.Arch }
        }
        if (-not $state.Outlook) {
            $o = Join-Path $r.Path 'OUTLOOK.EXE'
            if (Test-Path $o) { $state.Outlook = $true; $state.OutlookPath = $o; if ($state.Arch -eq 'none') { $state.Arch = $r.Arch } }
        }
    }
    return $state
}

function Get-C2RInfo {
    # Lee la instalacion Click-to-Run existente (Office de fabrica) para anadir Outlook sin
    # cambiar version, canal ni idiomas.
    $k = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    if (-not (Test-Path $k)) { return $null }
    $c = Get-ItemProperty $k -ErrorAction SilentlyContinue
    $channels = @{
        '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' = 'Current'
        '64256afe-f5d9-4f86-8936-8840a6a4f5be' = 'CurrentPreview'
        '5440fd1f-7ecb-4221-8110-145efaa6372f' = 'BetaChannel'
        '55336b82-a18d-4dd6-b5f6-9e5095c314a6' = 'MonthlyEnterprise'
        '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' = 'SemiAnnual'
        'b8f9b850-328d-4355-9145-c59439a0c4cf' = 'SemiAnnualPreview'
    }
    $guid = $null
    foreach ($u in @($c.UpdateChannel, $c.CDNBaseUrl, $c.UnmanagedUpdateUrl)) {
        if ($u -and ($u -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})')) { $guid = $matches[1].ToLower(); break }
    }
    $products = @("$($c.ProductReleaseIds)" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $suite = $products | Where-Object { $_ -match '^O365|ProPlus|Business|HomePrem|Professional|Standard' } | Select-Object -First 1
    return [pscustomobject]@{
        Products = $products
        Suite    = $suite
        Platform = $c.Platform
        Version  = $c.VersionToReport
        Channel  = $(if ($guid) { $channels[$guid] } else { $null })
        Guid     = $guid
        Culture  = $c.ClientCulture
    }
}

function New-OutlookClassicXml {
    # Anade el producto OutlookRetail (lo mismo que hace el instalador "classic Outlook" de
    # Microsoft) sobre el Office de fabrica: misma version (MatchInstalled), mismo canal y
    # mismos idiomas. Sin UI. Devuelve la ruta del XML o $null si no hay datos suficientes.
    param($C2R)
    if (-not $C2R -or -not $C2R.Channel) { return $null }
    $edition = if ($C2R.Platform -eq 'x86') { '32' } else { '64' }
    $target  = if ($C2R.Suite) { $C2R.Suite } else { 'All' }
    $logPath = Join-Path $Script:LogDir 'odt_outlook'
    $xml = @"
<Configuration ID="NodeDeploy-OutlookClassic">
  <Add OfficeClientEdition="$edition" Channel="$($C2R.Channel)" Version="MatchInstalled" AllowCdnFallback="TRUE">
    <Product ID="OutlookRetail">
      <Language ID="MatchInstalled" TargetProduct="$target" />
      <ExcludeApp ID="Groove" />
    </Product>
  </Add>
  <Display Level="None" AcceptEULA="TRUE" />
  <Logging Level="Standard" Path="$logPath" />
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
</Configuration>
"@
    $path = Join-Path $Script:LogDir 'outlook_classic.xml'
    Set-Content -Path $path -Value $xml -Encoding UTF8
    return $path
}

function Resolve-FullOfficeXml {
    foreach ($c in @((Join-Path $Source 'configuration.xml'), (Join-Path $Source 'Sc3.0\configuration.xml'))) {
        if (Test-Path $c) { return (Convert-Path $c) }
    }
    return $null
}

function Get-EsetIniProperties {
    param([string]$IniPath)
    if (-not (Test-Path $IniPath)) { return $null }
    $props = @()
    foreach ($line in (Get-Content $IniPath)) {
        $l = $line.Trim()
        if (-not $l -or $l -match '^[#;\[]') { continue }
        if ($l -match '^([A-Z_][A-Z0-9_]*)=(.*)$') { $props += '{0}="{1}"' -f $matches[1], $matches[2].Trim() }
    }
    if ($props.Count -eq 0) { return $null }
    return (($props | Select-Object -Unique) -join ' ')
}
#endregion

# ============================================================
#region PROCESS JOBS
# ============================================================
function Start-InstallerProcess {
    <#
        Lanza el instalador SIN redirigir stdout/stderr: los instaladores GUI no escriben ahi y
        la redireccion hace que procesos hijos hereden el pipe (el read-to-end de v4 podia quedarse
        esperando a un hijo residente -> "cuelgues" de PDFelement).
    #>
    param([string]$FilePath, [string]$Arguments, [string]$WorkingDirectory)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName        = $FilePath
    $psi.Arguments       = $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    return [System.Diagnostics.Process]::Start($psi)
}

function New-Job {
    # Job = instalador en curso (proceso real o simulado en -DryRun).
    param($App, [string]$FilePath, [string]$Arguments, [string]$WorkingDirectory, [string]$Display, [string]$LogFile, [int]$Attempt)
    $job = @{
        App = $App; Attempt = $Attempt; StartedAt = Get-Date; Timeout = [int]$App.Timeout
        Display = $Display; LogFile = $LogFile; Process = $null; FakeEnd = $null; FakeExit = 0; Error = $null
    }
    if (-not $job.Timeout) { $job.Timeout = 600 }
    if ($DryRun) {
        $sec = $Script:DryRunSeconds[$App.Name]; if (-not $sec) { $sec = 10 }
        $scale = 0.1; if ($env:NODEDEPLOY_DRYRUN_SCALE) { $scale = [double]$env:NODEDEPLOY_DRYRUN_SCALE }
        $job.FakeEnd  = (Get-Date).AddMilliseconds([Math]::Max(200, $sec * 1000 * $scale))
        $job.FakeExit = Get-DryRunExitCode -Name $App.Name -Attempt $Attempt
        return $job
    }
    try {
        $job.Process = Start-InstallerProcess -FilePath $FilePath -Arguments $Arguments -WorkingDirectory $WorkingDirectory
    } catch {
        $job.Error = "start_failed:$($_.Exception.Message)"
    }
    return $job
}

function Get-DryRunExitCode {
    # NODEDEPLOY_DRYRUN_FAIL="AqNet:1618:2,Autofirma:1603:1" -> falla los N primeros lanzamientos.
    param([string]$Name, [int]$Attempt)
    if (-not $env:NODEDEPLOY_DRYRUN_FAIL) { return 0 }
    foreach ($spec in ($env:NODEDEPLOY_DRYRUN_FAIL -split ',')) {
        $p = $spec.Split(':')
        if ($p.Count -ge 3 -and $p[0] -eq $Name -and $Attempt -le [int]$p[2]) { return [int]$p[1] }
    }
    return 0
}

function Test-JobDone {
    param($Job)
    if ($Job.Error) { return $true }
    if ($DryRun) { return ((Get-Date) -ge $Job.FakeEnd) }
    return $Job.Process.HasExited
}

function Test-JobTimedOut {
    param($Job)
    return (((Get-Date) - $Job.StartedAt).TotalSeconds -gt $Job.Timeout)
}

function Get-JobExitCode {
    param($Job)
    if ($Job.Error) { return -99 }
    if ($DryRun) { return $Job.FakeExit }
    try { return $Job.Process.ExitCode } catch { return -98 }
}

function Stop-JobTree {
    param($Job)
    if ($DryRun -or -not $Job.Process) { return }
    Write-Log "TIMEOUT $($Job.App.Name) ($($Job.Timeout)s) - matando PID $($Job.Process.Id) y sus hijos" 'WARN'
    Stop-ProcessTree -ProcessId $Job.Process.Id
    Stop-ProcessSafe -Names $Job.App.KillOnTimeout -WaitSec 1
}
#endregion

# ============================================================
#region INSTALL COMMANDS
# ============================================================
function New-InstallCommand {
    <# Construye comando + log por tipo. Devuelve $null (y Error) si el prep falla. #>
    param($App, $State)
    $file = Resolve-AppPath $App
    $name = [IO.Path]::GetFileNameWithoutExtension($file)
    $cmd  = @{ FilePath = $file; Arguments = ''; WorkingDirectory = $null; LogFile = ''; Error = $null }
    switch ($App.Type) {
        'msi' {
            $cmd.LogFile   = Join-Path $Script:LogDir "msi_$name.log"
            $cmd.FilePath  = $Script:MsiExec
            $cmd.Arguments = "/i `"$file`" /qn /norestart /l*v `"$($cmd.LogFile)`" $($App.MsiExtra)".Trim()
        }
        'msi-eset' {
            $cmd.LogFile = Join-Path $Script:LogDir "msi_$name.log"
            $ini = Get-EsetIniProperties (Join-Path $Source 'install_config.ini')
            $extra = if ($ini) { "P_INSTALL_MODE=1 $ini" } else {
                Write-Log 'ESET install_config.ini AUSENTE - el agente quedara SIN enrolar' 'WARN'
                'P_INSTALL_MODE=1'
            }
            $cmd.FilePath  = $Script:MsiExec
            $cmd.Arguments = "/i `"$file`" /qn /norestart /l*v `"$($cmd.LogFile)`" $extra"
        }
        'exe' {
            $cmd.Arguments = "$($App.Args)"
        }
        'inno' {
            $cmd.LogFile   = Join-Path $Script:LogDir "inno_$name.log"
            $cmd.Arguments = "$($App.Args) /LOG=`"$($cmd.LogFile)`""
        }
        'installshield' {
            # /s silent, /SMS espera al msiexec hijo, /v"..." se pasa al MSI interno.
            $cmd.LogFile = Join-Path $Script:LogDir "is_$name.log"
            $extra = if ($App.MsiExtra) { $App.MsiExtra } else { 'REBOOT=ReallySuppress' }
            $cmd.Arguments = "/s /SMS /v`"/qn /l*v \`"$($cmd.LogFile)\`" $extra`""
        }
        'burn' {
            $cmd.LogFile   = Join-Path $Script:LogDir "burn_$name.log"
            $cmd.Arguments = "/quiet /norestart /log `"$($cmd.LogFile)`""
        }
        'installshield-imanage' {
            # InstallScript (Work Desktop y Drive 10.13): "wrapper /s setup.iss" desde ruta corta sin
            # espacios (docs iManage). setup.iss pre-empaquetado junto al exe (respuesta del propio paquete).
            $cmd.LogFile = Join-Path $Script:LogDir ("is_{0}_{1}.log" -f ($App.Name -replace '\s',''), (Get-Date -Format 'yyyyMMdd_HHmmss'))
            if ($DryRun) { $cmd.Arguments = '/s setup.iss'; break }
            $extractDir = Join-Path $env:TEMP "imIS_$([guid]::NewGuid().ToString('N').Substring(0,6))"
            New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
            $shortExe = Join-Path $extractDir (Split-Path $file -Leaf)
            Copy-Item -LiteralPath $file -Destination $shortExe -Force
            $iss = Join-Path $extractDir 'setup.iss'
            $bundled = Join-Path (Split-Path -Parent $file) 'setup.iss'
            if (Test-Path $bundled) {
                Copy-Item -LiteralPath $bundled -Destination $iss -Force
            } else {
                Write-Log "setup.iss no pre-empaquetado junto al instalador; extrayendo el del propio paquete..." 'INFO'
                $ext = Join-Path $extractDir 'ext'
                $p = Start-InstallerProcess -FilePath $shortExe -Arguments "/s /extract_all:`"$ext`""
                if (-not $p.WaitForExit(300000)) { Stop-ProcessTree -ProcessId $p.Id }
                $found = Get-ChildItem $ext -Recurse -Filter 'setup.iss' -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) { Copy-Item -LiteralPath $found.FullName -Destination $iss -Force }
            }
            if (-not (Test-Path $iss)) { $cmd.Error = 'setup_iss_missing'; break }
            Add-DefenderBoost -State $State -Paths @($extractDir)
            $cmd.FilePath = $shortExe; $cmd.Arguments = '/s setup.iss'; $cmd.WorkingDirectory = $extractDir
        }
        default { $cmd.Error = "tipo_desconocido:$($App.Type)" }
    }
    return $cmd
}
#endregion

# ============================================================
#region OUTLOOK CLASICO (C2R en background)
# ============================================================
function Start-OfficeStep {
    param($App, $State)
    $rec = Get-OrNewRecord $State $App
    $rec.started = (Get-Date -Format 'o'); $rec.start_offset_sec = Get-Elapsed; $rec.status = 'running'
    $rec.attempts = 0; $rec.history = @(); $rec.errors = @(); $rec.lane = 'office'
    $os = Get-OfficeState
    $step = @{ App = $App; Mode = $null; Job = $null; Done = $false; Ok = $false; Tried = @(); StartedAt = Get-Date; Record = $rec; PostWaitUntil = $null }

    if ($os.Word -and $os.Outlook) {
        $step.Done = $true; $step.Ok = $true; $rec.status = 'ok'; $rec.validated = $true
        $rec.evidence = @("file:WINWORD.EXE($($os.Arch))", "file:OUTLOOK.EXE($($os.Arch))"); $rec.errors = @()
        $rec.finished = (Get-Date -Format 'o')
        Set-AppRecord $State $App.Name $rec
        Write-Log "Outlook clasico ya presente junto a Word ($($os.Arch)) - nada que instalar" 'OK'
        return $step
    }
    if (-not $os.Word) {
        if ($InstallFullOffice) {
            $xml = Resolve-FullOfficeXml
            if ($xml) {
                $step.Mode = 'full'
                Write-Log "[OFFICE] Word ausente + -InstallFullOffice: Microsoft 365 completo ($xml)" 'WARN'
                Start-OfficeProcess -Step $step -State $State -FilePath (Resolve-AppPath $App) -Arguments "/configure `"$xml`"" -Display "OfficeSetup.exe /configure $xml"
                return $step
            }
        }
        $step.Done = $true; $rec.status = 'fail'; $rec.errors = @('word_missing')
        $rec.finished = (Get-Date -Format 'o')
        Set-AppRecord $State $App.Name $rec
        Write-Log "[OFFICE] Word NO esta instalado. Los Lenovo traen Microsoft 365 de fabrica: revisa el equipo. iManage Work Desktop quedara bloqueado. (Office completo: -InstallFullOffice)" 'ERROR'
        return $step
    }
    Start-OutlookInstall -Step $step -State $State -Method $OutlookMethod
    return $step
}

function Start-OutlookInstall {
    <#
        bootstrap (defecto): instalador oficial de Microsoft "classic Outlook" (OutlookClassic.exe).
                  Ha funcionado en todos los Lenovo reales; arranca en t=0 y se ve progresar.
        odt     : ODT con OutlookRetail + Version=MatchInstalled (sin UI). En el primer Lenovo real
                  fallo tras ~2 min en silencio y retraso Outlook -> queda como plan B.
        Si el metodo elegido falla o no esta disponible, se prueba el otro.
    #>
    param($Step, $State, [string]$Method)
    $Step.Tried += $Method
    $Step.PostWaitUntil = $null
    if ($Method -eq 'bootstrap') {
        $boot = Join-Path $Source 'OutlookClassic.exe'
        if ($DryRun -or (Test-Path $boot)) {
            $Step.Mode = 'bootstrap'
            Write-Log "[OFFICE] Word presente, Outlook ausente -> OutlookClassic.exe (instalador Microsoft 'classic Outlook') en t=0" 'INFO'
            Start-OfficeProcess -Step $Step -State $State -FilePath $boot -Arguments '' -Display '"OutlookClassic.exe"'
            return
        }
        Write-Log '[OFFICE] OutlookClassic.exe no existe' 'WARN'
    } else {
        $odt = Resolve-AppPath $Step.App
        $c2r = if ($DryRun) { [pscustomobject]@{ Products=@('O365BusinessRetail'); Suite='O365BusinessRetail'; Platform='x64'; Version='16.0.20026.20112'; Channel='Current' } } else { Get-C2RInfo }
        $xml = if ($DryRun) { 'dryrun.xml' } elseif ((Test-Path $odt) -and $c2r) { New-OutlookClassicXml -C2R $c2r } else { $null }
        if ($xml) {
            $Step.Mode = 'odt'
            Write-Log ("[OFFICE] ODT OutlookRetail sobre {0} v{1} canal {2} (MatchInstalled)" -f ($c2r.Products -join '+'), $c2r.Version, $c2r.Channel) 'INFO'
            Start-OfficeProcess -Step $Step -State $State -FilePath $odt -Arguments "/configure `"$xml`"" -Display "OfficeSetup.exe /configure $xml"
            return
        }
        Write-Log '[OFFICE] Sin datos C2R/canal para ODT' 'WARN'
    }
    $other = if ($Method -eq 'bootstrap') { 'odt' } else { 'bootstrap' }
    if ($Step.Tried -notcontains $other) { Start-OutlookInstall -Step $Step -State $State -Method $other; return }
    $Step.Done = $true
    $Step.Record.status = 'fail'; $Step.Record.errors += 'outlook_sin_instalador'
    Set-AppRecord $State $Step.App.Name $Step.Record
    Write-Log '[OFFICE] Sin instalador de Outlook disponible (OutlookClassic.exe / ODT). Outlook clasico NO instalado' 'ERROR'
}

function Start-OfficeProcess {
    param($Step, $State, [string]$FilePath, [string]$Arguments, [string]$Display)
    $Step.Record.attempts++
    $Step.Record.args_used = $Display
    $Step.Job = New-Job -App $Step.App -FilePath $FilePath -Arguments $Arguments -Display $Display -Attempt $Step.Record.attempts
    $Step.Job.Timeout = if ($Step.Mode -eq 'bootstrap') { 1200 } else { [int]$Step.App.Timeout }
    Set-AppRecord $State $Step.App.Name $Step.Record
}

function Update-OfficeStep {
    # Llamado en cada vuelta del planificador. Fuente de verdad: EXE en disco + exit del setup.
    param($Step, $State)
    if ($Step.Done -or -not $Step.Job) { return }
    $job = $Step.Job
    $done = Test-JobDone $job
    if (-not $done -and -not (Test-JobTimedOut $job)) { return }
    if (-not $done) { Stop-JobTree $job }
    $code = if ($done) { Get-JobExitCode $job } else { -1 }

    if ($DryRun -and $code -eq 0) { $Script:DryRunOffice.Outlook = $true }
    $os = Get-OfficeState
    if (-not $DryRun -and $done -and $code -eq 0 -and $Step.Mode -eq 'bootstrap' -and -not $os.Outlook) {
        # El bootstrapper de consumo puede salir antes de que C2R termine de copiar OUTLOOK.EXE:
        # se sigue comprobando en las siguientes vueltas (sin bloquear los carriles) hasta 120 s.
        if (-not $Step.PostWaitUntil) { $Step.PostWaitUntil = (Get-Date).AddSeconds(120) }
        if ((Get-Date) -lt $Step.PostWaitUntil) { return }
    }
    $ok = $os.Outlook -and $os.Word
    $rec = $Step.Record
    $rec.history += [pscustomobject]@{ attempt = $job.Attempt; mode = $Step.Mode; exit = $code; sec = [int]((Get-Date) - $job.StartedAt).TotalSeconds }
    $rec.exit_code = $code

    if ($ok) {
        $Step.Done = $true; $Step.Ok = $true
        $rec.status = if ($code -in 3010,1641) { 'ok_reboot' } else { 'ok' }
        if ($code -in 3010,1641) { $State.reboot_required = $true }
        $rec.validated = $true; $rec.errors = @()
        $rec.evidence = @("file:WINWORD.EXE($($os.Arch))", "file:OUTLOOK.EXE($($os.Arch))", "mode:$($Step.Mode)")
        $rec.elapsed_sec = [int]((Get-Date) - $Step.StartedAt).TotalSeconds
        $rec.finished = (Get-Date -Format 'o')
        Set-AppRecord $State $Step.App.Name $rec
        Write-Log "OK   Outlook clasico [$($Step.Mode), exit $code] ($($rec.elapsed_sec)s)" 'OK'
        return
    }
    $rec.errors += "$($Step.Mode)_exit:$code"
    Write-Log "[OFFICE] $($Step.Mode) termino exit $code sin OUTLOOK.EXE" 'WARN'
    $other = switch ($Step.Mode) { 'bootstrap' { 'odt' } 'odt' { 'bootstrap' } default { $null } }
    if ($other -and $Step.Tried -notcontains $other) {
        Start-OutlookInstall -Step $Step -State $State -Method $other
        return
    }
    $Step.Done = $true
    $rec.status = if (-not $done) { 'fail_timeout' } else { 'fail' }
    $rec.timed_out = -not $done
    $rec.elapsed_sec = [int]((Get-Date) - $Step.StartedAt).TotalSeconds
    $rec.finished = (Get-Date -Format 'o')
    Set-AppRecord $State $Step.App.Name $rec
    Write-Log "FAIL Outlook clasico - revisa $($Script:LogDir)\odt_outlook" 'ERROR'
}
#endregion

# ============================================================
#region PLANIFICADOR
# ============================================================
$Script:TerminalStatus = @('ok','ok_reboot','ok_unverified','fail','fail_timeout','blocked','skipped_by_user','deferred_reboot')
$Script:OkStatus       = @('ok','ok_reboot','ok_unverified')

function Get-AppStatus {
    param($State, [string]$Name)
    $r = Get-AppRecord $State $Name
    if ($r) { return $r.status }
    return $null
}

function Get-ReadyCheck {
    <#
        Devuelve 'ready' | 'wait' | 'blocked:<motivo>' para una app pendiente.
    #>
    param($Entry, $State, $Office, $PendingNames)
    $app = $Entry.App
    foreach ($req in @($app.Requires)) {
        if (-not $req) { continue }
        if ($req -eq '@office') {
            if ($Office) {
                if (-not $Office.Done) { return 'wait' }
                if (-not $Office.Ok) { return 'blocked:outlook_or_word_missing' }
            } else {
                # Sin paso Office (-NoOffice / skip): vale si Word + Outlook ya estan.
                $os = Get-OfficeState
                if (-not ($os.Word -and $os.Outlook)) { return 'blocked:outlook_or_word_missing' }
            }
            continue
        }
        $st = Get-AppStatus $State $req
        if (($PendingNames -contains $req) -or ($st -notin $Script:TerminalStatus)) { return 'wait' }
        if ($st -eq 'skipped_by_user') {
            # Saltada por el usuario pero ya presente en el equipo -> requisito cumplido.
            $dep = $Script:Apps | Where-Object { $_.Name -eq $req } | Select-Object -First 1
            if ($dep -and ($DryRun -or (Test-AppInstalled -App $dep).Installed)) { continue }
        }
        if ($st -notin $Script:OkStatus) { return "blocked:requires_$($req -replace '\s','_')" }
    }
    foreach ($aft in @($app.After)) {
        if ($aft -and ($PendingNames -contains $aft)) { return 'wait' }
    }
    if ($app.AfterAll) {
        $others = @($PendingNames | Where-Object { $_ -ne $app.Name })
        if ($others.Count -gt 0) { return 'wait' }
        if ($Office -and -not $Office.Done) { return 'wait' }
    }
    if ((Get-Date) -lt $Entry.NotBefore) { return 'wait' }
    return 'ready'
}

function Start-AppJob {
    param($Entry, $State)
    $app = $Entry.App
    $rec = Get-OrNewRecord $State $app
    $Entry.Attempt++
    $Entry.Launches++
    $rec.attempts++
    $rec.status = 'running'
    $rec.lane   = $app.Lane
    if (-not $rec.started -or $Entry.Attempt -eq 1) { $rec.started = (Get-Date -Format 'o'); $rec.start_offset_sec = Get-Elapsed }

    if ($app.RequiresOffice -and -not $DryRun) {
        # Libera locks COM de Office. NO se tocan OfficeClickToRun/OfficeC2RClient (v4 los mataba
        # y podia romper un Outlook que aun estaba terminando de integrarse).
        Stop-ProcessSafe -Names @('OUTLOOK','WINWORD','EXCEL','POWERPNT','ONENOTE','MSACCESS') -WaitSec 2
        $im = @('iManageStayExec','iManageDrive','iManageWorkDesktop','iManageEFS','iManageAgentSvc')
        if (Get-Process -Name $im -ErrorAction SilentlyContinue) { Stop-ProcessSafe -Names $im -WaitSec 2 }
    }

    $cmd = New-InstallCommand -App $app -State $State
    $display = if ($cmd.FilePath -eq $Script:MsiExec) { "msiexec.exe $($cmd.Arguments)" } else { "`"$($cmd.FilePath)`" $($cmd.Arguments)" }
    $rec.args_used   = Protect-Secret $display
    $rec.install_log = $cmd.LogFile
    Set-AppRecord $State $app.Name $rec

    $tag = if ($Serial) { 'SER' } else { $app.Lane.ToUpper() }
    $busy = if ($Entry.BusyRetries) { " tras $($Entry.BusyRetries) espera(s) por MSI ocupado" } else { '' }
    Write-Log ("[{0}] >> {1} (intento {2}/{3}{4}) [{5}]{6}" -f $tag, $app.Name, $Entry.Attempt, ($MaxRetries + 1), $busy, $app.Type, $(if ($app.UsingFallback) { ' (fallback)' } else { '' })) 'STEP'
    Write-Log "CMD : $display" 'DEBUG'

    if ($cmd.Error) {
        return @{ Entry = $Entry; Job = @{ App = $app; Attempt = $Entry.Attempt; StartedAt = Get-Date; Timeout = 1; Error = $cmd.Error; Process = $null; LogFile = $cmd.LogFile } }
    }
    $job = New-Job -App $app -FilePath $cmd.FilePath -Arguments $cmd.Arguments -WorkingDirectory $cmd.WorkingDirectory -Display $display -LogFile $cmd.LogFile -Attempt $Entry.Launches
    return @{ Entry = $Entry; Job = $job }
}

function Get-RetryDelay {
    # $null = no reintentar. 1618 (MSI ocupado) no consume presupuesto de reintentos.
    param([int]$ExitCode, [bool]$TimedOut, $Entry)
    if ($ExitCode -eq 1618) {
        $Entry.BusyRetries++
        if ($Entry.BusyRetries -le 20) { $Entry.Attempt--; return 15 }
        return $null
    }
    if ($ExitCode -in 1601,1602,1619,1620,1633,1638,-99) { return $null }  # config/paquete/cancelado: reintentar no ayuda
    if ($Entry.Attempt -gt $MaxRetries) { return $null }
    if ($TimedOut) { return 5 }
    return @(10, 30, 60)[[Math]::Min($Entry.Attempt - 1, 2)]
}

function Complete-AppJob {
    <# Valida, registra y decide reintento. Devuelve delay (s) si hay que reintentar, si no $null. #>
    param($Entry, $Job, $State, [bool]$TimedOut)
    $app  = $Entry.App
    $rec  = Get-OrNewRecord $State $app
    $code = if ($TimedOut) { -1 } else { Get-JobExitCode $Job }
    $sec  = [int]((Get-Date) - $Job.StartedAt).TotalSeconds

    if ($app.Type -eq 'installshield-imanage' -and -not $DryRun -and -not $TimedOut) {
        $exeBase = [IO.Path]::GetFileNameWithoutExtension((Resolve-AppPath $app))
        Wait-InstallScriptChildren -Names @('ISBEW64', 'iuninst', $exeBase) -Timeout 90 | Out-Null
    }

    # Validacion con reintento corto (el registro puede tardar 1-2 s en reflejar el alta).
    $check = @{ Installed = $false; Evidence = @() }
    if ($DryRun) {
        if ($code -in 0,3010,1641) { $check = @{ Installed = $true; Evidence = @('dryrun') } }
    } elseif (-not $TimedOut -and -not $Job.Error) {
        for ($i = 0; $i -lt 4; $i++) {
            $check = Test-AppInstalled -App $app -Refresh
            if ($check.Installed -or $code -notin 0,3010,1641) { break }
            Start-Sleep -Seconds 2
        }
    }

    $rec.exit_code = $code; $rec.timed_out = $TimedOut; $rec.elapsed_sec = $sec
    $rec.evidence = $check.Evidence; $rec.validated = [bool]$check.Installed
    $rec.history += [pscustomobject]@{ attempt = $Job.Attempt; exit = $code; sec = $sec; at = Get-Elapsed }
    $hex = try { '0x{0:X8}' -f ([uint32]([int64]$code -band 0xFFFFFFFFL)) } catch { '' }
    $tag = if ($Serial) { 'SER' } else { $app.Lane.ToUpper() }

    if ($check.Installed) {
        $rec.status = if ($code -in 3010,1641) { 'ok_reboot' } else { 'ok' }
        if ($code -in 3010,1641) { $State.reboot_required = $true; $rec.errors += "reboot_required:$code" }
        else { $rec.errors = @() }
        $rec.finished = (Get-Date -Format 'o')
        Set-AppRecord $State $app.Name $rec
        Write-Log ("[{0}] OK   {1} ({2}s) [{3}]" -f $tag, $app.Name, $sec, ($check.Evidence -join ', ')) 'OK'
        return $null
    }
    if ($code -in 3010,1641) {
        $rec.status = 'ok_reboot'; $State.reboot_required = $true; $rec.errors += "reboot_required:$code"
        $rec.finished = (Get-Date -Format 'o'); Set-AppRecord $State $app.Name $rec
        Write-Log "[$tag] OK*  $($app.Name) - reboot requerido (exit $code)" 'WARN'
        return $null
    }
    if ($code -eq 0) {
        # exit 0 sin evidencia: no se reintenta (reinstalar no suele ayudar); se revalida al final.
        $rec.status = 'ok_unverified'; $rec.errors += 'exit_0_no_evidence'
        $rec.finished = (Get-Date -Format 'o'); Set-AppRecord $State $app.Name $rec
        Write-Log "[$tag] OK?  $($app.Name) - exit 0 pero sin evidencia (se revalida al final)" 'WARN'
        return $null
    }

    $reason = if ($Job.Error) { $Job.Error } elseif ($TimedOut) { "timeout:$($Job.Timeout)s" } elseif ($code -eq 1618) { 'msi_busy:1618' } else { "exit_code:$code($hex)" }
    $rec.errors += $reason
    $delay = Get-RetryDelay -ExitCode $code -TimedOut $TimedOut -Entry $Entry
    if ($null -ne $delay) {
        $rec.status = 'retry_pending'
        Set-AppRecord $State $app.Name $rec
        Write-Log "[$tag] RETRY $($app.Name) - $reason. Nuevo intento en ${delay}s" 'WARN'
        return $delay
    }
    $rec.status = if ($TimedOut) { 'fail_timeout' } else { 'fail' }
    $rec.finished = (Get-Date -Format 'o')
    Set-AppRecord $State $app.Name $rec
    Write-Log "[$tag] FAIL $($app.Name) - $reason tras $($rec.attempts) intento(s). Log: $($Job.LogFile)" 'ERROR'
    return $null
}

function Set-Blocked {
    param($Entry, $State, [string]$Reason)
    $rec = Get-OrNewRecord $State $Entry.App
    $rec.status = 'blocked'; $rec.errors += $Reason; $rec.finished = (Get-Date -Format 'o')
    Set-AppRecord $State $Entry.App.Name $rec
    Write-Log "BLOCKED $($Entry.App.Name) - $Reason (no se instala)" 'ERROR'
}

function Invoke-InstallPlan {
    param([object[]]$Plan, $State, $Office)
    $pending = New-Object System.Collections.ArrayList
    foreach ($a in ($Plan | Sort-Object Order)) {
        [void]$pending.Add(@{ App = $a; Attempt = 0; Launches = 0; NotBefore = [datetime]::MinValue; BusyRetries = 0 })
    }
    $lanes    = if ($Serial) { @('serial') } else { @('msi','exe') }
    $running  = @{}
    $msiWaitSince = $null; $msiWaitLogged = $null

    while ($true) {
        # 1) Jobs terminados / timeout
        foreach ($lane in @($running.Keys)) {
            $r = $running[$lane]
            $done = Test-JobDone $r.Job
            $to   = (-not $done) -and (Test-JobTimedOut $r.Job)
            if (-not $done -and -not $to) { continue }
            if ($to) { Stop-JobTree $r.Job }
            $running.Remove($lane)
            $delay = Complete-AppJob -Entry $r.Entry -Job $r.Job -State $State -TimedOut $to
            if ($null -ne $delay) {
                $r.Entry.NotBefore = (Get-Date).AddSeconds($delay)
                [void]$pending.Add($r.Entry)
            }
        }

        # 2) Outlook en background
        if ($Office) { Update-OfficeStep -Step $Office -State $State }

        # 3) Lanzar lo que este listo
        $pendingNames = @($pending | ForEach-Object { $_.App.Name }) + @($running.Values | ForEach-Object { $_.Entry.App.Name })
        foreach ($entry in @($pending | Sort-Object { $_.App.Order })) {
            $check = Get-ReadyCheck -Entry $entry -State $State -Office $Office -PendingNames ($pendingNames | Where-Object { $_ -ne $entry.App.Name })
            if ($check -like 'blocked:*') {
                $pending.Remove($entry)
                Set-Blocked -Entry $entry -State $State -Reason $check.Substring(8)
                $pendingNames = @($pendingNames | Where-Object { $_ -ne $entry.App.Name })
            }
        }
        foreach ($lane in $lanes) {
            if ($running.ContainsKey($lane)) { continue }
            $cands = @($pending | Where-Object { $Serial -or $_.App.Lane -eq $lane } | Sort-Object { $_.App.Order })
            $next = $null
            foreach ($entry in $cands) {
                $names = @($pendingNames | Where-Object { $_ -ne $entry.App.Name })
                if ((Get-ReadyCheck -Entry $entry -State $State -Office $Office -PendingNames $names) -eq 'ready') { $next = $entry; break }
            }
            if (-not $next) { continue }
            if (($Serial -or $lane -eq 'msi') -and $next.App.Lane -eq 'msi' -and (Test-MsiBusy)) {
                if (-not $msiWaitSince) { $msiWaitSince = Get-Date }
                $waited = [int]((Get-Date) - $msiWaitSince).TotalSeconds
                # El servicio MSI retiene el mutex 1-2 s tras cada instalacion: solo avisar si dura.
                if ($waited -ge 5 -and (-not $msiWaitLogged -or ((Get-Date) - $msiWaitLogged).TotalSeconds -ge 30)) {
                    Write-Log "[MSI] Windows Installer ocupado por otro proceso (Windows Update/Vantage?). Esperando para $($next.App.Name)... (${waited}s)" 'WARN'
                    $msiWaitLogged = Get-Date
                }
                if ($waited -lt 600) { continue }
                Write-Log '[MSI] 10 min esperando el mutex MSI; se lanza igualmente (1618 -> reintento)' 'WARN'
            }
            $msiWaitSince = $null; $msiWaitLogged = $null
            $pending.Remove($next)
            $running[$lane] = Start-AppJob -Entry $next -State $State
        }

        # 4) Fin / bloqueo
        $officeBusy = $Office -and -not $Office.Done
        if ($running.Count -eq 0 -and -not $officeBusy) {
            if ($pending.Count -eq 0) { break }
            $future = @($pending | Where-Object { $_.NotBefore -gt (Get-Date) })
            if ($future.Count -eq 0) {
                $pn = @($pending | ForEach-Object { $_.App.Name })
                $anyReady = $false
                foreach ($e in @($pending)) {
                    if ((Get-ReadyCheck -Entry $e -State $State -Office $Office -PendingNames ($pn | Where-Object { $_ -ne $e.App.Name })) -eq 'ready') { $anyReady = $true; break }
                }
                if (-not $anyReady) {
                    foreach ($e in @($pending)) { Set-Blocked -Entry $e -State $State -Reason 'dependencias_no_resueltas' }
                    break
                }
            }
        }
        Start-Sleep -Milliseconds 500
    }
}
#endregion

# ============================================================
#region REPORT
# ============================================================
function Get-AllRecords {
    # Solo apps del catalogo actual (un state heredado de v4 traia p.ej. 'Microsoft 365 Apps').
    param($State)
    $names = @($Script:Apps | ForEach-Object { $_.Name })
    return @($State.apps.PSObject.Properties | Where-Object { $names -contains $_.Name } | ForEach-Object { $_.Value })
}

function Write-FinalReport {
    param($State)
    $reportFile = Join-Path (Split-Path -Parent $Script:StatePath) 'POSTVALIDATE_REPORT.md'
    $apps  = Get-AllRecords $State
    $ok    = @($apps | Where-Object { $_.status -in $Script:OkStatus }).Count
    $fail  = @($apps | Where-Object { $_.status -like 'fail*' -or $_.status -eq 'blocked' }).Count
    $skip  = @($apps | Where-Object { $_.status -eq 'skipped_by_user' }).Count
    $total = @($Script:Apps).Count
    $dur   = Get-Elapsed

    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine("# POSTVALIDATE REPORT - NodeDeploy PRO v$($Script:Version)$(if ($DryRun) { ' (DRY-RUN: no se instalo nada)' })")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("- **Equipo:** $env:COMPUTERNAME")
    [void]$sb.AppendLine("- **Session:** $($Script:SessionId)")
    [void]$sb.AppendLine("- **Inicio:** $($Script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))")
    [void]$sb.AppendLine("- **Duracion total:** $(Format-Duration $dur) ($dur s)")
    [void]$sb.AppendLine("- **Modo:** $(if ($Serial) { 'serie' } else { 'carriles MSI + EXE en paralelo, Outlook en background' }) | reintentos max $MaxRetries")
    [void]$sb.AppendLine("- **Reboot requerido:** $($State.reboot_required)")
    [void]$sb.AppendLine("- **Log:** $($Script:LogFile)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Resumen')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Metrica | Valor |')
    [void]$sb.AppendLine('|---|---|')
    [void]$sb.AppendLine("| Total apps | $total |")
    [void]$sb.AppendLine("| OK | $ok |")
    [void]$sb.AppendLine("| FAIL / BLOCKED | $fail |")
    [void]$sb.AppendLine("| Skipped (usuario) | $skip |")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Detalle y cronograma')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| App | Carril | Estado | Inicio (mm:ss) | Duracion | Intentos | Exit | Evidencia / errores |')
    [void]$sb.AppendLine('|---|---|---|---|---|---|---|---|')
    foreach ($a in ($Script:Apps | Sort-Object Lane, Order)) {
        $r = Get-AppRecord $State $a.Name
        if (-not $r) { [void]$sb.AppendLine("| $($a.Name) | $($a.Lane) | not_run | - | - | - | - | - |"); continue }
        $info = if ($r.status -in $Script:OkStatus) { ($r.evidence -join '; ') } else { ($r.errors -join '; ') }
        if (-not $info) { $info = '-' }
        $ini = if ($null -ne $r.start_offset_sec -and "$($r.start_offset_sec)" -ne '') { Format-Clock ([int]$r.start_offset_sec) } else { '-' }
        $durTxt = if ($r.status -eq 'skipped_by_user' -or ($r.status -eq 'ok' -and -not $r.attempts)) { '-' } else { Format-Duration ([int]$r.elapsed_sec) }
        [void]$sb.AppendLine("| $($r.name) | $($a.Lane) | $($r.status) | $ini | $durTxt | $($r.attempts) | $($r.exit_code) | $info |")
    }
    $bad = @($apps | Where-Object { $_.status -like 'fail*' -or $_.status -eq 'blocked' })
    if ($bad.Count) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('## Apps con fallo')
        foreach ($a in $bad) {
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine("### $($a.name)")
            [void]$sb.AppendLine("- Estado: ``$($a.status)`` | Exit: ``$($a.exit_code)``")
            [void]$sb.AppendLine("- Args: ``$($a.args_used)``")
            [void]$sb.AppendLine("- Log: ``$($a.install_log)``")
            [void]$sb.AppendLine("- Errores: $($a.errors -join '; ')")
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
$quickEditOff = Disable-ConsoleQuickEdit
foreach ($l in @(
    '============================================================',
    "  NodeDeploy PRO v$($Script:Version)   session=$($Script:SessionId)$(if ($DryRun) { '   *** DRY-RUN ***' })",
    "  Source : $Source",
    "  State  : $($Script:StatePath)",
    "  Log    : $($Script:LogFile)",
    "  Phase  : $Phase   Retries: $MaxRetries   Modo: $(if ($Serial) { 'serie' } else { 'paralelo' })",
    "  Skip   : $(if ($SkipApps) { $SkipApps -join ', ' } else { '-' })   Outlook: $OutlookMethod   QuickEdit off: $quickEditOff",
    '============================================================')) { Write-Log $l 'STEP' }

$State = Get-State
# Purga registros de apps que ya no estan en el catalogo (p.ej. 'Microsoft 365 Apps' de v4).
$catalogNames = @($Script:Apps | ForEach-Object { $_.Name })
foreach ($p in @($State.apps.PSObject.Properties | Where-Object { $catalogNames -notcontains $_.Name })) {
    $State.apps.PSObject.Properties.Remove($p.Name)
}
if ($DryRun) { $Script:DryRunOffice = @{ Word = $true; Outlook = $false } }

Write-Step 'PRE-CHECKS'
if (-not $DryRun) {
    Write-Log "OS: $((Get-CimInstance Win32_OperatingSystem).Caption) ($([Environment]::OSVersion.Version))" 'INFO'
    $drive = Get-PSDrive C
    Write-Log ("Disco C: libre {0:N1} GB" -f ($drive.Free / 1GB)) 'INFO'
    if ($drive.Free -lt 8GB) { Write-Log 'WARN: <8GB libres en C:' 'WARN' }
    $reb = Test-PendingReboot
    if ($reb.HardPending) { Write-Log "Reboot pendiente (HARD): $($reb.HardSignals -join ', ') - no bloquea" 'WARN' }
    elseif ($reb.SoftSignals) { Write-Log "Reboot pendiente (SOFT/PFRO) - no bloquea" 'INFO' }
    if (Test-MsiBusy) { Write-Log 'Windows Installer ocupado ahora mismo (Windows Update?). El carril MSI esperara.' 'WARN' }
    Write-Log "Defender RTP: $(if (Test-DefenderRtp) { 'activo' } else { 'inactivo/ausente' }) | boost: $(if ($NoDefenderBoost) { 'desactivado' } else { 'activado' })" 'INFO'
    $os0 = Get-OfficeState
    $c2r0 = Get-C2RInfo
    Write-Log ("Office: Word={0} Outlook={1} ({2}) C2R={3} v{4} canal={5}" -f $os0.Word, $os0.Outlook, $os0.Arch, $(if ($c2r0) { $c2r0.Products -join '+' } else { '-' }), $(if ($c2r0) { $c2r0.Version } else { '-' }), $(if ($c2r0) { $c2r0.Channel } else { '-' })) 'INFO'
}

Write-Step 'VERIFICANDO ARCHIVOS DE INSTALACION'
foreach ($a in $Script:Apps) {
    $def = Resolve-AppDefinition $a
    $p = Resolve-AppPath $def
    if (Test-Path $p) {
        Write-Log "  [OK]   $($a.Name) -> $(Split-Path $p -Leaf)$(if ($def.UsingFallback) { '  (FALLBACK: falta ' + $a.File + ')' })" $(if ($def.UsingFallback) { 'WARN' } else { 'INFO' })
    } else {
        Write-Log "  [MISS] $($a.Name) -> $p" $(if ($SkipApps -contains $a.Name) { 'INFO' } else { 'WARN' })
    }
}
$wdDir = Join-Path $Source $imWork
if (-not (Test-Path (Join-Path $wdDir 'setup.iss'))) { Write-Log "  [INFO] setup.iss no pre-empaquetado en '$imWork' (se extraera del paquete, +~50s)" 'INFO' }

if ($Phase -eq 'probe') { Write-Log 'Phase=probe: salida sin instalar' 'OK'; exit 0 }

if ($Phase -eq 'validate') {
    Write-Step 'VALIDATE ONLY'
    $Script:InstalledCache = Get-InstalledApps
    foreach ($a in $Script:Apps) {
        $c = Test-AppInstalled -App $a
        $lvl = if ($c.Installed) { 'OK' } else { 'WARN' }
        Write-Log "[$lvl] $($a.Name): $($c.Evidence -join '; ')" $lvl
        $r = Get-OrNewRecord $State $a
        $r.evidence = $c.Evidence; $r.validated = $c.Installed; $r.finished = (Get-Date -Format 'o'); $r.errors = @()
        $r.status = if ($c.Installed) { 'ok' } else { 'missing' }
        Set-AppRecord $State $a.Name $r
    }
    Write-FinalReport $State | Out-Null
    exit 0
}

if ($Phase -eq 'cleanup') {
    Write-Step 'CLEANUP iManage residuales'
    Stop-ProcessSafe -Names @('iManageStayExec','iManageDrive','iManageWorkDesktop','iManageEFS','iManageAgentSvc') -WaitSec 3
    foreach ($svc in @('imUpdateManagerService','iManageWorkOfflineService')) {
        Get-Service -Name $svc -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Stop() } catch {} }
    }
    Clear-StaleDefenderBoost -State $State
    Write-Log 'Cleanup completo' 'OK'
    exit 0
}

# ---------------- full | install | resume ----------------
Write-Step "PLAN DE INSTALACION (Phase=$Phase)"
$State.reboot_required = $false
Save-State $State
Clear-StaleDefenderBoost -State $State
$Script:InstalledCache = Get-InstalledApps

$plan = @(); $officeApp = $null
foreach ($a in $Script:Apps) {
    $rec = Get-OrNewRecord $State $a
    if ($SkipApps -contains $a.Name) {
        $rec.status = 'skipped_by_user'; $rec.errors = @(); Set-AppRecord $State $a.Name $rec
        Write-Log "SKIP $($a.Name) (-SkipApps$(if ($Script:AVApps -contains $a.Name -and $SkipAV) { '/-SkipAV' }))" 'WARN'
        continue
    }
    if ($a.Type -eq 'office') {
        if ($NoOffice) {
            $rec.status = 'skipped_by_user'; Set-AppRecord $State $a.Name $rec
            Write-Log "SKIP $($a.Name) (-NoOffice)" 'WARN'
        } else { $officeApp = $a }
        continue
    }
    $def = Resolve-AppDefinition $a
    if (-not $ForceReinstall -and -not $DryRun) {
        $c = Test-AppInstalled -App $def
        if ($c.Installed) {
            $rec.status = 'ok'; $rec.evidence = $c.Evidence; $rec.validated = $true; $rec.errors = @(); $rec.finished = (Get-Date -Format 'o')
            Set-AppRecord $State $a.Name $rec
            Write-Log "SKIP $($a.Name) - ya instalado [$($c.Evidence -join ', ')]" 'OK'
            continue
        }
    }
    if (-not $DryRun -and -not (Test-Path (Resolve-AppPath $def))) {
        $rec.status = 'fail'; $rec.errors = @("file_not_found:$(Resolve-AppPath $def)"); $rec.finished = (Get-Date -Format 'o')
        Set-AppRecord $State $a.Name $rec
        Write-Log "FAIL $($a.Name) - instalador no existe: $(Resolve-AppPath $def)" 'ERROR'
        continue
    }
    $rec.status = 'queued'; $rec.errors = @(); $rec.attempts = 0; $rec.history = @()
    Set-AppRecord $State $a.Name $rec
    $plan += $def
}

# Defender boost para lo que realmente se va a instalar
$boostPaths = @(); $boostProcs = @()
foreach ($a in $plan) { if ($a.Boost) { $boostPaths += @($a.Boost.Paths); $boostProcs += @($a.Boost.Processes) } }

$exitCode = 0
try {
    if ($boostPaths.Count -or $boostProcs.Count) {
        Add-DefenderBoost -State $State -Paths ($boostPaths | Where-Object { $_ } | Select-Object -Unique) -Processes ($boostProcs | Where-Object { $_ } | Select-Object -Unique)
    }

    $office = $null
    if ($officeApp) {
        Write-Step 'OUTLOOK CLASICO (background)'
        $office = Start-OfficeStep -App $officeApp -State $State
        if ($SequentialOffice) {
            while (-not $office.Done) { Update-OfficeStep -Step $office -State $State; Start-Sleep -Milliseconds 500 }
        }
    }

    Write-Step ("INSTALACIONES: {0} apps en {1}" -f $plan.Count, $(if ($Serial) { 'serie' } else { 'carriles MSI + EXE en paralelo' }))
    Invoke-InstallPlan -Plan $plan -State $State -Office $office

    # Revalidacion final de 'exit 0 sin evidencia' (instaladores que terminan en segundo plano)
    if (-not $DryRun) {
        $Script:InstalledCache = Get-InstalledApps
        foreach ($a in $Script:Apps) {
            $r = Get-AppRecord $State $a.Name
            if ($r -and $r.status -eq 'ok_unverified') {
                $c = Test-AppInstalled -App (Resolve-AppDefinition $a)
                if ($c.Installed) {
                    $r.status = 'ok'; $r.validated = $true; $r.evidence = $c.Evidence; $r.errors = @()
                    Set-AppRecord $State $a.Name $r
                    Write-Log "OK   $($a.Name) confirmado en revalidacion final [$($c.Evidence -join ', ')]" 'OK'
                }
            }
        }
    }
} finally {
    Remove-DefenderBoost -State $State
}

Write-Step 'REPORT FINAL'
$reportFile = Write-FinalReport $State
$apps = Get-AllRecords $State
$failures = @($apps | Where-Object { $_.status -like 'fail*' -or $_.status -eq 'blocked' })

Write-Step 'RESUMEN'
Write-Log "Duracion total: $(Format-Duration (Get-Elapsed))" 'INFO'
Write-Log "OK: $(@($apps | Where-Object { $_.status -in $Script:OkStatus }).Count) / $(@($Script:Apps).Count)" 'OK'
Write-Log "FAIL/BLOCKED: $($failures.Count)$(if ($failures.Count) { ' -> ' + (($failures | ForEach-Object { $_.name }) -join ', ') })" $(if ($failures.Count) { 'ERROR' } else { 'INFO' })
Write-Log "Report: $reportFile" 'INFO'

if ($State.reboot_required) {
    Write-Log '=== REBOOT REQUERIDO === Reinicia y ejecuta: Deploy.bat resume' 'WARN'
    exit 3
}
if ($failures.Count -gt 0) { exit 1 }
exit 0
#endregion
