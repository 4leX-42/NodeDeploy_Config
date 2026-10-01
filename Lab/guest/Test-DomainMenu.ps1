<#
    Se ejecuta DENTRO de la VM, en la sesión con escritorio (-Interactive): dibuja la cabecera del cierre y el menú
    de dominios de Finalize.ps1 con teclas simuladas ($Script:UiKeys), para ver con una captura de pantalla cómo
    queda. Necesita en C:\LabRun: Finalize.ps1 y Dominios.txt. Resultado: C:\LabRun\domain_menu.txt.
    Teclas: abajo, abajo, "5", (pausa para la captura), arriba, Enter -> la sede 4 de la lista.
#>
. 'C:\LabRun\Finalize.ps1'
function Write-Log { param($Msg, $Level) }
$Script:UiKeys = New-Object System.Collections.Queue
function New-Key([string]$Key, [char]$Ch = [char]0) { New-Object ConsoleKeyInfo($Ch, [ConsoleKey]$Key, $false, $false, $false) }
foreach ($x in @(2500, (New-Key 'DownArrow'), 500, (New-Key 'DownArrow'), 500, (New-Key 'D5' '5'), 7000, (New-Key 'UpArrow'), 500, (New-Key 'Enter'))) { $Script:UiKeys.Enqueue($x) }
try {
    Write-UiRule 'cierre del equipo'
    Write-UiNote 'se aplica al final y solo si todas las apps quedan OK:'
    Write-UiNote 'administrador local · usuario fuera de administradores · dominio'
    $r = Read-DomainChoice -List @(Get-DomainList)
    "resultado=$r" | Set-Content -Path 'C:\LabRun\domain_menu.txt' -Encoding UTF8
} catch {
    "EXCEPCION: $($_.Exception.Message) | $($_.InvocationInfo.PositionMessage)" | Set-Content -Path 'C:\LabRun\domain_menu.txt' -Encoding UTF8
}
Start-Sleep -Seconds 10
exit 0
