<#
    Se ejecuta DENTRO de la VM. Copia incremental del repo (carpeta compartida solo lectura)
    a C:\nodedeploy, simulando el M.2 conectado al portatil.
    Por seguridad NO se copian los instaladores de antivirus/EDR (ESET, Cortex): aunque alguien
    olvide -SkipAV, en la VM no existen y NodeDeploy los marca file_not_found.
#>
param([string]$Target = 'C:\nodedeploy')
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Target)) { $Target = 'C:\nodedeploy' }
$share = '\\vmware-host\Shared Folders\nodedeploy'
$log   = 'C:\LabRun\sync.log'
New-Item -ItemType Directory -Force -Path 'C:\LabRun', $Target | Out-Null

$excludeDirs  = @('.git', '.claude', 'Lab', '_Quarantine', 'Office', 'ESET_Endpoint', 'PERSIST', '_legacy', 'state')
$avFiles      = @('eset_msi.msi', 'MDR_Windows_Andersen_8_2_x64.msi', 'epi_win_live_installer.exe', 'install_config.ini')
$excludeFiles = $avFiles + @('*.log')

$sw = [Diagnostics.Stopwatch]::StartNew()
# Sin /LOG: con /LOG robocopy abortaba con rc=16 sin escribir nada. Se captura la salida.
$rcArgs = @($share, $Target, '/MIR', '/R:2', '/W:2', '/NP', '/NFL', '/NDL', '/MT:8', '/XD') + $excludeDirs + @('/XF') + $excludeFiles
$rcOut = & robocopy @rcArgs 2>&1
$rc = $LASTEXITCODE
$rcOut | Set-Content -Path $log
"sync rc=$rc en $([int]$sw.Elapsed.TotalSeconds)s" | Add-Content -Path $log
if ($rc -ge 8) { exit $rc }

# Estado limpio de NodeDeploy en cada prueba (logs/state se regeneran)
Remove-Item (Join-Path $Target 'NodeDeploy_Run\state') -Recurse -Force -ErrorAction SilentlyContinue
foreach ($av in $avFiles) {
    Get-ChildItem $Target -Recurse -Filter $av -ErrorAction SilentlyContinue | Remove-Item -Force
}
exit 0

