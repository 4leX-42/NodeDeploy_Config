<#
    Se ejecuta DENTRO de la VM: prueba Cleanup.ps1 y el borrado diferido del vigilante (RebootMonitor.ps1) con
    carpetas de mentira (no toca C:\nodedeploy). Los reinicios que programan se cancelan al momento (shutdown /a).
      1) carpeta en el Escritorio + marca de reinicio -> se borra y programa el reinicio;
      2) la misma estructura fuera de C:\Users -> NO se borra (seguridad);
      3) vigilante: espera a un proceso de "actualizaciones", Windows Update sin fallos -> borra y reinicia;
      4) vigilante: Windows Update con fallos -> NO borra, pero reinicia (lo pedia el dominio: -Need).
    Resultado en C:\LabRun\cleanup_test.txt.
#>
$out = 'C:\LabRun\cleanup_test.txt'
$pd  = Join-Path $env:ProgramData 'NodeDeploy'
# Los scripts a probar: copiados por el host a C:\LabRun (prueba rapida, sin sincronizar el kit) o los del kit
$src = if (Test-Path 'C:\LabRun\Cleanup.ps1') { 'C:\LabRun' } else { 'C:\nodedeploy\NodeDeploy_Run\PRO' }
New-Item -ItemType Directory -Force -Path $pd | Out-Null
Remove-Item -LiteralPath (Join-Path $pd 'limpieza.log'), (Join-Path $pd 'vigilante.log') -Force -ErrorAction SilentlyContinue
$helper = Join-Path $env:TEMP 'NodeDeploy_Cleanup_test.ps1'
Copy-Item -LiteralPath "$src\Cleanup.ps1" -Destination $helper -Force
Copy-Item -LiteralPath "$src\Cleanup.ps1", "$src\RebootMonitor.ps1" -Destination $pd -Force
$l = @("== Cleanup $(Get-Date -Format s)")

function New-FakeKit([string]$d) {
    New-Item -ItemType Directory -Force -Path "$d\NodeDeploy_Run\PRO", "$d\NodeDeploy_Run\state\logs", "$d\1.Node_Preparation\Sub" | Out-Null
    Set-Content -Path "$d\NodeDeploy_Run\PRO\Deploy.ps1" -Value '# prueba'
    1..50 | ForEach-Object { Set-Content -Path "$d\1.Node_Preparation\Sub\f$_.bin" -Value ('x' * 1000) }
}
function Test-Abort {
    # 0 = habia un apagado/reinicio programado y se cancela; 1116 = no habia ninguno
    & shutdown.exe /a 2>$null | Out-Null
    return $LASTEXITCODE
}
function Add-Result([string]$Name, [string]$Dir, [string]$Expect, $Abort, $ExpectAbort) {
    $state = if (Test-Path -LiteralPath $Dir) { 'conservada' } else { 'borrada' }
    $ok = $state -eq $Expect -and ($null -eq $ExpectAbort -or $Abort -eq $ExpectAbort)
    $script:l += '{0} {1}: {2} -> {3} (esperado {4}){5}' -f $(if ($ok) { 'OK ' } else { 'MAL' }), $Name, $Dir, $state, $Expect,
        $(if ($null -ne $ExpectAbort) { "; shutdown /a = $Abort (esperado $ExpectAbort)" })
}

# 1) Deploy.bat: escritorio + reinicio
$d = "$env:USERPROFILE\Desktop\nodedeploy_prueba"
New-FakeKit $d
Set-Content -Path "$d\NodeDeploy_Run\state\borrar_carpeta.flag" -Value $d -Encoding UTF8
Set-Content -Path "$d\NodeDeploy_Run\state\reinicio_automatico.flag" -Value @('reiniciar', 'prueba') -Encoding ASCII
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $helper -FlagFile "$d\NodeDeploy_Run\state\borrar_carpeta.flag"
$ab = Test-Abort
Add-Result 'deploy.bat' $d 'borrada' $ab 0

# 2) fuera de C:\Users
$d = 'C:\nodedeploy_prueba_fuera'
New-FakeKit $d
Set-Content -Path "$d\NodeDeploy_Run\state\borrar_carpeta.flag" -Value $d -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $helper -FlagFile "$d\NodeDeploy_Run\state\borrar_carpeta.flag"
$ab = Test-Abort
Add-Result 'fuera de Users' $d 'conservada' $ab 1116
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# 3 y 4) vigilante
foreach ($case in @(@{ Name = 'vigilante sin fallos'; Failed = @(); Expect = 'borrada' },
                    @{ Name = 'vigilante con fallos'; Failed = @('KB0000001: codigo 4'); Expect = 'conservada' })) {
    $d = "$env:USERPROFILE\Desktop\nodedeploy_prueba_vig"
    New-FakeKit $d
    $wu = "$d\NodeDeploy_Run\state\logs\windows_update.json"
    [ordered]@{ found = 1; installed = @('KB0000002'); failed = $case.Failed; skipped = @(); reboot = $false; notes = @(); seconds = 1 } |
        ConvertTo-Json | Set-Content -Path $wu -Encoding UTF8
    Set-Content -Path "$pd\borrar_carpeta.flag" -Value $d -Encoding UTF8
    $busy = Start-Process -FilePath powershell.exe -ArgumentList '-NoProfile -Command Start-Sleep -Seconds 25' -WindowStyle Hidden -PassThru
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$pd\RebootMonitor.ps1" -Pids "$($busy.Id)" -LogFile "$d\NodeDeploy_Run\state\logs\Deploy_prueba.log" -CleanupFlag "$pd\borrar_carpeta.flag" -WuJson $wu -Need 'union al dominio'
    $ab = Test-Abort
    Add-Result "$($case.Name) ($([int]$sw.Elapsed.TotalSeconds) s)" $d $case.Expect $ab 0
    $l += "   marca del vigilante tras la prueba: $(if (Test-Path "$pd\borrar_carpeta.flag") { 'sigue (MAL)' } else { 'borrada (OK)' })"
    Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
}

$l += '--- limpieza.log:'
$l += @(Get-Content (Join-Path $pd 'limpieza.log') -ErrorAction SilentlyContinue)
$l += '--- vigilante.log:'
$l += @(Get-Content (Join-Path $pd 'vigilante.log') -ErrorAction SilentlyContinue)
$l | Set-Content -Path $out -Encoding UTF8
exit 0
