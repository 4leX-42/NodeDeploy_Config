<#
.SYNOPSIS
  Si el equipo es LG, desinstala McAfee (programas Win32 y app de la Store). En otro fabricante no hace nada.
  No reinicia: deja el reinicio a la instalacion que lo llama.

.USO
  powershell -ExecutionPolicy Bypass -File .\Quitar-McAfee-LG.ps1            # ejecuta
  powershell -ExecutionPolicy Bypass -File .\Quitar-McAfee-LG.ps1 -Probar    # solo muestra que haria
  Desde un .bat:
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Quitar-McAfee-LG.ps1"

  Log: C:\Diag\Quitar-McAfee_<fecha>.log (o -LogFile <ruta>)
  Dentro de NodeDeploy lo lanza Deploy.ps1 tras PRE-CHECKS, antes de instalar ESET/Cortex (-NoMcAfee lo omite).
  Codigo de salida: 0 = no es LG / no habia McAfee / quitado
                    1 = queda algo de McAfee instalado (mirar log)
                    2 = no se ejecuto como administrador
#>
param(
    [switch]$Probar,
    [string]$LogFile   # Deploy.ps1 lo deja en state\logs; suelto va a C:\Diag
)

$ErrorActionPreference = 'Continue'
$log = if ($LogFile) { $LogFile } else { "C:\Diag\Quitar-McAfee_$(Get-Date -Format 'yyyyMMdd_HHmmss').log" }
New-Item -ItemType Directory -Path (Split-Path $log) -Force | Out-Null
function Log([string]$m) { $l = "$(Get-Date -Format 'HH:mm:ss') $m"; Write-Host $l; $l | Out-File $log -Append -Encoding utf8 }

$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $esAdmin) { Log 'ERROR: hay que ejecutarlo como administrador.'; exit 2 }

# ---------- 1. Es LG? ----------
$fab = ((Get-CimInstance Win32_ComputerSystem).Manufacturer -replace "`0",'').Trim()
$mod = ((Get-CimInstance Win32_ComputerSystem).Model -replace "`0",'').Trim()
Log "Equipo: $env:COMPUTERNAME  Fabricante: '$fab'  Modelo: '$mod'  Probar: $Probar"
if ($fab -notmatch '^LG\b|LG Electronics') { Log 'No es LG: no se toca nada.'; exit 0 }

# ---------- 2. Buscar McAfee ----------
$claves = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
          'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
function Get-McAfee {
    Get-ItemProperty $claves -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and ($_.DisplayName -match 'McAfee' -or $_.Publisher -match 'McAfee') -and -not $_.SystemComponent } |
        Select-Object DisplayName, DisplayVersion, Publisher, UninstallString, QuietUninstallString, PSChildName
}
function Get-McAfeeAppx { Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'McAfee' -or $_.Publisher -match 'McAfee' } }

$prog = @(Get-McAfee)
$appx = @(Get-McAfeeAppx)
$prov = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'McAfee' })
if (-not $prog -and -not $appx -and -not $prov) { Log 'No hay McAfee instalado.'; exit 0 }

foreach ($p in $prog) { Log "Encontrado: $($p.DisplayName) $($p.DisplayVersion) [$($p.PSChildName)]`r`n           Uninstall: $($p.UninstallString)`r`n           Quiet:     $($p.QuietUninstallString)" }
foreach ($a in $appx) { Log "Encontrada app: $($a.PackageFullName)" }
foreach ($a in $prov) { Log "Encontrado provisionado: $($a.PackageName)" }

# Separa ejecutable y argumentos de una cadena de desinstalacion
function Split-Cmd([string]$s) {
    $s = $s.Trim()
    if ($s -match '^"([^"]+)"\s*(.*)$') { return $matches[1], $matches[2] }
    if ($s -match '^(.+?\.exe)\s*(.*)$') { return $matches[1], $matches[2] }
    return $s, ''
}

