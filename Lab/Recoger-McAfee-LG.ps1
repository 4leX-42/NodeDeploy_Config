<#
.SYNOPSIS
    Recoge del LG todo lo necesario para reproducir McAfee (WPS) en la VM NodeDeploy-Lab y estudiar su desinstalacion.
.DESCRIPTION
    SOLO LEE Y COPIA: no ejecuta nada de McAfee ni cambia el equipo. Pasalo en un LG con McAfee todavia instalado
    (recien sacado de la caja, ANTES de Pincha_pa_instalar.bat). Como administrador:
        powershell -ExecutionPolicy Bypass -File Recoger-McAfee-LG.ps1
    Deja C:\Diag\McAfee_<PC>_<fecha>.zip y una copia en el escritorio publico. Contenido:
      - el instalador original de fabrica, si se encuentra en el disco (busqueda por nombre y por firma de McAfee);
      - mc-update.exe y los ficheros de configuracion del desinstalador (para buscar sus parametros sin ejecutarlo);
      - registro de desinstalacion, servicios, drivers, tareas, Run/RunOnce, paquetes Appx de McAfee;
      - unattend/SetupComplete del fabricante (de ahi sale el comando con el que LG lo instala);
      - logs de instalacion de McAfee (ProgramData\McAfee\wps\log, installstatus.txt).
    Solo ASCII: Windows PowerShell 5.1 lee los .ps1 sin BOM como ANSI.
#>
param([string]$Salida = 'C:\Diag')

$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format 'yyyyMMdd_HHmm'
$dir   = Join-Path $Salida "McAfee_$($env:COMPUTERNAME)_$stamp"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$res = Join-Path $dir 'RESUMEN.txt'
function W([string]$t) { Add-Content -LiteralPath $res -Value $t; Write-Host $t }
function Copiar([string]$src, [string]$sub) {
    try {
        $d = Join-Path $dir $sub; New-Item -ItemType Directory -Force -Path $d | Out-Null
        Copy-Item -LiteralPath $src -Destination $d -Force -ErrorAction Stop; return $true
    } catch { W "  ! no se pudo copiar $src : $($_.Exception.Message)"; return $false }
}

$cs = Get-CimInstance Win32_ComputerSystem
$os = Get-CimInstance Win32_OperatingSystem
W "Equipo : $($env:COMPUTERNAME) | $($cs.Manufacturer) $($cs.Model) | $($os.Caption) $($os.Version)"
W "Instalado Windows: $($os.InstallDate)   Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
W ''

# 1) Entradas de desinstalacion (todas sus propiedades)
W '== Desinstalacion (registro) =='
$keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
$unin = @(Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object { "$($_.DisplayName)$($_.Publisher)" -match 'McAfee' })
foreach ($u in $unin) {
    W "-- $($u.DisplayName) $($u.DisplayVersion) [$($u.PSChildName)]"
    $u.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { W ("   {0} = {1}" -f $_.Name, $_.Value) }
}
W ''

# 2) Servicios, drivers, tareas, arranque, Appx
W '== Servicios y drivers =='
Get-CimInstance Win32_Service | Where-Object { "$($_.Name)$($_.DisplayName)$($_.PathName)" -match 'McAfee|\\mfe|mc-' } |
    ForEach-Object { W ("  svc {0} | {1} | {2} | {3}" -f $_.Name, $_.State, $_.StartMode, $_.PathName) }
Get-CimInstance Win32_SystemDriver | Where-Object { "$($_.Name)$($_.PathName)" -match 'mfe|McAfee' } |
    ForEach-Object { W ("  drv {0} | {1} | {2}" -f $_.Name, $_.State, $_.PathName) }
W ''
W '== Tareas programadas =='
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { "$($_.TaskPath)$($_.TaskName)$(($_.Actions | ForEach-Object { $_.Execute }) -join ' ')" -match 'McAfee' } |
    ForEach-Object { W ("  {0}{1} | {2} | {3}" -f $_.TaskPath, $_.TaskName, $_.State, (($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' ; ')) }
W ''
W '== Run / RunOnce =='
foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
               'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
               'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce') {
    $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
    if ($p) { $p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { W ("  {0} | {1} = {2}" -f $k, $_.Name, $_.Value) } }
}
W ''
W '== Appx =='
Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'McAfee' } |
    ForEach-Object { W ("  app  {0} | {1}" -f $_.PackageFullName, $_.InstallLocation) }
Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'McAfee' } |
    ForEach-Object { W ("  prov {0}" -f $_.PackageName) }
W ''

# 3) Desinstalador y su configuracion (no se ejecuta)
W '== Ficheros del programa =='
$wps = 'C:\Program Files\McAfee\wps'
if (Test-Path $wps) {
    Get-ChildItem $wps -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\vpn\\' } |
        Select-Object FullName, Length, LastWriteTime, @{n='Version';e={ $_.VersionInfo.FileVersion }} |
        Export-Csv (Join-Path $dir 'ficheros_wps.csv') -NoTypeInformation -Encoding UTF8
    foreach ($f in Get-ChildItem $wps -Recurse -File -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match '^(mc-update\.exe|mc-launch\.exe|mc-inst-uihost\.exe|mc-oem-subjob\.exe|mc-appx-inst\.exe|mc-inst-ui2\.dll|.*\.cfg|.*\.ini|.*\.lnk|.*\.pam|.*\.manifest)$' -and $_.FullName -notmatch '\\vpn\\' }) {
        $sub = 'programa' + $f.DirectoryName.Substring($wps.Length)
        if (Copiar $f.FullName $sub) { W "  copiado $($f.FullName.Substring($wps.Length)) ($([math]::Round($f.Length/1KB)) KB)" }
    }
} else { W "  no existe $wps" }
W ''

