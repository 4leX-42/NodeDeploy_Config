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
      * Outlook clasico en t=0. Desde v5.7 primero ODT (producto OutlookRetail, Version=MatchInstalled: solo
        Outlook, ~3 min) y de plan B el instalador oficial de Microsoft (OutlookClassic.exe, que actualiza todo
        Office: 13-16 min). -OutlookMethod bootstrap lo invierte.
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

    v5.0.2 (prueba real 25/09, TESTEOINTUNHOME):
      * Cortex ya no queda 'blocked' por error cuando es la ultima app y Windows Installer esta
        ocupado en ese instante (AfterAll contaba una app pendiente "fantasma").
      * Informe sin datos de pasadas anteriores: las apps que ya estaban salen "ok (ya estaba)".
      * Work Desktop espera (max. 2 min) a que Office este registrado (ProgID Word.Application); si
        falla, el informe incluye el ResultCode de setup.log y el motivo del log de iManage.
      * MitelConnect cierra antes las apps de Office abiertas (con Outlook abierto preguntaba Si/No).

    v5.1.0: cierre del equipo (Finalize.ps1). Al arrancar pregunta dominio (o "no"), usuario del
    dominio y contrasena del Administrador local; al final, solo si todo queda OK: Administrador
    activado -> 'usuario' fuera de Administradores -> union al dominio (lo ultimo).
    -Domain <nombre|no> responde la primera pregunta; -NoFinalize omite todo el cierre.

    v5.2.0: PDF24 Creator, Everything y dnGrep (MSI) + NanaZip (MSIX con DISM, para todos los
    usuarios). Nombres de instalador con comodin: para actualizar basta con sustituir el fichero.

    v5.3.0: Optimize.ps1. Limpieza en segundo plano desde t=0 (apps de Store sobrantes, publicidad,
    Bing, widgets, chat; tambien para usuarios nuevos). Al final: PDFelement, PDF24, Everything, b4notify
    y Edge sin arrancar con Windows; AnyDesk obligatorio (servicio automatico + sin Desinstalar);
    TRIM, software del fabricante a revisar y busqueda de Windows Update. -NoOptimize lo omite.
    Cierre del equipo: no vuelve a preguntar lo ya hecho (Administrador activado, equipo en dominio).

    v5.4.0: Adobe Acrobat Reader (paquete empresarial, sin quitar los PDF a PDFelement). La limpieza
    deja Spotify, el Outlook nuevo y Teams personal.
    v5.4.1: la cuenta estandar que sale de Administradores se busca como usuario / Usuario / user / User.

    v5.5.0: actualizaciones de Lenovo (Lenovo.ps1, modulo oficial Lenovo.Client.Update) en segundo plano
    desde t=0: controladores mientras se instalan las apps; red y firmware/BIOS al terminar (con cargador
    y BitLocker en pausa; se graban al reiniciar). -NoLenovoUpdates / -NoBIOS. Adobe Reader desde el punto
    de instalacion administrativa (AIP, parche ya aplicado). Reinicio automatico en 15 s solo si todo
    queda verificado: apps, Administrador local, cuenta estandar fuera de Administradores y dominio unido.
    PDF24 solo en local (Policy del catalogo) y en el escritorio solo PDF24 Toolbox. Barra de tareas: Outlook y
    Teams anclados, sin Microsoft Store. Ya no se lanza la busqueda de Windows Update (el portatil la hace al iniciar).
    v5.5.1: AnyDesk entero y con ID (repara una instalacion a medias; el ID sale en el informe). Hora del equipo al
    arrancar: zona de Espana y reloj en hora con la cabecera Date de un servidor web (-TimeZone <id|no>).
    v5.5.2: reinicio automatico tambien sin dominio: si todo queda verificado y algo pide reiniciar (dominio,
    firmware/BIOS de Lenovo, instaladores o Windows), siempre despues del paso del dominio (unido o "no").
    Si Lenovo pide apagar (algun firmware), se apaga.
    v5.5.3: dominio con menu numerado (Dominios.txt junto a los scripts, fuera de git): 1..N sedes, N+1 = otro a
    mano, 0 = sin dominio. -Domain admite el numero de la lista.
    v5.6.0: Windows Update (WindowsUpdate.ps1, agente de Windows Update) en segundo plano desde t=0: software
    (acumulativa, seguridad, .NET...) en paralelo a las apps; controladores al terminar apps y Lenovo. Nunca cambio
    de version de Windows. El reinicio entra en el automatico del final. -NoWindowsUpdate lo omite.
    v5.7.0: fallos rapidos (tiempos limite reales por app; colgado = no se reintenta, se apunta en que se quedo
    y se sigue; error rapido = 1 reintento). Reinicio cuando algo lo pide aunque falle una app (nunca antes del
    dominio pedido); vigilante (RebootMonitor.ps1) si las actualizaciones siguen al terminar: reinicia por ellas
    o por lo que ya lo pedia (dominio...) y antes borra la carpeta del escritorio si toca. -NoAutoReboot.
    Windows Update: tambien controladores opcionales y la version nueva si es paquete de habilitacion (26H2).
    Informe corto (tiempos marcados > 1 min). Logs en zip a la carpeta de red (Ajustes.local.txt; NodeDeploy_Success /
    NodeDeploy_Errors) o al lado de la carpeta. La carpeta pegada en un Escritorio se borra sola si todo quedo listo
    (Cleanup.ps1; -KeepFolder la conserva). Solo se abren lusrmgr / sysdm si hay algo que revisar.
    v5.7.1: informe: Outlook solo con aviso si pasa de 5 min (la excepcion; las demas, de 1 min); "apps de Store
    quitadas" cuenta apps, no paquetes (cada una salia dos veces: instalada + aprovisionada).
    v5.7.2: cortes por app ~2x lo normal en portatiles reales (min. 90 s; Adobe 8 min; Outlook, que tiene que
    quedar si o si: 15 min ODT / 25 min plan B). Un MSI cortado que deja Windows Installer ocupado: 30 s de
    gracia y se cortan los msiexec (antes las MSI siguientes esperaban 10 + 5 min cada una). Windows Installer
    ocupado por otro programa: max. 5 min + 3 min de 1618 por app.
    v5.7.3: Windows Update solo controladores y firmware (BIOS): sincroniza desde t=0 y al terminar apps y Lenovo
    los busca, descarga e instala uno a uno, ensenando que hace (wu_progreso.txt); max. 20 min. La acumulativa,
    .NET, Defender... los instala Windows por su cuenta (eran ~30 min de espera sin ver nada).
    NanaZip (DISM) espera a que Windows Update sincronice: mientras busca, DISM se quedaba colgado.
    Menu de dominios: se reserva el sitio antes de dibujar (con la pantalla llena salian lineas repetidas).

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
    [int]$MaxRetries = 1,
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
    [string]$OutlookMethod = 'odt',
    # Cierre del equipo (Finalize.ps1): se pregunta al arrancar y se aplica al final si todo queda OK.
    [string]$Domain,                     # nombre del dominio o 'no' (si se omite, se pregunta)
    [string[]]$StandardUser = @('usuario', 'user'),   # cuenta(s) que salen de Administradores (da igual mayusculas)
    [switch]$NoFinalize,                 # sin preguntas ni cierre (laboratorio / reintentos)
    [switch]$NoOptimize,                 # sin optimizacion de Windows (Optimize.ps1)
    [switch]$NoLenovoUpdates,            # sin actualizaciones de Lenovo (Lenovo.ps1)
    [switch]$NoBIOS,                     # actualizaciones de Lenovo sin firmware/BIOS
    [string]$TimeZone = 'Romance Standard Time',  # zona horaria si la del equipo no es de Espana; 'no' = no tocar la hora
    [switch]$NoWindowsUpdate,            # sin actualizaciones de Windows Update (WindowsUpdate.ps1)
    [switch]$NoAutoReboot,               # sin reinicio automatico ni vigilante (laboratorio / pruebas)
    [switch]$KeepFolder                  # no borrar la carpeta del escritorio al terminar
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

$Script:Version       = '5.7.3'
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
# Marcas para Deploy.bat (reinicio, borrar la carpeta, herramientas a abrir): solo valen las de ESTA pasada.
$Script:AutoRebootFlag = Join-Path $Script:StatePath 'reinicio_automatico.flag'
Remove-Item -LiteralPath $Script:AutoRebootFlag, (Join-Path $Script:StatePath 'borrar_carpeta.flag'), (Join-Path $Script:StatePath 'herramientas.txt') -Force -ErrorAction SilentlyContinue
# La del vigilante (borrado diferido hasta que acaben las actualizaciones) tampoco vale de una pasada anterior
$Script:MonitorDir = Join-Path $env:ProgramData 'NodeDeploy'; $Script:MonitorStarted = $false
Remove-Item -LiteralPath (Join-Path $Script:MonitorDir 'borrar_carpeta.flag') -Force -ErrorAction SilentlyContinue
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

