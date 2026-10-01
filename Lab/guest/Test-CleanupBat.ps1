<#
    Se ejecuta DENTRO de la VM: prueba el borrado de la carpeta por el camino real, como un doble clic en
    Pincha_pa_instalar.bat desde el Escritorio: Deploy.bat (real) -> Deploy.ps1 de mentira que deja la marca de
    borrado -> Deploy.bat copia Cleanup.ps1 (real) a %TEMP%, lo lanza y termina -> la carpeta debe desaparecer
    entera (sin restos por la consola que la usaba). Necesita en C:\LabRun: Deploy.bat, Cleanup.ps1,
    Pincha_pa_instalar.bat. Resultado en C:\LabRun\cleanup_bat_test.txt.
#>
$out  = 'C:\LabRun\cleanup_bat_test.txt'
$root = "$env:USERPROFILE\Desktop\nodedeploy_bat"
$pro  = "$root\NodeDeploy_Run\PRO"
$pd   = Join-Path $env:ProgramData 'NodeDeploy'
Remove-Item -LiteralPath (Join-Path $pd 'limpieza.log') -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $pro, "$root\NodeDeploy_Run\state", "$root\1.Node_Preparation\Sub" | Out-Null
Copy-Item -LiteralPath 'C:\LabRun\Deploy.bat', 'C:\LabRun\Cleanup.ps1' -Destination $pro -Force
Copy-Item -LiteralPath 'C:\LabRun\Pincha_pa_instalar.bat' -Destination $root -Force
1..200 | ForEach-Object { Set-Content -Path "$root\1.Node_Preparation\Sub\f$_.bin" -Value ('x' * 5000) }
# Deploy.ps1 de mentira: informe + marca de borrado (lo que hace el real al acabar con todo OK)
Set-Content -Path "$pro\Deploy.ps1" -Encoding ASCII -Value @'
param([string]$Phase, [string]$StatePath)
$sp = Convert-Path $StatePath
Set-Content -LiteralPath (Join-Path (Split-Path -Parent $sp) 'POSTVALIDATE_REPORT.md') -Value '# informe de prueba'
Set-Content -LiteralPath (Join-Path $sp 'borrar_carpeta.flag') -Value (Split-Path -Parent (Split-Path -Parent $sp)) -Encoding UTF8
exit 0
'@
Set-Content -Path "$pro\Validate.ps1" -Value 'exit 0' -Encoding ASCII

$l = @("== Cleanup por Deploy.bat $(Get-Date -Format s)")
$sw = [Diagnostics.Stopwatch]::StartNew()
# Como un doble clic: cmd /c con el directorio de trabajo en la carpeta del .bat
$p = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$root\Pincha_pa_instalar.bat`" full" -WorkingDirectory $root -WindowStyle Hidden -PassThru -Wait
$l += "Pincha_pa_instalar.bat termino en $([int]$sw.Elapsed.TotalSeconds) s (exit $($p.ExitCode))"
for ($i = 0; $i -lt 30 -and (Test-Path -LiteralPath $root); $i++) { Start-Sleep -Seconds 2 }
$state = if (Test-Path -LiteralPath $root) { "conservada: $(@(Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue).Count) elementos" } else { 'borrada' }
$l += "{0} {1} -> {2} a los {3} s" -f $(if ($state -eq 'borrada') { 'OK ' } else { 'MAL' }), $root, $state, [int]$sw.Elapsed.TotalSeconds
$task = Get-ScheduledTask -TaskName 'NodeDeployLimpieza' -ErrorAction SilentlyContinue
$l += "tarea de restos al arrancar: $(if ($task) { 'creada (MAL: quedaron restos)' } else { 'no hace falta (OK)' })"
$l += "ayudante en %TEMP%: $(if (Test-Path (Join-Path $env:TEMP 'NodeDeploy_Cleanup.ps1')) { 'presente' } else { 'no' })"
Get-Process notepad -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$l += '--- limpieza.log:'
$l += @(Get-Content (Join-Path $pd 'limpieza.log') -ErrorAction SilentlyContinue)
$l | Set-Content -Path $out -Encoding UTF8
exit 0
