<#
.SYNOPSIS
    Windows Update de NodeDeploy (proceso aparte: lo lanza Deploy.ps1 en t=0).
.DESCRIPTION
    Con el agente de Windows Update (API COM de Windows, sin módulos externos) hace lo mismo que "Descargar e instalar
    todo" de Configuración, sincronizado con el resto del despliegue:
      1) desde t=0, en paralelo a las apps: actualizaciones de software (acumulativa, seguridad, .NET, herramienta de
         eliminación de software malintencionado, Defender...). Nunca actualizaciones de características (cambio de
         versión de Windows) ni versiones preliminares;
      2) cuando Deploy.ps1 lo indica con el fichero señal (apps y Lenovo ya terminados): controladores de Windows
         Update, después de los de Lenovo para no pisarse. El firmware, solo con cargador y BitLocker en pausa.
    No reinicia: informa si hace falta; el reinicio lo hace Deploy.bat al final, después del dominio. Resultado en JSON.
#>
param(
    [ValidateSet('', 'run')][string]$WuMode = '',
    [string]$OutJson,
    [string]$SignalFile,
    [switch]$NoDrivers
)

$Script:WuBusy = -2145124330   # 0x80240016 WU_E_INSTALL_NOT_ALLOWED: otra instalacion en curso -> esperar y reintentar

function Test-WuOnACPower {
    try { $b = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction Stop | Select-Object -First 1; if ($null -ne $b) { return [bool]$b.PowerOnline } } catch {}
    try { $w = Get-CimInstance Win32_Battery -ErrorAction Stop | Select-Object -First 1; if ($w) { return ($w.BatteryStatus -eq 2) } } catch {}
    return $true
}

function Invoke-WuPhase {
    # Busca, descarga e instala un grupo de actualizaciones. Apunta resultado en $Res.
    # $Done: IDs ya instalados en esta ejecucion (hasta reiniciar Windows los sigue dando por no instalados).
    param($Session, [string]$Criteria, [string]$Label, $Res, [switch]$Drivers, $Done)
    $sr = $Session.CreateUpdateSearcher().Search($Criteria)
    $coll = New-Object -ComObject Microsoft.Update.UpdateColl
    $firmware = $false
    for ($i = 0; $i -lt $sr.Updates.Count; $i++) {
        $u = $sr.Updates.Item($i)
        if ($Done -and $Done.Contains("$($u.Identity.UpdateID)")) { continue }
        $cats = @(for ($c = 0; $c -lt $u.Categories.Count; $c++) { $u.Categories.Item($c).Name })
        if ($cats -contains 'Upgrades' -or $u.Title -match '(?i)feature update|actualizaci.n de caracter.sticas') { $Res.skipped += "$($u.Title) (cambio de version de Windows)"; continue }
        if ($u.Title -match '(?i)\bpreview\b|versi.n preliminar|vista previa') { $Res.skipped += "$($u.Title) (version preliminar)"; continue }
        if ($Drivers -and "$($u.DriverClass)" -match '(?i)firmware') {
            if (-not (Test-WuOnACPower)) { $Res.skipped += "$($u.Title) (firmware sin cargador: conectalo y relanza el script)"; continue }
            $firmware = $true
        }
        if (-not $u.EulaAccepted) { try { $u.AcceptEula() } catch {} }
        [void]$coll.Add($u)
    }
    $Res.found += $coll.Count
    if ($coll.Count -eq 0) { $Res.notes += "${Label}: nada pendiente"; return }
    if ($firmware) {
        try {
            $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
            if ("$($bl.ProtectionStatus)" -eq 'On') { Suspend-BitLocker -MountPoint $env:SystemDrive -RebootCount 1 -ErrorAction Stop | Out-Null; $Res.notes += 'BitLocker en pausa hasta el siguiente reinicio (firmware de Windows Update)' }
        } catch { $Res.notes += "BitLocker: $($_.Exception.Message)" }
    }
    # Descarga en prioridad baja (solo usa la red libre: no frena la descarga de Outlook ni la de Lenovo; en el
    # laboratorio, en prioridad normal, Outlook paso de 16 a mas de 20 min)
    $dl = $Session.CreateUpdateDownloader(); $dl.Updates = $coll
    try { $dl.Priority = 1 } catch {}
    $swp = [Diagnostics.Stopwatch]::StartNew()
    try { [void]$dl.Download() } catch { $Res.notes += "${Label} descarga: $($_.Exception.Message)" }
    $tDl = [int]$swp.Elapsed.TotalSeconds
    $ready = New-Object -ComObject Microsoft.Update.UpdateColl
    for ($i = 0; $i -lt $coll.Count; $i++) {
        $u = $coll.Item($i)
        if ($u.IsDownloaded) { [void]$ready.Add($u) } else { $Res.failed += "$($u.Title): no se pudo descargar" }
    }
    if ($ready.Count -eq 0) { return }
    # Instalacion; si Windows esta instalando otra cosa (WU_E_INSTALL_NOT_ALLOWED), se espera y se reintenta
    $inst = $Session.CreateUpdateInstaller(); $inst.Updates = $ready
    try { $inst.ForceQuiet = $true } catch {}
    $ir = $null
    $swp.Restart()
    for ($try = 1; $try -le 10 -and -not $ir; $try++) {
        try { $ir = $inst.Install() }
        catch { if ($_.Exception.HResult -eq $Script:WuBusy -and $try -lt 10) { Start-Sleep -Seconds 60 } else { $Res.failed += "${Label}: $($_.Exception.Message)"; return } }
    }
    for ($i = 0; $i -lt $ready.Count; $i++) {
        $r = $ir.GetUpdateResult($i); $t = $ready.Item($i).Title
        if ($r.ResultCode -in 2, 3) { $Res.installed += $t; if ($Done) { [void]$Done.Add("$($ready.Item($i).Identity.UpdateID)") } }
        else { $Res.failed += ("{0}: codigo {1} (0x{2:X8})" -f $t, $r.ResultCode, $r.HResult) }
    }
    if ($ir.RebootRequired) { $Res.reboot = $true }
    $Res.notes += "${Label}: $($ready.Count) (descarga $tDl s, instalacion $([int]$swp.Elapsed.TotalSeconds) s)"
}

