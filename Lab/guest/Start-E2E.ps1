<#
    Se ejecuta DENTRO de la VM: prueba de punta a punta como el tecnico. Mueve el kit sincronizado (C:\nodedeploy)
    al Escritorio y lanza Pincha_pa_instalar.bat con doble clic (cmd /c en la carpeta), SIN -NoAutoReboot: al
    terminar bien, Deploy.ps1 deja los logs al lado de la carpeta (LOGS_preparation, sin carpeta de red en el lab),
    la carpeta se borra sola y el equipo se reinicia. Los argumentos llegan sueltos: Start-E2E.ps1 full -SkipAV -Domain no
    Resultado: C:\LabRun\deploybat_result.txt (antes del reinicio); lo demas con Get-E2E.ps1 despues.
#>
$BatArgs = if ($args) { ($args -join ' ').Trim() } else { 'full -SkipAV -Domain no' }
$run  = 'C:\LabRun'
$desk = [Environment]::GetFolderPath('Desktop')
$root = Join-Path $desk 'nodedeploy'
New-Item -ItemType Directory -Force -Path $run | Out-Null
Remove-Item -LiteralPath "$run\deploybat_result.txt", "$run\deploybat_console.txt" -Force -ErrorAction SilentlyContinue
# Estado limpio: nada de pruebas anteriores
Remove-Item -LiteralPath (Join-Path $desk 'LOGS_preparation') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $env:ProgramData 'NodeDeploy\limpieza.log'), (Join-Path $env:ProgramData 'NodeDeploy\vigilante.log') -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
Move-Item -LiteralPath 'C:\nodedeploy' -Destination $root
"inicio $(Get-Date -Format s) args=$BatArgs kit=$root" | Set-Content -Path "$run\e2e_inicio.txt" -Encoding UTF8
$sw = [Diagnostics.Stopwatch]::StartNew()
$p = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"`"$root\Pincha_pa_instalar.bat`" $BatArgs > `"$run\deploybat_console.txt`" 2>&1`"" -WorkingDirectory $root -PassThru
$null = $p.Handle; $p.WaitForExit()
"exit=$($p.ExitCode) segundos=$([int]$sw.Elapsed.TotalSeconds) args=$BatArgs carpeta_al_salir=$(Test-Path -LiteralPath $root)" | Set-Content -Path "$run\deploybat_result.txt" -Encoding UTF8
exit 0
