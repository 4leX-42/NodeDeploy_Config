<#
.SYNOPSIS
    Windows Update de NodeDeploy: solo controladores y firmware (BIOS). Proceso aparte (lo lanza Deploy.ps1 en t=0).
.DESCRIPTION
    Con el agente de Windows Update (API COM de Windows, sin modulos externos):
      1) desde t=0, en paralelo a las apps: solo sincroniza con Windows Update (una busqueda de software, sin
         instalar nada), para que la de controladores del final sea rapida. La de controladores NO va aqui: en el
         lab, en paralelo a las apps, tardo 12 min y bloqueo a DISM (NanaZip colgado);
      2) cuando Deploy.ps1 lo indica con el fichero senal (apps y Lenovo ya terminados, para no pisarse con los
         controladores de Lenovo): busca los controladores y el firmware, los descarga y los instala uno a uno.
         El firmware, solo con cargador y con BitLocker en pausa.
    Lo demas (acumulativa, .NET, Defender, version nueva de Windows...) NO: lo instala Windows por su cuenta
    despues. Era lo que alargaba la espera del final (~30 min) sin que se viera nada.
    Progreso en -ProgressFile, una linea ("instalando 2/5: ..."), que Deploy.ps1 ensena mientras espera.
    No reinicia: informa si hace falta; el reinicio lo hace Deploy.bat al final, despues del dominio. Resultado en JSON.
    Solo ASCII: Windows PowerShell 5.1 lee los .ps1 sin BOM como ANSI.
#>
param(
    [ValidateSet('', 'run')][string]$WuMode = '',
    [string]$OutJson,
    [string]$SignalFile,
    [string]$ProgressFile
)

$Script:WuBusy  = -2145124330   # 0x80240016 WU_E_INSTALL_NOT_ALLOWED: otra instalacion en curso -> esperar y reintentar
$Script:DrvQuery = "IsInstalled=0 and IsHidden=0 and Type='Driver'"   # tambien opcionales: solo los del hardware presente

function Set-WuProgress([string]$Text) {
    if ($ProgressFile) { try { Set-Content -LiteralPath $ProgressFile -Value $Text -Encoding UTF8 -ErrorAction Stop } catch {} }
}

function Test-WuOnACPower {
    try { $b = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction Stop | Select-Object -First 1; if ($null -ne $b) { return [bool]$b.PowerOnline } } catch {}
    try { $w = Get-CimInstance Win32_Battery -ErrorAction Stop | Select-Object -First 1; if ($w) { return ($w.BatteryStatus -eq 2) } } catch {}
    return $true
}

function Get-WuDrivers {
    param($Session)
    $sr = $Session.CreateUpdateSearcher().Search($Script:DrvQuery)
    @(for ($i = 0; $i -lt $sr.Updates.Count; $i++) {
        $u = $sr.Updates.Item($i)
        if ($u.Title -notmatch '(?i)\bpreview\b|versi.n preliminar|vista previa') { $u }
    })
}

function Save-WuDriver {
    # Descarga un controlador (si no lo estaba ya). $true = listo para instalar.
    param($Session, $Update)
    if ($Update.IsDownloaded) { return $true }
    if (-not $Update.EulaAccepted) { try { $Update.AcceptEula() } catch {} }
    $c = New-Object -ComObject Microsoft.Update.UpdateColl; [void]$c.Add($Update)
    $d = $Session.CreateUpdateDownloader(); $d.Updates = $c
    try { $d.Priority = 2 } catch {}
    try { [void]$d.Download() } catch {}
    return [bool]$Update.IsDownloaded
}

