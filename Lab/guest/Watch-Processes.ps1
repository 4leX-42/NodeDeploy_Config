<#
    Se ejecuta DENTRO de la VM durante una prueba. Registra cada proceso nuevo (nombre, PID,
    padre, linea de comandos) y el estado del mutex _MSIExecute cada segundo. Sirve para saber
    que instaladores EXE usan Windows Installer por dentro y que hijos dejan vivos.
#>
param([string]$Out = 'C:\LabRun\proc_trace.csv', [string]$StopFile = 'C:\LabRun\stop_trace')
$seen = @{}
foreach ($p in Get-CimInstance Win32_Process) { $seen[[int]$p.ProcessId] = $true }
"time,event,pid,ppid,name,msi_busy,cmdline" | Set-Content -Path $Out -Encoding UTF8
$t0 = Get-Date
function Test-MsiBusy {
    $m = $null
    try {
        if (-not [Threading.Mutex]::TryOpenExisting('Global\_MSIExecute', [ref]$m)) { return 0 }
        if ($m.WaitOne(0)) { $m.ReleaseMutex(); return 0 }
        return 1
    } catch { return 1 } finally { if ($m) { $m.Dispose() } }
}
$lastBusy = -1
while (-not (Test-Path $StopFile)) {
    $now = [int]((Get-Date) - $t0).TotalSeconds
    $busy = Test-MsiBusy
    if ($busy -ne $lastBusy) { "$now,msi,,,,$busy," | Add-Content -Path $Out; $lastBusy = $busy }
    foreach ($p in Get-CimInstance Win32_Process) {
        $id = [int]$p.ProcessId
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id] = $true
        $cl = "$($p.CommandLine)" -replace '"', "'" -replace '(?i)(P_CERT_[A-Z_]*|PASSWORD)=\S+', '$1=***'
        if ($cl.Length -gt 300) { $cl = $cl.Substring(0, 300) }
        "$now,start,$id,$($p.ParentProcessId),$($p.Name),$busy,`"$cl`"" | Add-Content -Path $Out
    }
    Start-Sleep -Milliseconds 1000
}
