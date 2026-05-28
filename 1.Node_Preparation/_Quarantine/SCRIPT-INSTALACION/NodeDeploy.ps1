#Requires -RunAsAdministrator
<#
.SYNOPSIS
    N0DE_DEPL0Y v2.0 - Unified Node Deployment Script
.DESCRIPTION
    Four-phase automated deployment:
      Phase 0: Office background launch (descarga ~2GB en paralelo)
      Phase 1: Silent installations (MSI, EXE, MSIX, iManage)
      Phase 2: UI Automation installations (ESET, PDFelement, iManage Work Desktop)
      Phase 3: Outlook add-in cleanup and configuration (tras completar Office)
.NOTES
    v2.0 - 2026-04-11
#>

$ErrorActionPreference = 'Continue'

# ══════════════════════════════════════════════
# CONFIGURATION
# ══════════════════════════════════════════════

$Source          = '\\192.168.2.8\utilidades\1.Node_Preparation'
$LogDir          = "$env:USERPROFILE\LOGS_Script"
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$LogFile         = "$LogDir\NodeDeploy_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$Desktop         = [Environment]::GetFolderPath('CommonDesktopDirectory')
$LocalCache      = "$env:TEMP\_NodeDeploy_Cache"
$DefaultTimeout  = 300

# ══════════════════════════════════════════════
# CYBERPUNK UI ENGINE
# ══════════════════════════════════════════════