function Invoke-WindowsUpdate {
    $sw  = [Diagnostics.Stopwatch]::StartNew()
    $res = [ordered]@{ found = 0; installed = @(); failed = @(); skipped = @(); reboot = $false; notes = @(); seconds = 0 }
    $session = New-Object -ComObject Microsoft.Update.Session
    $session.ClientApplicationID = 'NodeDeploy'

    # 1) Ya, en paralelo a las apps: sincronizar (busqueda de software; no se instala nada de eso)
    Set-WuProgress 'sincronizando con Windows Update'
    $swS = [Diagnostics.Stopwatch]::StartNew()
    try {
        $soft = $session.CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0 and Type='Software' and BrowseOnly=0").Updates.Count
        $res.notes += "software pendiente: $soft (acumulativa, .NET, Defender...): no se instala aqui, lo pone Windows por su cuenta (sincronizado en $([int]$swS.Elapsed.TotalSeconds) s)"
    } catch { $res.notes += "sincronizacion: $($_.Exception.Message)" }

    # 2) Con apps y Lenovo terminados (fichero senal): controladores y firmware, uno a uno
    if ($SignalFile) {
        Set-WuProgress 'esperando a que terminen las apps y Lenovo'
        $deadline = (Get-Date).AddMinutes(180)
        while (-not (Test-Path $SignalFile) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 5 }
    }
    Set-WuProgress 'buscando controladores y firmware'
    $swB = [Diagnostics.Stopwatch]::StartNew()
    $todo = @(Get-WuDrivers -Session $session)
    $tB = [int]$swB.Elapsed.TotalSeconds
    $res.found = $todo.Count
    if (-not $todo.Count) {
        $res.notes += "controladores: nada pendiente (busqueda $tB s)"
        Set-WuProgress 'nada pendiente'
        $res.seconds = [int]$sw.Elapsed.TotalSeconds
        return $res
    }
    $swDl = [Diagnostics.Stopwatch]::StartNew()
    for ($i = 0; $i -lt $todo.Count; $i++) {
        Set-WuProgress ('descargando {0}/{1}: {2}' -f ($i + 1), $todo.Count, $todo[$i].Title)
        [void](Save-WuDriver -Session $session -Update $todo[$i])
    }
    $tDl = [int]$swDl.Elapsed.TotalSeconds
    $swIn = [Diagnostics.Stopwatch]::StartNew(); $blDone = $false
    for ($i = 0; $i -lt $todo.Count; $i++) {
        $u = $todo[$i]; $t = $u.Title
        if ("$($u.DriverClass)" -match '(?i)firmware') {
            if (-not (Test-WuOnACPower)) { $res.skipped += "$t (firmware sin cargador: conectalo y relanza el script)"; continue }
            if (-not $blDone) {
                $blDone = $true
                try {
                    $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
                    if ("$($bl.ProtectionStatus)" -eq 'On') { Suspend-BitLocker -MountPoint $env:SystemDrive -RebootCount 1 -ErrorAction Stop | Out-Null; $res.notes += 'BitLocker en pausa hasta el siguiente reinicio (firmware de Windows Update)' }
                } catch { $res.notes += "BitLocker: $($_.Exception.Message)" }
            }
        }
        Set-WuProgress ('instalando {0}/{1}: {2}' -f ($i + 1), $todo.Count, $t)
        if (-not (Save-WuDriver -Session $session -Update $u)) { $res.failed += "${t}: no se pudo descargar"; continue }
        $c = New-Object -ComObject Microsoft.Update.UpdateColl; [void]$c.Add($u)
        $inst = $session.CreateUpdateInstaller(); $inst.Updates = $c
        try { $inst.ForceQuiet = $true } catch {}
        $ir = $null; $err = $null
        # Si Windows esta instalando otra cosa (WU_E_INSTALL_NOT_ALLOWED), se espera y se reintenta (max. 5 min)
        for ($try = 1; $try -le 10 -and -not $ir; $try++) {
            try { $ir = $inst.Install() }
            catch {
                if ($_.Exception.HResult -eq $Script:WuBusy -and $try -lt 10) { Set-WuProgress ('esperando (Windows instala otra cosa) {0}/{1}: {2}' -f ($i + 1), $todo.Count, $t); Start-Sleep -Seconds 30 }
                else { $err = $_.Exception.Message; break }
            }
        }
        if (-not $ir) { $res.failed += "${t}: $err"; continue }
        $r = $ir.GetUpdateResult(0)
        if ($r.ResultCode -in 2, 3) { $res.installed += $t } else { $res.failed += ('{0}: codigo {1} (0x{2:X8})' -f $t, $r.ResultCode, $r.HResult) }
        if ($ir.RebootRequired) { $res.reboot = $true }
    }
    $res.notes += "controladores: $($todo.Count) (busqueda $tB s, descarga $tDl s, instalacion $([int]$swIn.Elapsed.TotalSeconds) s)"
    try { if ((New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired) { $res.reboot = $true } } catch {}
    Set-WuProgress ('terminado: {0} instalados, {1} con fallo' -f @($res.installed).Count, @($res.failed).Count)
    $res.seconds = [int]$sw.Elapsed.TotalSeconds
    return $res
}

if ($WuMode -eq 'run') {
    $r = try { Invoke-WindowsUpdate } catch { [ordered]@{ found = 0; installed = @(); failed = @("excepcion: $($_.Exception.Message)"); skipped = @(); reboot = $false; notes = @(); seconds = 0 } }
    if ($OutJson) { $r | ConvertTo-Json -Depth 4 | Set-Content -Path $OutJson -Encoding UTF8 }
    exit 0
}
