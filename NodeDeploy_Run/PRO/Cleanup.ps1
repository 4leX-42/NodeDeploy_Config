<#
.SYNOPSIS
    Borra la carpeta de NodeDeploy pegada en el escritorio cuando ya termino todo (scripts + ~6 GB de instaladores).
.DESCRIPTION
    Solo si Deploy.ps1 dejo la marca borrar_carpeta.flag (todo listo y la carpeta en un Escritorio). La lanzan:
      - Deploy.bat al terminar, desde una copia en %TEMP% (la carpeta no se puede borrar mientras se usa);
      - el vigilante (RebootMonitor.ps1), desde ProgramData\NodeDeploy, si al terminar seguian las actualizaciones.
    Los logs ya estan subidos (o en LOGS_preparation, fuera de la carpeta). Si hay reinicio o apagado automatico
    (reinicio_automatico.flag junto a la marca), lo hace despues de borrar. Lo que no se pueda borrar al momento
    (algo abierto) se borra en el siguiente arranque (tarea de SYSTEM). Registro: ProgramData\NodeDeploy\limpieza.log.
    Solo ASCII: Windows PowerShell 5.1 lee los .ps1 sin BOM como ANSI.
#>
param([string]$FlagFile)
# Sin -Action / -Why: Windows PowerShell 5.1 descarta los argumentos vacios ('') al llamar a un .exe y
# "-Action" sin valor impedia arrancar el script. La accion se lee de la marca de reinicio.

$log = Join-Path $env:ProgramData 'NodeDeploy\limpieza.log'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $log) | Out-Null
function Write-CleanupLog([string]$Msg) { Add-Content -LiteralPath $log -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg) }

# Reinicio / apagado pendiente (linea 1 = accion, linea 2 = motivo): se lee antes de borrar la carpeta que la contiene
$Action = ''; $Why = ''
try {
    $rb = if ($FlagFile) { Join-Path (Split-Path -Parent $FlagFile) 'reinicio_automatico.flag' } else { '' }
    if ($rb -and (Test-Path -LiteralPath $rb)) { $l = @(Get-Content -LiteralPath $rb); $Action = "$($l[0])".Trim(); $Why = "$($l[1])".Trim() }
} catch {}

try {
    $folder = if ($FlagFile -and (Test-Path -LiteralPath $FlagFile)) { "$(Get-Content -LiteralPath $FlagFile -Encoding UTF8 | Select-Object -First 1)".Trim() } else { '' }
    # Seguridad: solo una carpeta de NodeDeploy dentro de un perfil de usuario, en un disco fijo (nunca el M.2 / USB)
    $drive = if ($folder -match '^([A-Za-z]:)') { Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($matches[1])'" -ErrorAction SilentlyContinue }
    $ok = $folder -and (Test-Path -LiteralPath (Join-Path $folder 'NodeDeploy_Run\PRO\Deploy.ps1')) -and
          $folder -match '^[A-Za-z]:\\Users\\[^\\]+\\.+' -and $drive -and $drive.DriveType -eq 3
    if (-not $ok) {
        Write-CleanupLog "no se borra (no es una carpeta de NodeDeploy en un Escritorio de un disco fijo): '$folder'"
    } else {
        Write-CleanupLog "borrando $folder"
        Start-Sleep -Seconds 5   # que Deploy.bat (y Pincha_pa_instalar.bat) terminen y suelten sus ficheros
        for ($i = 0; $i -lt 12 -and (Test-Path -LiteralPath $folder); $i++) {
            & cmd.exe /c rd /s /q $folder 2>$null | Out-Null
            if (Test-Path -LiteralPath $folder) { Start-Sleep -Seconds 5 }
        }
        if (Test-Path -LiteralPath $folder) {
            $a = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument ('/c rd /s /q "{0}" & schtasks /delete /tn NodeDeployLimpieza /f' -f $folder)
            Register-ScheduledTask -TaskName 'NodeDeployLimpieza' -Action $a -Trigger (New-ScheduledTaskTrigger -AtStartup) -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
            Write-CleanupLog 'quedaba algo en uso: se termina de borrar en el siguiente arranque'
        } else {
            Write-CleanupLog 'carpeta borrada'
        }
    }
} catch { Write-CleanupLog "error: $($_.Exception.Message)" }

if ($Action -eq 'reiniciar') {
    Write-CleanupLog "reinicio en 15 s: $Why"
    & shutdown.exe /r /t 15 /c "NodeDeploy: reinicio en 15 s: $Why. Para cancelar: shutdown /a"
} elseif ($Action -eq 'apagar') {
    Write-CleanupLog "apagado en 15 s: $Why"
    & shutdown.exe /s /t 15 /c "NodeDeploy: apagado en 15 s para grabar el firmware de Lenovo: $Why. Enciendelo despues. Para cancelar: shutdown /a"
}
exit 0
