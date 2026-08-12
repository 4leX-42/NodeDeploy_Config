# Diag-iManageWD.ps1
# Diagnostico standalone de prerequisitos iManage Work Desktop 10.9.x
# Replica los checks internos del installer (workdesktop log).
# Uso: powershell -ExecutionPolicy Bypass -File .\Diag-iManageWD.ps1
# Salida: tabla por check + verdict final + path al ultimo workdesktop log si existe.

[CmdletBinding()]
param(
    [string]$OutFile = ''
)
if (-not $OutFile) {
    $base = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
    $OutFile = Join-Path $base ("Diag-iManageWD_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
}

$ErrorActionPreference = 'Continue'
$results = New-Object Collections.Generic.List[object]

function Add-Result {
    param([string]$Check, [string]$Status, [string]$Detail)
    $results.Add([pscustomobject]@{ Check = $Check; Status = $Status; Detail = $Detail })
}

# 1. OS / bitness
$os = Get-CimInstance Win32_OperatingSystem
Add-Result 'OS' 'INFO' "$($os.Caption) $($os.OSArchitecture) build $($os.BuildNumber)"

# 2. Reboot pendiente (iManage no es bloqueante en si pero MSI puede fallar)
$rebPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
)
$rebSig = @()
foreach ($p in $rebPaths) { if (Test-Path $p) { $rebSig += $p } }
try {
    $pfro = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop
    if ($pfro.PendingFileRenameOperations) { $rebSig += 'PendingFileRenameOperations' }
} catch {}
if ($rebSig.Count -gt 0) {
    Add-Result 'RebootPending' 'WARN' ($rebSig -join ' | ')
} else {
    Add-Result 'RebootPending' 'OK' 'sin pending'
}

# 3. Office: archivos
$o16 = "$env:ProgramFiles\Microsoft Office\root\Office16"
$o16x86 = "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16"
$officeRoot = if (Test-Path $o16) { $o16 } elseif (Test-Path $o16x86) { $o16x86 } else { $null }
if ($officeRoot) {
    Add-Result 'OfficeRoot' 'OK' $officeRoot
    foreach ($exe in 'WINWORD.EXE','OUTLOOK.EXE','EXCEL.EXE') {
        $f = Join-Path $officeRoot $exe
        if (Test-Path $f) {
            $ver = (Get-Item $f).VersionInfo.FileVersion
            Add-Result "Office.$exe" 'OK' "$f  v$ver"
        } else {
            Add-Result "Office.$exe" 'MISSING' $f
        }
    }
} else {
    Add-Result 'OfficeRoot' 'MISSING' 'ni Office16 x64 ni x86'
}

# 4. Office: ClickToRun virtual registry (lo que iManage realmente consulta)
# Ref: HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration
$c2rCfg = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
if (Test-Path $c2rCfg) {
    $cfg = Get-ItemProperty $c2rCfg
    $platform = $cfg.Platform
    $prodIds  = $cfg.ProductReleaseIds
    $verToReport = $cfg.VersionToReport
    Add-Result 'C2R.Platform' 'OK' $platform
    Add-Result 'C2R.ProductReleaseIds' 'OK' $prodIds
    Add-Result 'C2R.VersionToReport' 'OK' $verToReport
    # iManage exige Word presente en ProductReleaseIds o subscripcion completa.
    $hasWordPkg = $prodIds -match 'O365|Word|ProPlusRetail|StandardRetail|HomeBusinessRetail|HomeStudentRetail|ProfessionalRetail'
    if ($hasWordPkg) {
        Add-Result 'C2R.HasWordSku' 'OK' "match in ProductReleaseIds"
    } else {
        Add-Result 'C2R.HasWordSku' 'WARN' "ProductReleaseIds no parece incluir Word: $prodIds"
    }
} else {
    Add-Result 'C2R.Configuration' 'MISSING' "$c2rCfg ausente (Office no es ClickToRun o no esta instalado)"
}

# 5. Office: Word.Application COM ProgID (iManage tambien lo consulta)
$wordProg = 'HKLM:\SOFTWARE\Classes\Word.Application\CurVer'
$wordProgWow = 'HKLM:\SOFTWARE\WOW6432Node\Classes\Word.Application\CurVer'
$wordReg = $null
if (Test-Path $wordProg) { $wordReg = (Get-ItemProperty $wordProg).'(default)' }
elseif (Test-Path $wordProgWow) { $wordReg = (Get-ItemProperty $wordProgWow).'(default)' }
if ($wordReg) {
    Add-Result 'Word.Application.CurVer' 'OK' $wordReg
} else {
    Add-Result 'Word.Application.CurVer' 'MISSING' 'sin ProgID Word.Application (iManage fallara aqui)'
}