function Set-ClockAndTimeZone {
    # Zona horaria de Espana y reloj en hora antes de descargar nada: con la hora mal fallan las conexiones seguras
    # (descargas, AnyDesk sin ID) y la union al dominio (Kerberos). Windows no corrige solo un desfase grande
    # (MaxPhaseCorrection) y muchas redes cortan NTP: la hora buena sale de la cabecera Date de un servidor web por
    # HTTP (no depende del reloj). Zona: si no es de Espana (Madrid o Canarias) se pone -TimeZone; con -Force, siempre.
    param([string]$TimeZone = 'Romance Standard Time', [switch]$Force)
    $out = @()
    try {
        $tz = Get-TimeZone
        if (($Force -or $tz.Id -notin 'Romance Standard Time', 'GMT Standard Time') -and $tz.Id -ne $TimeZone) {
            Set-TimeZone -Id $TimeZone -ErrorAction Stop
            [TimeZoneInfo]::ClearCachedData()
            $out += "zona $TimeZone (antes $($tz.Id))"
        } else { $out += "zona $($tz.Id)" }
    } catch { $out += "zona: ERROR $($_.Exception.Message)" }
    $web = $null; $src = $null
    foreach ($u in 'http://www.msftconnecttest.com/connecttest.txt', 'http://www.google.com/generate_204') {
        try {
            $r = Invoke-WebRequest -Uri $u -Method Head -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
            $d = "$($r.Headers['Date'])"
            if ($d) { $web = [DateTimeOffset]::Parse($d, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime; $src = ([uri]$u).Host; break }
        } catch {}
    }
    if ($web) {
        $off = [int]($web - [DateTime]::UtcNow).TotalSeconds
        if ([math]::Abs($off) -gt 120) {
            $s = [TimeSpan]::FromSeconds([math]::Abs($off))
            $txt = if ($s.TotalDays -ge 1) { '{0} d {1} h' -f [int][math]::Floor($s.TotalDays), $s.Hours } elseif ($s.TotalHours -ge 1) { '{0} h {1} min' -f [int][math]::Floor($s.TotalHours), $s.Minutes } else { '{0} min' -f [int][math]::Ceiling($s.TotalMinutes) }
            try {
                Set-Date -Date ([TimeZoneInfo]::ConvertTimeFromUtc($web, [TimeZoneInfo]::Local)) -ErrorAction Stop | Out-Null
                $out += "reloj corregido: iba $(if ($off -gt 0) { 'atrasado' } else { 'adelantado' }) $txt (hora de $src)"
            } catch { $out += "reloj: ERROR $($_.Exception.Message)" }
        } else { $out += "reloj en hora ($src)" }
    } else { $out += 'reloj: sin conexion para comprobarlo' }
    # Sincronizacion automatica de Windows (en el dominio pasa a sincronizar con el controlador)
    try {
        Set-Service -Name W32Time -StartupType Automatic -ErrorAction Stop
        if ((Get-Service -Name W32Time).Status -ne 'Running') { Start-Service -Name W32Time -ErrorAction Stop }
        & w32tm.exe /resync /nowait 2>&1 | Out-Null
    } catch { $out += "W32Time: $($_.Exception.Message)" }
    return ($out -join '; ')
}

function Get-LocalSetting {
    # Ajustes del despacho en Ajustes.local.txt junto a los scripts ("Clave = valor"; fuera de git: el repo es publico).
    param([string]$Key)
    $f = Join-Path $Script:ScriptDir 'Ajustes.local.txt'
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    foreach ($l in @(Get-Content -LiteralPath $f -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ($l -notmatch '^\s*#' -and $l -match ('^\s*' + [regex]::Escape($Key) + '\s*=\s*(.+?)\s*$')) { return $matches[1] }
    }
    return $null
}

function Test-TcpPort {
    # Comprobacion rapida (3 s) antes de tocar una carpeta de red: si el servidor no responde, no se espera al SMB.
    param([string]$HostName, [int]$Port = 445, [int]$TimeoutMs = 3000)
    $c = New-Object Net.Sockets.TcpClient
    try { return [bool]($c.ConnectAsync($HostName, $Port).Wait($TimeoutMs) -and $c.Connected) } catch { return $false } finally { $c.Dispose() }
}

function Save-RunLogs {
    # Zip con los logs de esta ejecucion (informe, Deploy_*.log, logs de instaladores, resultados de Lenovo y Windows
    # Update, estado y datos del equipo) a la carpeta de red LogShare (Ajustes.local.txt), en NodeDeploy_Success o
    # NodeDeploy_Errors, con las credenciales del dominio si se dieron. Sin red o si falla: en LOGS_preparation, al
    # lado de la carpeta de NodeDeploy. No es critico: nunca para nada ni cuenta como fallo.
    param([bool]$HasErrors, $Credential, [string]$ReportFile, [string]$Summary)
    $sub  = if ($HasErrors) { 'NodeDeploy_Errors' } else { 'NodeDeploy_Success' }
    $note = $null
    try {
        $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
        $cs   = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        $os   = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $name = '{0}_{1}_{2}' -f (Get-Date -Format 'yyyy-MM-dd_HHmm'), $env:COMPUTERNAME, ("$($bios.SerialNumber)" -replace '[^\w-]', '')
        $tmp  = Join-Path $env:TEMP "NodeDeploy_$name"
        New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'logs') | Out-Null
        if ($ReportFile -and (Test-Path -LiteralPath $ReportFile)) { Copy-Item -LiteralPath $ReportFile -Destination $tmp -Force }
        $since = $Script:StartTime.AddMinutes(-2)
        Get-ChildItem -LiteralPath $Script:LogDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $since } | ForEach-Object {
            try { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $tmp 'logs') -Force -ErrorAction Stop } catch {}
        }
        $st = Join-Path $Script:StatePath 'nodedeploy_state.json'
        if (Test-Path -LiteralPath $st) { Copy-Item -LiteralPath $st -Destination $tmp -Force }
        @("Equipo   : $env:COMPUTERNAME | $($cs.Manufacturer) $($cs.SystemFamily) $($cs.Model) | n/s $($bios.SerialNumber) | BIOS $($bios.SMBIOSBIOSVersion)",
          "Windows  : $($os.Caption) $($os.Version) build $([Environment]::OSVersion.Version.Build).$((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).UBR)",
          "NodeDeploy $($Script:Version) | fase $Phase | inicio $($Script:StartTime.ToString('yyyy-MM-dd HH:mm')) | $(Format-Duration (Get-Elapsed))",
          "Resultado: $Summary") | Set-Content -LiteralPath (Join-Path $tmp 'equipo.txt') -Encoding UTF8
        $zip = Join-Path $env:TEMP "$name.zip"
        Compress-Archive -Path (Join-Path $tmp '*') -DestinationPath $zip -Force -ErrorAction Stop
        $dest  = $null
        $share = Get-LocalSetting 'LogShare'
        if ($share -and $share -match '^\\\\([^\\]+)\\') {
            if (Test-TcpPort -HostName $matches[1]) {
                try {
                    $base = $share
                    if ($Credential) { New-PSDrive -Name NDLOGS -PSProvider FileSystem -Root $share -Credential $Credential -ErrorAction Stop | Out-Null; $base = 'NDLOGS:\' }
                    $target = Join-Path $base $sub
                    if (-not (Test-Path -LiteralPath $target)) { New-Item -ItemType Directory -Force -Path $target -ErrorAction Stop | Out-Null }
                    Copy-Item -LiteralPath $zip -Destination $target -Force -ErrorAction Stop
                    $dest = Join-Path (Join-Path $share $sub) "$name.zip"
                } catch { $note = "carpeta de red: $($_.Exception.Message)" }
                finally { Remove-PSDrive -Name NDLOGS -Force -ErrorAction SilentlyContinue }
            } else { $note = "sin acceso a $($matches[1])" }
        }
        if (-not $dest) {
            $root  = Split-Path -Parent (Split-Path -Parent $Script:ScriptDir)
            $local = Join-Path (Split-Path -Parent $root) "LOGS_preparation\$sub"
            New-Item -ItemType Directory -Force -Path $local | Out-Null
            Copy-Item -LiteralPath $zip -Destination $local -Force
            $dest = Join-Path $local "$name.zip"
        }
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        return "$dest$(if ($note) { " ($note)" })"
    } catch { return "no se pudieron guardar: $($_.Exception.Message)" }
}

function Test-CleanupAllowed {
    # La carpeta que se pega en el escritorio (scripts + ~6 GB de instaladores) se borra sola al final, pero solo si
    # TODO quedo listo y solo si de verdad esta en un Escritorio: nunca el M.2 ni la copia maestra del PC.
    param([string]$Root, [bool]$AllDone)
    if (-not $AllDone -or -not $Root -or -not (Test-Path -LiteralPath (Join-Path $Root 'NodeDeploy_Run\PRO\Deploy.ps1'))) { return $false }
    $desks = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory')) +
             @(Get-ChildItem -Path 'C:\Users\*\Desktop', 'C:\Users\*\OneDrive*\Desktop' -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    return [bool](@($desks | Where-Object { $_ -and $Root.StartsWith($_.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) }).Count)
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
        validated = $false; timed_out = $false; preinstalled = $false
    }
}

function Get-OrNewRecord {
    param($State, $App)
    $r = Get-AppRecord $State $App.Name
    if (-not $r) { return (New-AppRecord $App) }
    foreach ($p in 'lane','history','start_offset_sec','timed_out','preinstalled') {
        if (-not ($r.PSObject.Properties.Name -contains $p)) { $r | Add-Member -NotePropertyName $p -NotePropertyValue $null -Force }
    }
    if (-not $r.history) { $r.history = @() }
    return $r
}

function Reset-RunFields {
    # Campos de UNA ejecucion. Sin esto, con un state heredado (segunda pasada u otro equipo) el
    # informe mezclaba horas, duraciones, argumentos y logs de ejecuciones anteriores.
    param($Rec)
    $Rec.attempts = 0; $Rec.exit_code = $null; $Rec.elapsed_sec = 0; $Rec.start_offset_sec = $null
    $Rec.started = $null; $Rec.finished = $null; $Rec.args_used = ''; $Rec.install_log = ''
    $Rec.errors = @(); $Rec.history = @(); $Rec.timed_out = $false; $Rec.preinstalled = $false
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
        # Admite comodin (p. ej. AnyDesk*: el servicio del cliente propio se llama AnyDesk-<id>_msi)
        foreach ($s in @(Get-Service -Name $svc -ErrorAction SilentlyContinue)) { $evidence += "service:$($s.Name)($($s.Status))" }
    }
    foreach ($fp in @($FilePaths)) {
        $f = if ($fp) { Get-Item -Path $fp -ErrorAction SilentlyContinue | Select-Object -First 1 }
        if ($f) { $evidence += "file:$($f.Name)"; break }
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
    if ($App.AppxName) {
        # MSIX: aprovisionado para todos los usuarios (o ya instalado en algun perfil).
        $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $App.AppxName })
        if ($prov) { return @{ Installed = $true; Evidence = @("appx-provisioned:$($App.AppxName) v$($prov[0].Version)"); Version = $prov[0].Version } }
        $usr = @(Get-AppxPackage -AllUsers -Name $App.AppxName -ErrorAction SilentlyContinue)
        if ($usr) { return @{ Installed = $true; Evidence = @("appx:$($App.AppxName) v$($usr[0].Version)"); Version = $usr[0].Version } }
        return @{ Installed = $false; Evidence = @(); Version = $null }
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
# WebView2 del sistema (Evergreen, lo mantiene Microsoft; viene con Windows 11): deteccion documentada por Microsoft.
$wv2 = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' -Name pv -ErrorAction SilentlyContinue).pv
$Script:HasWebView2 = [bool]($wv2 -and $wv2 -ne '0.0.0.0')
$pdf24Policy = [ordered]@{
    '!NoOnlineConverter'=1; '!NoOnlinePdfTools'=1; '!NoFax'=1; '!NoPDF24MailInterface'=1; '!NoUpdateCheckBtns'=1
    '!reader.enableJavaScript'=0; '!launcher.hideElements'='onlinePdfTools,onlineConverter,fax,updateCheck'; 'UpdateMode'=2
}
if ($Script:HasWebView2) { $pdf24Policy['!webview2.useEvergreen'] = 1 }

