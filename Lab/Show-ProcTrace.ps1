<#
.SYNOPSIS
    Resume proc_trace.csv de una prueba: que instalador lanzo cada msiexec (arbol de procesos),
    hijos de los instaladores del carril EXE y ventanas en las que Windows Installer estuvo ocupado.
.EXAMPLE
    .\Show-ProcTrace.ps1 -ResultDir .\results\20260924_190000_v5
#>
param([Parameter(Mandatory)][string]$ResultDir)

$csv = Get-ChildItem $ResultDir -Recurse -Filter 'proc_trace.csv' | Select-Object -First 1
if (-not $csv) { throw "No hay proc_trace.csv en $ResultDir" }
$rows = Import-Csv $csv.FullName
$procs = @{}
foreach ($r in ($rows | Where-Object event -eq 'start')) { $procs[[int]$r.pid] = $r }

function Get-Chain([int]$id) {
    $chain = @(); $guard = 0
    while ($procs.ContainsKey($id) -and $guard -lt 12) {
        $p = $procs[$id]; $chain += $p.name; $id = [int]$p.ppid; $guard++
    }
    return ($chain -join ' <- ')
}

"=== msiexec lanzados (cadena de padres) ==="
$rows | Where-Object { $_.event -eq 'start' -and $_.name -ieq 'msiexec.exe' } | ForEach-Object {
    "{0,5}s  {1}" -f $_.time, (Get-Chain ([int]$_.pid))
} | Select-Object -Unique

"`n=== Procesos hijos de instaladores EXE (Bit4id / PDFelement / Autofirma) ==="
$roots = $rows | Where-Object { $_.event -eq 'start' -and $_.name -match 'Bit4id|pdfelement|Autofirma' }
foreach ($root in $roots) {
    $rid = [int]$root.pid
    $kids = $rows | Where-Object { $_.event -eq 'start' -and [int]$_.ppid -eq $rid }
    "{0,5}s  {1} (PID {2}) -> {3}" -f $root.time, $root.name, $rid, (($kids | ForEach-Object { $_.name }) -join ', ')
}

"`n=== Windows Installer ocupado (mutex _MSIExecute) ==="
$busySince = $null
foreach ($r in ($rows | Where-Object event -eq 'msi')) {
    if ($r.msi_busy -eq '1' -and $null -eq $busySince) { $busySince = [int]$r.time }
    elseif ($r.msi_busy -eq '0' -and $null -ne $busySince) { "  {0,5}s -> {1,5}s ({2}s)" -f $busySince, $r.time, ([int]$r.time - $busySince); $busySince = $null }
}
if ($null -ne $busySince) { "  {0,5}s -> fin" -f $busySince }
