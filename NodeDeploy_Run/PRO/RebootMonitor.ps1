<#
.SYNOPSIS
    Vigilante de NodeDeploy (lo lanza Deploy.ps1, oculto, desde ProgramData\NodeDeploy).
.DESCRIPTION
    Si al terminar el despliegue siguen instalandose actualizaciones (Lenovo / Windows Update), espera a que esos
    procesos y Deploy.ps1 acaben (nunca los corta: podria estar grabandose firmware). A los -SoftMinutes le pide a
    Windows Update que pare al terminar el controlador en curso (-WuStopFile); Lenovo no se toca. Despues:
      1) carpeta del escritorio: si Deploy.ps1 la dejo marcada (todo listo salvo las actualizaciones) y estas no
         fallaron, la borra con Cleanup.ps1;
      2) reinicio: si algo lo pide (lo que ya pedia al terminar el despliegue, -Need: dominio, instaladores...; o
         Lenovo, Windows Update o Windows), reinicia con 60 s de aviso (apaga si el firmware de Lenovo lo pide).
         "shutdown /a" lo cancela. Se comprueba que shutdown.exe lo acepta; si no: reintento y tarea de SYSTEM.
    Si entretanto se lanzo otro despliegue, no hace nada (lo decide ese). Maximo 4 h.
    Registro en ProgramData\NodeDeploy\vigilante.log (y en el log del despliegue mientras exista).
    Solo ASCII: Windows PowerShell 5.1 lee los .ps1 sin BOM como ANSI.
#>
param(
    [string]$Pids,
    [string]$LenovoJson,
    [string]$WuJson,
    [string]$WuStopFile,
    [int]$WuPid = 0,
    [string]$LogFile,
    [string]$Need,
    [string]$CleanupFlag,
    [int]$SoftMinutes = 90,
    [int]$MaxHours = 4
)

$pdLog = Join-Path $env:ProgramData 'NodeDeploy\vigilante.log'
function Write-MonitorLog([string]$Msg) {
    $line = '{0} [MONITOR] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg
    foreach ($f in @($LogFile, $pdLog)) { if ($f) { try { Add-Content -LiteralPath $f -Value $line -ErrorAction Stop } catch {} } }
}

function Write-DesktopNote([string]$Msg) {
    # El tecnico lo ve aunque la carpeta de NodeDeploy ya no exista (mismo sitio que LOGS_ERRORES de Deploy.bat)
    try {
        $dir = Join-Path ([Environment]::GetFolderPath('Desktop')) 'LOGS_ERRORES'
        New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop | Out-Null
        Add-Content -LiteralPath (Join-Path $dir "$($env:COMPUTERNAME)_REINICIO.txt") -Value ('{0} | vigilante | {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg) -ErrorAction Stop
    } catch {}
}

function Invoke-CheckedShutdown([string]$Mode, [int]$Seconds, [string]$Comment) {
    # $Mode = 'r' (reiniciar) | 's' (apagar). $true si queda programado (shutdown.exe o, si no, tarea de SYSTEM).
    & shutdown.exe "/$Mode" /t $Seconds /c $Comment 2>$null; $rc = $LASTEXITCODE
    if ($rc -eq 1190) { & shutdown.exe /a 2>$null; & shutdown.exe "/$Mode" /t $Seconds /c $Comment 2>$null; $rc = $LASTEXITCODE }  # ya habia uno programado
    if ($rc -notin 0, 1115) { & shutdown.exe "/$Mode" /f /t $Seconds /c $Comment 2>$null; $rc = $LASTEXITCODE }
    Write-MonitorLog "shutdown /$Mode /t $Seconds -> codigo $rc"
    if ($rc -in 0, 1115) { return $true }
    try {
        $at = (Get-Date).AddMinutes(2)
        $a  = New-ScheduledTaskAction -Execute 'shutdown.exe' -Argument "/$Mode /f /t 0"
        Register-ScheduledTask -TaskName 'NodeDeployReinicio' -Action $a -Trigger (New-ScheduledTaskTrigger -Once -At $at) -User 'SYSTEM' -RunLevel Highest -Force -ErrorAction Stop | Out-Null
        Write-MonitorLog "shutdown.exe no lo acepto (codigo $rc): plan B, tarea NodeDeployReinicio a las $($at.ToString('HH:mm'))"
        Write-DesktopNote "shutdown.exe devolvio $rc; programada la tarea NodeDeployReinicio a las $($at.ToString('HH:mm'))"
        return $true
    } catch {
        Write-MonitorLog "no se pudo programar el reinicio (shutdown $rc; tarea: $($_.Exception.Message)): REINICIA A MANO"
        Write-DesktopNote "NO SE PUDO REINICIAR SOLO (shutdown $rc). Reinicia a mano."
        return $false
    }
}

$ids = @("$Pids" -split ',' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
Write-MonitorLog "vigilando PID $($ids -join ', ') (Windows Update para a los $SoftMinutes min; max. $MaxHours h)$(if ($Need) { "; ya pedia reinicio: $Need" })"
$start    = Get-Date
$deadline = $start.AddHours($MaxHours)
$stopSent = $false
while ((Get-Date) -lt $deadline -and @($ids | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue }).Count) {
    if (-not $stopSent -and $WuStopFile -and ((Get-Date) - $start).TotalMinutes -ge $SoftMinutes -and
        $WuPid -and (Get-Process -Id $WuPid -ErrorAction SilentlyContinue)) {
        try { Set-Content -LiteralPath $WuStopFile -Value 'parar' -Encoding ASCII -ErrorAction Stop } catch {}
        $stopSent = $true
        Write-MonitorLog "Windows Update lleva $SoftMinutes min: se le pide parar al terminar el controlador en curso"
    }
    Start-Sleep -Seconds 20
}
if (@($ids | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue }).Count) {
    Write-MonitorLog "siguen instalando tras $MaxHours h: no se borra la carpeta ni se reinicia"
    Write-DesktopNote "tras $MaxHours h siguen instalandose actualizaciones; no se reinicia solo$(if ($Need) { " (pendiente: $Need)" }). Reinicia a mano cuando terminen."
    exit 0
}
$other = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
           Where-Object { "$($_.CommandLine)" -match 'Deploy\.ps1' })