$Script:Apps = @(
    # ---------- Outlook clasico (background desde t=0) ----------
    [pscustomobject]@{
        Name=$Script:OfficeAppName; File='OfficeSetup.exe'; Type='office'; Lane='office'; Order=0; Timeout=1800
        Detect=@(); FilePaths=@()
    },

    # ---------- Carril MSI ----------
    [pscustomobject]@{
        # Cliente propio: un solo ejecutable (AnyDesk-<id>_msi.exe) + servicio AnyDesk-<id>_msi; tarda ~7 s.
        # Al terminar las apps, Test-AnyDeskHealth comprueba que quede entero y con ID (repara si no).
        Name='AnyDesk'; File='AnyDesk.msi'; Type='msi'; Lane='msi'; Order=10; Timeout=90
        Detect=@('AnyDesk'); ServiceNames=@('AnyDesk*')
        FilePaths=@("${env:ProgramFiles(x86)}\AnyDesk*\AnyDesk*.exe","$env:ProgramFiles\AnyDesk*\AnyDesk*.exe")
    },
    [pscustomobject]@{
        Name='AqNet'; File='AqNetInstalacion.msi'; Type='msi'; Lane='msi'; Order=20; Timeout=90
        Detect=@('AqNet','Aqnet','Deposito Digital')
    },
    [pscustomobject]@{
        Name='Nebula CertAgent'; File='nebula-certAgent-winx64-5.0.0.msi'; Type='msi'; Lane='msi'; Order=30; Timeout=90
        Detect=@('Nebula','CertAgent','nebulaCERTagent'); ServiceNames=@('nebulaCERTagent','nebulaCERT')
        FilePaths=@("$env:ProgramFiles\Vintegris\nebulaCERTagent\nebulaCERTagent.exe")
    },
    [pscustomobject]@{
        Name='ESET Management Agent'; File='eset_msi.msi'; Type='msi-eset'; Lane='msi'; Order=40; Timeout=120
        Detect=@('ESET Management Agent','ESET Remote Administrator Agent'); ServiceNames=@('EraAgentSvc')
        FilePaths=@("$env:ProgramFiles\ESET\RemoteAdministrator\Agent\ERAAgent.exe")
    },
    [pscustomobject]@{
        # Enterprise MSI offline (~160 MB): sin descarga en el momento, exit codes MSI fiables.
        Name='Google Chrome'; File='GoogleChromeStandaloneEnterprise64.msi'; Type='msi'; Lane='msi'; Order=50; Timeout=210
        Detect=@('Google Chrome')
        FilePaths=@("$env:ProgramFiles\Google\Chrome\Application\chrome.exe","${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe")
        Fallback=[pscustomobject]@{ File='ChromeSetup.exe'; Type='exe'; Lane='exe'; Args='/silent /install' }
    },
    [pscustomobject]@{
        # CloseOffice: con Outlook abierto el instalador pregunta Si/No (integra complemento de Outlook).
        Name='MitelConnect'; File='MitelConnect.exe'; Type='installshield'; Lane='msi'; Order=60; Timeout=300
        MsiExtra='REBOOT=ReallySuppress'; CloseOffice=$true
        Detect=@('Mitel Connect','Mitel','MiCollab')
        FilePaths=@("$env:ProgramFiles\Mitel\Connect Client\ConnectAgent.exe","${env:ProgramFiles(x86)}\Mitel\Connect Client\ConnectAgent.exe")
        Boost=@{ Paths=@("${env:ProgramFiles(x86)}\Mitel","$env:ProgramFiles\Mitel") }
    },
    [pscustomobject]@{
        Name='iManage Agent Services'; Path="$imWork\iManageAgentServices.exe"; Type='installshield'; Lane='msi'; Order=70; Timeout=90
        MsiExtra='REBOOT=ReallySuppress'
        Detect=@('iManage Agent Services','iManage Agent','iManageAgent')
    },
    [pscustomobject]@{
        # 10.13 ya NO es WiX Burn (10.10 lo era): es InstallShield InstallScript puro y /quiet
        # abria la GUI. Silencioso = "setup.exe /s" + setup.iss (el que trae el paquete, junto al exe).
        Name='iManage Drive'; Path="$imDrive\iManageDriveSetup.exe"; Type='installshield-imanage'; Lane='msi'; Order=80; Timeout=240
        Detect=@('iManage Drive'); ExcludeDetect=@('Native')
        FilePaths=@("$env:ProgramFiles\iManage\iManage Drive\iManageDrive.exe")
        Boost=@{ Processes=@('iManageDriveSetup.exe','ISBEW64.exe'); Paths=@("$env:ProgramFiles\iManage") }
    },
    [pscustomobject]@{
        Name='iManage Drive Native'; Path="$imNative\iManageDriveNative.exe"; Type='burn'; Lane='msi'; Order=90; Timeout=90
        Requires=@('iManage Drive')
        Detect=@('iManage Drive Native','iManageDriveNative')
    },
    [pscustomobject]@{
        # InstallScript puro. Prerequisitos HARD (log iManage): Agent Services + Office con Word y Outlook.
        Name='iManage Work Desktop'; Path="$imWork\iManageWorkDesktopforWindowsx64.exe"; Type='installshield-imanage'; Lane='msi'; Order=100; Timeout=120
        Requires=@('iManage Agent Services','@office'); RequiresOffice=$true
        Detect=@('iManage Work Desktop','iManage Work')
        Boost=@{ Processes=@('iManageWorkDesktopforWindowsx64.exe','ISBEW64.exe'); Paths=@("$env:ProgramFiles\iManage","${env:ProgramFiles(x86)}\iManage") }
    },
    [pscustomobject]@{
        # WiX, por equipo. LAUNCHAPPONEXIT=0: que no abra dnGrep al terminar.
        Name='dnGrep'; File='dnGREP.*.x64.msi'; Type='msi'; Lane='msi'; Order=110; Timeout=90
        MsiExtra='LAUNCHAPPONEXIT=0'
        Detect=@('dnGrep'); FilePaths=@("$env:ProgramFiles\dnGREP\dnGREP.exe")
    },
    [pscustomobject]@{
        # Propiedades documentadas por voidtools (EVERYTHING_SERVICE, START_ON_STARTUP, *_SHORTCUT...) valen 1
        # por defecto: servicio + arranque con Windows + accesos directos. 1.4.1.1031+ arranca el servicio en /qn.
        Name='Everything'; File='Everything-*.x64.msi'; Type='msi'; Lane='msi'; Order=120; Timeout=90
        Detect=@('Everything'); ServiceNames=@('Everything'); FilePaths=@("$env:ProgramFiles\Everything\Everything.exe")
    },
    [pscustomobject]@{
        # ~500 MB. AUTOUPDATE=No (el MSI deja UpdateMode=2: sin actualizaciones ni avisos a usuarios sin admin; se
        # actualiza cambiando el MSI), REGISTERREADER=No (no se registra como lector PDF), FAXPRINTER=No.
        # Policy (manual oficial v11, HKLM\SOFTWARE\PDF24; '!' = el valor del equipo manda sobre el del usuario):
        # todo en local, sin conversor online, enlaces a las herramientas web, fax ni correo de PDF24; sin JavaScript
        # en su lector; WebView2 del sistema (lo parchea Microsoft) en vez de la copia fija que trae PDF24.
        # Escritorio: el MSI pone PDF24 Toolbox y PDF24 Launcher; se quita el Launcher (anuncia redes sociales).
        Name='PDF24 Creator'; File='pdf24-creator-*-x64.msi'; Type='msi'; Lane='msi'; Order=130; Timeout=180
        MsiExtra='AUTOUPDATE=No REGISTERREADER=No FAXPRINTER=No'
        Detect=@('PDF24 Creator','PDF24'); FilePaths=@("$env:ProgramFiles\PDF24\pdf24.exe")
        Boost=@{ Paths=@("$env:ProgramFiles\PDF24") }
        Policy=[pscustomobject]@{ Key='HKLM:\SOFTWARE\PDF24'; Values=$pdf24Policy
            RemoveShortcuts=@('PDF24 Launcher.lnk')
            Text="solo local: sin conversor online, herramientas web, fax ni correo de PDF24; sin JavaScript en su lector; sin actualizaciones ni botones de actualizar; en el escritorio solo PDF24 Toolbox; $(if ($Script:HasWebView2) { 'WebView2 del sistema' } else { 'WebView2 propio (falta el del sistema)' })" }
    },
    [pscustomobject]@{
        # Imagen administrativa con el parche ya aplicado (carpeta AdobeReader_x64_*_AIP): no descomprime ni parchea
        # al instalar (lab: 86 s frente a 111 s). Si falta, paquete empresarial (setup.exe = MSI base + parche .msp).
        # En Reader aparece como "Adobe Acrobat (64-bit)". EULA_ACCEPT=YES (sin licencia al abrir), ENABLE_CHROMEEXT=0
        # (sin extension de Chrome), LEAVE_PDFOWNERSHIP=YES (no quita los PDF a PDFelement). Actualizador activo (seguridad).
        Name='Adobe Acrobat Reader'; File='AdobeReader_x64_*_AIP\AcroPro.msi'; Type='msi'; Lane='msi'; Order=140; Timeout=480
        MsiExtra='EULA_ACCEPT=YES ENABLE_CHROMEEXT=0 LEAVE_PDFOWNERSHIP=YES'
        Detect=@('Adobe Acrobat'); FilePaths=@("$env:ProgramFiles\Adobe\Acrobat DC\Acrobat\Acrobat.exe")
        Boost=@{ Paths=@(@("$env:ProgramFiles\Adobe", "${env:ProgramFiles(x86)}\Common Files\Adobe") +
                         @(Get-ChildItem -Path (Join-Path $Source 'AdobeReader_x64_*_AIP') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })) }
        Fallback=[pscustomobject]@{ File='AdobeReader_x64_*\setup.exe'; Type='exe'; Lane='msi'; Args='/sAll /rs /msi EULA_ACCEPT=YES ENABLE_CHROMEEXT=0 LEAVE_PDFOWNERSHIP=YES' }
    },
    [pscustomobject]@{
        # Siempre el ultimo: su monitor de comportamiento bloquea el runtime InstallScript de iManage.
        Name='MDR Cortex XDR'; File='MDR_Windows_Andersen_8_2_x64.msi'; Type='msi'; Lane='msi'; Order=999; Timeout=120
        AfterAll=$true; MsiExtra='REBOOT=ReallySuppress'
        Detect=@('Cortex XDR','Palo Alto','Traps'); ServiceNames=@('cyserver','CyveraService')
    },

    # ---------- Carril EXE (sin Windows Installer, en paralelo al carril MSI) ----------
    [pscustomobject]@{
        Name='Bit4id Middleware'; File='Bit4id_Middleware.exe'; Type='exe'; Lane='exe'; Order=10; Timeout=120
        Args='/S'
        Detect=@('Bit4id','Universal Middleware')
        FilePaths=@("$env:ProgramFiles\Bit4id\Universal MW\bin\bit4xpki.exe","${env:ProgramFiles(x86)}\Bit4id\Universal MW\bin\bit4xpki.exe")
        Boost=@{ Processes=@('Bit4id_Middleware.exe'); Paths=@("$env:ProgramFiles\Bit4id","${env:ProgramFiles(x86)}\Bit4id") }
    },
    [pscustomobject]@{
        # Inno Setup 571 MB. /NOPAGE es obligatorio en silencioso segun la guia de despliegue de
        # Wondershare (sin el, el instalador espera en la pagina final). /LOG deja traza propia.
        Name='PDFelement Business'; File=$pdfExe; Type='inno'; Lane='exe'; Order=20; Timeout=180
        Args='/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /NOPAGE /NOCANCEL /CLOSEAPPLICATIONS'
        Detect=@('PDFelement','Wondershare PDFelement')
        FilePaths=@("$env:ProgramFiles\Wondershare\PDFelement\PDFelement.exe","${env:ProgramFiles(x86)}\Wondershare\PDFelement\PDFelement.exe")
        KillOnTimeout=@('PDFelement','wshelper','WsAppService')
        Boost=@{ Processes=@($pdfExe, [IO.Path]::ChangeExtension($pdfExe, '.tmp')); Paths=@("$env:ProgramFiles\Wondershare","${env:ProgramFiles(x86)}\Wondershare") }
    },
    [pscustomobject]@{
        # Configura Chrome (y Firefox) al instalarse -> debe ir DESPUES de Chrome.
        Name='Autofirma'; File='Autofirma_64_v1_9_installer.exe'; Type='exe'; Lane='exe'; Order=30; Timeout=120
        Args='/S'; After=@('Google Chrome')
        Detect=@('Autofirma','AutoFirma')
        FilePaths=@("$env:ProgramFiles\Autofirma\Autofirma\Autofirma.exe","$env:ProgramFiles\AutoFirma\AutoFirma.exe")
        Boost=@{ Processes=@('Autofirma_64_v1_9_installer.exe'); Paths=@("$env:ProgramFiles\Autofirma") }
    },
    [pscustomobject]@{
        # MSIX (Windows 10 2004+): aprovisionado para todos los usuarios; cada perfil lo recibe al iniciar sesion.
        Name='NanaZip'; File='NanaZip_*.msixbundle'; Type='appx'; Lane='exe'; Order=40; Timeout=120; WaitWuSync=$true
        AppxName='40174MouriNaruto.NanaZip'
    }
)

# Duraciones de referencia (s) para -DryRun (medidas en campo, Defender off, jul-2026).
$Script:DryRunSeconds = @{
    'Outlook clasico'=240; 'AnyDesk'=3; 'AqNet'=7; 'Nebula CertAgent'=6; 'ESET Management Agent'=17
    'Google Chrome'=30; 'MitelConnect'=61; 'iManage Agent Services'=9; 'iManage Drive'=53
    'iManage Drive Native'=5; 'iManage Work Desktop'=45; 'MDR Cortex XDR'=23
    'Bit4id Middleware'=35; 'PDFelement Business'=53; 'Autofirma'=36
    'dnGrep'=20; 'Everything'=6; 'PDF24 Creator'=60; 'NanaZip'=10; 'Adobe Acrobat Reader'=90
}
#endregion

# Cierre del equipo (Administrador local, usuario estandar, dominio)
$Script:FinalizePs1 = Join-Path $Script:ScriptDir 'Finalize.ps1'
if (Test-Path $Script:FinalizePs1) { . $Script:FinalizePs1 }
# Optimizacion de Windows (apps de Store sobrantes, publicidad, arranque, barra de tareas, TRIM)
$Script:OptimizePs1 = Join-Path $Script:ScriptDir 'Optimize.ps1'
if (Test-Path $Script:OptimizePs1) { . $Script:OptimizePs1 }

