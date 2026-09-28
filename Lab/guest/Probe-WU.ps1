<#
    Se ejecuta DENTRO de la VM: lo que Windows Update aun tiene pendiente (solo busca, no instala) -> C:\LabRun\wu_probe.txt.
#>
$out = 'C:\LabRun\wu_probe.txt'
$l = @("== Windows Update pendiente $(Get-Date -Format s)")
try {
    $s = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
    foreach ($crit in "IsInstalled=0 and IsHidden=0 and Type='Software' and BrowseOnly=0", "IsInstalled=0 and IsHidden=0 and Type='Driver' and BrowseOnly=0", "IsInstalled=0 and IsHidden=0 and BrowseOnly=1") {
        $r = $s.Search($crit)
        $l += "--- $crit : $($r.Updates.Count)"
        for ($i = 0; $i -lt $r.Updates.Count; $i++) { $l += "  $($r.Updates.Item($i).Title)" }
    }
    $l += "reinicio pendiente (WU): $((New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired)"
} catch { $l += "ERROR: $($_.Exception.Message)" }
$l | Set-Content -Path $out -Encoding UTF8
exit 0