# 4) Logs de instalacion
W '== Logs de McAfee =='
foreach ($f in @(Get-ChildItem 'C:\ProgramData\McAfee' -Recurse -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -match '\.(etl|log|txt)$|^product\.cfg$|^settings\.lines$' -and $_.Length -lt 50MB })) {
    $sub = 'programdata' + $f.DirectoryName.Substring('C:\ProgramData\McAfee'.Length)
    if (Copiar $f.FullName $sub) { W "  copiado $($f.FullName)" }
}
W ''

# 5) Como lo instala el fabricante: unattend, SetupComplete, carpetas OEM
W '== Instalacion de fabrica (unattend / OEM) =='
foreach ($f in 'C:\Windows\Panther\unattend.xml', 'C:\Windows\Panther\Unattend\unattend.xml', 'C:\Windows\System32\Sysprep\unattend.xml',
               'C:\Windows\Setup\Scripts\SetupComplete.cmd', 'C:\Windows\Setup\Scripts\ErrorHandler.cmd') {
    if (Test-Path $f) {
        if (Copiar $f 'oem') { W "  copiado $f" }
        Select-String -LiteralPath $f -Pattern 'McAfee|mcafee|WPS' -ErrorAction SilentlyContinue | ForEach-Object { W "    linea $($_.LineNumber): $($_.Line.Trim())" }
    }
}
foreach ($d in 'C:\Windows\Setup\Scripts', 'C:\Windows\OEM', 'C:\OEM', 'C:\Recovery\OEM', 'C:\LG', 'C:\LGSoftware', 'C:\ProgramData\LGE',
               'C:\Program Files\LG Software', 'C:\Program Files (x86)\LG Software', 'C:\Windows\Panther') {
    if (Test-Path $d) {
        $n = @(Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue).Count
        W "  existe $d ($n ficheros)"
        Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue | Select-Object FullName, Length, LastWriteTime |
            Export-Csv (Join-Path $dir ('lista_' + ($d -replace '[:\\ ()]', '_') + '.csv')) -NoTypeInformation -Encoding UTF8
    }
}
W ''

# 6) Instalador original: exe/msi/cab/appx de McAfee fuera de su carpeta de programa
W '== Posibles instaladores de McAfee en el disco =='
$skip = '^C:\\(Windows\\(WinSxS|servicing|SoftwareDistribution|Installer\\\$PatchCache\$)|Program Files\\McAfee\\wps\\[\d.]+\\vpn|Diag\\|ProgramData\\McAfee\\|Users\\All Users\\McAfee\\)'
$cand = @(Get-ChildItem 'C:\' -Recurse -File -Force -ErrorAction SilentlyContinue -Include *.exe, *.msi, *.cab, *.zip, *.appx, *.msix, *.msixbundle |
          Where-Object { $_.FullName -notmatch $skip -and $_.FullName -notlike 'C:\Program Files\McAfee\wps\*' -and $_.Length -gt 1MB -and
                         ($_.Name -match 'mcafee|mcaf|wps|mcpr|mc-|livesafe|webadvisor' -or
                          "$($_.VersionInfo.CompanyName)$($_.VersionInfo.ProductName)" -match 'McAfee') })
foreach ($c in $cand) {
    $sig = try { (Get-AuthenticodeSignature -LiteralPath $c.FullName).SignerCertificate.Subject } catch { '' }
    W ("  {0} | {1} MB | {2} | {3} | firma: {4}" -f $c.FullName, [math]::Round($c.Length/1MB, 1), $c.LastWriteTime, $c.VersionInfo.ProductName, $sig)
    if ($c.Length -lt 800MB) { [void](Copiar $c.FullName ('instaladores' + ($c.DirectoryName -replace '^C:', '' -replace '[:]', ''))) }
}
if (-not $cand.Count) { W '  ninguno encontrado fuera de C:\Program Files\McAfee' }
W ''

# 7) Ventanas de McAfee abiertas ahora (lo que el usuario ve)
W '== Procesos de McAfee en marcha =='
Get-CimInstance Win32_Process | Where-Object { "$($_.ExecutablePath)" -match 'McAfee' } |
    ForEach-Object { W ("  {0} (PID {1}) | {2}" -f $_.Name, $_.ProcessId, $_.CommandLine) }

$zip = "$dir.zip"
try {
    Compress-Archive -Path "$dir\*" -DestinationPath $zip -Force -ErrorAction Stop
    Copy-Item $zip 'C:\Users\Public\Desktop' -Force -ErrorAction SilentlyContinue
    W ''; W "Listo: $zip (y copia en el escritorio publico)"
} catch { W "No se pudo comprimir ($($_.Exception.Message)). Carpeta: $dir" }
