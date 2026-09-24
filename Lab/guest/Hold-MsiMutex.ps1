<#
    Se ejecuta DENTRO de la VM. Simula "Windows Update/Vantage instalando algo": retiene el
    mutex global de Windows Installer durante N segundos. Cualquier msiexec lanzado mientras
    tanto devuelve 1618 (ERROR_INSTALL_ALREADY_RUNNING).
#>
param([int]$Seconds = 90)
$created = $false
$m = New-Object System.Threading.Mutex($true, 'Global\_MSIExecute', [ref]$created)
"$(Get-Date -Format 'HH:mm:ss') mutex _MSIExecute retenido (creado=$created) durante ${Seconds}s" | Add-Content C:\LabRun\msi_hold.log
Start-Sleep -Seconds $Seconds
$m.ReleaseMutex(); $m.Dispose()
"$(Get-Date -Format 'HH:mm:ss') mutex liberado" | Add-Content C:\LabRun\msi_hold.log
