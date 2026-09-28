<#
.SYNOPSIS
    Actualizaciones de Lenovo (controladores, firmware y BIOS) con el módulo oficial Lenovo.Client.Update.

.DESCRIPTION
    Lo lanza Deploy.ps1 en segundo plano desde t=0 (proceso aparte), solo en equipos Lenovo:
      1) módulo Lenovo.Client.Update: copia local (1.Node_Preparation\Lenovo\Lenovo.Client.Update) o PowerShell Gallery;
      2) actualizaciones pendientes del modelo: solo desatendidas y críticas/recomendadas. Nunca las de reinicio
         forzado inmediato (RebootType 1, p. ej. firmware de docks);
      3) descarga todo e instala ya los controladores y apps que solo piden reinicio (tipo 0/3) y no son de red;
      4) espera a que Deploy.ps1 termine las apps (fichero señal) e instala el resto: controladores de red
         (así no corta descargas en marcha) y firmware/BIOS (tipo 5). Estos, solo con el cargador conectado
         y con BitLocker en pausa hasta el siguiente reinicio, que es cuando se graban.
    Nunca reinicia el equipo: informa de lo pendiente (REBOOT_MANDATORY / SHUTDOWN). Resultado en JSON.

    -PlanOnly: solo muestra qué haría (no descarga ni instala). -TestModel: catálogo de otro modelo (laboratorio).
#>
param(
    [ValidateSet('', 'run')][string]$LenovoMode = '',
    [string]$OutJson,
    [string]$SignalFile,
    [string]$ModuleSource,
    [switch]$NoBIOS,
    [switch]$PlanOnly,
    [string]$TestModel
)

function Test-OnACPower {
    try { $b = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction Stop | Select-Object -First 1; if ($null -ne $b) { return [bool]$b.PowerOnline } } catch {}
    try { $w = Get-CimInstance Win32_Battery -ErrorAction Stop | Select-Object -First 1; if ($w) { return ($w.BatteryStatus -eq 2) } } catch {}
    return $true   # sin batería: corriente
}

