<#
.SYNOPSIS
    Recoge de un portatil (Samsung, LG, Lenovo, Surface u otro) el hardware, el software del fabricante y todo lo
    que explica por que Windows Update no instala o el equipo no se reinicia solo.
.DESCRIPTION
    SOLO LEE Y COPIA: no instala, no desinstala, no reinicia ni cambia nada. Como administrador:
        powershell -ExecutionPolicy Bypass -File Recoger-Equipo.ps1
    Mejor justo despues de un NodeDeploy que no reinicio (los logs de ProgramData\NodeDeploy y LOGS_ERRORES van
    dentro). Tarda 5-15 min (la busqueda de Windows Update y el log de WU son lo lento).
    Deja C:\Diag\Equipo_<PC>_<fecha>.zip y una copia en el escritorio publico. Abrir primero RESUMEN.txt: al final
    trae "== Claves ==" con lo que mas suele explicar el problema.
    -Rapido omite la busqueda de actualizaciones pendientes, el log de WU y gpresult.
    Solo ASCII: Windows PowerShell 5.1 lee los .ps1 sin BOM como ANSI.
#>
param([string]$Salida = 'C:\Diag', [switch]$Rapido)

$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format 'yyyyMMdd_HHmm'
$dir   = Join-Path $Salida "Equipo_$($env:COMPUTERNAME)_$stamp"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$res = Join-Path $dir 'RESUMEN.txt'
$claves = New-Object System.Collections.Generic.List[string]
function W([string]$t) { Add-Content -LiteralPath $res -Value $t; Write-Host $t }
function K([string]$t) { $claves.Add($t); W "  >> $t" }
function Paso([string]$t) { Write-Host ''; Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $t" -ForegroundColor Cyan }
function Copiar([string]$src, [string]$sub) {
    try {
        $d = Join-Path $dir $sub; New-Item -ItemType Directory -Force -Path $d | Out-Null
        Copy-Item -LiteralPath $src -Destination $d -Recurse -Force -ErrorAction Stop; return $true
    } catch { W "  ! no se pudo copiar $src : $($_.Exception.Message)"; return $false }
}
function Txt([string]$name, $lines) { $lines | Out-File -LiteralPath (Join-Path $dir $name) -Encoding UTF8 -Width 400 }
function Reg([string]$path) {
    if (-not (Test-Path $path)) { return }
    foreach ($k in @(Get-Item $path) + @(Get-ChildItem $path -Recurse -ErrorAction SilentlyContinue)) {
        $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
        if ($p) { $p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { W ("  {0} | {1} = {2}" -f ($k.Name -replace '^HKEY_LOCAL_MACHINE', 'HKLM'), $_.Name, $_.Value) } }
    }
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host 'Ejecutalo como administrador (sin eso faltan powercfg, eventos y Windows Update).' -ForegroundColor Yellow }
$OEM = 'Samsung|LG Electronics|LGE|\bLG\b|Lenovo|Surface|Intel(\(R\)| Corporation)|Realtek|Qualcomm|MediaTek|Dolby|Synaptics|Elan|Goodix|Conexant|Waves|Dell|HP Inc|ASUS|Acer'

# 0) Equipo
Paso 'Equipo y hardware'
$cs   = Get-CimInstance Win32_ComputerSystem
$csp  = Get-CimInstance Win32_ComputerSystemProduct
$bios = Get-CimInstance Win32_BIOS
$os   = Get-CimInstance Win32_OperatingSystem
$cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
$bb   = Get-CimInstance Win32_BaseBoard
$ubr  = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue)
$arch = switch ($cpu.Architecture) { 9 { 'x64' } 12 { 'ARM64' } 0 { 'x86' } default { "arq $($cpu.Architecture)" } }
W "Equipo   : $($env:COMPUTERNAME) | $($cs.Manufacturer) | familia $($cs.SystemFamily) | modelo $($cs.Model) | SKU $($cs.SystemSKUNumber)"
W "Producto : $($csp.Name) | version $($csp.Version) | n/s $($bios.SerialNumber) | UUID $($csp.UUID)"
W "Placa    : $($bb.Manufacturer) $($bb.Product) $($bb.Version)"
W "BIOS     : $($bios.Manufacturer) $($bios.SMBIOSBIOSVersion) | fecha $($bios.ReleaseDate) | EC $($bios.EmbeddedControllerMajorVersion).$($bios.EmbeddedControllerMinorVersion)"
W "CPU      : $($cpu.Name) | $arch | $($cpu.NumberOfCores) nucleos | RAM $([math]::Round($cs.TotalPhysicalMemory/1GB,1)) GB"
W "Windows  : $($os.Caption) $($ubr.DisplayVersion) build $($os.BuildNumber).$($ubr.UBR) | instalado $($os.InstallDate) | arranque $($os.LastBootUpTime)"
W "Dominio  : $($cs.Domain) (en dominio: $($cs.PartOfDomain)) | Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
$up = (Get-Date) - $os.LastBootUpTime
W ("Encendido: {0:N1} h desde el ultimo arranque" -f $up.TotalHours)
try { $tpm = Get-Tpm -ErrorAction Stop; W "TPM      : presente $($tpm.TpmPresent) | listo $($tpm.TpmReady)" } catch { W "TPM      : no se pudo leer" }
try { W "SecureBoot: $(Confirm-SecureBootUEFI -ErrorAction Stop)" } catch { W "SecureBoot: no se pudo leer (BIOS heredada o sin permisos)" }
Get-CimInstance Win32_DiskDrive | ForEach-Object { W ("Disco    : {0} | {1} GB | {2} | firmware {3}" -f $_.Model, [math]::Round($_.Size/1GB), $_.InterfaceType, $_.FirmwareRevision) }
$vol = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
W ("C:       : libre {0} GB de {1} GB" -f [math]::Round($vol.FreeSpace/1GB,1), [math]::Round($vol.Size/1GB))
if ($vol.FreeSpace -lt 20GB) { K "Poco espacio en C: ($([math]::Round($vol.FreeSpace/1GB,1)) GB): Windows Update puede no instalar" }
$bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
if ($bat) {
    $ac = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue | Select-Object -First 1).PowerOnline
    W "Bateria  : $($bat.EstimatedChargeRemaining)% | estado $($bat.BatteryStatus) | cargador conectado: $ac"
    if ($ac -eq $false) { K 'Sin cargador: Windows Update aplaza reinicios e instalaciones con bateria' }
}
Get-CimInstance Win32_VideoController | ForEach-Object { W ("Video    : {0} | driver {1} ({2})" -f $_.Name, $_.DriverVersion, $_.DriverDate) }
W ''

