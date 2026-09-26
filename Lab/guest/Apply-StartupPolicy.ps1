<#
    Se ejecuta DENTRO de la VM: aplica solo el ajuste de arranque de Optimize.ps1 (Set-StartupPolicy)
    sobre la VM ya desplegada, para comprobar que sobrevive a un reinicio. Nunca en el host.
#>
$out = 'C:\LabRun\startup_apply.txt'
New-Item -ItemType Directory -Force -Path 'C:\LabRun' | Out-Null
try {
    . 'C:\nodedeploy\NodeDeploy_Run\PRO\Optimize.ps1'
    $r = Set-StartupPolicy
    ($r.GetEnumerator() | ForEach-Object { "$($_.Key) = $($_.Value)" }) | Set-Content -Path $out -Encoding UTF8
    exit 0
} catch {
    "EXCEPCION: $($_.Exception.Message)" | Set-Content -Path $out -Encoding UTF8
    exit 1
}