function Invoke-LenovoUpdates {
    $sw  = [Diagnostics.Stopwatch]::StartNew()
    $res = [ordered]@{ model = ''; found = 0; installed = @(); failed = @(); skipped = @(); pending = @(); notes = @(); plan = @(); seconds = 0 }
    $cs  = Get-CimInstance Win32_ComputerSystem
    if (-not $TestModel -and $cs.Manufacturer -notmatch 'LENOVO') { $res.notes += "no es un Lenovo ($($cs.Manufacturer))"; return $res }
    $res.model = if ($TestModel) { "catalogo de prueba $TestModel" } else { "$($cs.SystemFamily) ($($cs.Model))" }

    # 1) Módulo oficial de Lenovo
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $local = if ($ModuleSource) { Join-Path $ModuleSource 'Lenovo.Client.Update' } else { $null }
    if ($local -and (Test-Path $local)) { Import-Module $local -ErrorAction Stop; $res.notes += 'modulo Lenovo.Client.Update: copia local' }
    else {
        if (-not (Get-Module -ListAvailable -Name Lenovo.Client.Update)) {
            if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge [version]'2.8.5.201' })) {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
            }
            Install-Module -Name Lenovo.Client.Update -Force -Scope AllUsers -AllowClobber -ErrorAction Stop
        }
        Import-Module Lenovo.Client.Update -ErrorAction Stop
        $res.notes += "modulo Lenovo.Client.Update $((Get-Module Lenovo.Client.Update).Version)"
    }

    # 2) Pendientes del modelo y reparto (en el equipo real solo lo aplicable y no instalado; con -TestModel el
    #    catalogo entero, porque en otra maquina ningun paquete es aplicable)
    $all = if ($TestModel) { @(Get-LnvUpdate -Model $TestModel -All -ErrorAction Stop) } else { @(Get-LnvUpdate -ErrorAction Stop) }
    $res.found = $all.Count
    $isOptional = { param($u) "$($u.Severity)" -match '^(3|Optional)$' }
    $isNet      = { param($u) "$($u.Category)" -match 'Networking|Ethernet|Wireless|WLAN|WWAN|\bLAN\b' }
    $isFirm     = { param($u) "$($u.Type)" -in 'BIOS', 'Firmware' -or "$($u.RebootType)" -eq '5' }
    $cand = @()
    foreach ($u in $all) {
        if (-not $u.Installer.Unattended) { $res.skipped += "$($u.Title) (no desatendida)"; continue }
        if ("$($u.RebootType)" -eq '1')   { $res.skipped += "$($u.Title) (reinicio forzado inmediato)"; continue }
        if (& $isOptional $u)             { $res.skipped += "$($u.Title) (opcional)"; continue }
        $cand += $u
    }
    $now  = @($cand | Where-Object { -not (& $isFirm $_) -and -not (& $isNet $_) })
    $net  = @($cand | Where-Object { -not (& $isFirm $_) -and (& $isNet $_) })
    $firm = @($cand | Where-Object { & $isFirm $_ })
    if ($NoBIOS -and $firm) { foreach ($u in $firm) { $res.skipped += "$($u.Title) (-NoBIOS)" }; $firm = @() }
    $res.plan = @($now | ForEach-Object { "ya: [$($_.Type)] $($_.Title)" }) + @($net | ForEach-Object { "al final (red): $($_.Title)" }) + @($firm | ForEach-Object { "al final (firmware/BIOS): [$($_.Type)] $($_.Title)" })
    if ($PlanOnly) { $res.notes += 'solo plan: no se descarga ni instala nada'; $res.seconds = [int]$sw.Elapsed.TotalSeconds; return $res }

    # 3) Descarga de todo lo que se va a instalar
    $dl = Join-Path $env:ProgramData 'NodeDeploy\LenovoUpdates'
    New-Item -ItemType Directory -Force -Path $dl | Out-Null
    if ($cand) { $cand | Save-LnvUpdate -Path $dl -ErrorAction Continue | Out-Null }

    $install = {
        param($u)
        try {
            foreach ($x in @($u | Install-LnvUpdate -Path $dl -ErrorAction Stop)) {
                $ok = if ($x.PSObject.Properties.Name -contains 'Success') { [bool]$x.Success } else { $true }
                $pa = "$($x.PendingAction)"
                if ($ok) {
                    $res.installed += "$($u.Title)$(if ($pa -and $pa -ne 'NONE') { " [$pa]" })"
                    if ($pa -and $pa -ne 'NONE') { $res.pending += $pa }
                } else { $res.failed += "$($u.Title): $($x.FailureReason) (exit $($x.ExitCode))" }
            }
        } catch { $res.failed += "$($u.Title): $($_.Exception.Message)" }
    }

    # 4) Ya: controladores y apps (solo piden reinicio) que no son de red
    foreach ($u in $now) { & $install $u }

    # 5) Al terminar las apps: red y firmware/BIOS
    if ($SignalFile) {
        $deadline = (Get-Date).AddMinutes(120)
        while (-not (Test-Path $SignalFile) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 5 }
    }
    foreach ($u in $net) { & $install $u }
    if ($firm) {
        if (-not (Test-OnACPower)) {
            foreach ($u in $firm) { $res.skipped += "$($u.Title) (sin cargador: conectalo y relanza el script)" }
        } else {
            try {
                $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
                if ("$($bl.ProtectionStatus)" -eq 'On') {
                    Suspend-BitLocker -MountPoint $env:SystemDrive -RebootCount 1 -ErrorAction Stop | Out-Null
                    $res.notes += 'BitLocker en pausa hasta el siguiente reinicio (firmware/BIOS)'
                }
            } catch { $res.notes += "BitLocker: $($_.Exception.Message)" }
            foreach ($u in $firm) { & $install $u }
        }
    }
    $res.pending = @($res.pending | Select-Object -Unique)
    $res.seconds = [int]$sw.Elapsed.TotalSeconds
    return $res
}

if ($LenovoMode -eq 'run') {
    $r = try { Invoke-LenovoUpdates } catch { [ordered]@{ model = ''; found = 0; installed = @(); failed = @("excepcion: $($_.Exception.Message)"); skipped = @(); pending = @(); notes = @(); plan = @(); seconds = 0 } }
    if ($OutJson) { $r | ConvertTo-Json -Depth 4 | Set-Content -Path $OutJson -Encoding UTF8 }
    exit 0
}