if ($other.Count) { Write-MonitorLog 'hay otro despliegue de NodeDeploy en marcha: el decide el borrado y el reinicio'; exit 0 }

# Resultado final de las actualizaciones (Deploy.ps1 solo pasa las que lanzo: sin JSON = no termino bien)
$why = @("$Need" -split ',\s*' | Where-Object { $_ }); $off = $false; $bad = @()
foreach ($j in @($LenovoJson, $WuJson) | Where-Object { $_ }) {
    $name = [IO.Path]::GetFileNameWithoutExtension($j)
    try {
        $r = Get-Content -LiteralPath $j -Raw -ErrorAction Stop | ConvertFrom-Json
        Write-MonitorLog ('{0}: {1} instaladas, {2} con fallo{3}' -f $name, @($r.installed).Count, @($r.failed).Count, $(if (@($r.failed).Count) { ": $(@($r.failed) -join '; ')" }))
        if (@($r.failed).Count) { $bad += $name }
        if (@($r.pending) -match 'REBOOT|SHUTDOWN' -or $r.reboot) { $why += $name }
        if (@($r.pending) -contains 'SHUTDOWN') { $off = $true }
    } catch { $bad += $name; Write-MonitorLog "${name}: sin resultado" }
}
foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
               'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
    if (Test-Path $k) { $why += 'Windows'; break }
}

# 1) Carpeta del escritorio (antes del reinicio)
if ($CleanupFlag -and (Test-Path -LiteralPath $CleanupFlag)) {
    $cleanup = Join-Path (Split-Path -Parent $CleanupFlag) 'Cleanup.ps1'
    if ($bad.Count) {
        Write-MonitorLog "no se borra la carpeta de NodeDeploy: fallos en $($bad -join ', ') (sus logs siguen en la carpeta)"
    } elseif (Test-Path -LiteralPath $cleanup) {
        Write-MonitorLog 'actualizaciones terminadas sin fallos: se borra la carpeta de NodeDeploy (ver limpieza.log)'
        & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $cleanup -FlagFile $CleanupFlag -NoReboot
    }
    Remove-Item -LiteralPath $CleanupFlag -Force -ErrorAction SilentlyContinue
}

# 2) Reinicio / apagado
if (-not $why) { Write-MonitorLog 'las actualizaciones terminaron y nada pide reiniciar'; exit 0 }
$why = @($why | Select-Object -Unique)
Write-MonitorLog "piden reinicio: $($why -join ', '). $(if ($off) { 'Apagado' } else { 'Reinicio' }) en 60 s (shutdown /a lo cancela)"
if ($off) {
    [void](Invoke-CheckedShutdown 's' 60 'NodeDeploy: actualizaciones terminadas. Apagado en 60 s para grabar el firmware de Lenovo; enciendelo despues. Para cancelar: shutdown /a')
} else {
    [void](Invoke-CheckedShutdown 'r' 60 'NodeDeploy: actualizaciones terminadas. Reinicio en 60 s. Para cancelar: shutdown /a')
}
exit 0