# 1) Software y servicios del fabricante
Paso 'Software del fabricante'
W '== Programas instalados (todos en programas.csv; aqui los del fabricante) =='
$keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
$apps = @(Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } |
          Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, UninstallString, QuietUninstallString, PSChildName)
$apps | Sort-Object DisplayName | Export-Csv (Join-Path $dir 'programas.csv') -NoTypeInformation -Encoding UTF8
$apps | Where-Object { "$($_.DisplayName) $($_.Publisher)" -match $OEM -or $_.DisplayName -match '\b(Update|Updater|Settings|Vantage|Support|Assistant|McAfee|Norton)\b' } |
    Sort-Object Publisher, DisplayName | ForEach-Object { W ("  {0} {1} | {2}" -f $_.DisplayName, $_.DisplayVersion, $_.Publisher) }
W ''
W '== Apps de la Store del fabricante =='
Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { "$($_.Name) $($_.Publisher)" -match 'Samsung|LGE|LGElectronics|Lenovo|Surface|McAfee|Intel\.|AppUp\.Intel|Realtek|Dolby|Waves' } |
    ForEach-Object { W ("  {0} {1}" -f $_.Name, $_.Version) }
W ''
W '== Servicios que no son de Microsoft =='
$svc = @(Get-CimInstance Win32_Service | Where-Object { $_.PathName -and $_.PathName -notmatch '\\Windows\\(System32|SysWOW64)\\svchost|\\Windows Defender\\|\\Microsoft\\' })
$svc | Select-Object Name, DisplayName, State, StartMode, PathName | Sort-Object Name | Export-Csv (Join-Path $dir 'servicios.csv') -NoTypeInformation -Encoding UTF8
$svc | Where-Object { "$($_.Name) $($_.DisplayName) $($_.PathName)" -match $OEM -or $_.DisplayName -match 'Update' } |
    ForEach-Object { W ("  {0} | {1} | {2} | {3}" -f $_.Name, $_.DisplayName, $_.State, $_.StartMode) }
