<#
.SYNOPSIS
    NodeDeploy - guarda en el Escritorio (LOGS_ERRORES) los logs de una ejecucion que se corto a mitad.
.DESCRIPTION
    Deploy.ps1 deja state\en_curso.txt (ruta de su log) al empezar a instalar y lo borra al acabar. Si sigue ahi,
    la ejecucion no termino: Deploy.ps1 murio, se cerro la ventana o se apago el equipo. Lo llaman:
      - Deploy.bat, en cuanto Deploy.ps1 sale sin haber terminado;
      - Deploy.ps1, al arrancar, si lo dejo una ejecucion anterior (ventana cerrada: el .bat tampoco llego a nada).
    Zip con los logs de esa ejecucion, el estado, la copia de la consola y los eventos de Windows de esos minutos
    (cierres de Restart Manager, programas que fallan, reinicios), que es lo que explica un paron sin nada en el log.
    No es critico: nunca para nada ni cuenta como fallo. Devuelve la ruta del zip (o el motivo si no pudo).
#>
param(
    [Parameter(Mandatory)][string]$StatePath,
    [string]$Motivo = 'ejecucion cortada'
)
$ErrorActionPreference = 'Continue'
try {
    $marker = Join-Path $StatePath 'en_curso.txt'
    if (-not (Test-Path -LiteralPath $marker)) { return 'nada que guardar' }
    $log = "$(Get-Content -LiteralPath $marker -TotalCount 1 -ErrorAction SilentlyContinue)".Trim()
    # Inicio de esa ejecucion: el del nombre del log (Deploy_yyyyMMdd_HHmmss.log); si no, la fecha de la marca
    $start = (Get-Item -LiteralPath $marker).LastWriteTime
    if ($log -match 'Deploy_(\d{8}_\d{6})\.log$') { $start = [datetime]::ParseExact($matches[1], 'yyyyMMdd_HHmmss', $null) }

    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $cs   = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $os   = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $name = '{0}_{1}_{2}_CORTADO' -f $start.ToString('yyyy-MM-dd_HHmm'), $env:COMPUTERNAME, ("$($bios.SerialNumber)" -replace '[^\w-]', '')
    $tmp  = Join-Path $env:TEMP "NodeDeploy_$name"
    New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'logs') | Out-Null

    $since = $start.AddMinutes(-2)
    Get-ChildItem -LiteralPath (Join-Path $StatePath 'logs') -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $since } | ForEach-Object {
        try { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $tmp 'logs') -Force -ErrorAction Stop } catch {}
    }
    foreach ($f in (Join-Path $StatePath 'nodedeploy_state.json'), (Join-Path (Split-Path -Parent $StatePath) 'POSTVALIDATE_REPORT.md')) {
        if (Test-Path -LiteralPath $f) { Copy-Item -LiteralPath $f -Destination $tmp -Force -ErrorAction SilentlyContinue }
    }

    # Eventos de Windows desde el inicio: errores de Aplicacion, todo lo de Restart Manager y Windows Installer,
    # y en Sistema apagados/reinicios (41 corte, 1074 reinicio pedido, 6008 apagado inesperado).
    $ev = @()
    $ev += @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $since; Level = 1, 2 } -MaxEvents 200 -ErrorAction SilentlyContinue)
    $ev += @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $since; ProviderName = 'Microsoft-Windows-RestartManager', 'MsiInstaller' } -MaxEvents 300 -ErrorAction SilentlyContinue)
    $ev += @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $since; Id = 41, 1074, 6005, 6006, 6008 } -MaxEvents 50 -ErrorAction SilentlyContinue)
    $lines = @($ev | Sort-Object TimeCreated, RecordId -Unique |
        ForEach-Object { '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2} {3}: {4}' -f $_.TimeCreated, $_.LogName, $_.ProviderName, $_.Id, ("$($_.Message)" -replace '\s+', ' ') })
    if (-not $lines) { $lines = @("sin eventos de error, Restart Manager, Windows Installer ni reinicios desde $since") }
    $lines | Set-Content -LiteralPath (Join-Path $tmp 'eventos_windows.txt') -Encoding UTF8

    @("Equipo   : $env:COMPUTERNAME | $($cs.Manufacturer) $($cs.SystemFamily) $($cs.Model) | n/s $($bios.SerialNumber) | BIOS $($bios.SMBIOSBIOSVersion)",
      "Windows  : $($os.Caption) $($os.Version) | $env:PROCESSOR_ARCHITECTURE",
      "NodeDeploy: inicio $($start.ToString('yyyy-MM-dd HH:mm:ss')) | log $log",
      "Resultado: CORTADO ($Motivo)") | Set-Content -LiteralPath (Join-Path $tmp 'equipo.txt') -Encoding UTF8

    $dir = Join-Path ([Environment]::GetFolderPath('Desktop')) 'LOGS_ERRORES'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $zip = Join-Path $dir "$name.zip"
    Compress-Archive -Path (Join-Path $tmp '*') -DestinationPath $zip -Force -ErrorAction Stop
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
    return $zip
} catch { return "no se pudieron guardar: $($_.Exception.Message)" }
