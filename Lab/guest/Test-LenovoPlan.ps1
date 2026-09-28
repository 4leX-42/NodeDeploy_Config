<#
    Se ejecuta DENTRO de la VM: Lenovo.ps1 en modo "solo plan" con el catalogo del ThinkPad L14 (21C1).
    No descarga ni instala nada. Comprueba el reparto (ya / al final / omitidas) y los parametros del modulo.
#>
$out = 'C:\LabRun\lenovo_plan.txt'
New-Item -ItemType Directory -Force -Path 'C:\LabRun' | Out-Null
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File 'C:\nodedeploy\NodeDeploy_Run\PRO\Lenovo.ps1' -LenovoMode run -PlanOnly -TestModel 21C1 -OutJson 'C:\LabRun\lenovo_plan.json'
$j = Get-Content 'C:\LabRun\lenovo_plan.json' -Raw | ConvertFrom-Json
$lines = @("== Lenovo plan (21C1) $(Get-Date -Format s)", "modelo: $($j.model) | pendientes: $($j.found) | $($j.seconds) s", "notas: $(@($j.notes) -join '; ')", "fallos: $(@($j.failed) -join '; ')")
$lines += '--- plan:'; $lines += @($j.plan | ForEach-Object { "  $_" })
$lines += '--- omitidas:'; $lines += @($j.skipped | ForEach-Object { "  $_" })
try { Import-Module Lenovo.Client.Update -ErrorAction Stop; $lines += "Save-LnvUpdate parametros: $(((Get-Command Save-LnvUpdate).Parameters.Keys | Where-Object { $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters }) -join ', ')" } catch { $lines += "modulo: $($_.Exception.Message)" }
$lines | Set-Content -Path $out -Encoding UTF8
exit 0