W ''
W '== Tareas programadas de fabricante y de actualizacion =='
$tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue)
$tasks | Where-Object { "$($_.TaskPath)$($_.TaskName)$(($_.Actions | ForEach-Object { $_.Execute }) -join ' ')" -match "$OEM|UpdateOrchestrator|WindowsUpdate|Reboot|Shutdown" } |
    ForEach-Object {
        $i = $_ | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        W ("  {0}{1} | {2} | ultima {3} (res {4}) | proxima {5}" -f $_.TaskPath, $_.TaskName, $_.State, $i.LastRunTime, $i.LastTaskResult, $i.NextRunTime)
    }
W ''

# 2) Windows Update: servicios, directivas, estado
Paso 'Windows Update (servicios y directivas)'
W '== Servicios de Windows Update =='
foreach ($n in 'wuauserv', 'UsoSvc', 'BITS', 'DoSvc', 'WaaSMedicSvc', 'TrustedInstaller', 'CryptSvc', 'msiserver') {
    $s = Get-CimInstance Win32_Service -Filter "Name='$n'" -ErrorAction SilentlyContinue
    if ($s) { W ("  {0} | {1} | {2}" -f $n, $s.State, $s.StartMode); if ($s.StartMode -eq 'Disabled') { K "Servicio $n DESACTIVADO" } }
    else { W "  $n | no existe"; K "Servicio $n no existe" }
}
W ''
W '== Directivas (GPO / MDM) de Windows Update =='
Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
Reg 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update'
$au = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -ErrorAction SilentlyContinue
if ($au.NoAutoUpdate -eq 1)  { K 'Directiva NoAutoUpdate=1: actualizaciones automaticas desactivadas' }
if ($au.NoAutoRebootWithLoggedOnUsers -eq 1) { K 'Directiva NoAutoRebootWithLoggedOnUsers=1: no reinicia con usuario conectado' }
if ($au.UseWUServer -eq 1) { K "Usa servidor WSUS: $((Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue).WUServer)" }
$wup = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
if ($wup.ExcludeWUDriversInQualityUpdate -eq 1) { K 'Directiva ExcludeWUDriversInQualityUpdate=1: Windows Update no trae controladores' }
if ($wup.DisableWindowsUpdateAccess -eq 1) { K 'Directiva DisableWindowsUpdateAccess=1' }
W ''
W '== Ajustes de usuario de Windows Update (pausa, horas activas) =='
Reg 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
$ux = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' -ErrorAction SilentlyContinue
foreach ($p in 'PauseUpdatesExpiryTime', 'PauseQualityUpdatesEndTime', 'PauseFeatureUpdatesEndTime') {
    if ($ux.$p) { try { $t = [datetime]$ux.$p; if ($t -gt (Get-Date)) { K "Windows Update en PAUSA hasta $t ($p)" } } catch {} }
}
W ''
W '== Controladores del fabricante bloqueados (metadatos de dispositivo) =='
Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata'
Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching'
$ds = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' -ErrorAction SilentlyContinue
if ($ds.SearchOrderConfig -eq 0) { K 'SearchOrderConfig=0: Windows no busca controladores en Windows Update' }
W ''

