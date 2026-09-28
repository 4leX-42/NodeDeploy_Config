<#
    Se ejecuta DENTRO de la VM: desconfigura la hora como en un portatil de fabrica mal puesto (zona del Pacifico y
    reloj 3 dias y 5 horas atrasado) para probar que Deploy.ps1 la corrige. Resultado en C:\LabRun\clock_break.txt.
#>
$out = 'C:\LabRun\clock_break.txt'
# Marca de fin de Deploy.bat (la escribe Run-DeployBat.ps1): se borra para esperar a la nueva
Remove-Item -LiteralPath 'C:\LabRun\deploybat_result.txt' -Force -ErrorAction SilentlyContinue
$tools = Join-Path $env:ProgramFiles 'VMware\VMware Tools\VMwareToolboxCmd.exe'
if (Test-Path $tools) { & $tools timesync disable | Out-Null }   # que VMware no la corrija por su cuenta
Set-TimeZone -Id 'Pacific Standard Time'
Set-Date -Date (Get-Date).AddDays(-3).AddHours(-5) | Out-Null
"roto: zona=$((Get-TimeZone).Id) hora=$(Get-Date -Format s)" | Set-Content -Path $out -Encoding UTF8
exit 0
