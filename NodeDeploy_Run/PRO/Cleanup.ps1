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
param(
    [string]$FlagFile,
    [switch]$NoReboot   # el reinicio ya lo programo quien llama (Deploy.bat / vigilante): aqui solo se borra
)
# Sin -Action / -Why: Windows PowerShell 5.1 descarta los argumentos vacios ('') al llamar a un .exe y
# "-Action" sin valor impedia arrancar el script. La accion se lee de la marca de reinicio.
# v5.7.6: Deploy.bat programa el reinicio ANTES de lanzar este script (-NoReboot) y la tarea de borrado al arrancar
# se registra ANTES de empezar a borrar: si el reinicio llega a mitad (o un antivirus corta este proceso), la carpeta
# se termina de borrar en el siguiente arranque.

$log = Join-Path $env:ProgramData 'NodeDeploy\limpieza.log'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $log) | Out-Null
function Write-CleanupLog([string]$Msg) { Add-Content -LiteralPath $log -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg) }

function Test-PathNoReparse([string]$Path) {
    # True solo si NINGUN componente de la ruta (de la raiz a la hoja) es un reparse point. Asi un junction en un
    # tramo intermedio (p.ej. ...\Desktop) no puede redirigir el borrado privilegiado a otra carpeta.
    try {
        $cur = [IO.Path]::GetFullPath($Path)
        while ($cur) {
            if ((Test-Path -LiteralPath $cur) -and ((Get-Item -LiteralPath $cur -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $false }
            $parent = Split-Path -Parent $cur
            if (-not $parent -or $parent -eq $cur) { break }
            $cur = $parent
        }
        return $true
    } catch { return $false }
}

# Reinicio / apagado pendiente (linea 1 = accion, linea 2 = motivo): se lee antes de borrar la carpeta que la contiene
$Action = ''; $Why = ''
try {
    $rb = if ($FlagFile) { Join-Path (Split-Path -Parent $FlagFile) 'reinicio_automatico.flag' } else { '' }
    if ($rb -and (Test-Path -LiteralPath $rb)) { $l = @(Get-Content -LiteralPath $rb); $Action = "$($l[0])".Trim(); $Why = "$($l[1])".Trim() }
} catch {}

try {
    $folder = if ($FlagFile -and (Test-Path -LiteralPath $FlagFile)) { "$(Get-Content -LiteralPath $FlagFile -Encoding UTF8 | Select-Object -First 1)".Trim() } else { '' }
    # Normalizar y rechazar '..' (recorrido de rutas) antes de validar nada
    if ($folder) {
        if ($folder -match '(^|\\)\.\.(\\|$)') { $folder = '' } else { try { $folder = [IO.Path]::GetFullPath($folder) } catch { $folder = '' } }
    }
    # Seguridad: solo una carpeta de NodeDeploy dentro de un perfil de usuario, en un disco fijo (nunca el M.2 / USB)
    $drive = if ($folder -match '^([A-Za-z]:)') { Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($matches[1])'" -ErrorAction SilentlyContinue }
    $ok = $folder -and (Test-Path -LiteralPath (Join-Path $folder 'NodeDeploy_Run\PRO\Deploy.ps1')) -and
          $folder -match '^[A-Za-z]:\\Users\\[^\\]+\\.+' -and $drive -and $drive.DriveType -eq 3
    if (-not $ok) {
        Write-CleanupLog "no se borra (no es una carpeta de NodeDeploy en un Escritorio de un disco fijo): '$folder'"
    } else {
        Write-CleanupLog "borrando $folder"
        Start-Sleep -Seconds 5   # que Deploy.bat (y Pincha_pa_instalar.bat) terminen y suelten sus ficheros
        # No se borra si CUALQUIER componente de la ruta es un junction/symlink: borrar seguiria el enlace y
        # destruiria su destino. Un atacante local podria colar un junction en un tramo escribible (p.ej. Desktop).
        if (-not (Test-PathNoReparse $folder)) {
            Write-CleanupLog "no se borra: hay un reparse point (junction/symlink) en la ruta: '$folder'"
        } else {
            # Red de seguridad primero: si este proceso no llega al final, el siguiente arranque termina el borrado
            try {
                $a = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument ('/c rd /s /q "{0}" & schtasks /delete /tn NodeDeployLimpieza /f' -f $folder)
                Register-ScheduledTask -TaskName 'NodeDeployLimpieza' -Action $a -Trigger (New-ScheduledTaskTrigger -AtStartup) -User 'SYSTEM' -RunLevel Highest -Force -ErrorAction Stop | Out-Null
                Write-CleanupLog 'tarea de borrado al arrancar registrada (por si esto se corta)'
            } catch { Write-CleanupLog "no se pudo registrar la tarea de borrado al arrancar: $($_.Exception.Message)" }
            for ($i = 0; $i -lt 12 -and (Test-Path -LiteralPath $folder); $i++) {
                # Revalidado en CADA intento (TOCTOU): si aparece un reparse point en cualquier tramo, se corta.
                if (-not (Test-PathNoReparse $folder)) { Write-CleanupLog 'aparecio un reparse point en la ruta: se corta el borrado'; break }
                # 'cmd rd /s /q' con la ruta ENTRE COMILLAS: no sigue junctions/symlinks (ni raiz ni hijos), maneja
                # espacios, y como una ruta NTFS real no puede contener comillas no hay escape de argumento posible.
                & cmd.exe /c "rd /s /q `"$folder`"" 2>$null | Out-Null
                if (Test-Path -LiteralPath $folder) { Start-Sleep -Seconds 5 }
            }
        }
        if (Test-Path -LiteralPath $folder) {
            Write-CleanupLog 'quedaba algo en uso: se termina de borrar en el siguiente arranque (tarea NodeDeployLimpieza)'
        } else {
            Unregister-ScheduledTask -TaskName 'NodeDeployLimpieza' -Confirm:$false -ErrorAction SilentlyContinue
            Write-CleanupLog 'carpeta borrada'
        }
    }
} catch { Write-CleanupLog "error: $($_.Exception.Message)" }

if ($NoReboot) { Write-CleanupLog 'sin reinicio desde aqui (-NoReboot: ya lo programo quien me llamo)'; exit 0 }
# Compatibilidad (Deploy.bat anterior a 5.7.6): el reinicio lo hacia este script. Se comprueba el codigo.
if ($Action -in 'reiniciar', 'apagar') {
    $m = if ($Action -eq 'apagar') { 's' } else { 'r' }
    $c = if ($m -eq 's') { "NodeDeploy: apagado en 15 s para grabar el firmware de Lenovo: $Why. Enciendelo despues. Para cancelar: shutdown /a" } else { "NodeDeploy: reinicio en 15 s: $Why. Para cancelar: shutdown /a" }
    & shutdown.exe "/$m" /t 15 /c $c 2>$null; $rc = $LASTEXITCODE
    if ($rc -eq 1190) { & shutdown.exe /a 2>$null; & shutdown.exe "/$m" /t 15 /c $c 2>$null; $rc = $LASTEXITCODE }
    if ($rc -notin 0, 1115) { & shutdown.exe "/$m" /f /t 15 /c $c 2>$null; $rc = $LASTEXITCODE }
    Write-CleanupLog "$Action en 15 s ($Why): shutdown codigo $rc"
}
exit 0