# 3) Reinicio: pendientes, energia, eventos
Paso 'Reinicio y energia'
W '== Reinicio pendiente =='
$pend = @()
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pend += 'CBS RebootPending' }
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pend += 'WU RebootRequired' }
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending') { $pend += 'CBS PackagesPending' }
$pfro = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue).PendingFileRenameOperations
if ($pfro) { $pend += "PendingFileRenameOperations ($(@($pfro | Where-Object { $_ }).Count))"; Txt 'pending_file_rename.txt' $pfro }
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Updates\UpdateExeVolatile') { $pend += 'UpdateExeVolatile' }
try { $si = New-Object -ComObject Microsoft.Update.SystemInfo; if ($si.RebootRequired) { $pend += 'Microsoft.Update.SystemInfo.RebootRequired' } } catch {}
if ($pend) { W "  $($pend -join ' | ')"; K "Reinicio PENDIENTE: $($pend -join ', ')" } else { W '  ninguno' }
W ''
W '== Programas que impiden suspender o apagar (powercfg /requests) =='
$req = & powercfg.exe /requests 2>&1; $req | ForEach-Object { W "  $_" }
W ''
W '== Estados de energia (powercfg /a) =='
$pa = & powercfg.exe /a 2>&1; $pa | ForEach-Object { W "  $_" }
if (($pa -join ' ') -match 'S0 .*(Low Power Idle|bajo consumo)') { K 'Modern Standby (S0): con la tapa cerrada sigue "despierto" y WU puede posponer el reinicio' }
W ''
W '== Temporizadores de activacion =='
& powercfg.exe /waketimers 2>&1 | ForEach-Object { W "  $_" }
$hb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction SilentlyContinue).HiberbootEnabled
W "  Inicio rapido (HiberbootEnabled): $hb"
if ($hb -eq 1) { K 'Inicio rapido activo: "Apagar" no es un reinicio real; las actualizaciones piden reiniciar' }
Txt 'powercfg_plan.txt' (& powercfg.exe /q 2>&1)
& powercfg.exe /batteryreport /output (Join-Path $dir 'battery_report.html') 2>&1 | Out-Null
& powercfg.exe /sleepstudy /output (Join-Path $dir 'sleepstudy.html') 2>&1 | Out-Null
W ''
W '== Apagados y reinicios (14 dias) =='
$since = (Get-Date).AddDays(-14)
$ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 41, 1074, 1076, 6005, 6006, 6008, 109, 1, 42, 107; StartTime = $since } -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -notin 1, 42, 107 -or $_.ProviderName -match 'Kernel-General|Kernel-Power|Power-Troubleshooter' } | Select-Object -First 80)
foreach ($e in $ev) { W ("  {0:yyyy-MM-dd HH:mm} | {1} {2} | {3}" -f $e.TimeCreated, $e.ProviderName, $e.Id, (($e.Message -split "`r?`n") | Where-Object { $_ } | Select-Object -First 2) -join ' / ') }
if (@($ev | Where-Object Id -eq 41).Count) { K "Kernel-Power 41 (apagado sucio) $(@($ev | Where-Object Id -eq 41).Count) veces en 14 dias" }
W ''

# 4) Controladores y dispositivos
Paso 'Controladores y dispositivos'
W '== Dispositivos con problema =='
$bad = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.Status -in 'Error', 'Degraded' -or ($_.Present -and $_.ConfigManagerErrorCode -ne 0) })
foreach ($d in $bad) { W ("  {0} | {1} | codigo {2} | {3}" -f $d.FriendlyName, $d.Class, $d.ConfigManagerErrorCode, $d.InstanceId) }
if ($bad.Count) { K "$($bad.Count) dispositivo(s) con problema o sin controlador (ver arriba)" } else { W '  ninguno' }
Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | Where-Object { $_.DeviceName } |
    Select-Object DeviceName, DeviceClass, Manufacturer, DriverProviderName, DriverVersion, DriverDate, InfName, HardWareID |
    Sort-Object DeviceClass, DeviceName | Export-Csv (Join-Path $dir 'controladores.csv') -NoTypeInformation -Encoding UTF8
Txt 'pnputil_drivers.txt' (& pnputil.exe /enum-drivers 2>&1)
W '  lista completa en controladores.csv y pnputil_drivers.txt'
W ''

