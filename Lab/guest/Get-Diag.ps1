<#
    Se ejecuta DENTRO de la VM: estado de la hora, AnyDesk y la ultima ejecucion de Deploy.bat -> C:\LabRun\diag.txt.
    Copia tambien la consola de Deploy.bat aunque siga abierta (FileShare ReadWrite).
#>
param([string]$Tag = 'diag')
$Tag = $Tag.Trim()
$run = 'C:\LabRun'
$l = @("== $Tag $(Get-Date -Format s) (UTC $([DateTime]::UtcNow.ToString('s'))) zona=$((Get-TimeZone).Id)")
$w = Get-Service -Name W32Time -ErrorAction SilentlyContinue
$l += "W32Time: $($w.Status) $($w.StartType)"
$svc = Get-CimInstance Win32_Service -Filter "Name LIKE 'AnyDesk%'" -ErrorAction SilentlyContinue | Select-Object -First 1
$exe = if ($svc -and "$($svc.PathName)" -match '^\s*"([^"]+)"') { $matches[1] }
$id = if ($exe -and (Test-Path $exe)) { "$(& $exe --get-id 2>$null | Out-String)".Trim() }
$l += "AnyDesk: servicio=$($svc.Name) $($svc.State) id=$id"
$l += '--- C:\LabRun:'
$l += @(Get-ChildItem $run -File | Sort-Object LastWriteTime | Select-Object -Last 12 | ForEach-Object { "  {0,-32} {1,10} {2}" -f $_.Name, $_.Length, $_.LastWriteTime.ToString('s') })
$l += '--- Deploy logs:'
$l += @(Get-ChildItem 'C:\nodedeploy\NodeDeploy_Run\state\logs' -Filter 'Deploy_*.log' -ErrorAction SilentlyContinue | ForEach-Object { "  $($_.Name) $($_.LastWriteTime.ToString('s'))" })
$l += '--- Run-DeployBat.out.log:'
$l += @(Get-Content "$run\Run-DeployBat.out.log" -ErrorAction SilentlyContinue | Select-Object -Last 10)
$l | Set-Content -Path "$run\$Tag.txt" -Encoding UTF8
foreach ($n in 'deploybat_console.txt') {
    try {
        $fs = [IO.File]::Open("$run\$n", 'Open', 'Read', 'ReadWrite'); $sr = New-Object IO.StreamReader($fs)
        $sr.ReadToEnd() | Set-Content -Path "$run\${Tag}_console.txt" -Encoding UTF8; $sr.Close()
    } catch {}
}
exit 0
