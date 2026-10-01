<#
    Se ejecuta DENTRO de la VM, en la sesion con escritorio: dibuja la cabecera del cierre y el menu de dominios
    de Finalize.ps1 con teclas simuladas ($Script:UiKeys), para verlo con una captura de pantalla.
    -Scroll N: antes escribe N lineas (como la cabecera de Deploy.bat / Deploy.ps1), para que el menu salga abajo
    y la pantalla corra al dibujarlo (asi salia "Madrid" repetido en campo). -Finalize: que Finalize.ps1 usar.
    Necesita en C:\LabRun: Finalize.ps1 (o el indicado) y Dominios.txt. Resultado: C:\LabRun\domain_menu.txt.
    Teclas: abajo, (pausa para la captura), abajo, Enter -> la sede 3 de la lista.
#>
param([int]$Scroll = 0, [string]$Finalize = 'C:\LabRun\Finalize.ps1')
# Trim: el ultimo argumento llega por vmrun con un espacio al final (".ps1 " ya no es un script: lo abre el Bloc de notas)
. $Finalize.Trim()
function Write-Log { param($Msg, $Level) }
$Script:UiKeys = New-Object System.Collections.Queue
function New-Key([string]$Key, [char]$Ch = [char]0) { New-Object ConsoleKeyInfo($Ch, [ConsoleKey]$Key, $false, $false, $false) }
foreach ($x in @(1500, (New-Key 'DownArrow'), 7000, (New-Key 'DownArrow'), 500, (New-Key 'Enter'))) { $Script:UiKeys.Enqueue($x) }
try {
    for ($i = 1; $i -le $Scroll; $i++) { Write-Host ("{0:HH:mm:ss} [INFO] linea de relleno {1} (cabecera de Deploy)" -f (Get-Date), $i) }
    Write-UiRule 'cierre del equipo'
    Write-UiNote 'se aplica al final y solo si todas las apps quedan OK:'
    $r = Read-DomainChoice -List @(Get-DomainList)
    "resultado=$r ($(Split-Path -Leaf $Finalize), scroll $Scroll)" | Set-Content -Path 'C:\LabRun\domain_menu.txt' -Encoding UTF8
} catch {
    "EXCEPCION: $($_.Exception.Message) | $($_.InvocationInfo.PositionMessage)" | Set-Content -Path 'C:\LabRun\domain_menu.txt' -Encoding UTF8
}
Start-Sleep -Seconds 4
exit 0
