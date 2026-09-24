# Se ejecuta DENTRO de la VM: empaqueta resultados de la ultima ejecucion de NodeDeploy.
$run = 'C:\LabRun'; $root = 'C:\nodedeploy'
New-Item -ItemType File -Path "$run\stop_trace" -Force | Out-Null   # detiene Watch-Processes
Start-Sleep -Seconds 3
$items = @("$run\deploy_console.txt", "$run\proc_trace.csv", "$run\msi_hold.log", "$root\NodeDeploy_Run\state", "$root\NodeDeploy_Run\POSTVALIDATE_REPORT.md", "$root\NodeDeploy_Run\Validate_Report.md") | Where-Object { Test-Path $_ }
Compress-Archive -Path $items -DestinationPath "$run\artifacts.zip" -Force
exit 0