function Run([string]$exe, [string]$argumentos, [int]$minutos = 15) {
    Log "  > `"$exe`" $argumentos"
    if ($Probar) { return 0 }
    if (-not (Test-Path $exe) -and $exe -notmatch '^msiexec') { Log "  ! No existe $exe"; return -1 }
    $sp = @{ FilePath = $exe; PassThru = $true; WindowStyle = 'Hidden' }
    if ($argumentos) { $sp.ArgumentList = $argumentos }
    $pr = Start-Process @sp
    # Mientras espera, apunta cualquier ventana visible de McAfee: si sale, el modo silencioso no lo es
    $fin = (Get-Date).AddMinutes($minutos); $vistas = @{}
    while (-not $pr.WaitForExit(2000)) {
        if ((Get-Date) -gt $fin) { Log "  ! Sigue en marcha tras $minutos min (puede estar esperando una ventana)"; return -2 }
        Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and "$($_.Path)" -match '\\McAfee\\' } | ForEach-Object {
            $k = "$($_.ProcessName)|$($_.MainWindowTitle)"
            if (-not $vistas[$k]) { $vistas[$k] = 1; Log "  ! VENTANA de McAfee a la vista: $($_.ProcessName) '$($_.MainWindowTitle)'" }
        }
    }
    Log "  Codigo salida: $($pr.ExitCode)$(if (-not $vistas.Count) { ' (sin ventanas)' })"
    return $pr.ExitCode
}

# ---------- 3. Desinstalar programas Win32 ----------
# Orden: primero los complementos (WebAdvisor, etc.) y al final el producto principal (WPS / "McAfee")
$prog = $prog | Sort-Object { if ($_.DisplayName -match '^McAfee$|Total Protection|LiveSafe|WPS|McAfee\+') { 1 } else { 0 } }
foreach ($p in $prog) {
    Log "Desinstalando: $($p.DisplayName)"
    if ($p.QuietUninstallString) {
        $exe, $arg = Split-Cmd $p.QuietUninstallString
        Run $exe $arg | Out-Null
    }
    elseif ($p.UninstallString -match 'msiexec' -and $p.PSChildName -match '^\{[0-9A-F-]+\}$') {
        Run 'msiexec.exe' "/x $($p.PSChildName) /qn /norestart REBOOT=ReallySuppress" | Out-Null
    }
    elseif ($p.UninstallString -match 'mc-update\.exe') {
        # McAfee WPS (el que trae LG). "/uninstall" abre su ventana (LG 05-11-2026, "--quiet" no vale). mc-update.exe
        # 1.40 trae en su tabla de ordenes "silentuninstall" (junto a uninstall, repair, cleanup...): se usa esa.
        $exe, $arg = Split-Cmd $p.UninstallString
        Run $exe '/silentuninstall' | Out-Null
    }
    elseif ($p.UninstallString -match 'WebAdvisor') {
        $exe, $arg = Split-Cmd $p.UninstallString
        Run $exe "$arg /s".Trim() | Out-Null
    }
    elseif ($p.UninstallString) {
        $exe, $arg = Split-Cmd $p.UninstallString
        Run $exe "$arg /S /silent /quiet /norestart".Trim() | Out-Null
    }
    else { Log '  ! Sin cadena de desinstalacion' }
}

# ---------- 4. Apps de la Store ----------
foreach ($a in $appx) {
    Log "Quitando app: $($a.PackageFullName)"
    if (-not $Probar) { try { Remove-AppxPackage -Package $a.PackageFullName -AllUsers -ErrorAction Stop } catch { Log "  ! $($_.Exception.Message)" } }
}
foreach ($a in $prov) {
    Log "Quitando provisionado: $($a.PackageName)"
    if (-not $Probar) { try { Remove-AppxProvisionedPackage -Online -PackageName $a.PackageName -ErrorAction Stop | Out-Null } catch { Log "  ! $($_.Exception.Message)" } }
}

# ---------- 5. Comprobar ----------
if ($Probar) { Log 'Modo -Probar: no se ha desinstalado nada.'; exit 0 }
Start-Sleep -Seconds 5
$resto  = @(Get-McAfee)
$restoA = @(Get-McAfeeAppx)
$svc    = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'McAfee' -or $_.Name -match '^mc-|^mfe|^McAfee' })
foreach ($r in $resto)  { Log "SIGUE instalado: $($r.DisplayName) $($r.DisplayVersion)" }
foreach ($r in $restoA) { Log "SIGUE la app: $($r.PackageFullName)" }
foreach ($s in $svc)    { Log "Servicio McAfee aun presente: $($s.Name) ($($s.Status)) - puede irse tras reiniciar" }
$def = Get-MpComputerStatus -ErrorAction SilentlyContinue
if ($def) { Log "Defender: AMServiceEnabled=$($def.AMServiceEnabled) RealTime=$($def.RealTimeProtectionEnabled)  (si sale False, se activa tras reiniciar)" }

if ($resto -or $restoA) { Log "RESULTADO: queda McAfee. Pasa este log: $log"; exit 1 }
Log 'RESULTADO: McAfee desinstalado. Hace falta reiniciar para terminar.'
exit 0
