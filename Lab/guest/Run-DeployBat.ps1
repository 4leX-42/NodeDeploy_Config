<#
    Se ejecuta DENTRO de la VM: lanza Deploy.bat entero, como el tecnico (fase, validacion final, informe),
    con los argumentos indicados. Resultados: Pack-Results.ps1 (aparte).
    Los argumentos llegan sueltos (LabCommon no admite comillas): Run-DeployBat.ps1 full -SkipAV -Domain no
#>
$BatArgs = if ($args) { ($args -join ' ').Trim() } else { 'full -SkipAV -Domain no' }
$run = 'C:\LabRun'; $root = 'C:\nodedeploy'
New-Item -ItemType Directory -Force -Path $run | Out-Null
$sw = [Diagnostics.Stopwatch]::StartNew()
# cmd /c quita la primera y la ultima comilla: la linea entera va entre un par extra.
$p = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"`"$root\NodeDeploy_Run\PRO\Deploy.bat`" $BatArgs > `"$run\deploybat_console.txt`" 2>&1`"" -PassThru -WindowStyle Hidden
$null = $p.Handle; $p.WaitForExit()
"exit=$($p.ExitCode) segundos=$([int]$sw.Elapsed.TotalSeconds) args=$BatArgs flag_reinicio=$(Test-Path "$root\NodeDeploy_Run\state\reinicio_automatico.flag")" | Set-Content -Path "$run\deploybat_result.txt" -Encoding UTF8
exit 0
