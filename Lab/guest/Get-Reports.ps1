<#
    Se ejecuta DENTRO de la VM: deja en C:\LabRun, con nombres fijos, los informes y los dos ultimos logs de Deploy
    (para copiarlos uno a uno al host, sin zip) y un listado de C:\LabRun.
#>
$run = 'C:\LabRun'; $root = 'C:\nodedeploy\NodeDeploy_Run'
Copy-Item -LiteralPath "$root\POSTVALIDATE_REPORT.md" -Destination "$run\rep_postvalidate.md" -Force -ErrorAction SilentlyContinue
Copy-Item -LiteralPath "$root\Validate_Report.md" -Destination "$run\rep_validate.md" -Force -ErrorAction SilentlyContinue
Copy-Item -LiteralPath "$root\state\logs\msi_AcroPro.log" -Destination "$run\rep_msi_acropro.log" -Force -ErrorAction SilentlyContinue
# Zip de logs que deja Deploy.ps1 (sin carpeta de red en el laboratorio: al lado de la carpeta de NodeDeploy)
$z = Get-ChildItem -Path 'C:\LOGS_preparation' -Recurse -Filter '*.zip' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
if ($z) { Copy-Item -LiteralPath $z.FullName -Destination "$run\rep_logs.zip" -Force; Set-Content -Path "$run\rep_logs_ruta.txt" -Value $z.FullName }
$i = 0
foreach ($l in @(Get-ChildItem "$root\state\logs" -Filter 'Deploy_*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 2)) {
    $i++; Copy-Item -LiteralPath $l.FullName -Destination "$run\rep_deploy_$i.log" -Force -ErrorAction SilentlyContinue
}
Get-ChildItem $run | Sort-Object LastWriteTime | ForEach-Object { "{0,-40} {1,12} {2}" -f $_.Name, $_.Length, $_.LastWriteTime.ToString('HH:mm:ss') } | Set-Content "$run\rep_listing.txt" -Encoding UTF8
exit 0
