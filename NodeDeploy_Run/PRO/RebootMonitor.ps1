<#
.SYNOPSIS
    Vigilante de NodeDeploy (lo lanza Deploy.ps1, oculto, desde ProgramData\NodeDeploy).
.DESCRIPTION
    Si al terminar el despliegue siguen instalandose actualizaciones (Lenovo / Windows Update), espera a que esos
    procesos y Deploy.ps1 acaben (nunca los corta: podria estar grabandose firmware). Despues:
      1) carpeta del escritorio: si Deploy.ps1 la dejo marcada (todo listo salvo las actualizaciones) y estas no
         fallaron, la borra con Cleanup.ps1;
      2) reinicio: si algo lo pide (lo que ya pedia al terminar el despliegue, -Need: dominio, instaladores...; o
         Lenovo, Windows Update o Windows), reinicia con 60 s de aviso (apaga si el firmware de Lenovo lo pide).
         "shutdown /a" lo cancela.
    Si entretanto se lanzo otro despliegue, no hace nada (lo decide ese). Maximo 4 h.
    Registro en ProgramData\NodeDeploy\vigilante.log (y en el log del despliegue mientras exista).
    Solo ASCII: Windows PowerShell 5.1 lee los .ps1 sin BOM como ANSI.
#>
param(
    [string]$Pids,
    [string]$LenovoJson,
    [string]$WuJson,
    [string]$LogFile,
    [string]$Need,
    [string]$CleanupFlag,
    [int]$MaxHours = 4
)

$pdLog = Join-Path $env:ProgramData 'NodeDeploy\vigilante.log'
function Write-MonitorLog([string]$Msg) {
    $line = '{0} [MONITOR] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg
    foreach ($f in @($LogFile, $pdLog)) { if ($f) { try { Add-Content -LiteralPath $f -Value $line -ErrorAction Stop } catch {} } }
}

$ids = @("$Pids" -split ',' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
Write-MonitorLog "vigilando PID $($ids -join ', ') (max. $MaxHours h)$(if ($Need) { "; ya pedia reinicio: $Need" })"
$deadline = (Get-Date).AddHours($MaxHours)
while ((Get-Date) -lt $deadline -and @($ids | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue }).Count) { Start-Sleep -Seconds 20 }
if (@($ids | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue }).Count) {
    Write-MonitorLog "siguen instalando tras $MaxHours h: no se borra la carpeta ni se reinicia"
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
        & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $cleanup -FlagFile $CleanupFlag
    }
    Remove-Item -LiteralPath $CleanupFlag -Force -ErrorAction SilentlyContinue
}

# 2) Reinicio / apagado
if (-not $why) { Write-MonitorLog 'las actualizaciones terminaron y nada pide reiniciar'; exit 0 }
$why = @($why | Select-Object -Unique)
Write-MonitorLog "piden reinicio: $($why -join ', '). $(if ($off) { 'Apagado' } else { 'Reinicio' }) en 60 s (shutdown /a lo cancela)"
if ($off) {
    & shutdown.exe /s /t 60 /c "NodeDeploy: actualizaciones terminadas. Apagado en 60 s para grabar el firmware de Lenovo; enciendelo despues. Para cancelar: shutdown /a"
} else {
    & shutdown.exe /r /t 60 /c "NodeDeploy: actualizaciones terminadas. Reinicio en 60 s. Para cancelar: shutdown /a"
}
exit 0