# ============================================================
#region PATHS / OFFICE HELPERS
# ============================================================
function Resolve-AppPath {
    param($App)
    $rel  = if ($App.Path) { $App.Path } else { $App.File }
    $full = Join-Path $Source $rel
    if ($rel -match '[\*\?]') {
        # Nombre con comodin (p. ej. pdf24-creator-*-x64.msi): para actualizar basta con sustituir el
        # instalador; si hubiera varios, se usa el mas reciente.
        $hit = Get-ChildItem -Path $full -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
        if ($hit) { return $hit.FullName }
    }
    return $full
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

function Get-AutoRebootDecision {
    # Reinicio / apagado automatico del final (sin efectos: solo decide). Action = reiniciar | apagar | $null.
    # Need = lo que pide reiniciar (dominio unido, Lenovo, Windows Update, instaladores, Windows).
    # Why = lo que lo impide, solo dos cosas: actualizaciones aun instalandose (lo recoge el vigilante) o un dominio
    #       pedido que aun no esta unido (el dominio va siempre antes del reinicio).
    # Warn = avisos que NO frenan el reinicio (app con fallo, cierre pospuesto): se apuntan en el informe.
    param($Records, $FinalizeStatus, [bool]$DomainWanted, $LenovoResult, $WuResult, [bool]$WindowsPending, [bool]$UpdatesRunning)
    $fs = $FinalizeStatus
    $lnPend = @(if ($LenovoResult) { $LenovoResult.pending })
    $need = @()
    if ($fs -and $fs.DomainJoined)          { $need += 'union al dominio' }
    if ($lnPend -match 'REBOOT|SHUTDOWN')   { $need += 'actualizaciones de Lenovo' }
    if ($WuResult -and $WuResult.reboot)    { $need += 'Windows Update' }
    if (@($Records | Where-Object { $_.status -eq 'ok_reboot' }).Count) { $need += 'instaladores' }
    if ($WindowsPending -and -not ($WuResult -and $WuResult.reboot)) { $need += 'Windows lo pide' }
    $why = @()
    if ($UpdatesRunning) { $why += 'actualizaciones aun instalandose' }
    if ($DomainWanted -and -not ($fs -and $fs.DomainDone)) { $why += 'falta unir al dominio (va antes del reinicio)' }
    $warn = @()
    $bad = @($Records | Where-Object { $_.status -like 'fail*' -or $_.status -eq 'blocked' } | ForEach-Object { $_.name })
    if ($bad) { $warn += "apps con fallo: $($bad -join ', ')" }
    if ($LenovoResult -and @($LenovoResult.failed).Count -and -not $UpdatesRunning) { $warn += 'Lenovo con fallos' }
    if ($WuResult -and @($WuResult.failed).Count -and -not $UpdatesRunning)         { $warn += 'Windows Update con fallos' }
    $act = if ($why.Count -or -not $need.Count) { $null } elseif ($lnPend -contains 'SHUTDOWN') { 'apagar' } else { 'reiniciar' }
    return [pscustomobject]@{ Action = $act; Need = $need; Why = $why; Warn = $warn }
}

function Set-AppPolicies {
    # Ajustes de registro del catalogo (Policy) en las apps que han quedado OK, instaladas ahora o ya presentes.
    # Idempotente: en cada pasada se vuelven a escribir.
    param($State)
    $res = [ordered]@{}
    foreach ($a in @($Script:Apps | Where-Object { $_.Policy })) {
        $r = Get-AppRecord $State $a.Name
        if (-not $r -or $r.status -notin $Script:OkStatus) { continue }
        try {
            if (-not (Test-Path $a.Policy.Key)) { New-Item -Path $a.Policy.Key -Force | Out-Null }
            foreach ($n in $a.Policy.Values.Keys) {
                $v = $a.Policy.Values[$n]
                New-ItemProperty -Path $a.Policy.Key -Name $n -Value $v -PropertyType $(if ($v -is [string]) { 'String' } else { 'DWord' }) -Force -ErrorAction Stop | Out-Null
            }
            # Accesos directos del escritorio (el comun y el del usuario que ejecuta el script)
            foreach ($lnk in @($a.Policy.RemoveShortcuts)) {
                if (-not $lnk) { continue }
                foreach ($desk in @([Environment]::GetFolderPath('CommonDesktopDirectory'), [Environment]::GetFolderPath('Desktop'))) {
                    $f = Join-Path $desk $lnk
                    if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction Stop; Write-Log "Quitado del escritorio: $f" 'INFO' }
                }
            }
            $res[$a.Name] = $a.Policy.Text
            Write-Log "Configuracion de $($a.Name): $($a.Policy.Text)" 'OK'
        } catch {
            $res[$a.Name] = "ERROR: $($_.Exception.Message)"
            Write-Log "Configuracion de $($a.Name): $($_.Exception.Message)" 'ERROR'
        }
    }
    return $res
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

function Get-ProcessTreeText {
    # Procesos del instalador (raiz + hijos) con el titulo de su ventana: dice en que se quedo colgado.
    param([int]$RootId)
    $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Select-Object ProcessId, ParentProcessId)
    $ids = New-Object System.Collections.Generic.List[int]; $ids.Add($RootId)
    for ($i = 0; $i -lt $ids.Count; $i++) {
        foreach ($c in @($all | Where-Object { $_.ParentProcessId -eq $ids[$i] })) { if (-not $ids.Contains([int]$c.ProcessId)) { $ids.Add([int]$c.ProcessId) } }
    }
    $out = foreach ($id in $ids) {
        $p = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($p) { "$($p.ProcessName)$(if ($p.MainWindowTitle) { " [ventana: $($p.MainWindowTitle)]" })" }
    }
    return (@($out) -join ', ')
}

function Get-LogTail {
    # Lineas utiles del log del instalador para el informe: en MSI, lo anterior al primer "Return value 3"; si no, el final.
    param([string]$Path, [int]$Lines = 6)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return @() }
    try {
        $all = [string[]]@(Get-Content -LiteralPath $Path -ErrorAction Stop)
        $i = [array]::FindIndex($all, [Predicate[string]]{ param($l) $l -match 'Return value 3' })
        $sel = if ($i -ge 0) { $all[[Math]::Max(0, $i - $Lines)..$i] } else { $all | Select-Object -Last $Lines }
        return @($sel | ForEach-Object { $s = "$_".Trim(); if ($s.Length -gt 200) { $s.Substring(0, 200) + '...' } else { $s } } | Where-Object { $_ })
    } catch { return @() }
}