# 6. Office bitness check (iManage compara con su 64-bit)
# Detect Office bitness desde C2R Configuration.Platform
$officeBit = $null
if (Test-Path $c2rCfg) {
    $officeBit = (Get-ItemProperty $c2rCfg).Platform  # x86 | x64
}
# iManage Work Desktop x64 EXIGE Office x64
if ($officeBit -eq 'x64') {
    Add-Result 'Office.Bitness' 'OK' 'x64 (match iManage WD x64)'
} elseif ($officeBit -eq 'x86') {
    Add-Result 'Office.Bitness' 'FAIL' 'Office x86 - iManage WD x64 NO instalara. Reinstala Office x64 o usa iManage WD x86.'
} else {
    Add-Result 'Office.Bitness' 'WARN' "no detectado ($officeBit)"
}

# 7. iManage Agent Services (prereq)
$asReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like '*iManage Agent Services*' } | Select-Object -First 1
if ($asReg) {
    Add-Result 'iManageAgentServices' 'OK' "$($asReg.DisplayName) v$($asReg.DisplayVersion)"
} else {
    Add-Result 'iManageAgentServices' 'MISSING' 'sin entrada registry - iManage WD abortara'
}

# 8. iManage Work Desktop ya instalado?
$wdReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like '*iManage Work Desktop*' } | Select-Object DisplayName,DisplayVersion
if ($wdReg) {
    Add-Result 'iManageWorkDesktop' 'INFO' (($wdReg | ForEach-Object { "$($_.DisplayName) v$($_.DisplayVersion)" }) -join ' | ')
} else {
    Add-Result 'iManageWorkDesktop' 'INFO' 'NO instalado'
}

# 9. .NET Framework 4.x (iManage check)
$ndp = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue
if ($ndp -and $ndp.Release -ge 461808) {
    Add-Result '.NET48+' 'OK' "Release=$($ndp.Release) Version=$($ndp.Version)"
} elseif ($ndp) {
    Add-Result '.NET48+' 'WARN' "Release=$($ndp.Release) (<461808 = no es 4.7.2+)"
} else {
    Add-Result '.NET48+' 'MISSING' 'NDP\v4\Full ausente'
}

# 10. WebView2 (iManage check)
$wv2Paths = @(
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
    'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
)
$wv2 = $null
foreach ($p in $wv2Paths) {
    if (Test-Path $p) { $wv2 = (Get-ItemProperty $p).pv; break }
}
if ($wv2) {
    Add-Result 'WebView2' 'OK' "v$wv2"
} else {
    Add-Result 'WebView2' 'MISSING' 'EdgeUpdate WebView2 client key ausente'
}

# 11. Procesos Office bloqueantes
$lockProc = Get-Process -Name OUTLOOK,WINWORD,EXCEL,POWERPNT,ONENOTE -ErrorAction SilentlyContinue
if ($lockProc) {
    Add-Result 'OfficeProcs' 'WARN' (($lockProc | ForEach-Object { "$($_.ProcessName)(PID=$($_.Id))" }) -join ', ')
} else {
    Add-Result 'OfficeProcs' 'OK' 'sin Office abierto'
}

# 12. Ultimo workdesktop log
$wdLog = Get-ChildItem $env:TEMP -Filter 'workdesktop_v109_*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($wdLog) {
    Add-Result 'LastWorkDesktopLog' 'INFO' "$($wdLog.FullName) ($($wdLog.LastWriteTime))"
    $errLines = Select-String -Path $wdLog.FullName -Pattern '### ERROR ###|### WARNING ###' -SimpleMatch:$false
    if ($errLines) {
        foreach ($l in $errLines) {
            Add-Result 'LogLine' $(if ($l.Line -cmatch '### ERROR ###') { 'FAIL' } else { 'WARN' }) $l.Line.Trim()
        }
    }
} else {
    Add-Result 'LastWorkDesktopLog' 'INFO' 'sin log previo en %TEMP%'
}

# Output
$lines = New-Object Collections.Generic.List[string]
$lines.Add("=== iManage Work Desktop Prereq Diagnostic ===")
$lines.Add("Host    : $env:COMPUTERNAME")
$lines.Add("User    : $env:USERNAME")
$lines.Add("Time    : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add("")
$fmt = '{0,-30} {1,-7} {2}'
$lines.Add([string]::Format($fmt, 'Check','Status','Detail'))
$lines.Add(('-' * 100))
foreach ($r in $results) {
    $lines.Add([string]::Format($fmt, $r.Check, $r.Status, $r.Detail))
}

# Verdict
$lines.Add("")
$fails = $results | Where-Object { $_.Status -in 'FAIL','MISSING' -and $_.Check -notin 'iManageWorkDesktop','LastWorkDesktopLog','LogLine' }
if ($fails) {
    $lines.Add(">>> VERDICT: NO LISTO. Bloqueos:")
    foreach ($f in $fails) { $lines.Add("    - $($f.Check): $($f.Detail)") }
} else {
    $lines.Add(">>> VERDICT: prereqs OK. Si install sigue fallando: revisar ultimo workdesktop log o lanzar instalador con UI.")
}

$out = $lines -join [Environment]::NewLine
Write-Host $out
$out | Out-File -FilePath $OutFile -Encoding UTF8 -Force
Write-Host ""
Write-Host "Saved: $OutFile"