# 5) Windows Update: historial y pendientes
Paso 'Windows Update (historial y pendientes)'
W '== Historial (ultimas 60) =='
try {
    $sess = New-Object -ComObject Microsoft.Update.Session
    $srch = $sess.CreateUpdateSearcher()
    $n = $srch.GetTotalHistoryCount()
    $hist = if ($n) { @($srch.QueryHistory(0, [math]::Min($n, 60))) } else { @() }
    $rc = @{ 0 = 'no empezada'; 1 = 'en curso'; 2 = 'OK'; 3 = 'OK con errores'; 4 = 'FALLO'; 5 = 'cancelada' }
    foreach ($h in $hist) { W ("  {0:yyyy-MM-dd HH:mm} | {1} | 0x{2:X8} | {3}" -f $h.Date, $rc[[int]$h.ResultCode], $h.HResult, $h.Title) }
    $fail = @($hist | Where-Object { $_.ResultCode -eq 4 })
    if ($fail.Count) { K "$($fail.Count) actualizacion(es) FALLIDAS en el historial (p. ej. 0x$('{0:X8}' -f $fail[0].HResult) $($fail[0].Title))" }
    $ok = $hist | Where-Object { $_.ResultCode -eq 2 } | Select-Object -First 1
    if ($ok) { W "  ultima correcta: $($ok.Date)" } else { K 'Ninguna actualizacion correcta en el historial' }
} catch { W "  ! no se pudo leer el historial: $($_.Exception.Message)" }
W ''
if (-not $Rapido) {
    W '== Pendientes (busqueda de Windows Update, max. 8 min) =='
    $job = Start-Job -ScriptBlock {
        $s = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        foreach ($q in "IsInstalled=0 and IsHidden=0 and Type='Software'", "IsInstalled=0 and IsHidden=0 and Type='Driver'") {
            try {
                foreach ($u in $s.Search($q).Updates) {
                    [pscustomobject]@{ Tipo = ($q -replace '.*Type=''(\w+)''.*', '$1'); Titulo = $u.Title; Descargada = $u.IsDownloaded
                                       Opcional = $u.BrowseOnly; Reinicio = $u.RebootRequired; Proveedor = "$($u.DriverProvider) $($u.DriverManufacturer)".Trim()
                                       Modelo = $u.DriverModel; Clase = $u.DriverClass; Fecha = $u.DriverVerDate; MB = [math]::Round($u.MaxDownloadSize/1MB, 1) }
                }
            } catch { [pscustomobject]@{ Tipo = 'ERROR'; Titulo = "$q -> $($_.Exception.Message)" } }
        }
    }
    if (Wait-Job $job -Timeout 480) {
        $pendU = @(Receive-Job $job)
        $pendU | Export-Csv (Join-Path $dir 'wu_pendientes.csv') -NoTypeInformation -Encoding UTF8
        foreach ($u in $pendU) { W ("  [{0}] {1} | descargada {2} | opcional {3} | {4}" -f $u.Tipo, $u.Titulo, $u.Descargada, $u.Opcional, $u.Proveedor) }
        $sw = @($pendU | Where-Object { $_.Tipo -eq 'Software' -and -not $_.Opcional }).Count
        $dr = @($pendU | Where-Object Tipo -eq 'Driver').Count
        $er = @($pendU | Where-Object Tipo -eq 'ERROR')
        if ($er) { K "Busqueda de Windows Update con ERROR: $($er[0].Titulo)" }
        if ($sw) { K "$sw actualizacion(es) de Windows pendientes" }
        if ($dr) { K "$dr controlador(es)/firmware pendientes en Windows Update" }
        if (-not $pendU.Count) { W '  nada pendiente' }
    } else { Stop-Job $job; K 'La busqueda de Windows Update no termino en 8 min (servicio colgado o sin red)' }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    W ''
}

# 6) Eventos y logs
Paso 'Eventos y logs'
foreach ($l in 'Microsoft-Windows-WindowsUpdateClient/Operational', 'Microsoft-Windows-Kernel-PnP/Configuration', 'Setup') {
    $f = Join-Path $dir (($l -replace '[/\\ ]', '_') + '.evtx')
    & wevtutil.exe epl $l $f /q:"*[System[TimeCreated[timediff(@SystemTime) <= 1209600000]]]" 2>&1 | Out-Null
}
& wevtutil.exe epl System (Join-Path $dir 'System.evtx') /q:"*[System[TimeCreated[timediff(@SystemTime) <= 1209600000]]]" 2>&1 | Out-Null
& wevtutil.exe epl Application (Join-Path $dir 'Application.evtx') /q:"*[System[(Level=1 or Level=2) and TimeCreated[timediff(@SystemTime) <= 1209600000]]]" 2>&1 | Out-Null
W '== Errores de WindowsUpdateClient (14 dias) =='
Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-WindowsUpdateClient/Operational'; Level = 2; StartTime = $since } -MaxEvents 30 -ErrorAction SilentlyContinue |
    ForEach-Object { W ("  {0:yyyy-MM-dd HH:mm} | {1} | {2}" -f $_.TimeCreated, $_.Id, (($_.Message -split "`r?`n")[0])) }
