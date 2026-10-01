<#
    Se ejecuta DENTRO de la VM despues de Start-E2E.ps1 (y del reinicio): deja en C:\LabRun el resumen
    (e2e_resumen.txt: reinicio, carpeta borrada, restos, logs), el zip de logs (e2e_logs.zip) y los registros
    de limpieza y vigilante.
#>
$run  = 'C:\LabRun'
$desk = [Environment]::GetFolderPath('Desktop')
$root = Join-Path $desk 'nodedeploy'
$pd   = Join-Path $env:ProgramData 'NodeDeploy'
$l = @("== E2E $(Get-Date -Format s)")
$l += "inicio: $(Get-Content "$run\e2e_inicio.txt" -ErrorAction SilentlyContinue)"
$l += "deploy: $(Get-Content "$run\deploybat_result.txt" -ErrorAction SilentlyContinue)"
$l += "ultimo arranque de Windows: $((Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('s'))"
$l += "carpeta del escritorio: $(if (Test-Path -LiteralPath $root) { "SIGUE ($(@(Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue).Count) elementos)" } else { 'borrada' })"
$l += "tarea de restos: $(if (Get-ScheduledTask -TaskName 'NodeDeployLimpieza' -ErrorAction SilentlyContinue) { 'existe' } else { 'no' })"
$l += "escritorio: $((Get-ChildItem -LiteralPath $desk -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) -join ' | ')"
$z = Get-ChildItem -Path (Join-Path $desk 'LOGS_preparation') -Recurse -Filter '*.zip' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
if ($z) { Copy-Item -LiteralPath $z.FullName -Destination "$run\e2e_logs.zip" -Force; $l += "zip de logs: $($z.FullName) ($([int]($z.Length / 1KB)) KB)" } else { $l += 'zip de logs: NO HAY' }
foreach ($n in 'limpieza.log', 'vigilante.log') {
    $l += "--- ${n}:"; $l += @(Get-Content (Join-Path $pd $n) -ErrorAction SilentlyContinue)
}
$l | Set-Content -Path "$run\e2e_resumen.txt" -Encoding UTF8
exit 0