function Stop-JobTree {
    param($Job)
    if ($DryRun -or -not $Job.Process) { return }
    $Job.HangInfo = Get-ProcessTreeText -RootId $Job.Process.Id
    Write-Log "TIMEOUT $($Job.App.Name) ($($Job.Timeout)s) - colgado en: $($Job.HangInfo). Se corta y se sigue con las demas" 'WARN'
    Stop-ProcessTree -ProcessId $Job.Process.Id
    Stop-ProcessSafe -Names $Job.App.KillOnTimeout -WaitSec 1
    # Un MSI cortado sigue en el servicio de Windows Installer (msiexec del sistema, fuera del arbol del proceso
    # cortado): o retiene el mutex o deja el servicio atascado, y las MSI siguientes se colgarian una tras otra
    # (lab: dnGrep congelado -> Everything colgado tambien). 30 s para que lo deshaga y se reinicia Windows
    # Installer (sus procesos; el servicio vuelve a arrancar solo con la siguiente instalacion).
    if ($Job.App.Lane -eq 'msi') {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ((Test-MsiBusy) -and $sw.Elapsed.TotalSeconds -lt 30) { Start-Sleep -Seconds 2 }
        $mp = @(Get-Process -Name 'msiexec' -ErrorAction SilentlyContinue)
        if ($mp.Count) {
            Write-Log "Tras cortar $($Job.App.Name) se reinicia Windows Installer ($($mp.Count) msiexec$(if (Test-MsiBusy) { ', seguia ocupado' }))" 'WARN'
            # taskkill: el msiexec del servicio corre como SYSTEM (taskkill activa el privilegio de depuracion)
            & "$env:SystemRoot\System32\taskkill.exe" /F /T /IM msiexec.exe 2>&1 | Out-Null
            # Servicio nuevo ya: si no, la siguiente instalacion espera ~2 min a que Windows descarte el muerto (lab)
            for ($i = 0; $i -lt 10 -and "$((Get-Service -Name msiserver -ErrorAction SilentlyContinue).Status)" -ne 'Stopped'; $i++) { Start-Sleep -Seconds 1 }
            try { Start-Service -Name msiserver -ErrorAction Stop } catch {}
            $Job.HangInfo = "$($Job.HangInfo); Windows Installer reiniciado"
        }
    }
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
        'appx' {
            # MSIX para todos los usuarios con DISM (codigos de salida fiables; no usa Windows Installer).
            # Licencia: el .xml con el mismo nombre que el paquete; si no hay, /SkipLicense.
            # /Region:all: sin el, Windows solo aprovisiona las apps ancladas en el menu Inicio.
            $cmd.LogFile  = Join-Path $Script:LogDir "dism_$name.log"
            $lic = [IO.Path]::ChangeExtension($file, '.xml')
            $licArg = if (Test-Path $lic) { "/LicensePath:`"$lic`"" } else { '/SkipLicense' }
            $cmd.FilePath  = Join-Path $env:SystemRoot 'System32\dism.exe'
            $cmd.Arguments = "/Online /Add-ProvisionedAppxPackage /PackagePath:`"$file`" $licArg /Region:all /NoRestart /Quiet /LogPath:`"$($cmd.LogFile)`""
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
        $step.Done = $true; $step.Ok = $true; $rec.status = 'ok'; $rec.validated = $true; $rec.preinstalled = $true
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
        odt (defecto desde v5.7): ODT con OutlookRetail + Version=MatchInstalled: solo anade Outlook a la version de
                  Office que ya trae el portatil (lab: 3 min). Maximo 10 min; si falla o se pasa, plan B.
        bootstrap: instalador oficial de Microsoft "classic Outlook" (OutlookClassic.exe). Funciona siempre, pero
                  actualiza TODO el Office de fabrica a la ultima version (3-4 GB del CDN: 13-16 min en campo).
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
    # Outlook tiene que quedar si o si: margen amplio (depende de la red). ODT solo baja lo de Outlook (3 min en el
    # lab): 15 min y, si no, plan B (bootstrap, que baja todo Office: 8-14 min en campo): 25 min
    $Step.Job.Timeout = if ($Step.Mode -eq 'bootstrap') { 1500 } else { 900 }
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

function Test-OfficeReadyForImanage {
    <#
        Work Desktop aborta con 0x80042000 si no "ve" Office: ademas de los .exe tiene que estar
        registrado el ProgID Word.Application (lo que comprueba iManage). OfficeC2RClient NO sirve de
        indicador: sigue vivo varios minutos despues de que Outlook este listo (visto en el lab).
    #>
    $prog = Test-Path 'Registry::HKEY_CLASSES_ROOT\Word.Application\CurVer'
    return @{ Ready = $prog; Reasons = @(if (-not $prog) { 'word_progid_missing' }) }
}

function Get-ReadyCheck {
    <#
        Devuelve 'ready' | 'wait' | 'blocked:<motivo>' para una app pendiente.
    #>
    param($Entry, $State, $Office, $PendingNames)
    # $null | Where-Object ... emite un $null: sin este filtro AfterAll contaba una app "fantasma"
    # pendiente y Cortex acababa marcado 'dependencias_no_resueltas'.
    $PendingNames = @(@($PendingNames) | Where-Object { $_ })
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
            if ($app.RequiresOffice -and -not $DryRun) {
                $rdy = Test-OfficeReadyForImanage
                if (-not $rdy.Ready) {
                    if (-not $Entry.OfficeWaitSince) {
                        $Entry.OfficeWaitSince = Get-Date
                        Write-Log "[MSI] $($app.Name) espera a que Office termine de registrarse ($($rdy.Reasons -join ', '))" 'INFO'
                    }
                    # Hasta 2 min: si el ProgID no aparece, iManage fallara igual y el informe dira el motivo.
                    $limit = 2
                    if (((Get-Date) - $Entry.OfficeWaitSince).TotalMinutes -lt $limit) {
                        $Entry.NotBefore = (Get-Date).AddSeconds(10)   # espera con plazo: no es un bloqueo
                        return 'wait'
                    }
                    if (-not $Entry.OfficeWaitWarned) {
                        $Entry.OfficeWaitWarned = $true
                        Write-Log "[MSI] $limit min esperando a Office ($($rdy.Reasons -join ', ')); se lanza $($app.Name) igualmente" 'WARN'
                    }
                }
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
    # DISM (NanaZip) necesita el servicio de componentes de Windows, que Windows Update ocupa mientras sincroniza
    # (lab: DISM colgado hasta el corte, dos veces). Espera a que termine de sincronizar, max. 15 min, avisando.
    if ($app.WaitWuSync -and -not $DryRun -and $Script:WuProc -and -not $Script:WuProc.HasExited) {
        $wp = try { "$(Get-Content -LiteralPath $Script:WuProgress -Raw -ErrorAction Stop)".Trim() } catch { '' }
        if (-not $wp -or $wp -like 'sincronizando*') {
            if (-not $Entry.WuWaitSince) {
                $Entry.WuWaitSince = Get-Date; $Entry.WuWaitLog = Get-Date
                Write-Log "[EXE] $($app.Name) espera a que Windows Update termine de sincronizar (si no, DISM se queda colgado)" 'INFO'
            }
            $mins = ((Get-Date) - $Entry.WuWaitSince).TotalMinutes
            if ($mins -lt 15) {
                if (((Get-Date) - $Entry.WuWaitLog).TotalSeconds -ge 60) { $Entry.WuWaitLog = Get-Date; Write-Log "[EXE] $($app.Name) sigue esperando a Windows Update ($([int]$mins) min)" 'INFO' }
                $Entry.NotBefore = (Get-Date).AddSeconds(10)
                return 'wait'
            }
        }
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

    if (($app.RequiresOffice -or $app.CloseOffice) -and -not $DryRun) {
        # Cierra las apps de Office abiertas: libera locks COM y evita que el instalador pregunte si
        # cerrar Outlook. NO se tocan OfficeClickToRun/OfficeC2RClient (v4 los mataba y podia romper
        # un Outlook que aun estaba terminando de integrarse).
        $open = @(Get-Process -Name 'OUTLOOK','WINWORD','EXCEL','POWERPNT','ONENOTE','MSACCESS' -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName } | Select-Object -Unique)
        if ($open.Count) { Write-Log "Cerrando Office abierto antes de $($app.Name): $($open -join ', ')" 'INFO' }
        Stop-ProcessSafe -Names @('OUTLOOK','WINWORD','EXCEL','POWERPNT','ONENOTE','MSACCESS') -WaitSec 2
    }
    if ($app.RequiresOffice -and -not $DryRun) {
        $im = @('iManageStayExec','iManageDrive','iManageWorkDesktop','iManageEFS','iManageAgentSvc')
        if (Get-Process -Name $im -ErrorAction SilentlyContinue) { Stop-ProcessSafe -Names $im -WaitSec 2 }
    }

    $cmd = New-InstallCommand -App $app -State $State
    # Solo laboratorio: NODEDEPLOY_TEST_HANG="App:segundos" cambia el instalador de esa app por un proceso que se
    # queda colgado (prueba del corte por tiempo, el diagnostico y que el resto siga). "App:segundos:freeze" deja
    # el instalador real y a los 8 s congela Windows Installer: un MSI colgado de verdad (mutex retenido por el
    # msiexec del servicio, fuera del arbol del proceso), para probar que se libera y las demas MSI siguen.
    if ($env:NODEDEPLOY_TEST_HANG -and -not $DryRun -and $env:NODEDEPLOY_TEST_HANG.Split(':')[0] -eq $app.Name) {
        $hp = $env:NODEDEPLOY_TEST_HANG.Split(':')
        $app = $app.PSObject.Copy(); $app.Timeout = [int]$hp[1]
        if ($hp.Count -ge 3 -and $hp[2] -eq 'freeze') {
            $frz = @'
Start-Sleep -Seconds 8
[System.Diagnostics.Process]::EnterDebugMode()
Add-Type -Name F -Namespace N -MemberDefinition '[DllImport("ntdll.dll")] public static extern int NtSuspendProcess(IntPtr h);'
Get-Process msiexec -ErrorAction SilentlyContinue | ForEach-Object { [void][N.F]::NtSuspendProcess($_.Handle) }
'@
            $delay = if ($hp.Count -ge 4) { [int]$hp[3] } else { 8 }   # "App:segundos:freeze:retardo"
            $frz = $frz -replace 'Start-Sleep -Seconds 8', "Start-Sleep -Seconds $delay"
            $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($frz))
            Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -WindowStyle Hidden -ArgumentList "-NoProfile -EncodedCommand $enc" | Out-Null
            Write-Log "PRUEBA: $($app.Name) con Windows Installer congelado a los $delay s (timeout $($app.Timeout) s)" 'WARN'
        } else {
            $cmd.FilePath = Join-Path $PSHOME 'powershell.exe'; $cmd.Arguments = '-NoProfile -Command "Start-Sleep -Seconds 3600"'
            Write-Log "PRUEBA: $($app.Name) se sustituye por un proceso colgado (timeout $($app.Timeout) s)" 'WARN'
        }
    }
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
    $job.WorkDir = $cmd.WorkingDirectory
    return @{ Entry = $Entry; Job = $job }
}

function Get-RetryDelay {
    # $null = no reintentar: se apunta el fallo y se sigue con las demas. 1618 (MSI ocupado) espera y no gasta
    # intentos. Colgado (timeout): no se reintenta, se colgaria igual (en campo: 3 x 15 min perdidos). Fallo rapido
    # (codigo de error): un reintento corto, por si era algo pasajero.
    param([int]$ExitCode, [bool]$TimedOut, $Entry)
    if ($ExitCode -eq 1618) {
        $Entry.BusyRetries++
        if ($Entry.BusyRetries -le 12) { $Entry.Attempt--; return 15 }   # max. 3 min; luego fallo y se sigue
        return $null
    }
    if ($TimedOut) { return $null }
    if ($ExitCode -in 1601,1602,1619,1620,1633,1638,-99) { return $null }  # config/paquete/cancelado: reintentar no ayuda
    if ($Entry.Attempt -gt $MaxRetries) { return $null }
    return 10
}

function Get-IManageSetupErrors {
    <#
        Work Desktop / Drive (InstallScript) dejan su propio log en %TEMP% (p. ej. workdesktop_v10_10_2_62_*.log)
        con el motivo real de 0x80042000 ("### ERROR ### ... did not detect MS Office is installed").
        Se copia a state\logs y se devuelven las lineas de error para el informe.
    #>
    param([datetime]$Since, [string]$Tag, [string]$WorkDir)
    $msgs = @()
    # setup.log de InstallScript (se crea junto al setup.iss): ResultCode del modo silencioso.
    $sl = if ($WorkDir) { Join-Path $WorkDir 'setup.log' } else { $null }
    if ($sl -and (Test-Path -LiteralPath $sl)) {
        try { Copy-Item -LiteralPath $sl -Destination (Join-Path $Script:LogDir ('{0}_setup.log' -f $Tag)) -Force } catch {}
        $rc = Select-String -LiteralPath $sl -Pattern '^\s*ResultCode\s*=\s*(-?\d+)' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($rc) {
            $n = [int]$rc.Matches[0].Groups[1].Value
            $meaning = @{ 0 = 'ok'; -1 = 'error general'; -3 = 'falta un dato en setup.iss'; -5 = 'un fichero no existe'
                          -11 = 'error desconocido'; -12 = 'dialogos fuera de orden: setup.iss no coincide'
                          -51 = 'no se pudo crear una carpeta'; -52 = 'sin acceso a un fichero o carpeta' }[$n]
            $msgs += "setup.log ResultCode=$n$(if ($meaning) { " ($meaning)" })"
        }
    }
    $files = foreach ($pat in 'workdesktop*.log', 'imanage*.log') {
        Get-ChildItem -Path $env:TEMP -Filter $pat -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $Since.AddSeconds(-5) }
    }
    foreach ($f in @($files | Sort-Object FullName -Unique)) {
        try { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $Script:LogDir ('{0}_{1}' -f $Tag, $f.Name)) -Force } catch {}
        $msgs += @(Select-String -LiteralPath $f.FullName -Pattern '### ERROR ###\s*(.+)$' -ErrorAction SilentlyContinue | ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() })
    }
    return @($msgs | Select-Object -Unique)
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

    $reason = if ($Job.Error) { $Job.Error } elseif ($TimedOut) { "colgado: sin terminar en $(Format-Duration $Job.Timeout)$(if ($Job.HangInfo) { " (procesos: $($Job.HangInfo))" })" } elseif ($code -eq 1618) { 'msi_busy:1618' } else { "exit_code:$code($hex)" }
    $rec.errors += $reason
    if ($app.Type -eq 'installshield-imanage' -and -not $DryRun) {
        foreach ($m in (Get-IManageSetupErrors -Since $Job.StartedAt -Tag ($app.Name -replace '\s','') -WorkDir $Job.WorkDir)) {
            if ($rec.errors -notcontains "imanage:$m") { $rec.errors += "imanage:$m" }
        }
    }
    $delay = Get-RetryDelay -ExitCode $code -TimedOut $TimedOut -Entry $Entry
    if ($null -ne $delay) {
        $rec.status = 'retry_pending'
        Set-AppRecord $State $app.Name $rec
        Write-Log "[$tag] RETRY $($app.Name) - $reason. Nuevo intento en ${delay}s" 'WARN'
        return $delay
    }
    $rec.status = if ($TimedOut) { 'fail_timeout' } else { 'fail' }
    $rec.finished = (Get-Date -Format 'o')
    $rec | Add-Member -NotePropertyName log_tail -NotePropertyValue @(Get-LogTail -Path $Job.LogFile) -Force
    Set-AppRecord $State $app.Name $rec
    Write-Log "[$tag] FAIL $($app.Name) - $reason tras $($rec.attempts) intento(s). Se sigue con las demas. Log: $($Job.LogFile)" 'ERROR'
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
            $check = Get-ReadyCheck -Entry $entry -State $State -Office $Office -PendingNames @($pendingNames | Where-Object { $_ -ne $entry.App.Name })
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
                if ($waited -lt 300) { continue }
                Write-Log '[MSI] 5 min esperando el mutex MSI; se lanza igualmente (1618 -> reintento)' 'WARN'
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
                    if ((Get-ReadyCheck -Entry $e -State $State -Office $Office -PendingNames @($pn | Where-Object { $_ -ne $e.App.Name })) -eq 'ready') { $anyReady = $true; break }
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

function Get-ReportIcon {
    # Iconos del informe (se generan aqui para que este .ps1 siga siendo ASCII: PowerShell 5.1 sin BOM).
    param([string]$Name)
    $cp = @{ ok = 0x2705; fail = 0x274C; warn = 0x26A0; skip = 0x23ED; stop = 0x26D4; time = 0x23F1; reboot = 0x1F504; pause = 0x23F8 }[$Name]
    if (-not $cp) { return '' }
    return [char]::ConvertFromUtf32($cp)
}

function Write-FinalReport {
    # Informe corto y al grano: resultado en una linea, "Atencion" solo si hay algo que hacer, tabla App / Estado /
    # Tiempo (lo que pasa de 1 minuto, en negrita y marcado) y el equipo en pocas lineas. El detalle tecnico
    # (comandos, evidencias, intentos, codigos) esta en el log y en el zip de logs.
    param($State)
    $reportFile = Join-Path (Split-Path -Parent $Script:StatePath) 'POSTVALIDATE_REPORT.md'
    $iOk = Get-ReportIcon ok; $iFail = Get-ReportIcon fail; $iWarn = Get-ReportIcon warn; $iSkip = Get-ReportIcon skip
    $iStop = Get-ReportIcon stop; $iTime = Get-ReportIcon time; $iReb = Get-ReportIcon reboot; $iPause = Get-ReportIcon pause
    $apps  = @(Get-AllRecords $State)
    $total = @($Script:Apps).Count
    $okN   = @($apps | Where-Object { $_.status -in $Script:OkStatus }).Count
    $bad   = @($apps | Where-Object { $_.status -like 'fail*' -or $_.status -eq 'blocked' })
    $skipN = @($apps | Where-Object { $_.status -eq 'skipped_by_user' }).Count
    # Minutos en negrita; aviso si pasa de lo esperado: 1 min (Outlook, la excepcion: 5 min)
    $fmtT  = { param([int]$s, [int]$lim = 60) $t = Format-Duration $s; if ($s -gt 60) { "**$t**$(if ($s -gt $lim) { " $iWarn" })" } else { $t } }

    $sb = New-Object Text.StringBuilder
    $add = { param([string]$l = '') [void]$sb.AppendLine($l) }
    & $add "# NodeDeploy $($Script:Version) - $env:COMPUTERNAME - $($Script:StartTime.ToString('dd/MM/yyyy HH:mm'))$(if ($DryRun) { ' (simulacion: no se instalo nada)' })"
    & $add
    $appsTxt = if ($bad.Count) { "$iFail **$okN/$total apps OK** - $($bad.Count) con fallo: $(($bad | ForEach-Object { $_.name }) -join ', ')" } else { "$iOk **$okN/$total apps OK**$(if ($skipN) { " ($skipN saltadas)" })" }
    $rb = if ($Script:FinalizeResult) { "$($Script:FinalizeResult['Reinicio automatico'])" } else { '' }
    $rbTxt = switch -Regex ($rb) {
        '^si: (\w+) en 15 s \(([^)]*)\)' { "$iReb se va a $($matches[1]) en 15 s ($($matches[2]))"; break }
        '^pendiente'                     { "$iReb reinicia solo al terminar las actualizaciones (no lo apagues)"; break }
        '^no hace falta'                 { 'sin reinicio: no hace falta'; break }
        '^desactivado'                   { 'sin reinicio automatico (-NoAutoReboot)'; break }
        '^no: (.+?)( \| aviso.*)?$'      { "$iPause sin reinicio: $($matches[1])"; break }
        default                          { if ($State.reboot_required) { "$iReb hace falta reiniciar" } else { '' } }
    }
    & $add "$appsTxt  |  $iTime **$(Format-Duration (Get-Elapsed))**$(if ($rbTxt) { "  |  $rbTxt" })"
    & $add

    # Atencion: solo lo que hay que mirar o hacer
    $att = New-Object System.Collections.Generic.List[string]
    foreach ($a in $bad) {
        $why = "$(@($a.errors | Where-Object { $_ }) | Select-Object -Last 1)"
        if ($why -match '^exit_code:(-?\d+)') {
            $msg = @{ '1603' = 'fallo grave del instalador'; '1625' = 'bloqueado por directiva'; '1632' = 'carpeta temporal inaccesible'
                      '1641' = 'reinicio iniciado'; '1638' = 'ya hay otra version instalada'; '1619' = 'no se pudo abrir el paquete' }[$matches[1]]
            $why = "error $($matches[1])$(if ($msg) { " ($msg)" })"
        }
        $logName = if ($a.install_log) { ' - log `' + (Split-Path $a.install_log -Leaf) + '`' } else { '' }
        $att.Add("- $iFail **$($a.name)**: $why$logName")
        foreach ($l in @($a.log_tail | Where-Object { $_ } | Select-Object -Last 4)) { $att.Add("    $l") }
        if ("$($a.exit_code)" -eq '-2147213312') { $att.Add('    0x80042000 = iManage no ve un prerrequisito (Office con Word y Outlook, o Agent Services): `Diag-iManageWD.ps1`') }
    }
    if ($Script:FinalizeResult) {
        foreach ($k in $Script:FinalizeResult.Keys) {
            $v = "$($Script:FinalizeResult[$k])"
            if ($v -match '^ERROR') { $att.Add("- $iFail **${k}**: $v") }
            if ($k -eq 'Pospuesto') { $att.Add("- $iPause **Cierre pospuesto**: Administrador, usuario y dominio se hacen al relanzar el script con todo OK") }
        }
    }
    foreach ($src in @(@{ n = 'Lenovo'; r = $Script:LenovoResult }, @{ n = 'Windows Update'; r = $Script:WuResult })) {
        if (-not $src.r) { continue }
        foreach ($f in @($src.r.failed)) { if ($f) { $att.Add("- $iWarn **$($src.n)**: $f") } }
        foreach ($s in @($src.r.skipped | Where-Object { "$_" -match 'cargador' })) { $att.Add("- $iWarn **$($src.n)**: $s") }
    }
    $ad = if ($Script:PolicyResult) { "$($Script:PolicyResult['AnyDesk'])" } else { '' }
    if ($ad -match '^(AVISO|ERROR)') { $att.Add("- $iWarn **AnyDesk**: $ad") }
    if ($att.Count) { & $add "## $iWarn Atencion"; & $add; foreach ($l in $att) { & $add $l }; & $add }

    # Apps: primero las que fallan, luego las mas lentas; las que ya estaban, al final
    $rows = foreach ($a in $Script:Apps) {
        $r = Get-AppRecord $State $a.Name
        if (-not $r) { [pscustomobject]@{ N = $a.Name; E = '- sin ejecutar'; S = -1; K = 3 }; continue }
        $sec = [int](@($r.history) | Measure-Object -Property sec -Sum).Sum
        if (-not $sec) { $sec = [int]$r.elapsed_sec }
        $e, $k = if ($r.preinstalled) { "$iOk ya estaba", 2 }
                 elseif ($r.status -eq 'ok') { $iOk, 1 }
                 elseif ($r.status -eq 'ok_reboot') { "$iOk pide reinicio", 1 }
                 elseif ($r.status -eq 'ok_unverified') { "$iWarn sin confirmar", 1 }
                 elseif ($r.status -eq 'fail_timeout') { "$iFail colgado", 0 }
                 elseif ($r.status -eq 'fail') { "$iFail error $($r.exit_code)", 0 }
                 elseif ($r.status -eq 'blocked') { "$iStop bloqueada", 0 }
                 elseif ($r.status -eq 'skipped_by_user') { "$iSkip saltada", 2 }
                 else { $r.status, 1 }
        [pscustomobject]@{ N = $r.name; E = $e; S = $(if ($r.preinstalled -or $r.status -in 'skipped_by_user','blocked') { -1 } else { $sec }); K = $k }
    }
    & $add '## Apps'
    & $add
    & $add '| App | Estado | Tiempo |'
    & $add '|---|---|---|'
    foreach ($w in ($rows | Sort-Object K, @{ Expression = 'S'; Descending = $true }, N)) {
        & $add "| $($w.N) | $($w.E) | $(if ($w.S -ge 0) { & $fmtT $w.S $(if ($w.N -like 'Outlook*') { 300 } else { 60 }) } else { '-' }) |"
    }
    & $add

    # Equipo, en pocas lineas (la seccion solo sale si hay algo que contar)
    $sbMain = $sb; $sb = New-Object Text.StringBuilder
    $fs = $Script:FinalizeStatus
    if ($fs) {
        $dom = "$($Script:FinalizeResult['Dominio'])"
        & $add ("- **Cierre:** Administrador {0} | usuario fuera de Administradores {1} | dominio: {2}" -f $(if ($fs.AdminOk) { $iOk } else { $iFail }), $(if ($fs.UserOk) { $iOk } else { $iFail }), $(if ($dom) { $dom } else { '-' }))
    } elseif ($Script:FinalizeResult -and $Script:FinalizeResult.Contains('Pospuesto')) {
        & $add "- **Cierre:** $iPause pospuesto (hay apps con fallo)"
    }
    if ($ad) { & $add "- **AnyDesk:** $ad" }
    if ($Script:ClockResult -and $Script:ClockResult -match 'antes|corregido|ERROR') { & $add "- **Hora:** $($Script:ClockResult)" }
    if ($Script:LenovoResult) {
        $lr = $Script:LenovoResult
        & $add ("- **Lenovo** ({0}): {1} instaladas{2}{3}" -f $(if ($lr.model) { $lr.model } else { '-' }), @($lr.installed).Count, $(if (@($lr.pending).Count) { ', firmware/controladores pendientes de reinicio' }), $(if ($lr.seconds) { " - $(Format-Duration ([int]$lr.seconds))" }))
    }
    if ($Script:WuResult) {
        $wr = $Script:WuResult
        & $add ("- **Windows Update:** {0} instaladas{1}{2}" -f @($wr.installed).Count, $(if ($wr.reboot) { ', pide reinicio' }), $(if (@($wr.notes | Where-Object { $_ -match 'descarga' }).Count) { " ($((@($wr.notes | Where-Object { $_ -match 'descarga' })) -join '; '))" }))
    }
    if ($Script:PolicyResult -and $Script:PolicyResult.Contains('PDF24 Creator')) { & $add '- **PDF24:** solo en local (sin servicios online); en el escritorio solo PDF24 Toolbox' }
    if ($Script:OptimizeResult) {
        $o = $Script:OptimizeResult
        # Cada app sale dos veces (instalada + aprovisionada para usuarios nuevos): se cuentan apps, no paquetes
        $nApps = @("$($o['Apps de Store quitadas'])" -split ', ' | Where-Object { $_ -and $_ -notmatch '^ninguna' } | ForEach-Object { $_ -replace ' \(aprovisionada\)$', '' } | Select-Object -Unique).Count
        $off = @($o.Keys | Where-Object { $_ -like 'Arranque:*' -and "$($o[$_])" -eq 'deshabilitado' } | ForEach-Object { $_ -replace '^Arranque: ', '' -replace '\.lnk$', '' })
        & $add ("- **Optimizacion:** {0} apps de Store quitadas | sin arrancar con Windows: {1} | barra de tareas: Outlook y Teams, sin Store | TRIM {2}" -f $nApps, $(if ($off) { $off -join ', ' } else { '-' }), "$($o['TRIM (SSD)'])")
    }
    $eq = $sb.ToString(); $sb = $sbMain
    if ($eq.Trim()) { & $add '## Equipo'; & $add; [void]$sb.Append($eq); & $add }

    # Detalle de actualizaciones (lo que se instalo), al final y en una linea por origen
    $upd = @()
    if ($Script:LenovoResult -and @($Script:LenovoResult.installed).Count) { $upd += "- **Lenovo:** $(@($Script:LenovoResult.installed) -join '; ')" }
    if ($Script:WuResult -and @($Script:WuResult.installed).Count)         { $upd += "- **Windows Update:** $(@($Script:WuResult.installed) -join '; ')" }
    if ($upd) { & $add '## Actualizaciones instaladas'; & $add; foreach ($u in $upd) { & $add $u }; & $add }
    & $add "Log: ``$($Script:LogFile)``"

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

# Preguntas del cierre del equipo al arrancar: el resto del despliegue va desatendido.
$Script:FinalizeAnswers = $null; $Script:FinalizeResult = $null
if ($Phase -in 'full','install','resume' -and -not $DryRun -and -not $NoFinalize) {
    if (Get-Command Read-FinalizeAnswers -ErrorAction SilentlyContinue) {
        $Script:FinalizeAnswers = Read-FinalizeAnswers -Domain $Domain
    } else {
        Write-Log "Finalize.ps1 no encontrado junto a Deploy.ps1: sin cierre del equipo (Administrador / usuario / dominio)" 'WARN'
    }
}

# Hora del equipo antes de descargar nada (zona de Espana + reloj en hora). La duracion se mide con el reloj: se
# recoloca el inicio para que el cambio de hora no la falsee.
$Script:ClockResult = $null
if ($Phase -in 'full','install','resume' -and -not $DryRun -and $TimeZone -ne 'no') {
    $pre = Get-Elapsed; $swClock = [Diagnostics.Stopwatch]::StartNew()
    $Script:ClockResult = Set-ClockAndTimeZone -TimeZone $TimeZone -Force:($PSBoundParameters.ContainsKey('TimeZone'))
    $Script:StartTime = (Get-Date).AddSeconds(-($pre + $swClock.Elapsed.TotalSeconds))
    Write-Log "Hora: $($Script:ClockResult)" 'INFO'
}

# Limpieza de Windows en segundo plano desde t=0 (no alarga el despliegue); el arranque se ajusta al final.
$Script:DoOptimize =($Phase -in 'full','install','resume') -and -not $DryRun -and -not $NoOptimize -and (Test-Path $Script:OptimizePs1)
$Script:DebloatProc = $null; $Script:OptimizeResult = $null
$Script:DebloatJson = Join-Path $Script:LogDir 'optimize_debloat.json'
if ($Script:DoOptimize) {
    Remove-Item -LiteralPath $Script:DebloatJson -Force -ErrorAction SilentlyContinue
    $Script:DebloatProc = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -WindowStyle Hidden -PassThru `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($Script:OptimizePs1)`" -OptimizeMode debloat -OptimizeOutJson `"$($Script:DebloatJson)`""
    Write-Log 'Optimizacion de Windows en segundo plano: apps de Store sobrantes, publicidad, Bing, widgets' 'INFO'
}

# Actualizaciones de Lenovo en segundo plano (controladores ya; red, firmware y BIOS al terminar las apps).
$Script:LenovoProc = $null; $Script:LenovoResult = $null
$Script:LenovoPs1    = Join-Path $Script:ScriptDir 'Lenovo.ps1'
$Script:LenovoJson   = Join-Path $Script:LogDir 'lenovo_updates.json'
$Script:LenovoSignal = Join-Path $Script:LogDir 'lenovo_continuar.flag'
if (($Phase -in 'full','install','resume') -and -not $DryRun -and -not $NoLenovoUpdates -and (Test-Path $Script:LenovoPs1)) {
    $mfr = (Get-CimInstance Win32_ComputerSystem).Manufacturer
    if ($mfr -match 'LENOVO') {
        Remove-Item -LiteralPath $Script:LenovoJson, $Script:LenovoSignal -Force -ErrorAction SilentlyContinue
        $lnArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$($Script:LenovoPs1)`" -LenovoMode run -OutJson `"$($Script:LenovoJson)`" -SignalFile `"$($Script:LenovoSignal)`" -ModuleSource `"$(Join-Path $Source 'Lenovo')`""
        if ($NoBIOS) { $lnArgs += ' -NoBIOS' }
        $Script:LenovoProc = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -WindowStyle Hidden -PassThru -ArgumentList $lnArgs
        Write-Log 'Actualizaciones de Lenovo en segundo plano: controladores ya; red, firmware y BIOS al terminar las apps' 'INFO'
    } else {
        Write-Log "Sin actualizaciones de Lenovo: el equipo es $mfr" 'INFO'
    }
}

# Windows Update en segundo plano: solo controladores y firmware (BIOS). Ya solo sincroniza; al terminar apps y Lenovo
# los busca, descarga e instala uno a uno. El resto (acumulativa, .NET, Defender...) lo pone Windows.
$Script:WuProc = $null; $Script:WuResult = $null
$Script:WuPs1      = Join-Path $Script:ScriptDir 'WindowsUpdate.ps1'
$Script:WuJson     = Join-Path $Script:LogDir 'windows_update.json'
$Script:WuSignal   = Join-Path $Script:LogDir 'wu_continuar.flag'
$Script:WuProgress = Join-Path $Script:LogDir 'wu_progreso.txt'
if (($Phase -in 'full','install','resume') -and -not $DryRun -and -not $NoWindowsUpdate -and (Test-Path $Script:WuPs1)) {
    Remove-Item -LiteralPath $Script:WuJson, $Script:WuSignal, $Script:WuProgress -Force -ErrorAction SilentlyContinue
    $Script:WuProc = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -WindowStyle Hidden -PassThru `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($Script:WuPs1)`" -WuMode run -OutJson `"$($Script:WuJson)`" -SignalFile `"$($Script:WuSignal)`" -ProgressFile `"$($Script:WuProgress)`""
    Write-Log 'Windows Update en segundo plano: solo controladores y firmware (sincroniza ya; los busca e instala al terminar las apps y Lenovo)' 'INFO'
}

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
    Reset-RunFields $rec
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
            $rec.status = 'ok'; $rec.evidence = $c.Evidence; $rec.validated = $true; $rec.preinstalled = $true; $rec.finished = (Get-Date -Format 'o')
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

# Configuracion de apps del catalogo (p. ej. PDF24 solo en local), tambien si ya estaban instaladas.
$Script:PolicyResult = if ($DryRun) { $null } else { Set-AppPolicies $State }

# AnyDesk obligatorio: entero, en marcha y con ID (antes de que Lenovo toque la red). Repara una instalacion a medias.
$adApp = $Script:Apps | Where-Object { $_.Name -eq 'AnyDesk' } | Select-Object -First 1
$adRec = Get-AppRecord $State 'AnyDesk'
if (-not $DryRun -and $adRec -and $adRec.status -in $Script:OkStatus -and (Get-Command Test-AnyDeskHealth -ErrorAction SilentlyContinue)) {
    $adTxt = try { Test-AnyDeskHealth -Msi (Resolve-AppPath $adApp) } catch { "ERROR: $($_.Exception.Message)" }
    if (-not $Script:PolicyResult) { $Script:PolicyResult = [ordered]@{} }
    $Script:PolicyResult['AnyDesk'] = $adTxt
    Write-Log "AnyDesk: $adTxt" $(if ($adTxt -like 'ID *') { 'OK' } else { 'WARN' })
}

# Lenovo: con las apps ya instaladas, via libre para red, firmware y BIOS; se espera a que termine.
if ($Script:LenovoProc) {
    Write-Step 'ACTUALIZACIONES LENOVO'
    Set-Content -LiteralPath $Script:LenovoSignal -Value (Get-Date -Format 'o') -Encoding ASCII
    if (-not $Script:LenovoProc.HasExited) {
        Write-Log 'Esperando a las actualizaciones de Lenovo (red, firmware y BIOS; max. 30 min)...' 'INFO'
        [void]$Script:LenovoProc.WaitForExit(1800000)
    }
    if (-not $Script:LenovoProc.HasExited) {
        # No se corta: podria estar grabando firmware. Se informa y se sigue; el vigilante reinicia cuando acabe.
        $Script:LenovoRunning = $true
        $Script:LenovoResult = [ordered]@{ failed = @('no termino en 30 min: sigue en segundo plano (no apagues el equipo)'); installed = @(); skipped = @(); pending = @(); notes = @() }
        Write-Log 'Lenovo: no termino en 30 min, sigue en segundo plano' 'WARN'
    } elseif (Test-Path -LiteralPath $Script:LenovoJson) {
        $Script:LenovoResult = Get-Content -LiteralPath $Script:LenovoJson -Raw | ConvertFrom-Json
        $lr = $Script:LenovoResult
        if (@($lr.pending) -match 'REBOOT|SHUTDOWN') { $State.reboot_required = $true }
        Write-Log ("Lenovo: {0} instaladas, {1} con fallo, {2} omitidas en {3} s{4}" -f @($lr.installed).Count, @($lr.failed).Count, @($lr.skipped).Count, $lr.seconds, $(if (@($lr.pending).Count) { " | pendiente: $(@($lr.pending) -join ', ')" })) $(if (@($lr.failed).Count) { 'WARN' } else { 'OK' })
    } else {
        $Script:LenovoResult = [ordered]@{ failed = @('sin resultado'); installed = @(); skipped = @(); pending = @(); notes = @() }
    }
}

# Windows Update: con apps y Lenovo terminados, via libre para sus controladores; se espera a que acabe (no se
# reinicia con Windows instalando).
if ($Script:WuProc) {
    Write-Step 'WINDOWS UPDATE (controladores y firmware)'
    Set-Content -LiteralPath $Script:WuSignal -Value (Get-Date -Format 'o') -Encoding ASCII
    # Se ensena lo que hace (WindowsUpdate.ps1 deja una linea en wu_progreso.txt) y cada minuto que sigue vivo.
    # Max. 20 min: si no, sigue en segundo plano y el vigilante reinicia cuando acabe.
    $swWu = [Diagnostics.Stopwatch]::StartNew(); $wuTxt = ''; $wuBeat = 0
    while (-not $Script:WuProc.HasExited -and $swWu.Elapsed.TotalMinutes -lt 20) {
        $t = try { "$(Get-Content -LiteralPath $Script:WuProgress -Raw -ErrorAction Stop)".Trim() } catch { '' }
        if ($t -and $t -ne $wuTxt) { Write-Log "[WU] $t" 'INFO'; $wuTxt = $t; $wuBeat = $swWu.Elapsed.TotalSeconds }
        elseif ($swWu.Elapsed.TotalSeconds - $wuBeat -ge 60) { Write-Log "[WU] sigue: $(if ($wuTxt) { $wuTxt } else { 'buscando' }) ($(Format-Duration ([int]$swWu.Elapsed.TotalSeconds)))" 'INFO'; $wuBeat = $swWu.Elapsed.TotalSeconds }
        [void]$Script:WuProc.WaitForExit(2000)
    }
    if (-not $Script:WuProc.HasExited) {
        $Script:WuRunning = $true
        $Script:WuResult = [ordered]@{ found = 0; installed = @(); failed = @('no termino en 20 min: sigue en segundo plano (no apagues el equipo)'); skipped = @(); reboot = $false; notes = @() }
        Write-Log "Windows Update: no termino en 20 min ($wuTxt), sigue en segundo plano" 'WARN'
    } elseif (Test-Path -LiteralPath $Script:WuJson) {
        $Script:WuResult = Get-Content -LiteralPath $Script:WuJson -Raw | ConvertFrom-Json
        $wr = $Script:WuResult
        if ($wr.reboot) { $State.reboot_required = $true }
        Write-Log ("Windows Update: {0} instaladas, {1} con fallo, {2} omitidas en {3} s{4}" -f @($wr.installed).Count, @($wr.failed).Count, @($wr.skipped).Count, $wr.seconds, $(if ($wr.reboot) { ' | pide reinicio' })) $(if (@($wr.failed).Count) { 'WARN' } else { 'OK' })
    } else {
        $Script:WuResult = [ordered]@{ found = 0; installed = @(); failed = @('sin resultado'); skipped = @(); reboot = $false; notes = @() }
    }
}

# Optimizacion de Windows: resultado de la limpieza + arranque (las entradas ya existen: apps instaladas).
if ($Script:DoOptimize -and (Get-Command Set-StartupPolicy -ErrorAction SilentlyContinue)) {
    Write-Step 'OPTIMIZACION DE WINDOWS'
    $opt = [ordered]@{}
    if ($Script:DebloatProc) {
        if (-not $Script:DebloatProc.HasExited) {
            Write-Log 'Esperando a que termine la limpieza de apps (max. 5 min)...' 'INFO'
            [void]$Script:DebloatProc.WaitForExit(300000)
        }
        if (Test-Path $Script:DebloatJson) {
            $d = Get-Content -LiteralPath $Script:DebloatJson -Raw | ConvertFrom-Json
            $opt['Apps de Store quitadas'] = if (@($d.removed).Count) { @($d.removed) -join ', ' } else { 'ninguna (no estaban)' }
            $opt['Directivas'] = @($d.policies) -join '; '
            if (@($d.errors).Count) { $opt['Avisos de la limpieza'] = (@($d.errors) | Select-Object -First 5) -join ' | ' }
            Write-Log "Limpieza: $(@(@($d.removed) | ForEach-Object { $_ -replace ' \(aprovisionada\)$', '' } | Select-Object -Unique).Count) apps quitadas en $($d.seconds)s" 'OK'
        } else {
            $opt['Limpieza'] = 'sin resultado (no termino a tiempo)'
            Write-Log 'Limpieza de apps sin resultado (no termino a tiempo)' 'WARN'
        }
    }
    try {
        $st = Set-StartupPolicy
        foreach ($k in $st.Keys) { $opt["Arranque: $k"] = $st[$k] }
        Write-Log ("Arranque: " + (($st.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; ')) 'OK'
        $opt['Barra de tareas'] = Set-TaskbarLayout
        Write-Log "Barra de tareas: $($opt['Barra de tareas'])" 'OK'
        $chk = Get-OptimizeChecks
        foreach ($k in $chk.Keys) { $opt[$k] = $chk[$k] }
    } catch { $opt['ERROR'] = $_.Exception.Message; Write-Log "Optimizacion: $($_.Exception.Message)" 'ERROR' }
    $Script:OptimizeResult = $opt
}

# Cierre del equipo: solo con todas las apps OK (Administrador -> usuario -> dominio, en ese orden).
$Script:DomainWanted = [bool]($Script:FinalizeAnswers -and $Script:FinalizeAnswers.Domain)
if ($Script:FinalizeAnswers) {
    $pending = @(Get-AllRecords $State | Where-Object { $_.status -like 'fail*' -or $_.status -eq 'blocked' })
    if ($pending.Count -eq 0) {
        Write-Step 'CIERRE DEL EQUIPO'
        $Script:FinalizeResult = Invoke-Finalize -Answers $Script:FinalizeAnswers -State $State -StandardUser $StandardUser
    } else {
        $Script:FinalizeResult = [ordered]@{ 'Pospuesto' = "hay $($pending.Count) app(s) con fallo; se hara al relanzar el script cuando todas esten OK" }
        Write-Log "[CIERRE] Pospuesto: $($pending.Count) app(s) con fallo. Relanza el script cuando esten OK." 'WARN'
    }
    # Las contrasenas no se guardan: la del dominio vive en memoria solo hasta subir los logs (misma cuenta).
    $Script:LogCred = $Script:FinalizeAnswers.DomainCredential
    $Script:FinalizeAnswers = $null

    # Reinicio / apagado automatico (lo hace Deploy.bat, con 15 s de aviso) siempre que algo lo pida: dominio unido,
    # Lenovo, Windows Update, instaladores o Windows. Nunca antes del dominio: si se pidio dominio y no esta unido,
    # no. Si las actualizaciones siguen instalandose, un vigilante reinicia cuando terminen. Una app con fallo no
    # lo frena (se apunta). Si Lenovo pide apagar (algun firmware), se apaga.
    $dec = Get-AutoRebootDecision -Records @(Get-AllRecords $State) -FinalizeStatus $Script:FinalizeStatus -DomainWanted $Script:DomainWanted `
        -LenovoResult $Script:LenovoResult -WuResult $Script:WuResult -WindowsPending ([bool](Test-PendingReboot).HardPending) `
        -UpdatesRunning ([bool]($Script:LenovoRunning -or $Script:WuRunning))
    $warnTxt = if ($dec.Warn) { " | aviso: $($dec.Warn -join '; ')" } else { '' }
    if ($NoAutoReboot) {
        $Script:FinalizeResult['Reinicio automatico'] = "desactivado (-NoAutoReboot)$(if ($dec.Need) { "; pediria: $($dec.Need -join ', ')" })"
    } elseif ($dec.Action) {
        Set-Content -LiteralPath $Script:AutoRebootFlag -Value @($dec.Action, ($dec.Need -join ', ')) -Encoding ASCII
        $Script:FinalizeResult['Reinicio automatico'] = "si: $($dec.Action) en 15 s ($($dec.Need -join ', ')); shutdown /a para cancelar$warnTxt"
        Write-Log "[CIERRE] $($dec.Action) automatico en 15 s: $($dec.Need -join ', ')$warnTxt" 'OK'
    } elseif ($dec.Why.Count -eq 1 -and $dec.Why[0] -eq 'actualizaciones aun instalandose') {
        # El vigilante espera a que terminen (sin cortarlas) y a que acabe este script; luego borra la carpeta del
        # escritorio si se marca abajo y reinicia si algo lo pide, tambien lo que ya pedia ahora (Need: dominio...).
        # Se ejecuta desde ProgramData: no depende de la carpeta de NodeDeploy (la del escritorio se puede borrar)
        $mon = Join-Path $Script:MonitorDir 'RebootMonitor.ps1'
        try {
            New-Item -ItemType Directory -Force -Path $Script:MonitorDir | Out-Null
            Copy-Item -LiteralPath (Join-Path $Script:ScriptDir 'RebootMonitor.ps1'), (Join-Path $Script:ScriptDir 'Cleanup.ps1') -Destination $Script:MonitorDir -Force
        } catch {}
        $pidList = @(@($Script:LenovoProc, $Script:WuProc) | Where-Object { $_ -and -not $_.HasExited } | ForEach-Object { $_.Id }) + @($PID)
        $monArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$mon`" -Pids $($pidList -join ',') -LogFile `"$($Script:LogFile)`" -CleanupFlag `"$(Join-Path $Script:MonitorDir 'borrar_carpeta.flag')`""
        # Solo los JSON de lo que se lanzo (sin JSON al final = no termino bien). Nada vacio: PS 5.1 lo descarta.
        if ($Script:LenovoProc) { $monArgs += " -LenovoJson `"$($Script:LenovoJson)`"" }
        if ($Script:WuProc)     { $monArgs += " -WuJson `"$($Script:WuJson)`"" }
        if ($dec.Need)          { $monArgs += " -Need `"$($dec.Need -join ', ')`"" }
        if (Test-Path -LiteralPath $mon) {
            Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -WindowStyle Hidden -ArgumentList $monArgs | Out-Null
            $Script:MonitorStarted = $true
            $Script:FinalizeResult['Reinicio automatico'] = "pendiente: el vigilante reinicia cuando terminen las actualizaciones (no apagues el equipo)$warnTxt"
            Write-Log "[CIERRE] Vigilante de reinicio activo (PID $($pidList -join ', ')): reinicia al terminar las actualizaciones" 'OK'
        } else {
            $Script:FinalizeResult['Reinicio automatico'] = "no: actualizaciones aun instalandose (reinicia tu cuando terminen)$warnTxt"
        }
    } elseif (-not $dec.Why) {
        $Script:FinalizeResult['Reinicio automatico'] = "no hace falta: nada pide reiniciar$warnTxt"
        Write-Log '[CIERRE] Nada pide reiniciar' 'OK'
    } else {
        $Script:FinalizeResult['Reinicio automatico'] = "no: $($dec.Why -join '; ')$warnTxt"
        Write-Log "[CIERRE] Sin reinicio automatico: $($dec.Why -join '; ')" 'INFO'
    }
    Save-State $State
}

# Herramientas que abre Deploy.bat al terminar: solo lo que haya que revisar a mano (cuentas / dominio).
$fsT = $Script:FinalizeStatus
$toolsList = @()
if (-not ($fsT -and $fsT.AdminOk -and $fsT.UserOk)) { $toolsList += 'lusrmgr' }
if (-not ($fsT -and $fsT.DomainDone))               { $toolsList += 'sysdm' }
Set-Content -LiteralPath (Join-Path $Script:StatePath 'herramientas.txt') -Value $toolsList -Encoding ASCII

Write-Step 'REPORT FINAL'
$reportFile = Write-FinalReport $State
$apps = Get-AllRecords $State
$failures = @($apps | Where-Object { $_.status -like 'fail*' -or $_.status -eq 'blocked' })

Write-Step 'RESUMEN'
Write-Log "Duracion total: $(Format-Duration (Get-Elapsed))" 'INFO'
Write-Log "OK: $(@($apps | Where-Object { $_.status -in $Script:OkStatus }).Count) / $(@($Script:Apps).Count)" 'OK'
Write-Log "FAIL/BLOCKED: $($failures.Count)$(if ($failures.Count) { ' -> ' + (($failures | ForEach-Object { $_.name }) -join ', ') })" $(if ($failures.Count) { 'ERROR' } else { 'INFO' })
Write-Log "Report: $reportFile" 'INFO'

# Logs de esta ejecucion a la carpeta de red (o al lado de la carpeta de NodeDeploy) y, si TODO quedo listo y la
# carpeta esta en un Escritorio, aviso a Deploy.bat para borrarla al terminar. Nada de esto frena ni cuenta como fallo.
if (-not $DryRun -and $Phase -in 'full','install','resume') {
    $realFail = { param($r) @(@($r.failed) | Where-Object { $_ -and "$_" -notmatch '^no termino' }).Count }
    $errs = @()
    if ($failures.Count) { $errs += "apps: $(($failures | ForEach-Object { $_.name }) -join ', ')" }
    if ($Script:LenovoResult -and (& $realFail $Script:LenovoResult)) { $errs += 'Lenovo' }
    if ($Script:WuResult -and (& $realFail $Script:WuResult)) { $errs += 'Windows Update' }
    if ($Script:FinalizeResult -and @(@($Script:FinalizeResult.Values) -match '^ERROR').Count) { $errs += 'cierre del equipo' }
    if ($Script:PolicyResult -and "$($Script:PolicyResult['AnyDesk'])" -match '^(AVISO|ERROR)') { $errs += 'AnyDesk' }
    $summary = if ($errs) { "CON ERRORES ($($errs -join '; '))" } else { 'SIN ERRORES' }
    try {
        $logsTxt = Save-RunLogs -HasErrors ([bool]$errs.Count) -Credential $Script:LogCred -ReportFile $reportFile -Summary $summary
        Write-Log "Logs ($summary): $logsTxt" 'INFO'
        Add-Content -LiteralPath $reportFile -Value "`r`n**Logs:** $logsTxt" -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { Write-Log "Logs: no se pudieron guardar ($($_.Exception.Message))" 'WARN' }
    $Script:LogCred = $null

    $fsC = $Script:FinalizeStatus
    $allDone = (-not $errs.Count) -and $fsC -and $fsC.AdminOk -and $fsC.UserOk -and $fsC.DomainDone
    $nodeRoot = Split-Path -Parent (Split-Path -Parent $Script:ScriptDir)
    if (-not $KeepFolder -and (Test-CleanupAllowed -Root $nodeRoot -AllDone $allDone)) {
        if (-not ($Script:LenovoRunning -or $Script:WuRunning)) {
            Set-Content -LiteralPath (Join-Path $Script:StatePath 'borrar_carpeta.flag') -Value $nodeRoot -Encoding UTF8
            Write-Log "Todo listo: la carpeta $nodeRoot se borra al terminar (-KeepFolder la conserva)" 'OK'
            Add-Content -LiteralPath $reportFile -Value "`r`n**Carpeta:** se borra sola al cerrar (logs ya guardados)." -Encoding UTF8 -ErrorAction SilentlyContinue
        } elseif ($Script:MonitorStarted) {
            # Las actualizaciones siguen (usan la carpeta): la borra el vigilante cuando terminen, si no fallan
            Set-Content -LiteralPath (Join-Path $Script:MonitorDir 'borrar_carpeta.flag') -Value $nodeRoot -Encoding UTF8
            Write-Log "Todo listo salvo las actualizaciones: el vigilante borra $nodeRoot cuando terminen (si no fallan)" 'OK'
            Add-Content -LiteralPath $reportFile -Value "`r`n**Carpeta:** se borra sola cuando terminen las actualizaciones, si no fallan (vigilante.log en ProgramData\NodeDeploy)." -Encoding UTF8 -ErrorAction SilentlyContinue
        }
    }
}

if ($State.reboot_required) {
    Write-Log '=== REINICIO REQUERIDO === Reinicia el equipo para completar (instaladores que lo piden y/o union al dominio)' 'WARN'
    exit 3
}
if ($failures.Count -gt 0) { exit 1 }
exit 0
#endregion
