<#
    Primer inicio de sesion de la VM de laboratorio (lo lanza FirstLogonCommands desde la ISO).
    1. Sin suspension.
    2. VMware Tools en silencio y ESPERA real a que el servicio VMTools este en marcha y el
       mutex de Windows Installer libre (setup64.exe puede volver antes que su msiexec).
    3. UAC off (solo laboratorio) -> efectivo tras el reinicio.
    4. Marcador C:\lab_ready.txt y reinicio final.
#>
$ErrorActionPreference = 'Continue'
$log = 'C:\lab_firstlogon.log'
function L([string]$m) { "$(Get-Date -Format 'HH:mm:ss') $m" | Add-Content -Path $log }
function Test-MsiFree {
    $m = $null
    try {
        if (-not [Threading.Mutex]::TryOpenExisting('Global\_MSIExecute', [ref]$m)) { return $true }
        if ($m.WaitOne(0)) { $m.ReleaseMutex(); return $true }
        return $false
    } catch { return $false } finally { if ($m) { $m.Dispose() } }
}

L 'inicio'
powercfg /change standby-timeout-ac 0 | Out-Null
powercfg /change monitor-timeout-ac 0 | Out-Null
powercfg /hibernate off | Out-Null

# Tools 12.x trae un unico setup.exe (x64); versiones antiguas setup64.exe. OJO: la ISO de Windows
# tambien tiene setup.exe en la raiz -> solo se acepta junto a VMwareToolsUpgrader.exe.
$setup = Get-PSDrive -PSProvider FileSystem | ForEach-Object {
    foreach ($dir in @((Join-Path $_.Root 'vmtools'), $_.Root)) {
        if (-not (Test-Path (Join-Path $dir 'VMwareToolsUpgrader.exe'))) { continue }
        foreach ($exe in 'setup64.exe', 'setup.exe') { Join-Path $dir $exe }
    }
} | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($setup) {
    L "VMware Tools: $setup"
    $p = Start-Process -FilePath $setup -ArgumentList '/S /v"/qn REBOOT=R"' -Wait -PassThru
    L "setup64 exit $($p.ExitCode)"
    $free = 0
    for ($i = 0; $i -lt 180; $i++) {
        $svc = Get-Service -Name VMTools -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running' -and (Test-MsiFree)) { $free++ } else { $free = 0 }
        if ($free -ge 3) { break }
        Start-Sleep -Seconds 5
    }
    L "VMTools=$((Get-Service -Name VMTools -ErrorAction SilentlyContinue).Status) tras $($i * 5)s"
} else {
    L 'instalador de VMware Tools NO encontrado en ninguna unidad'
}

reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v EnableLUA /t REG_DWORD /d 0 /f | Out-Null
L 'EnableLUA=0 (efectivo tras reinicio)'
"lab-ready $(Get-Date -Format 'o')" | Set-Content -Path 'C:\lab_ready.txt'
L 'reinicio final'
shutdown /r /t 15 /c "NodeDeploy Lab: reinicio final"