W ''
foreach ($f in 'C:\Windows\Logs\CBS\CBS.log', 'C:\Windows\WindowsUpdate.log', 'C:\Windows\INF\setupapi.dev.log', 'C:\Windows\Panther\setupact.log') {
    if ((Test-Path $f) -and (Get-Item $f).Length -lt 80MB) { [void](Copiar $f 'logs') }
}
if (-not $Rapido) {
    $wul = Join-Path $dir 'WindowsUpdate_decodificado.log'
    $j = Start-Job -ScriptBlock { param($o) Get-WindowsUpdateLog -LogPath $o -ErrorAction SilentlyContinue | Out-Null } -ArgumentList $wul
    if (-not (Wait-Job $j -Timeout 240)) { Stop-Job $j; W '  log de WU: no termino en 4 min, se copian los .etl'; Copiar 'C:\Windows\Logs\WindowsUpdate' 'logs' | Out-Null }
    Remove-Job $j -Force -ErrorAction SilentlyContinue
    if ($cs.PartOfDomain) { & gpresult.exe /scope computer /h (Join-Path $dir 'gpresult.html') /f 2>&1 | Out-Null }
}
Copiar 'C:\ProgramData\USOShared\Logs' 'logs' | Out-Null

# 7) NodeDeploy y software de fabrica que actualiza
Paso 'Logs de NodeDeploy'
W '== NodeDeploy =='
$nd = @('C:\ProgramData\NodeDeploy') + @(Get-ChildItem 'C:\Users\*\Desktop', 'C:\Users\Public\Desktop' -Directory -ErrorAction SilentlyContinue |
      ForEach-Object { Get-ChildItem $_.FullName -Directory -ErrorAction SilentlyContinue | Where-Object Name -match '^LOGS_(ERRORES|preparation)$' } |
      ForEach-Object { $_.FullName })
foreach ($p in $nd) { if (Test-Path $p) { if (Copiar $p ('nodedeploy\' + (($p -replace '^C:\\', '') -replace '\\', '_'))) { W "  copiado $p" } } }
$vg = 'C:\ProgramData\NodeDeploy\vigilante.log'
if (Test-Path $vg) { W '  -- ultimas lineas del vigilante --'; Get-Content $vg -Tail 25 | ForEach-Object { W "    $_" } }
W ''
foreach ($d in 'C:\ProgramData\Samsung', 'C:\Program Files\Samsung', 'C:\Program Files (x86)\Samsung', 'C:\ProgramData\LGE', 'C:\Program Files\LG Software',
               'C:\ProgramData\Lenovo', 'C:\Program Files\Lenovo', 'C:\Windows\Setup\Scripts', 'C:\Windows\OEM', 'C:\OEM') {
    if (Test-Path $d) {
        Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue | Select-Object FullName, Length, LastWriteTime |
            Export-Csv (Join-Path $dir ('lista_' + ($d -replace '[:\\ ()]', '_') + '.csv')) -NoTypeInformation -Encoding UTF8
        Get-ChildItem $d -Recurse -File -Include *.log -ErrorAction SilentlyContinue | Where-Object { $_.Length -lt 20MB -and $_.LastWriteTime -gt $since } |
            ForEach-Object { [void](Copiar $_.FullName ('oem' + ($_.DirectoryName -replace '^C:', ''))) }
    }
}

# Claves
W ''
W '== Claves =='
if ($claves.Count) { $claves | ForEach-Object { W "  - $_" } } else { W '  nada llamativo: mirar historial de WU, eventos y vigilante.log' }

$zip = "$dir.zip"
try {
    Compress-Archive -Path "$dir\*" -DestinationPath $zip -Force -ErrorAction Stop
    Copy-Item $zip 'C:\Users\Public\Desktop' -Force -ErrorAction SilentlyContinue
    W ''; W "Listo: $zip (y copia en el escritorio publico)"
} catch { W "No se pudo comprimir ($($_.Exception.Message)). Carpeta: $dir" }