function Invoke-WindowsUpdate {
    $sw  = [Diagnostics.Stopwatch]::StartNew()
    $res = [ordered]@{ found = 0; installed = @(); failed = @(); skipped = @(); reboot = $false; notes = @(); seconds = 0 }
    $session = New-Object -ComObject Microsoft.Update.Session
    $session.ClientApplicationID = 'NodeDeploy'
    $done = [Collections.Generic.HashSet[string]]::new()
    $soft = "IsInstalled=0 and IsHidden=0 and Type='Software' and BrowseOnly=0"
    # 1) Software, en paralelo a las apps
    Invoke-WuPhase -Session $session -Criteria $soft -Label 'software' -Res $res -Done $done
    # 2) Al terminar apps y Lenovo (fichero señal): controladores y lo que aparezca encadenado a lo ya instalado
    #    (p. ej. la plataforma de Defender tras la de seguridad)
    if ($SignalFile) {
        $deadline = (Get-Date).AddMinutes(180)
        while (-not (Test-Path $SignalFile) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 5 }
    }
    if (-not $NoDrivers) {
        Invoke-WuPhase -Session $session -Criteria "IsInstalled=0 and IsHidden=0 and Type='Driver' and BrowseOnly=0" -Label 'controladores' -Res $res -Drivers -Done $done
    }
    Invoke-WuPhase -Session $session -Criteria $soft -Label 'software (2a vuelta)' -Res $res -Done $done
    try { if ((New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired) { $res.reboot = $true } } catch {}
    $res.seconds = [int]$sw.Elapsed.TotalSeconds
    return $res
}

if ($WuMode -eq 'run') {
    $r = try { Invoke-WindowsUpdate } catch { [ordered]@{ found = 0; installed = @(); failed = @("excepcion: $($_.Exception.Message)"); skipped = @(); reboot = $false; notes = @(); seconds = 0 } }
    if ($OutJson) { $r | ConvertTo-Json -Depth 4 | Set-Content -Path $OutJson -Encoding UTF8 }
    exit 0
}