$Script:SpinIdx     = 0
$Script:SpinChars   = @('/', '-', '\', '|')
$Script:TotalApps   = 0
$Script:CurrentApp  = 0

function Show-Banner {
    $banner = @"

    `e[36m ___  ___  ________  ________  _______                              `e[0m
    `e[36m|\  \|\  \|\   __  \|\   ___ \|\  ___ \                             `e[0m
    `e[36m\ \  \\\  \ \  \|\  \ \  \_|\ \ \   __/|                            `e[0m
    `e[36m \ \   __  \ \  \\\  \ \  \ \\ \ \  \_|/__                           `e[0m
    `e[36m  \ \  \ \  \ \  \\\  \ \  \_\\ \ \  \_|\ \                          `e[0m
    `e[36m   \ \__\ \__\ \_______\ \_______\ \_______\                         `e[0m
    `e[36m    \|__|\|__|\|_______|\|_______|\|_______|                         `e[0m
    `e[35m ________  _______   ________  ___       ________  ___    ___        `e[0m
    `e[35m|\   ___ \|\  ___ \ |\   __  \|\  \     |\   __  \|\  \  /  /|      `e[0m
    `e[35m\ \  \_|\ \ \   __/|\ \  \|\  \ \  \    \ \  \|\  \ \  \/  / /      `e[0m
    `e[35m \ \  \ \\ \ \  \_|/_\ \   ____\ \  \    \ \  \\\  \ \    / /       `e[0m
    `e[35m  \ \  \_\\ \ \  \_|\ \ \  \___|\ \  \____\ \  \\\  \ \  / /        `e[0m
    `e[35m   \ \_______\ \_______\ \__\    \ \_______\ \_______\ \__/ /        `e[0m
    `e[35m    \|_______|\|_______|\|__|     \|_______|\|_______|\|__|/         `e[0m

"@
    Write-Host $banner

    Write-Host "  `e[36m" -NoNewline
    Write-Host ('=' * 66) -NoNewline -ForegroundColor Cyan
    Write-Host "`e[0m"
    Write-Host "  `e[36m||`e[0m" -NoNewline
    Write-Host "  N 0 D E _ D E P L 0 Y   //   v2.0   //   $(Get-Date -Format 'yyyy.MM.dd')" -ForegroundColor Magenta -NoNewline
    Write-Host "  `e[36m||`e[0m"
    Write-Host "  `e[36m||`e[0m" -NoNewline
    Write-Host "  Unified Deployment System  //  3-Phase Installer Engine    " -ForegroundColor DarkGray -NoNewline
    Write-Host "  `e[36m||`e[0m"
    Write-Host "  `e[36m" -NoNewline
    Write-Host ('=' * 66) -NoNewline -ForegroundColor Cyan
    Write-Host "`e[0m"
    Write-Host ""
}

function Show-PhaseHeader {
    param([int]$Phase, [string]$Title, [string]$Subtitle)
    Write-Host ""
    Write-Host "  `e[36m+$('-' * 64)+`e[0m" -ForegroundColor Cyan
    Write-Host "  `e[36m|`e[0m" -NoNewline
    $phaseText = "  PHASE $Phase :: $Title"
    Write-Host $phaseText -ForegroundColor Magenta -NoNewline
    $pad = 64 - $phaseText.Length
    if ($pad -gt 0) { Write-Host (' ' * $pad) -NoNewline }
    Write-Host "`e[36m|`e[0m" -ForegroundColor Cyan
    if ($Subtitle) {
        Write-Host "  `e[36m|`e[0m" -NoNewline
        $subText = "  $Subtitle"
        Write-Host $subText -ForegroundColor DarkGray -NoNewline
        $pad2 = 64 - $subText.Length
        if ($pad2 -gt 0) { Write-Host (' ' * $pad2) -NoNewline }
        Write-Host "`e[36m|`e[0m" -ForegroundColor Cyan
    }
    Write-Host "  `e[36m+$('-' * 64)+`e[0m" -ForegroundColor Cyan
    Write-Host ""
}

function Show-GroupHeader {
    param([string]$Label)
    Write-Host ""
    Write-Host "  `e[36m>>>>`e[0m $Label" -ForegroundColor Cyan
    Write-Host "  `e[36m----`e[0m$('-' * 50)" -ForegroundColor DarkGray
}

function Show-AppProgress {
    param([string]$AppName, [string]$Status, [int]$Percent = -1)
    $spin = $Script:SpinChars[$Script:SpinIdx % 4]
    $Script:SpinIdx++

    if ($Percent -ge 0) {
        $filled = [int]($Percent / 5)
        $empty  = 20 - $filled
        $bar    = ('>' * $filled) + ('-' * $empty)
        $pctStr = "$Percent%".PadLeft(4)
        Write-Host "  [$bar] $pctStr " -ForegroundColor Cyan -NoNewline
        Write-Host "$Status " -ForegroundColor Yellow -NoNewline
        Write-Host "$AppName" -ForegroundColor White
    } else {
        Write-Host "  [$spin] " -ForegroundColor Cyan -NoNewline
        Write-Host "$Status " -ForegroundColor Yellow -NoNewline
        Write-Host "$AppName" -ForegroundColor White
    }
}

function Show-AppResult {
    param([string]$AppName, [string]$Result, [string]$Detail = '')
    switch ($Result) {
        'ok' {
            Write-Host "  [" -NoNewline -ForegroundColor DarkGray
            Write-Host "OK" -NoNewline -ForegroundColor Green
            Write-Host "] " -NoNewline -ForegroundColor DarkGray
            Write-Host "$AppName" -ForegroundColor Green -NoNewline
            if ($Detail) { Write-Host " $Detail" -ForegroundColor DarkGray } else { Write-Host "" }
        }
        'skip' {
            Write-Host "  [" -NoNewline -ForegroundColor DarkGray
            Write-Host "SKIP" -NoNewline -ForegroundColor Yellow
            Write-Host "] " -NoNewline -ForegroundColor DarkGray
            Write-Host "$AppName" -ForegroundColor Yellow -NoNewline
            Write-Host " already installed" -ForegroundColor DarkGray
        }
        'fail' {
            Write-Host "  [" -NoNewline -ForegroundColor DarkGray
            Write-Host "FAIL" -NoNewline -ForegroundColor Red
            Write-Host "] " -NoNewline -ForegroundColor DarkGray
            Write-Host "$AppName" -ForegroundColor Red -NoNewline
            if ($Detail) { Write-Host " $Detail" -ForegroundColor DarkGray } else { Write-Host "" }
        }
    }
}

function Show-FinalSummary {
    param([hashtable]$Results, [string]$Elapsed)
    Write-Host ""
    Write-Host "  `e[36m" -NoNewline
    Write-Host ('+' + '=' * 50 + '+') -ForegroundColor Cyan
    Write-Host "  `e[36m|`e[0m" -NoNewline
    Write-Host "          DEPLOYMENT COMPLETE                    " -ForegroundColor Magenta -NoNewline
    Write-Host "`e[36m|`e[0m" -ForegroundColor Cyan
    Write-Host "  `e[36m" -NoNewline
    Write-Host ('+' + '-' * 50 + '+') -ForegroundColor Cyan

    $okLine   = "   Installed  : $($Results.OK)".PadRight(50)
    $skipLine = "   Skipped    : $($Results.Skipped)".PadRight(50)
    $failLine = "   Failed     : $($Results.Failed)".PadRight(50)
    $timeLine = "   Duration   : $Elapsed".PadRight(50)
    $logLine  = "   Log        : $LogFile"
    if ($logLine.Length -gt 50) { $logLine = $logLine.Substring(0, 47) + '...' }
    $logLine  = $logLine.PadRight(50)

    Write-Host "  `e[36m|`e[0m" -NoNewline
    Write-Host $okLine -ForegroundColor Green -NoNewline
    Write-Host "`e[36m|`e[0m" -ForegroundColor Cyan
    Write-Host "  `e[36m|`e[0m" -NoNewline
    Write-Host $skipLine -ForegroundColor Yellow -NoNewline
    Write-Host "`e[36m|`e[0m" -ForegroundColor Cyan
    if ($Results.Failed -gt 0) {
        Write-Host "  `e[36m|`e[0m" -NoNewline
        Write-Host $failLine -ForegroundColor Red -NoNewline
        Write-Host "`e[36m|`e[0m" -ForegroundColor Cyan
    } else {
        Write-Host "  `e[36m|`e[0m" -NoNewline
        Write-Host $failLine -ForegroundColor DarkGray -NoNewline
        Write-Host "`e[36m|`e[0m" -ForegroundColor Cyan
    }
    Write-Host "  `e[36m|`e[0m" -NoNewline
    Write-Host $timeLine -ForegroundColor DarkGray -NoNewline
    Write-Host "`e[36m|`e[0m" -ForegroundColor Cyan
    Write-Host "  `e[36m" -NoNewline
    Write-Host ('+' + '-' * 50 + '+') -ForegroundColor Cyan
    Write-Host "  `e[36m|`e[0m" -NoNewline
    Write-Host $logLine -ForegroundColor DarkGray -NoNewline
    Write-Host "`e[36m|`e[0m" -ForegroundColor Cyan
    Write-Host "  `e[36m" -NoNewline
    Write-Host ('+' + '=' * 50 + '+') -ForegroundColor Cyan
    Write-Host ""
}

# ══════════════════════════════════════════════
# CORE FUNCTIONS
# ══════════════════════════════════════════════

function Write-Log {
    param([string]$Msg, [string]$Level = 'INFO')
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Msg"
    Add-Content -Path $LogFile -Value $entry
}

function Write-LogAndDisplay {
    param([string]$Msg, [string]$Level = 'INFO')
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Msg"
    Add-Content -Path $LogFile -Value $entry
    switch ($Level) {
        'ERROR' { Write-Host "  $Msg" -ForegroundColor Red }
        'WARN'  { Write-Host "  $Msg" -ForegroundColor Yellow }
        'OK'    { Write-Host "  $Msg" -ForegroundColor Green }
        default { Write-Host "  $Msg" -ForegroundColor DarkGray }
    }
}

function Get-InstalledApps {
    @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    ) | ForEach-Object {
        Get-ItemProperty $_ -EA SilentlyContinue
    } | Where-Object { $_.DisplayName } | Select-Object -ExpandProperty DisplayName
}

function Test-Installed {
    param(
        [string[]]$Keywords,
        [string]$AppxName,
        [switch]$Refresh
    )
    if ($Refresh) {
        $Global:InstalledCache = Get-InstalledApps
    }
    if ($AppxName) {
        if (Get-AppxPackage -Name "*$AppxName*" -EA SilentlyContinue) { return $true }
    }
    if ($Keywords) {
        foreach ($kw in $Keywords) {
            if ($Global:InstalledCache | Where-Object { $_ -like "*$kw*" }) { return $true }
        }
    }
    return $false
}

function Start-InstallProcess {
    param(
        [string]$FilePath,
        [string]$Arguments,
        [int]$Timeout = $DefaultTimeout,
        [string[]]$KillProcesses = @()
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

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    try {
        [void]$proc.Start()
    } catch {
        Write-Log "  Launch failed: $_" 'ERROR'
        return @{ ExitCode = -99; TimedOut = $false }
    }

    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()

    $finished = $proc.WaitForExit($Timeout * 1000)

    if (-not $finished) {
        Write-Log "  TIMEOUT ${Timeout}s - killing PID $($proc.Id)" 'WARN'
        try {
            $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc.Id)" -EA SilentlyContinue
            foreach ($child in $children) {
                Stop-Process -Id $child.ProcessId -Force -EA SilentlyContinue
            }
        } catch {}
        try { $proc.Kill() } catch {}
        foreach ($pn in $KillProcesses) {
            Get-Process -Name $pn -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
        }
        return @{ ExitCode = -1; TimedOut = $true }
    }

    # Close async handles
    $proc.WaitForExit()
    $code = $proc.ExitCode

    try {
        $stderr = $stderrTask.Result
        if ($stderr -and $stderr.Trim()) {
            $lines = ($stderr.Trim() -split "`n" | Select-Object -First 3) -join ' | '
            Write-Log "  STDERR: $lines" 'WARN'
        }
    } catch {}

    Start-Sleep -Milliseconds 800
    foreach ($pn in $KillProcesses) {
        Get-Process -Name $pn -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
    }

    $proc.Dispose()
    return @{ ExitCode = $code; TimedOut = $false }
}

function Wait-ChildMsi {
    param([int]$Timeout = 120)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Seconds 5
    while ($sw.Elapsed.TotalSeconds -lt $Timeout) {
        $userMsi = Get-Process -Name 'msiexec' -EA SilentlyContinue |
                   Where-Object { $_.SessionId -ne 0 }
        if (-not $userMsi) { break }
        Start-Sleep -Seconds 3
    }
    $sw.Stop()
    Write-Log "  msiexec children finished ($([int]$sw.Elapsed.TotalSeconds)s)"
}

function Copy-ToLocal {
    param([string]$NetworkPath)
    if (-not (Test-Path $LocalCache)) { New-Item -Path $LocalCache -ItemType Directory -Force | Out-Null }
    $dest = Join-Path $LocalCache ([IO.Path]::GetFileName($NetworkPath))
    if (-not (Test-Path $dest)) {
        Write-Log "  Copying to local cache..."
        Copy-Item -Path $NetworkPath -Destination $dest -Force
    }
    return $dest
}

function New-Shortcut {
    param([string]$Name, [string]$TargetPath)
    if (-not $TargetPath -or -not (Test-Path $TargetPath)) { return }
    $lnk = Join-Path $Desktop "$Name.lnk"
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
    param([hashtable]$Shortcut)
    if (-not $Shortcut) { return $null }
    if ($Shortcut.Exe -and (Test-Path $Shortcut.Exe)) { return $Shortcut.Exe }
    if ($Shortcut.Alt) {
        $m = Resolve-Path $Shortcut.Alt -EA SilentlyContinue | Select-Object -First 1
        if ($m) { return $m.Path }
    }
    return $null
}

# ══════════════════════════════════════════════
# OFFICE BACKGROUND INSTALL
# ══════════════════════════════════════════════

function Start-OfficeBackground {
    <# Lanza Office en background para aprovechar el tiempo de descarga (~2GB).
       Retorna un hashtable con el proceso y metadata para comprobar luego. #>

    $officeDetect = @('Microsoft Outlook','Microsoft 365 Apps','Microsoft Office')
    if (Test-Installed -Keywords $officeDetect) {
        Write-Log "  Office already installed - SKIP" 'OK'
        Show-AppResult -AppName 'Microsoft Outlook (Office)' -Result 'skip'
        return @{ Status = 'skip'; Process = $null }
    }

    $officeExe = Join-Path $Source 'OfficeSetup.exe'
    $xmlFile   = Join-Path $Source 'configuration.xml'

    if (-not (Test-Path $officeExe)) {
        Write-Log "  OfficeSetup.exe not found: $officeExe" 'ERROR'
        Show-AppResult -AppName 'Microsoft Outlook (Office)' -Result 'fail' -Detail '(file not found)'
        return @{ Status = 'fail'; Process = $null }
    }
    if (-not (Test-Path $xmlFile)) {
        Write-Log "  configuration.xml not found: $xmlFile" 'ERROR'
        Show-AppResult -AppName 'Microsoft Outlook (Office)' -Result 'fail' -Detail '(xml not found)'
        return @{ Status = 'fail'; Process = $null }
    }

    # Cerrar procesos Office
    'OUTLOOK','WINWORD','EXCEL','POWERPNT','OfficeClickToRun','OfficeC2RClient' | ForEach-Object {
        Get-Process -Name $_ -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
    }
    Start-Sleep -Seconds 2

    # Copiar a local
    $localExe = Copy-ToLocal -NetworkPath $officeExe
    $localXml = Copy-ToLocal -NetworkPath $xmlFile

    Write-Log "  Launching Office install in BACKGROUND: $localExe /configure $localXml"
    Show-AppProgress -AppName 'Microsoft Outlook (Office)' -Status "BACKGROUND" -Percent 5

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $localExe
    $psi.Arguments              = "/configure `"$localXml`""
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    # NO redirigir stdout/stderr: si no se leen, el buffer se llena y el proceso se bloquea
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError  = $false

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    try { [void]$proc.Start() } catch {
        Write-Log "  Office launch failed: $_" 'ERROR'
        Show-AppResult -AppName 'Microsoft Outlook (Office)' -Result 'fail' -Detail '(launch error)'
        return @{ Status = 'fail'; Process = $null }
    }

    Write-Log "  Office PID=$($proc.Id) running in background"
    Write-Host "  Office PID=$($proc.Id) downloading in background..." -ForegroundColor DarkGray

    return @{
        Status    = 'running'
        Process   = $proc
        StartTime = [Diagnostics.Stopwatch]::StartNew()
        Detect    = $officeDetect
    }
}

function Wait-OfficeBackground {
    <# Espera a que Office termine (si aun esta corriendo). Timeout 900s. #>
    param([hashtable]$OfficeJob)

    if (-not $OfficeJob -or $OfficeJob.Status -ne 'running') { return $OfficeJob.Status }

    $proc    = $OfficeJob.Process
    $sw      = $OfficeJob.StartTime
    $timeout = 900

    if (-not $proc.HasExited) {
        Write-Host ""
        Write-Host "  Waiting for Office background install to finish..." -ForegroundColor Cyan
        Write-Log "  Waiting for Office background process..."

        while (-not $proc.HasExited -and $sw.Elapsed.TotalSeconds -lt $timeout) {
            $spin = $Script:SpinChars[$Script:SpinIdx % 4]
            $Script:SpinIdx++
            $t   = [int]$sw.Elapsed.TotalSeconds
            $min = [int]($t / 60)
            $sec = $t % 60
            $pct = [Math]::Min(95, [int]($t / $timeout * 100))
            Write-Host "`r  [$spin] Office installing... ${min}m ${sec}s ($pct%)" -ForegroundColor DarkGray -NoNewline
            Start-Sleep -Seconds 3
        }
        Write-Host ""
    }

    if (-not $proc.HasExited) {
        Write-Log "  Office TIMEOUT ${timeout}s - killing" 'WARN'
        @('OfficeClickToRun','OfficeC2RClient','setup') | ForEach-Object {
            Get-Process -Name $_ -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
        }
        try { $proc.Kill() } catch {}
    }

    $proc.WaitForExit()
    $code = $proc.ExitCode
    $secs = [int]$sw.Elapsed.TotalSeconds
    Write-Log "  Office finished: code=$code (${secs}s)"
    $proc.Dispose()

    # Verificar
    Start-Sleep -Seconds 3
    $Global:InstalledCache = Get-InstalledApps
    $outlookExe = "$env:ProgramFiles\Microsoft Office\root\Office16\OUTLOOK.EXE"

    if ((Test-Installed -Keywords $OfficeJob.Detect) -or (Test-Path $outlookExe)) {
        Write-Log "  Office INSTALLED OK (${secs}s, code=$code)" 'OK'
        Show-AppResult -AppName 'Microsoft Outlook (Office)' -Result 'ok' -Detail "(${secs}s, background)"
        return 'ok'
    } elseif ($code -eq 0) {
        Write-Log "  Office code=0 but not detected yet" 'WARN'
        Show-AppResult -AppName 'Microsoft Outlook (Office)' -Result 'ok' -Detail "(code=0, ${secs}s)"
        return 'ok'
    } else {
        Write-Log "  Office NOT INSTALLED (code=$code, ${secs}s)" 'ERROR'
        Show-AppResult -AppName 'Microsoft Outlook (Office)' -Result 'fail' -Detail "(code=$code, ${secs}s)"
        return 'fail'
    }
}

# ══════════════════════════════════════════════
# Aplicaciones a instalar en modo SILENT
# ══════════════════════════════════════════════

$SilentApps = @(
    # -- GROUP 1: MSIs --
    @{
        Name     = 'AnyDesk'
        File     = 'AnyDesk.msi'
        Type     = 'msi'
        Detect   = @('AnyDesk')
        Group    = 1
        Shortcut = @{ Exe = "${env:ProgramFiles(x86)}\AnyDesk\AnyDesk.exe" }
    },
    @{
        Name   = 'AqNet'
        File   = 'AqNetInstalacion.msi'
        Type   = 'msi'
        Detect = @('AqNet','Aqnet','Deposito Digital','AQNET')
        Group  = 1
    },
    @{
        Name   = 'Nebula CertAgent'
        File   = 'nebula-certAgent-winx64-5.0.0.msi'
        Type   = 'msi'
        Detect = @('Nebula','CertAgent','certAgent')
        Group  = 1
    },
    @{
        Name     = 'MDR / Cortex XDR'
        File     = 'MDR_Windows_Andersen_8_2_x64.msi'
        Type     = 'msi'
        Detect   = @('Cortex XDR','Cortex','Palo Alto','Traps')
        MsiExtra = 'REBOOT=ReallySuppress'
        Group    = 1
    },

    # -- GROUP 2: EXEs --
    @{
        Name     = 'Google Chrome'
        File     = 'ChromeSetup.exe'
        Type     = 'exe'
        Args     = '/silent /install'
        Detect   = @('Google Chrome')
        Group    = 2
        Shortcut = @{ Exe = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe" }
    },
    @{
        Name     = 'Autofirma'
        File     = 'Autofirma_64_v1_9_installer.exe'
        Type     = 'exe'
        Args     = '/S'
        Detect   = @('AutoFirma','Autofirma')
        Group    = 2
        Timeout  = 180
        Shortcut = @{ Exe = "$env:ProgramFiles\AutoFirma\AutoFirma.exe" }
    },
    @{
        Name   = 'Instalar D2'
        File   = 'Instalar_D2_2025.exe'
        Type   = 'exe'
        Args   = '/S'
        Detect = @('D2')
        Group  = 2
    },
    @{
        Name       = 'NanaZip'
        File       = 'NanaZip.msixbundle'
        Type       = 'msixbundle'
        AppxDetect = 'NanaZip'
        Group      = 2
    },

    # -- GROUP 3: Complex --
    @{
        Name    = 'Bit4id Middleware'
        File    = 'Bit4id_Middleware.exe'
        Type    = 'exe'
        Args    = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS'
        Detect  = @('Bit4id','bit4id','Universal Middleware')
        Group   = 3
        Timeout = 300
        KillGUI = @('Bit4id*','universal*')
    },
    # ESET movido a Phase 2 (UI Automation) - el --silent no funciona
    @{
        Name    = 'MitelConnect'
        File    = 'MitelConnect.exe'
        Type    = 'exe'
        Args    = '/s /v"/qn REBOOT=ReallySuppress"'
        Detect  = @('Mitel','MiCollab','Mitel Connect')
        Group   = 3
        Timeout = 300
        KillGUI = @('MitelConnect*','Mitel*')
    }

    # Office movido a ejecucion background al inicio del deploy (se lanza primero)
)

$iManageSilentApps = @(
    @{
        Name   = 'iManage Agent Services'
        Path   = 'Imanage 2.0\iManage Work Desktop for Windows 10.9.4.39 (x64 Office)\iManageAgentServices.exe'
        Type   = 'installshield'
        Args   = '/s /SMS /v"/qn REBOOT=ReallySuppress"'
        Detect = @('iManage Agent','iManageAgent')
    },
    @{
        Name    = 'iManage Drive'
        Path    = 'Imanage 2.0\iManage Drive for Windows 10.10.0.410\iManage Drive for Windows 10.10.0.410\iManageDriveSetup.exe'
        Type    = 'burn'
        Args    = '/quiet /norestart'
        Detect  = @('iManage Drive')
        Timeout = 600
        Shortcut = @{ Exe = "$env:ProgramFiles\iManage\iManage Drive\iManageDrive.exe" }
    },
    @{
        Name    = 'iManage Drive Native'
        Path    = 'Imanage 2.0\iManage Drive for Windows 10.10.0.410\iManageDrive Native 10.6.1.15\iManageDriveNative.exe'
        Type    = 'burn'
        Args    = '/quiet /norestart'
        Detect  = @('iManage Drive Native','iManageDriveNative')
        Timeout = 300
    }
)

# ══════════════════════════════════════════════
# PHASE 1: SILENT INSTALLATION ENGINE
# ══════════════════════════════════════════════

function Invoke-SilentInstall {
    param([hashtable]$App)

    $name    = $App.Name
    $type    = $App.Type
    $timeout = if ($App.Timeout) { $App.Timeout } else { $DefaultTimeout }

    # Pre-detection
    if (Test-Installed -Keywords $App.Detect -AppxName $App.AppxDetect) {
        Write-Log "  SKIP $name - already installed" 'OK'
        Show-AppResult -AppName $name -Result 'skip'
        return 'skip'
    }

    $filePath = if ($App.Path) { Join-Path $Source $App.Path } else { Join-Path $Source $App.File }

    if (-not (Test-Path $filePath)) {
        Write-Log "  $name - FILE NOT FOUND: $filePath" 'ERROR'
        Show-AppResult -AppName $name -Result 'fail' -Detail '(file not found)'
        return 'fail'
    }

    Write-Log "--- $name [$type] ---"
    Show-AppProgress -AppName $name -Status "Installing" -Percent 10
    $sw = [Diagnostics.Stopwatch]::StartNew()

    $result = switch ($type) {

        'msi' {
            $msiLog = "$LogDir\msi_$([IO.Path]::GetFileNameWithoutExtension($App.File)).log"
            $extra  = if ($App.MsiExtra) { " $($App.MsiExtra)" } else { '' }
            Start-InstallProcess `
                -FilePath 'msiexec.exe' `
                -Arguments "/i `"$filePath`" /qn /norestart /l*v `"$msiLog`"$extra" `
                -Timeout $timeout
        }

        'msixbundle' {
            try {
                Add-AppxPackage -Path $filePath -ErrorAction Stop
                @{ ExitCode = 0; TimedOut = $false }
            } catch {
                if ("$_" -match 'higher version|ya instalada|already installed') {
                    Write-Log "  Same or higher version exists" 'OK'
                    @{ ExitCode = 0; TimedOut = $false }
                } else {
                    Write-Log "  AppxPackage error: $_" 'ERROR'
                    @{ ExitCode = -3; TimedOut = $false }
                }
            }
        }

        'exe' {
            $killList = if ($App.KillGUI) { $App.KillGUI } else { @() }
            Start-InstallProcess `
                -FilePath $filePath `
                -Arguments $App.Args `
                -Timeout $timeout `
                -KillProcesses $killList
        }

        'office' {
            $xmlPath = Join-Path $Source 'configuration.xml'
            if (-not (Test-Path $xmlPath)) {
                Write-Log "  MISSING configuration.xml" 'ERROR'
                @{ ExitCode = -4; TimedOut = $false }
            } else {
                'OUTLOOK','WINWORD','EXCEL','POWERPNT','OfficeClickToRun','OfficeC2RClient' | ForEach-Object {
                    Get-Process -Name $_ -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
                }
                Start-Sleep -Seconds 2

                $localExe = Copy-ToLocal -NetworkPath $filePath
                $localXml = Copy-ToLocal -NetworkPath $xmlPath

                $killList = if ($App.KillGUI) { $App.KillGUI } else { @() }
                Start-InstallProcess `
                    -FilePath $localExe `
                    -Arguments "/configure `"$localXml`"" `
                    -Timeout $timeout `
                    -KillProcesses $killList
            }
        }

        'installshield' {
            Write-Log "  Type: InstallShield InstallScript (/SMS)"
            $r = Start-InstallProcess `
                -FilePath $filePath `
                -Arguments $App.Args `
                -Timeout $timeout `
                -KillProcesses @('iManage*')

            if (-not $r.TimedOut) {
                Wait-ChildMsi -Timeout 120
            }
            $r
        }

        'burn' {
            Write-Log "  Type: WiX Burn (/quiet /norestart)"
            Start-InstallProcess `
                -FilePath $filePath `
                -Arguments $App.Args `
                -Timeout $timeout `
                -KillProcesses @('iManage*')
        }
    }

    $sw.Stop()
    $secs     = [int]$sw.Elapsed.TotalSeconds
    $code     = $result.ExitCode
    $timedOut = $result.TimedOut

    # Post-install verification
    $postCheck = $false
    if ($code -ne 0 -or $timedOut) {
        Write-Log "  Exit code: $code - checking registry..." 'WARN'
        Start-Sleep -Seconds 2
        $postCheck = Test-Installed -Keywords $App.Detect -AppxName $App.AppxDetect -Refresh
    }

    if ($code -eq 0) {
        Write-Log "  OK $name (${secs}s, code=$code)" 'OK'
        Show-AppResult -AppName $name -Result 'ok' -Detail "(${secs}s)"
        return 'ok'
    }
    elseif ($code -in @(3010, 1641)) {
        Write-Log "  OK $name - reboot pending (${secs}s, code=$code)" 'WARN'
        Show-AppResult -AppName $name -Result 'ok' -Detail "(${secs}s, reboot pending)"
        return 'ok'
    }
    elseif ($postCheck) {
        Write-Log "  OK $name - installed (verified in registry, code=$code, ${secs}s)" 'OK'
        Show-AppResult -AppName $name -Result 'ok' -Detail "(${secs}s, registry verified)"
        return 'ok'
    }
    elseif ($timedOut) {
        Write-Log "  FAIL $name - TIMEOUT ${timeout}s and not in registry" 'ERROR'
        Show-AppResult -AppName $name -Result 'fail' -Detail "(TIMEOUT ${timeout}s)"
        return 'fail'
    }
    else {
        Write-Log "  FAIL $name - code=$code, not in registry (${secs}s)" 'ERROR'
        Show-AppResult -AppName $name -Result 'fail' -Detail "(code=$code, ${secs}s)"
        return 'fail'
    }
}

# ══════════════════════════════════════════════
# PHASE 2: UI AUTOMATION ENGINE
# ══════════════════════════════════════════════

function Initialize-UIAutomation {
    <# Load UI Automation assemblies and Win32 helpers #>
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    Add-Type -AssemblyName System.Windows.Forms

    Add-Type -MemberDefinition @'
        [DllImport("user32.dll")]
        public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, int dwExtraInfo);
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);
'@ -Name 'Win32UI' -Namespace 'PInvoke' -EA SilentlyContinue
}

function Invoke-UIClick {
    param([System.Windows.Automation.AutomationElement]$Element, [string]$Label)
    # Method 1: InvokePattern
    try {
        $ip = $Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $ip.Invoke()
        Write-Log "    Click (Invoke): '$Label'" 'OK'
        return $true
    } catch {}
    # Method 2: SelectionItemPattern (radio buttons)
    try {
        $sp = $Element.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        $sp.Select()
        Write-Log "    Click (Select): '$Label'" 'OK'
        return $true
    } catch {}
    # Method 3: Physical coordinates
    try {
        $rect = $Element.Current.BoundingRectangle
        if ($rect.Width -gt 0 -and $rect.Height -gt 0) {
            $x = [int]($rect.X + $rect.Width / 2)
            $y = [int]($rect.Y + $rect.Height / 2)
            [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
            Start-Sleep -Milliseconds 150
            [PInvoke.Win32UI]::mouse_event(0x0002, 0, 0, 0, 0)  # LEFTDOWN
            [PInvoke.Win32UI]::mouse_event(0x0004, 0, 0, 0, 0)  # LEFTUP
            Write-Log "    Click (coords $x,$y): '$Label'" 'OK'
            return $true
        }
    } catch {}
    return $false
}

function Find-UIButton {
    param(
        [System.Windows.Automation.AutomationElement]$Window,
        [string[]]$Names
    )
    foreach ($n in $Names) {
        $cName = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, $n)
        $cType = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Button)
        $cAnd  = New-Object System.Windows.Automation.AndCondition($cName, $cType)
        $el = $Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cAnd)
        if ($el) { return @{ Element = $el; Name = $n } }
    }
    return $null
}

function Select-UIRadioButton {
    param(
        [System.Windows.Automation.AutomationElement]$Window,
        [string[]]$Patterns
    )
    $rbCondition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::RadioButton)
    $radios = $Window.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants, $rbCondition)

    foreach ($rb in $radios) {
        try {
            $rbName = $rb.Current.Name
            foreach ($pat in $Patterns) {
                if ($rbName -like "*$pat*") {
                    $clicked = Invoke-UIClick -Element $rb -Label "RadioButton: $rbName"
                    if ($clicked) { return $true }
                }
            }
        } catch {}
    }
    return $false
}

function Select-UICheckbox {
    param(
        [System.Windows.Automation.AutomationElement]$Window,
        [string[]]$Patterns
    )
    $cbCondition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::CheckBox)
    $checkboxes = $Window.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants, $cbCondition)

    foreach ($cb in $checkboxes) {
        try {
            $cbName = $cb.Current.Name
            foreach ($pat in $Patterns) {
                if ($cbName -like "*$pat*") {
                    $toggle = $cb.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
                    if ($toggle.Current.ToggleState -ne 'On') {
                        $toggle.Toggle()
                        Write-Log "    Checkbox checked: '$cbName'" 'OK'
                        return $true
                    }
                }
            }
        } catch {}
    }
    return $false
}

function Write-UIDump {
    param([System.Windows.Automation.AutomationElement]$Window)
    Write-Log "    --- CONTROL DUMP ---"
    $all = $Window.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($el in $all) {
        try {
            $n = $el.Current.Name
            $t = $el.Current.ControlType.ProgrammaticName
            $enabled = $el.Current.IsEnabled
            if ($n -and $n.Length -gt 0) {
                Write-Log "      [$t] '$n' (enabled=$enabled)"
            }
        } catch {}
    }
    Write-Log "    --- END DUMP ---"
}

function Find-InstallerWindow {
    param([string]$Pattern, [int]$TimeoutSec = 10)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        $windows = $root.FindAll(
            [System.Windows.Automation.TreeScope]::Children,
            [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($w in $windows) {
            try {
                $title = $w.Current.Name
                if ($title -match $Pattern) {
                    return $w
                }
            } catch {}
        }
        Start-Sleep -Milliseconds 400
    }
    return $null
}

function Invoke-UIAutomationLoop {
    <#
    .SYNOPSIS
        Generic UI Automation loop for wizard-based installers.
        Detects pages, clicks buttons in priority order, handles stuck detection.
    #>
    param(
        [System.Diagnostics.Process]$Process,
        [string]$WindowPattern,
        [int]$MaxWaitSec = 600,
        [string]$AppLabel = 'App'
    )

    # Button name lists (Spanish + English)
    $acceptBtns  = @('Acepto','I Agree','Accept','Aceptar','OK','Agree',
                      'I accept the agreement','Acepto el acuerdo')
    $installBtns = @('Instalar','Install','Install Now','Instalar ahora')
    $nextBtns    = @('Siguiente >','Siguiente','Next >','Next')
    $skipBtns    = @('Omitir','Skip','No, gracias','No thanks','Later','Despues','Cancel')
    $finishBtns  = @('Finalizar','Finish','Close','Cerrar','Done','Listo','Complete')

    $acceptRadio = @('Acepto el acuerdo','Acepto','I accept the agreement',
                      'I accept','Acepto los','I agree','accept the terms',
                      'accept the license','accept the agreement')

    $swTotal       = [Diagnostics.Stopwatch]::StartNew()
    $clickCount    = 0
    $samePageCount = 0
    $pageHash      = ''

    while ($swTotal.Elapsed.TotalSeconds -lt $MaxWaitSec) {
        # Check if process exited
        if ($Process.HasExited) {
            Write-Log "  Process exited (code=$($Process.ExitCode))"
            break
        }

        # Animated spinner on console
        $spin = $Script:SpinChars[$Script:SpinIdx % 4]
        $Script:SpinIdx++
        $elapsed = [int]$swTotal.Elapsed.TotalSeconds
        Write-Host "`r  [$spin] UI Automation: ${elapsed}s elapsed, $clickCount actions..." -ForegroundColor Cyan -NoNewline

        # Find window
        $win = Find-InstallerWindow -Pattern $WindowPattern -TimeoutSec 5
        if (-not $win) {
            Start-Sleep -Seconds 2
            continue
        }

        # Page change detection
        $currentTitle = $win.Current.Name
        $btnState = ''
        try {
            $btns = $win.FindAll(
                [System.Windows.Automation.TreeScope]::Descendants,
                (New-Object System.Windows.Automation.PropertyCondition(
                    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                    [System.Windows.Automation.ControlType]::Button)))
            foreach ($b in $btns) {
                try { $btnState += $b.Current.Name + $b.Current.IsEnabled.ToString() } catch {}
            }
        } catch {}
        $newHash = "$currentTitle|$btnState"

        if ($newHash -ne $pageHash) {
            $pageHash = $newHash
            $samePageCount = 0
            Write-Log "  Page: '$currentTitle'"
        } else {
            $samePageCount++
        }

        # Stuck detection: dump controls at 3 iterations
        if ($samePageCount -eq 3) {
            Write-Log "  STUCK on: '$currentTitle' - analyzing controls..." 'WARN'
            Write-UIDump -Window $win
        }

        # Last resort: send Enter at 10+ iterations
        if ($samePageCount -ge 10 -and $samePageCount % 5 -eq 0) {
            Write-Log "  Trying Enter as last resort..." 'WARN'
            try {
                [PInvoke.Win32UI]::SetForegroundWindow($win.Current.NativeWindowHandle)
                Start-Sleep -Milliseconds 200
                [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
                $clickCount++
                Start-Sleep -Seconds 2
                continue
            } catch {}
        }

        $clicked = $false

        # STEP 1: License radio buttons
        if (-not $clicked) {
            $rbSelected = Select-UIRadioButton -Window $win -Patterns $acceptRadio
            if ($rbSelected) {
                $clicked = $true
                Start-Sleep -Milliseconds 500
                $nextBtn = Find-UIButton -Window $win -Names $nextBtns
                if ($nextBtn) {
                    Start-Sleep -Milliseconds 300
                    Invoke-UIClick -Element $nextBtn.Element -Label $nextBtn.Name | Out-Null
                    $clickCount++
                }
            }
        }

        # STEP 2: License checkboxes
        if (-not $clicked) {
            $cbSelected = Select-UICheckbox -Window $win -Patterns $acceptRadio
            if ($cbSelected) {
                $clicked = $true
                Start-Sleep -Milliseconds 500
                $nextBtn = Find-UIButton -Window $win -Names $nextBtns
                if ($nextBtn) {
                    Invoke-UIClick -Element $nextBtn.Element -Label $nextBtn.Name | Out-Null
                    $clickCount++
                }
            }
        }

        # STEP 3: Accept/Agree buttons
        if (-not $clicked) {
            $btn = Find-UIButton -Window $win -Names $acceptBtns
            if ($btn) { $clicked = Invoke-UIClick -Element $btn.Element -Label $btn.Name }
        }

        # STEP 4: Install button
        if (-not $clicked) {
            $btn = Find-UIButton -Window $win -Names $installBtns
            if ($btn) { $clicked = Invoke-UIClick -Element $btn.Element -Label $btn.Name }
        }

        # STEP 5: Next button (only if enabled)
        if (-not $clicked) {
            $btn = Find-UIButton -Window $win -Names $nextBtns
            if ($btn -and $btn.Element.Current.IsEnabled) {
                $clicked = Invoke-UIClick -Element $btn.Element -Label $btn.Name
            }
        }

        # STEP 6: Skip button
        if (-not $clicked) {
            $btn = Find-UIButton -Window $win -Names $skipBtns
            if ($btn) { $clicked = Invoke-UIClick -Element $btn.Element -Label $btn.Name }
        }

        # STEP 7: Finish button
        if (-not $clicked) {
            $btn = Find-UIButton -Window $win -Names $finishBtns
            if ($btn) { $clicked = Invoke-UIClick -Element $btn.Element -Label $btn.Name }
        }

        if ($clicked) { $clickCount++ }
        Start-Sleep -Seconds 2
    }

    # Clear spinner line
    Write-Host "`r  " + (' ' * 70) -NoNewline
    Write-Host "`r" -NoNewline

    return $clickCount
}

function Install-PDFelementUI {
    Write-Log "== PDFELEMENT - UI AUTOMATION =="

    if (Test-Installed -Keywords @('PDFelement','Wondershare','PDFelement Business')) {
        Write-Log "  PDFelement already installed - SKIP" 'OK'
        Show-AppResult -AppName 'PDFelement' -Result 'skip'
        return 'skip'
    }

    $pdfExe = "$Source\pdfelement_business-15066_10.1.5.exe"
    if (-not (Test-Path $pdfExe)) {
        Write-Log "  File not found: $pdfExe" 'ERROR'
        Show-AppResult -AppName 'PDFelement' -Result 'fail' -Detail '(file not found)'
        return 'fail'
    }

    # Copy to local cache
    if (-not (Test-Path $LocalCache)) { New-Item -Path $LocalCache -ItemType Directory -Force | Out-Null }
    $localPdf = "$LocalCache\pdfelement_setup.exe"
    if (-not (Test-Path $localPdf)) {
        Show-AppProgress -AppName 'PDFelement' -Status "Copying to local cache" -Percent 5
        Copy-Item $pdfExe $localPdf -Force
    }

    # Kill pre-existing Wondershare processes
    'PDFelement*','Wondershare*','wshelper*','WsAppService*','ElevationService*' | ForEach-Object {
        Get-Process -Name $_ -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
    }

    Show-AppProgress -AppName 'PDFelement' -Status "Launching installer" -Percent 15

    # Launch installer
    $proc = Start-Process -FilePath $localPdf -PassThru
    Write-Log "  Launched PDFelement installer PID=$($proc.Id)"

    # UI Automation loop
    Show-AppProgress -AppName 'PDFelement' -Status "UI Automation running" -Percent 30
    $clickCount = Invoke-UIAutomationLoop `
        -Process $proc `
        -WindowPattern 'PDFelement|Wondershare|Instalar|Setup|Select Setup' `
        -MaxWaitSec 600 `
        -AppLabel 'PDFelement'

    # Kill residual Wondershare GUI processes
    Start-Sleep -Seconds 3
    'PDFelement','Wondershare PDFelement','wshelper','WsAppService',
    'ElevationService','Wondershare Helper Compact' | ForEach-Object {
        Get-Process -Name $_ -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
    }

    # Verification
    Start-Sleep -Seconds 2
    $Global:InstalledCache = Get-InstalledApps
    if (Test-Installed -Keywords @('PDFelement','Wondershare')) {
        Write-Log "  PDFelement INSTALLED OK ($clickCount actions)" 'OK'
        Show-AppResult -AppName 'PDFelement' -Result 'ok' -Detail "($clickCount UI actions)"

        # Create shortcut
        $pdfExePath = Resolve-ExePath -Shortcut @{
            Exe = "$env:ProgramFiles\Wondershare\PDFelement\PDFelement.exe"
            Alt = "${env:ProgramFiles(x86)}\Wondershare\PDFelement\PDFelement.exe"
        }
        New-Shortcut -Name 'PDFelement' -TargetPath $pdfExePath

        return 'ok'
    } else {
        Write-Log "  PDFelement NOT detected in registry after $clickCount actions" 'ERROR'
        Show-AppResult -AppName 'PDFelement' -Result 'fail' -Detail "($clickCount actions, not in registry)"
        return 'fail'
    }
}

function Install-iManageWorkUI {
    Write-Log "== IMANAGE WORK DESKTOP - UI AUTOMATION =="

    if (Test-Installed -Keywords @('iManage Work Desktop','iManage Work')) {
        Write-Log "  iManage Work Desktop already installed - SKIP" 'OK'
        Show-AppResult -AppName 'iManage Work Desktop' -Result 'skip'
        return 'skip'
    }

    $imExe = "$Source\Imanage 2.0\iManage Work Desktop for Windows 10.9.4.39 (x64 Office)\iManageWorkDesktopforWindowsx64.exe"
    if (-not (Test-Path $imExe)) {
        Write-Log "  File not found: $imExe" 'ERROR'
        Show-AppResult -AppName 'iManage Work Desktop' -Result 'fail' -Detail '(file not found)'
        return 'fail'
    }

    # Copy ENTIRE folder to local cache to bypass network security warnings
    # InstallShield needs setup.ini, .cab files etc alongside the .exe
    if (-not (Test-Path $LocalCache)) { New-Item -Path $LocalCache -ItemType Directory -Force | Out-Null }
    $imSourceFolder = Split-Path $imExe
    $imLocalFolder  = "$LocalCache\iManage_WorkDesktop"
    if (-not (Test-Path $imLocalFolder)) {
        Show-AppProgress -AppName 'iManage Work Desktop' -Status "Copying folder to local cache" -Percent 5
        Write-Log "  Copying entire folder to local: $imSourceFolder -> $imLocalFolder"
        Copy-Item -Path $imSourceFolder -Destination $imLocalFolder -Recurse -Force
    }
    $localIm = Join-Path $imLocalFolder ([IO.Path]::GetFileName($imExe))

    Show-AppProgress -AppName 'iManage Work Desktop' -Status "Launching installer" -Percent 15

    # Launch installer from local cache (no network security warning)
    $proc = Start-Process -FilePath $localIm -PassThru
    Write-Log "  Launched iManage Work Desktop installer PID=$($proc.Id)"

    # UI Automation loop
    Show-AppProgress -AppName 'iManage Work Desktop' -Status "UI Automation running" -Percent 30
    $clickCount = Invoke-UIAutomationLoop `
        -Process $proc `
        -WindowPattern 'iManage|InstallShield|Work Desktop' `
        -MaxWaitSec 600 `
        -AppLabel 'iManage Work Desktop'

    # Wait for msiexec child processes (InstallShield spawns msiexec internally)
    Write-Host "  Waiting for msiexec child processes..." -ForegroundColor DarkGray
    Write-Log "  Waiting for msiexec children..."
    $swMsi = [Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Seconds 5
    while ($swMsi.Elapsed.TotalSeconds -lt 300) {
        $msi = Get-Process -Name 'msiexec' -EA SilentlyContinue |
               Where-Object { $_.SessionId -ne 0 }
        if (-not $msi) { break }

        $spin = $Script:SpinChars[$Script:SpinIdx % 4]
        $Script:SpinIdx++
        $elapsed = [int]$swMsi.Elapsed.TotalSeconds
        Write-Host "`r  [$spin] msiexec active... ${elapsed}s" -ForegroundColor DarkGray -NoNewline

        Start-Sleep -Seconds 5
    }
    Write-Host "`r  " + (' ' * 50) -NoNewline
    Write-Host ""
    Write-Log "  msiexec children finished ($([int]$swMsi.Elapsed.TotalSeconds)s)"

    # Verification
    Start-Sleep -Seconds 3
    $Global:InstalledCache = Get-InstalledApps
    if (Test-Installed -Keywords @('iManage Work Desktop','iManage Work')) {
        Write-Log "  iManage Work Desktop INSTALLED OK ($clickCount actions)" 'OK'
        Show-AppResult -AppName 'iManage Work Desktop' -Result 'ok' -Detail "($clickCount UI actions)"
        return 'ok'
    } else {
        Write-Log "  iManage Work Desktop NOT detected in registry" 'ERROR'
        Show-AppResult -AppName 'iManage Work Desktop' -Result 'fail' -Detail "($clickCount actions, not in registry)"
        return 'fail'
    }
}

# ══════════════════════════════════════════════
# ESET UI AUTOMATION (Sciter custom GUI)
# ══════════════════════════════════════════════

function Find-ESETWindow {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $wins = $root.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($w in $wins) {
        try {
            $t = $w.Current.Name
            if ($t -match 'Bloc de notas|Notepad|Visual Studio|Code|Explorer|Bulk|Uninstall|Update|Notification|Terminal|PowerShell|pwsh|cmd|NodeDeploy') {
                continue
            }
            if ($t -match 'ESET|Endpoint.*Security|Package Installer') {
                try { [PInvoke.Win32UI]::SetForegroundWindow($w.Current.NativeWindowHandle) | Out-Null } catch {}
                return $w
            }
        } catch {}
    }
    return $null
}

function Invoke-ESETClickCoords {
    param($Win, [double]$RelX, [double]$RelY, [string]$Label)
    try {
        $rect = $Win.Current.BoundingRectangle
        if ($rect.Width -le 0 -or $rect.Height -le 0) { return $false }
        $x = [int]($rect.X + $rect.Width  * $RelX)
        $y = [int]($rect.Y + $rect.Height * $RelY)
        [PInvoke.Win32UI]::SetForegroundWindow($Win.Current.NativeWindowHandle) | Out-Null
        Start-Sleep -Milliseconds 200
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
        Start-Sleep -Milliseconds 150
        [PInvoke.Win32UI]::mouse_event(0x0002,0,0,0,0)
        [PInvoke.Win32UI]::mouse_event(0x0004,0,0,0,0)
        Write-Log "    Click COORDS (${RelX},${RelY} -> abs=$x,$y): '$Label'" 'OK'
        return $true
    } catch {
        Write-Log "    Click COORDS failed: $_" 'ERROR'
        return $false
    }
}

function Find-ESETAnyByName {
    # Busca CUALQUIER elemento cuyo Name sea exacto (Sciter no expone como Button)
    param($Win, [string[]]$Names)
    $all = $Win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($el in $all) {
        try {
            $n = $el.Current.Name
            if (-not $n -or $n.Length -eq 0) { continue }
            foreach ($target in $Names) {
                if ($n -eq $target) {
                    $clickable = $false
                    try { $null = $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern); $clickable = $true } catch {}
                    if (-not $clickable) {
                        try { $r = $el.Current.BoundingRectangle; if ($r.Width -gt 0) { $clickable = $true } } catch {}
                    }
                    if ($clickable) { return @{ Element = $el; Name = "$target [$($el.Current.ControlType.ProgrammaticName)]" } }
                }
            }
        } catch {}
    }
    return $null
}

function Install-ESETUI {
    Write-Log "== ESET ENDPOINT - UI AUTOMATION =="

    if (Test-Installed -Keywords @('ESET Endpoint','ESET Endpoint Security','ESET Endpoint Antivirus')) {
        Write-Log "  ESET Endpoint already installed - SKIP" 'OK'
        Show-AppResult -AppName 'ESET Endpoint' -Result 'skip'
        return 'skip'
    }

    $esetExe = Join-Path $Source 'epi_win_live_installer.exe'
    if (-not (Test-Path $esetExe)) {
        Write-Log "  ESET installer not found: $esetExe" 'ERROR'
        Show-AppResult -AppName 'ESET Endpoint' -Result 'fail' -Detail '(file not found)'
        return 'fail'
    }

    # Copiar a local (el live installer requiere cache local)
    $localExe = Copy-ToLocal -NetworkPath $esetExe

    Show-AppProgress -AppName 'ESET Endpoint' -Status "Launching installer" -Percent 10

    $proc = Start-Process -FilePath $localExe -PassThru
    Write-Log "  ESET PID=$($proc.Id)"

    Show-AppProgress -AppName 'ESET Endpoint' -Status "UI Automation (Sciter GUI)" -Percent 20

    # Botones ES + EN
    $continueBtns = @('Continuar','Continue','Seguir')
    $nextBtns     = @('Siguiente','Next','Siguiente >','Next >')
    $acceptBtns   = @('Acepto','Aceptar','Accept','I Agree','I Accept','Agree')
    $installBtns  = @('Instalar','Install','Comenzar instalacion','Start installation')
    $finishBtns   = @('Finalizar','Finish','Listo','Done','Hecho')
    $acceptRadio  = @('Acepto','I accept','I agree','Acepto los terminos',
                       'accept the terms','accept the license','accept the agreement',
                       'Acepto el acuerdo','Acepto las condiciones')
    $allActionBtns = $continueBtns + $nextBtns + $acceptBtns + $installBtns + $finishBtns

    # Coordenadas relativas del boton "Continuar" en pantalla de licencia ESET
    $btnRelX = 0.36
    $btnRelY = 0.95

    $swTotal    = [Diagnostics.Stopwatch]::StartNew()
    $maxWait    = 600
    $clickCount = 0
    $pageHash   = ''
    $stuckCount = 0
    $progressStuckCount = 0

    while ($swTotal.Elapsed.TotalSeconds -lt $maxWait) {
        # Proceso termino?
        if ($proc.HasExited) {
            $winCheck = Find-ESETWindow
            if (-not $winCheck) {
                Write-Log "  ESET process exited (code=$($proc.ExitCode)), no window"
                break
            }
        }

        $win = Find-ESETWindow
        if (-not $win) { Start-Sleep -Seconds 3; continue }

        # Detectar pagina
        $title = $win.Current.Name
        $bState = ''
        try {
            $btns = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants,
                (New-Object System.Windows.Automation.PropertyCondition(
                    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                    [System.Windows.Automation.ControlType]::Button)))
            foreach ($b in $btns) { try { $bState += $b.Current.Name + $b.Current.IsEnabled } catch {} }
        } catch {}
        $hash = "$title|$bState"

        if ($hash -ne $pageHash) {
            $pageHash = $hash; $stuckCount = 0
            $short = if ($title.Length -gt 80) { $title.Substring(0,80) + '...' } else { $title }
            Write-Log "  Page: '$short'"
        } else {
            $stuckCount++
        }

        # Spinner
        $spin = $Script:SpinChars[$Script:SpinIdx % 4]; $Script:SpinIdx++
        $elapsed = [int]$swTotal.Elapsed.TotalSeconds

        # Deteccion de progreso (solo Cancelar visible, sin botones de accion)
        $hasCancel = $bState -match 'Cancelar|Cancel'
        $hasAction = $bState -match 'Continuar|Continue|Siguiente|Next|Instalar|Install|Finalizar|Finish|Acepto|Accept'
        $isProgress = $hasCancel -and -not $hasAction

        if ($isProgress) {
            if ($stuckCount -gt 0) { $progressStuckCount++ } else { $progressStuckCount = 0 }

            # Estancado en "progreso" >30s: la 2da pantalla puede no exponer botones
            if ($progressStuckCount -ge 6) {
                Write-Log "  ESET progress stalled ($progressStuckCount iter) - trying fallbacks" 'WARN'

                if ($progressStuckCount -eq 6) { Write-UIDump -Window $win }

                # Busqueda amplia (cualquier ControlType)
                $anyBtn = Find-ESETAnyByName -Win $win -Names ($continueBtns + $acceptBtns + $installBtns + $nextBtns)
                if ($anyBtn) {
                    Write-Log "  Found via broad search: '$($anyBtn.Name)'" 'OK'
                    if (Invoke-UIClick -Element $anyBtn.Element -Label $anyBtn.Name) {
                        $clickCount++; $progressStuckCount = 0; Start-Sleep -Seconds 3; continue
                    }
                }

                # Fallback: click por coordenadas
                if ($progressStuckCount -ge 7 -and $progressStuckCount % 2 -eq 1) {
                    Write-Log "  Fallback: COORDS click at ($btnRelX, $btnRelY)" 'WARN'
                    if (Invoke-ESETClickCoords -Win $win -RelX $btnRelX -RelY $btnRelY -Label 'Continuar (coords)') {
                        $clickCount++; $progressStuckCount = 0; Start-Sleep -Seconds 3; continue
                    }
                }

                # Fallback: ENTER
                if ($progressStuckCount -ge 8 -and $progressStuckCount % 2 -eq 0) {
                    Write-Log "  Fallback: ENTER" 'WARN'
                    try {
                        [PInvoke.Win32UI]::SetForegroundWindow($win.Current.NativeWindowHandle) | Out-Null
                        Start-Sleep -Milliseconds 300
                        [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
                        $clickCount++; Start-Sleep -Seconds 3; continue
                    } catch {}
                }

                # Fallback: TAB+ENTER
                if ($progressStuckCount -ge 10 -and $progressStuckCount % 4 -eq 0) {
                    Write-Log "  Fallback: TAB+ENTER" 'WARN'
                    try {
                        [PInvoke.Win32UI]::SetForegroundWindow($win.Current.NativeWindowHandle) | Out-Null
                        Start-Sleep -Milliseconds 300
                        [System.Windows.Forms.SendKeys]::SendWait('{TAB}')
                        Start-Sleep -Milliseconds 200
                        [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
                        $clickCount++; Start-Sleep -Seconds 3; continue
                    } catch {}
                }
            }

            $extra = if ($progressStuckCount -gt 0) { " stall=$progressStuckCount" } else { '' }
            Write-Host "`r  [$spin] ESET downloading/installing... ${elapsed}s$extra" -ForegroundColor DarkGray -NoNewline
            Start-Sleep -Seconds 5
            continue
        } else {
            $progressStuckCount = 0
        }

        # Cancelacion accidental
        if ($title -match 'seguro|sure|cancel.*confirm|cerrar.*asistente') {
            $noBtn = Find-UIButton -Window $win -Names @('No')
            if ($noBtn) { Invoke-UIClick -Element $noBtn.Element -Label 'No'; $clickCount++; Start-Sleep -Seconds 2; continue }
        }

        # Dump si atascado
        if ($stuckCount -eq 6) {
            Write-Log "  ESET stuck on non-progress page" 'WARN'
            Write-UIDump -Window $win
        }

        # Enter si muy atascado
        if ($stuckCount -ge 15 -and $stuckCount % 5 -eq 0) {
            Write-Log "  Sending Enter..." 'WARN'
            try {
                [PInvoke.Win32UI]::SetForegroundWindow($win.Current.NativeWindowHandle) | Out-Null
                Start-Sleep -Milliseconds 200
                [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
                $clickCount++; Start-Sleep -Seconds 2; continue
            } catch {}
        }

        $clicked = $false

        # 1. Radio buttons de licencia
        if (-not $clicked) {
            $rbSelected = Select-UIRadioButton -Window $win -Patterns $acceptRadio
            if ($rbSelected) {
                $clicked = $true
                Start-Sleep -Milliseconds 500
                $nb = Find-UIButton -Window $win -Names ($nextBtns + $continueBtns)
                if ($nb) { Invoke-UIClick -Element $nb.Element -Label $nb.Name | Out-Null; $clickCount++ }
            }
        }

        # 2. Checkboxes de licencia
        if (-not $clicked -and $title -match 'Acuerdo|License|licencia|EULA') {
            $cbSelected = Select-UICheckbox -Window $win -Patterns ($acceptRadio + @('*'))
            if ($cbSelected) {
                $clicked = $true
                Start-Sleep -Milliseconds 500
                $nb = Find-UIButton -Window $win -Names ($nextBtns + $continueBtns)
                if ($nb) { Invoke-UIClick -Element $nb.Element -Label $nb.Name | Out-Null; $clickCount++ }
            }
        }

        # 3. Continuar
        if (-not $clicked) {
            $b = Find-UIButton -Window $win -Names $continueBtns
            if ($b) { $clicked = Invoke-UIClick -Element $b.Element -Label $b.Name }
        }

        # 4. Accept
        if (-not $clicked) {
            $b = Find-UIButton -Window $win -Names $acceptBtns
            if ($b) { $clicked = Invoke-UIClick -Element $b.Element -Label $b.Name }
        }

        # 5. Install
        if (-not $clicked) {
            $b = Find-UIButton -Window $win -Names $installBtns
            if ($b) { $clicked = Invoke-UIClick -Element $b.Element -Label $b.Name }
        }

        # 6. Next
        if (-not $clicked) {
            $b = Find-UIButton -Window $win -Names $nextBtns
            if ($b -and $b.Element.Current.IsEnabled) { $clicked = Invoke-UIClick -Element $b.Element -Label $b.Name }
        }

        # 7. Finish
        if (-not $clicked) {
            $b = Find-UIButton -Window $win -Names $finishBtns
            if ($b) { $clicked = Invoke-UIClick -Element $b.Element -Label $b.Name }
        }

        # 8. Busqueda amplia (Sciter custom)
        if (-not $clicked) {
            $anyBtn = Find-ESETAnyByName -Win $win -Names $allActionBtns
            if ($anyBtn) {
                Write-Log "    Found (broad): '$($anyBtn.Name)'"
                $clicked = Invoke-UIClick -Element $anyBtn.Element -Label $anyBtn.Name
            }
        }

        # 9. Coords fallback en pagina licencia
        if (-not $clicked -and $stuckCount -ge 4 -and $title -match 'Acuerdo|License|licencia|EULA') {
            Write-Log "    License page, no button detected - coords click" 'WARN'
            $clicked = Invoke-ESETClickCoords -Win $win -RelX $btnRelX -RelY $btnRelY -Label 'Continuar (coords-lic)'
        }

        if ($clicked) { $clickCount++; Start-Sleep -Seconds 3 } else { Start-Sleep -Seconds 2 }

        Write-Host "`r  [$spin] ESET UI Automation: ${elapsed}s, $clickCount actions" -ForegroundColor Cyan -NoNewline
    }

    Write-Host ""

    # Esperar procesos ESET post-install
    Write-Log "  Waiting for ESET post-install processes..."
    $swPost = [Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Seconds 10
    while ($swPost.Elapsed.TotalSeconds -lt 120) {
        $ep = Get-Process | Where-Object { $_.Name -match 'epi_win|eset.*install|msiexec' -and $_.SessionId -ne 0 }
        if (-not $ep) { break }
        Start-Sleep -Seconds 5
    }
    Write-Log "  ESET post processes done ($([int]$swPost.Elapsed.TotalSeconds)s)"

    # Verificar
    Start-Sleep -Seconds 5
    $Global:InstalledCache = Get-InstalledApps

    if (Test-Installed -Keywords @('ESET Endpoint') -Refresh) {
        Write-Log "  ESET Endpoint INSTALLED ($clickCount actions)" 'OK'
        Show-AppResult -AppName 'ESET Endpoint' -Result 'ok' -Detail "($clickCount UI actions)"
        return 'ok'
    } else {
        Write-Log "  ESET Endpoint NOT INSTALLED ($clickCount actions)" 'ERROR'
        Show-AppResult -AppName 'ESET Endpoint' -Result 'fail' -Detail "($clickCount actions)"
        return 'fail'
    }
}

# ══════════════════════════════════════════════
# PHASE 3: OUTLOOK ADD-IN CLEANUP
# ══════════════════════════════════════════════

function Invoke-OutlookAddinCleanup {
    Write-Log "== OUTLOOK ADD-IN CLEANUP =="

    # 3a: Close Outlook
    $outlookProc = Get-Process -Name 'OUTLOOK' -EA SilentlyContinue
    if ($outlookProc) {
        Write-Host "  Closing Outlook..." -ForegroundColor Yellow
        Write-Log "  Closing Outlook..."
        $outlookProc | Stop-Process -Force -EA SilentlyContinue
        Start-Sleep -Seconds 3
    }

    $addinRegPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins',
        'HKCU:\SOFTWARE\Microsoft\Office\Outlook\Addins'
    )

    # 3b: Log current state
    Write-Log "  --- Current add-in state ---"
    foreach ($regPath in $addinRegPaths) {
        if (Test-Path $regPath) {
            $addins = Get-ChildItem $regPath -EA SilentlyContinue
            foreach ($addin in $addins) {
                $props = Get-ItemProperty $addin.PSPath -EA SilentlyContinue
                Write-Log "    [$regPath] $($addin.PSChildName) | $($props.FriendlyName) | LB=$($props.LoadBehavior)"
            }
        }
    }

    # 3c: Remove Mitel add-ins
    Write-Host "  Removing Mitel add-ins..." -ForegroundColor Yellow
    Write-Log "  --- Removing Mitel add-ins ---"
    $mitelPatterns = @('*Mitel*', '*MiCollab*', '*MiVoice*', '*ShoreTel*')
    $mitelRemoved = 0

    foreach ($regPath in $addinRegPaths) {
        if (-not (Test-Path $regPath)) { continue }
        $addins = Get-ChildItem $regPath -EA SilentlyContinue
        foreach ($addin in $addins) {
            $name     = $addin.PSChildName
            $props    = Get-ItemProperty $addin.PSPath -EA SilentlyContinue
            $friendly = $props.FriendlyName
            $isMitel  = $false

            foreach ($pattern in $mitelPatterns) {
                if ($name -like $pattern -or $friendly -like $pattern) {
                    $isMitel = $true; break
                }
            }

            if ($isMitel) {
                Write-Log "    REMOVING: $name ($friendly)" 'WARN'
                Remove-Item $addin.PSPath -Recurse -Force -EA SilentlyContinue
                $mitelRemoved++
            }
        }
    }
    Write-Host "  Mitel add-ins removed: $mitelRemoved" -ForegroundColor $(if ($mitelRemoved -gt 0) { 'Green' } else { 'DarkGray' })

    # 3d: Remove Outlook Social Connector
    Write-Host "  Removing Outlook Social Connector..." -ForegroundColor Yellow
    Write-Log "  --- Removing Outlook Social Connector ---"
    $oscPatterns = @('*Social*Connector*', '*OscAddin*', '*OSC*')
    $oscRemoved = 0

    foreach ($regPath in $addinRegPaths) {
        if (-not (Test-Path $regPath)) { continue }
        $addins = Get-ChildItem $regPath -EA SilentlyContinue
        foreach ($addin in $addins) {
            $name     = $addin.PSChildName
            $props    = Get-ItemProperty $addin.PSPath -EA SilentlyContinue
            $friendly = $props.FriendlyName
            $isOSC    = $false

            foreach ($pattern in $oscPatterns) {
                if ($name -like $pattern -or $friendly -like $pattern) {
                    $isOSC = $true; break
                }
            }

            if ($isOSC) {
                Write-Log "    REMOVING: $name ($friendly)" 'WARN'
                Remove-Item $addin.PSPath -Recurse -Force -EA SilentlyContinue
                $oscRemoved++
            }
        }
    }
    Write-Host "  Social Connector add-ins removed: $oscRemoved" -ForegroundColor $(if ($oscRemoved -gt 0) { 'Green' } else { 'DarkGray' })

    # 3e: Enable iManage add-in (LoadBehavior=3)
    Write-Host "  Enabling iManage add-in..." -ForegroundColor Yellow
    Write-Log "  --- Configuring iManage add-in ---"
    $imanageFound = $false

    foreach ($regPath in $addinRegPaths) {
        if (-not (Test-Path $regPath)) { continue }
        $addins = Get-ChildItem $regPath -EA SilentlyContinue
        foreach ($addin in $addins) {
            $name = $addin.PSChildName
            if ($name -like '*iManage*') {
                $imanageFound = $true
                Set-ItemProperty -Path $addin.PSPath -Name 'LoadBehavior' -Value 3 -Type DWord -EA SilentlyContinue
                Write-Log "    iManage add-in enabled (LoadBehavior=3): $name" 'OK'
                Write-Host "  iManage add-in enabled: $name" -ForegroundColor Green
            }
        }
    }

    if (-not $imanageFound) {
        Write-Log "  WARNING: No iManage add-in found in Outlook registry" 'WARN'
        Write-Host "  WARNING: No iManage add-in found" -ForegroundColor Yellow
    }

    # 3f: Clean Outlook Resiliency registry
    Write-Host "  Cleaning Outlook Resiliency..." -ForegroundColor Yellow
    Write-Log "  --- Cleaning Resiliency ---"

    $resiliencyPaths = @(
        'HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Resiliency\DisabledItems',
        'HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Resiliency\CrashingAddinList',
        'HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Resiliency\DoNotDisableAddinList'
    )

    foreach ($rp in $resiliencyPaths) {
        if (Test-Path $rp) {
            $props = Get-ItemProperty $rp -EA SilentlyContinue
            if ($props) {
                $props.PSObject.Properties | Where-Object {
                    $_.Name -notmatch '^PS' -and $_.Value -match 'iManage'
                } | ForEach-Object {
                    Write-Log "    Removing resiliency entry: $($_.Name)" 'OK'
                    Remove-ItemProperty -Path $rp -Name $_.Name -EA SilentlyContinue
                }
            }
        }
    }

    # 3g: Mark iManage as DoNotDisable
    $doNotDisable = 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Resiliency\DoNotDisableAddinList'
    if (-not (Test-Path $doNotDisable)) {
        New-Item -Path $doNotDisable -Force | Out-Null
    }

    foreach ($regPath in $addinRegPaths) {
        if (-not (Test-Path $regPath)) { continue }
        Get-ChildItem $regPath -EA SilentlyContinue | Where-Object { $_.PSChildName -like '*iManage*' } | ForEach-Object {
            $progId = $_.PSChildName
            Set-ItemProperty -Path $doNotDisable -Name $progId -Value 1 -Type DWord -EA SilentlyContinue
            Write-Log "    Marked DoNotDisable: $progId" 'OK'
            Write-Host "  Marked DoNotDisable: $progId" -ForegroundColor Green
        }
    }

    # 3h: Restart Windows Search service
    Write-Host "  Restarting Windows Search..." -ForegroundColor Yellow
    Write-Log "  Restarting WSearch..."
    try {
        $ws = Get-Service -Name 'WSearch' -EA SilentlyContinue
        if ($ws -and $ws.Status -eq 'Running') {
            Restart-Service -Name 'WSearch' -Force -EA SilentlyContinue
            Write-Log "  WSearch restarted" 'OK'
            Write-Host "  Windows Search restarted" -ForegroundColor Green
        }
    } catch {
        Write-Log "  WSearch restart failed: $_" 'WARN'
    }

    # 3i: Final add-in state
    Write-Log "  --- Final add-in state ---"
    foreach ($regPath in $addinRegPaths) {
        if (-not (Test-Path $regPath)) { continue }
        $addins = Get-ChildItem $regPath -EA SilentlyContinue
        foreach ($addin in $addins) {
            $props = Get-ItemProperty $addin.PSPath -EA SilentlyContinue
            $status = switch ($props.LoadBehavior) {
                0  { 'Disabled' }
                1  { 'Loaded (not at startup)' }
                2  { 'Loaded at startup (not connected)' }
                3  { 'Enabled (loaded at startup)' }
                8  { 'Load on demand' }
                9  { 'Load on demand (connected)' }
                16 { 'First-time load' }
                default { "Unknown ($($props.LoadBehavior))" }
            }
            Write-Log "    $($addin.PSChildName) | $($props.FriendlyName) -> $status"
        }
    }
}

# ══════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ══════════════════════════════════════════════════════════════════

# Clear screen and show banner
Clear-Host
Show-Banner

Write-Log "============================================"
Write-Log " N0DE_DEPL0Y v2.0 - Session Start"
Write-Log " Source: $Source"
Write-Log " Log:    $LogFile"
Write-Log "============================================"

# Verify network source
if (-not (Test-Path $Source)) {
    Write-Host "  [ERROR] Cannot access: $Source" -ForegroundColor Red
    Write-Log "Cannot access $Source" 'ERROR'
    Write-Host ""
    Write-Host "  Press Enter to exit..." -ForegroundColor Cyan
    Read-Host
    exit 1
}
Write-Host "  Source: " -ForegroundColor DarkGray -NoNewline
Write-Host "$Source" -ForegroundColor Cyan
Write-Host "  Log:    " -ForegroundColor DarkGray -NoNewline
Write-Host "$LogFile" -ForegroundColor Cyan
Write-Host ""

# Initialize
$totalSW = [Diagnostics.Stopwatch]::StartNew()
$results = @{ OK = 0; Skipped = 0; Failed = 0 }

# Build registry cache
Write-Host "  Scanning installed applications..." -ForegroundColor DarkGray
Write-Log "Scanning registry..."
$Global:InstalledCache = Get-InstalledApps
Write-Log "  $($Global:InstalledCache.Count) apps detected"
Write-Host "  $($Global:InstalledCache.Count) apps detected in registry" -ForegroundColor DarkGray

# ────────────────────────────────────────────────────────────────
# PHASE 0: OFFICE BACKGROUND (se lanza primero, descarga en paralelo)
# ────────────────────────────────────────────────────────────────

Show-PhaseHeader -Phase 0 -Title "OFFICE BACKGROUND LAUNCH" -Subtitle "Office se lanza primero - descarga ~2GB en paralelo con el resto"

Show-GroupHeader -Label "Microsoft Outlook (Office) - BACKGROUND"
$officeJob = Start-OfficeBackground
switch ($officeJob.Status) {
    'skip'    { $results.Skipped++ }
    'fail'    { $results.Failed++ }
    'running' { Write-Host "  Office downloading in background while other installs proceed..." -ForegroundColor Green }
}

# ────────────────────────────────────────────
# PHASE 1: SILENT INSTALLATIONS
# ────────────────────────────────────────────

Show-PhaseHeader -Phase 1 -Title "SILENT INSTALLATIONS" -Subtitle "MSI / EXE / MSIX / iManage (Office downloading in background)"

# Groups 1-3
$groups = $SilentApps | Group-Object { $_.Group } | Sort-Object Name

foreach ($grp in $groups) {
    $groupApps = @($grp.Group)
    $label = switch ($grp.Name) {
        '1' { 'MSI Packages' }
        '2' { 'EXE Installers' }
        '3' { 'Complex Installers' }
        default { "Group $($grp.Name)" }
    }
    Show-GroupHeader -Label "$label ($($groupApps.Count) apps)"

    foreach ($app in $groupApps) {
        $r = Invoke-SilentInstall -App $app
        switch ($r) {
            'ok'   { $results.OK++ }
            'skip' { $results.Skipped++ }
            'fail' { $results.Failed++ }
        }
        if ($r -eq 'ok' -and $app.Shortcut) {
            $exe = Resolve-ExePath -Shortcut $app.Shortcut
            New-Shortcut -Name $app.Name -TargetPath $exe
        }
    }
}

# Group 5: iManage silent components
Show-GroupHeader -Label "iManage Components ($($iManageSilentApps.Count) apps)"

foreach ($im in $iManageSilentApps) {
    $r = Invoke-SilentInstall -App $im
    switch ($r) {
        'ok'   { $results.OK++ }
        'skip' { $results.Skipped++ }
        'fail' { $results.Failed++ }
    }
    if ($r -eq 'ok' -and $im.Shortcut) {
        $exe = Resolve-ExePath -Shortcut $im.Shortcut
        New-Shortcut -Name $im.Name -TargetPath $exe
    }
}

# ────────────────────────────────────────────
# PHASE 2: UI AUTOMATION INSTALLATIONS
# ────────────────────────────────────────────

Show-PhaseHeader -Phase 2 -Title "UI AUTOMATION INSTALLATIONS" -Subtitle "Installers without silent mode - automated via Windows UI Automation"

# Initialize UI Automation framework
Write-Host "  Loading UI Automation framework..." -ForegroundColor DarkGray
Initialize-UIAutomation
Write-Host "  UI Automation ready" -ForegroundColor Green
Write-Host ""

# ESET Endpoint (Sciter custom GUI)
Show-GroupHeader -Label "ESET Endpoint (Sciter GUI - UI Automation)"
$r = Install-ESETUI
switch ($r) {
    'ok'   { $results.OK++ }
    'skip' { $results.Skipped++ }
    'fail' { $results.Failed++ }
}

Write-Host ""

# PDFelement
Show-GroupHeader -Label "PDFelement (NSIS Wondershare - UI Automation)"
$r = Install-PDFelementUI
switch ($r) {
    'ok'   { $results.OK++ }
    'skip' { $results.Skipped++ }
    'fail' { $results.Failed++ }
}

Write-Host ""

# iManage Work Desktop
Show-GroupHeader -Label "iManage Work Desktop (InstallShield - UI Automation)"
$r = Install-iManageWorkUI
switch ($r) {
    'ok'   { $results.OK++ }
    'skip' { $results.Skipped++ }
    'fail' { $results.Failed++ }
}

# ────────────────────────────────────────────────────────────────
# WAIT FOR OFFICE (debe completarse antes de Phase 3 - addins)
# ────────────────────────────────────────────────────────────────

if ($officeJob.Status -eq 'running') {
    Show-GroupHeader -Label "Waiting for Office background install to complete"
    $officeResult = Wait-OfficeBackground -OfficeJob $officeJob
    switch ($officeResult) {
        'ok'   { $results.OK++ }
        'fail' { $results.Failed++ }
    }
}

# ────────────────────────────────────────────
# PHASE 3: OUTLOOK ADD-IN CLEANUP
# ────────────────────────────────────────────

Show-PhaseHeader -Phase 3 -Title "OUTLOOK ADD-IN CLEANUP" -Subtitle "Remove Mitel/Social Connector, enable iManage, clean resiliency"

Invoke-OutlookAddinCleanup

# ────────────────────────────────────────────
# CLEANUP AND SUMMARY
# ────────────────────────────────────────────

# Clean local cache
if (Test-Path $LocalCache) {
    Remove-Item $LocalCache -Recurse -Force -EA SilentlyContinue
    Write-Log "  Local cache cleaned"
}

$totalSW.Stop()
$elapsed = $totalSW.Elapsed.ToString('hh\:mm\:ss')

Write-Log ""
Write-Log "============================================"
Write-Log " SUMMARY"
Write-Log "============================================"
Write-Log "  Installed : $($results.OK)"
Write-Log "  Skipped   : $($results.Skipped)"
Write-Log "  Failed    : $($results.Failed)"
Write-Log "  Duration  : $elapsed"
Write-Log "  Log       : $LogFile"
Write-Log "============================================"

Show-FinalSummary -Results $results -Elapsed $elapsed

if ($results.Failed -gt 0) {
    Write-Host "  There were $($results.Failed) failure(s). Check the log for details." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "  Press Enter to exit..." -ForegroundColor Cyan
Read-Host