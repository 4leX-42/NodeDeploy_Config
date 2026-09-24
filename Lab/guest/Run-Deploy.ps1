<#
    Se ejecuta DENTRO de la VM. Lanza NodeDeploy (v5 actual o v4 de referencia) como lo haria
    un tecnico y deja resultado + artefactos en C:\LabRun.
    Los AV/EDR (ESET, Cortex) siempre se excluyen: en la VM ni siquiera se copian sus instaladores.
#>
param(
    [ValidateSet('v5','v4')][string]$Version = 'v5',
    [string]$ExtraArgs = '',
    [string]$ExtraArgsB64 = '',  # igual que ExtraArgs pero en base64 (vmrun no admite comillas)
    [switch]$Profile,
    [int]$HoldMsiSeconds = 0     # >0: simula Windows Update reteniendo el mutex MSI al empezar
)
$ErrorActionPreference = 'Continue'
if ($ExtraArgsB64) { $ExtraArgs = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ExtraArgsB64)) }
$root = 'C:\nodedeploy'
$run  = 'C:\LabRun'
New-Item -ItemType Directory -Force -Path $run | Out-Null
Remove-Item "$run\result.json","$run\artifacts.zip","$run\deploy_console.txt","$run\proc_trace.csv","$run\stop_trace" -Force -ErrorAction SilentlyContinue

if ($Profile) {
    Start-Process -FilePath powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\Watch-Processes.ps1`" -Out `"$run\proc_trace.csv`" -StopFile `"$run\stop_trace`""
    Start-Sleep -Seconds 2
}

if ($HoldMsiSeconds -gt 0) {
    Remove-Item "$run\msi_hold.log" -Force -ErrorAction SilentlyContinue
    Start-Process -FilePath powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\Hold-MsiMutex.ps1`" -Seconds $HoldMsiSeconds"
    Start-Sleep -Seconds 3
}

$ps1 = if ($Version -eq 'v4') { "$root\NodeDeploy_Run\PRO\Deploy_v4.ps1" } else { "$root\NodeDeploy_Run\PRO\Deploy.ps1" }
$cmd = if ($Version -eq 'v4') {
    "& '$ps1' -Phase full -SkipApps 'ESET Management Agent','MDR Cortex XDR' $ExtraArgs; exit `$LASTEXITCODE"
} else {
    "& '$ps1' -Phase full -SkipAV $ExtraArgs; exit `$LASTEXITCODE"
}
$sw = [Diagnostics.Stopwatch]::StartNew()
# Sin -Wait: Start-Process -Wait espera tambien a los hijos que quedan residentes
# (OfficeC2RClient, iManageStayExec...) y el wrapper no terminaba nunca.
$p = Start-Process -FilePath powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`"" -PassThru -RedirectStandardOutput "$run\deploy_console.txt" -RedirectStandardError "$run\deploy_stderr.txt"
$null = $p.Handle   # sin esto ExitCode queda vacio con Start-Process -PassThru
$p.WaitForExit()
$sec = [int]$sw.Elapsed.TotalSeconds
if ($Profile) { New-Item -ItemType File -Path "$run\stop_trace" -Force | Out-Null; Start-Sleep -Seconds 3 }

[pscustomobject]@{
    version  = $Version
    exit     = $p.ExitCode
    seconds  = $sec
    finished = (Get-Date -Format 'o')
    extra    = $ExtraArgs
} | ConvertTo-Json | Set-Content -Path "$run\result.json" -Encoding UTF8

$items = @("$run\result.json", "$run\deploy_console.txt", "$run\deploy_stderr.txt", "$root\NodeDeploy_Run\state", "$root\NodeDeploy_Run\POSTVALIDATE_REPORT.md", "$root\NodeDeploy_Run\Validate_Report.md")
if ($Profile) { $items += "$run\proc_trace.csv" }
if ($HoldMsiSeconds -gt 0) { $items += "$run\msi_hold.log" }
$items = $items | Where-Object { Test-Path $_ }
Compress-Archive -Path $items -DestinationPath "$run\artifacts.zip" -Force
exit $p.ExitCode
