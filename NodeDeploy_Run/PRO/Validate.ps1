<#
.SYNOPSIS
    NodeDeploy PRO v5 - Validador post-instalacion independiente.
.DESCRIPTION
    Smoke tests por app (registro Uninstall + servicio + binario), Outlook clasico + Word,
    y add-ins iManage en Outlook. Las apps que el despliegue salto a proposito (-SkipApps /
    -SkipAV, segun nodedeploy_state.json) se informan como SKIPPED, no como MISSING.
    Deja Validate_Report.md junto a NodeDeploy_Run.
#>
[CmdletBinding()]
param(
    [string]$StatePath
)

$ErrorActionPreference = 'Continue'
$Script:ScriptDir = Split-Path -Parent $PSCommandPath
if (-not $StatePath) { $StatePath = Join-Path (Split-Path -Parent $Script:ScriptDir) 'state' }
$reportFile = Join-Path (Split-Path -Parent $StatePath) 'Validate_Report.md'
$logFile    = Join-Path $StatePath ("logs\Validate_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
if (-not (Test-Path (Split-Path $logFile))) { New-Item -ItemType Directory -Path (Split-Path $logFile) -Force | Out-Null }

function Out-Line {
    param([string]$Msg, [ValidateSet('OK','WARN','ERR','INFO')]$Lvl = 'INFO')
    $color = switch ($Lvl) { 'OK' {'Green'} 'WARN' {'Yellow'} 'ERR' {'Red'} default {'Gray'} }
    $entry = "$(Get-Date -Format 'HH:mm:ss') [$Lvl] $Msg"
    Add-Content -Path $logFile -Value $entry
    Write-Host $entry -ForegroundColor $color
}

# Apps saltadas a proposito en el ultimo despliegue
$skipped = @()
$stateFile = Join-Path $StatePath 'nodedeploy_state.json'
if (Test-Path $stateFile) {
    try {
        $st = Get-Content $stateFile -Raw | ConvertFrom-Json
        $skipped = @($st.apps.PSObject.Properties | Where-Object { $_.Value.status -eq 'skipped_by_user' } | ForEach-Object { $_.Name })
    } catch {}
}

$pf = $env:ProgramFiles; $pf86 = ${env:ProgramFiles(x86)}
$Script:Checks = @(
    [pscustomobject]@{ App='AnyDesk';               RegKw='AnyDesk';               Svc='AnyDesk';         File=@("$pf86\AnyDesk\AnyDesk.exe","$pf\AnyDesk\AnyDesk.exe") },
    [pscustomobject]@{ App='AqNet';                 RegKw='AqNet';                 Svc=$null;             File=@() },
    [pscustomobject]@{ App='Nebula CertAgent';      RegKw='nebulaCERTagent';       Svc='nebulaCERTagent'; File=@("$pf\Vintegris\nebulaCERTagent\nebulaCERTagent.exe") },
    [pscustomobject]@{ App='ESET Management Agent'; RegKw='ESET Management Agent'; Svc='EraAgentSvc';     File=@("$pf\ESET\RemoteAdministrator\Agent\ERAAgent.exe") },
    [pscustomobject]@{ App='Google Chrome';         RegKw='Google Chrome';         Svc=$null;             File=@("$pf\Google\Chrome\Application\chrome.exe","$pf86\Google\Chrome\Application\chrome.exe") },
    [pscustomobject]@{ App='MitelConnect';          RegKw='Mitel Connect';         Svc=$null;             File=@("$pf\Mitel\Connect Client\ConnectAgent.exe","$pf86\Mitel\Connect Client\ConnectAgent.exe") },
    [pscustomobject]@{ App='Outlook clasico';       RegKw=$null;                   Svc='ClickToRunSvc';   File=@(); Office=$true },
    [pscustomobject]@{ App='iManage Agent Services'; RegKw='iManage Agent';        Svc=$null;             File=@() },
    [pscustomobject]@{ App='iManage Drive';         RegKw='iManage Drive';         Svc=$null;             File=@("$pf\iManage\iManage Drive\iManageDrive.exe"); Exclude='Native' },
    [pscustomobject]@{ App='iManage Drive Native';  RegKw='iManage Drive Native';  Svc=$null;             File=@() },
    [pscustomobject]@{ App='iManage Work Desktop';  RegKw='iManage Work Desktop';  Svc=$null;             File=@() },
    [pscustomobject]@{ App='MDR Cortex XDR';        RegKw='Cortex XDR';            Svc='cyserver';        File=@() },
    [pscustomobject]@{ App='Bit4id Middleware';     RegKw='Bit4id';                Svc=$null;             File=@("$pf\Bit4id\Universal MW\bin\bit4xpki.exe","$pf86\Bit4id\Universal MW\bin\bit4xpki.exe") },
    [pscustomobject]@{ App='PDFelement Business';   RegKw='PDFelement';            Svc=$null;             File=@("$pf\Wondershare\PDFelement\PDFelement.exe","$pf86\Wondershare\PDFelement\PDFelement.exe") },
    [pscustomobject]@{ App='Autofirma';             RegKw='Autofirma';             Svc=$null;             File=@("$pf\Autofirma\Autofirma\Autofirma.exe","$pf\AutoFirma\AutoFirma.exe") }
)

$installed = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
) | ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } | Where-Object { $_.DisplayName }

$results = @()
foreach ($c in $Script:Checks) {
    $status = 'MISSING'; $detail = ''; $version = $null; $svc = $null; $file = $null
    if ($c.Office) {
        $root = @("$pf\Microsoft Office\root\Office16", "$pf86\Microsoft Office\root\Office16") | Where-Object { Test-Path (Join-Path $_ 'OUTLOOK.EXE') } | Select-Object -First 1
        $word = @("$pf\Microsoft Office\root\Office16", "$pf86\Microsoft Office\root\Office16") | Where-Object { Test-Path (Join-Path $_ 'WINWORD.EXE') } | Select-Object -First 1
        $c2r  = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
        $svc  = Get-Service -Name 'ClickToRunSvc' -ErrorAction SilentlyContinue
        if ($root -and $word) { $status = 'OK'; $file = Join-Path $root 'OUTLOOK.EXE' }
        elseif ($root -or $word) { $status = 'PARTIAL' }
        $version = $c2r.VersionToReport
        $detail = "Outlook=$([bool]$root) Word=$([bool]$word) C2R=$($c2r.ProductReleaseIds) v$version"
    } else {
        $reg = $installed | Where-Object { $_.DisplayName -like "*$($c.RegKw)*" -and (-not $c.Exclude -or $_.DisplayName -notlike "*$($c.Exclude)*") } | Select-Object -First 1
        $svc = if ($c.Svc) { Get-Service -Name $c.Svc -ErrorAction SilentlyContinue } else { $null }
        foreach ($f in $c.File) { if (Test-Path $f) { $file = $f; break } }
        if ($reg) { $status = 'OK'; $version = $reg.DisplayVersion; $detail = "v$version" }
        elseif ($svc -or $file) { $status = 'PARTIAL'; $detail = if ($svc) { "svc=$($svc.Status)" } else { 'file_only' } }
    }
    if ($status -ne 'OK' -and $skipped -contains $c.App) { $status = 'SKIPPED'; $detail = 'saltada en el despliegue (-SkipApps/-SkipAV)' }

    $lvl = switch ($status) { 'OK' {'OK'} 'MISSING' {'ERR'} default {'WARN'} }
    Out-Line ("{0,-26} {1,-8} {2}" -f $c.App, $status, $detail) $lvl
    $results += [pscustomobject]@{ App=$c.App; Status=$status; Version=$version; Service=$(if ($svc) { $svc.Status }); File=$file; Detail=$detail }
}

Out-Line '' 'INFO'
Out-Line '--- Outlook: add-ins iManage ---' 'INFO'
$found = @()
foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins\*',
                 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins\*',
                 'HKCU:\SOFTWARE\Microsoft\Office\Outlook\Addins\*')) {
    Get-ChildItem $k -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match 'iManage|imWork' } | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        $found += [pscustomobject]@{ Key=$_.PSChildName; FriendlyName=$p.FriendlyName; LoadBehavior=$p.LoadBehavior }
    }
}
if ($found) { foreach ($f in $found) { Out-Line "  Addin: $($f.Key) ($($f.FriendlyName)) LoadBehavior=$($f.LoadBehavior)" 'OK' } }
else { Out-Line '  Ningun add-in iManage encontrado en Outlook.' 'WARN' }

$sb = New-Object Text.StringBuilder
[void]$sb.AppendLine('# Validate Report')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("- **Fecha:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$sb.AppendLine("- **Equipo:** $env:COMPUTERNAME")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| App | Status | Version | Service | Detalle |')
[void]$sb.AppendLine('|---|---|---|---|---|')
foreach ($r in $results) { [void]$sb.AppendLine("| $($r.App) | $($r.Status) | $($r.Version) | $($r.Service) | $($r.Detail) |") }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Outlook: add-ins iManage')
[void]$sb.AppendLine('')
if ($found) { foreach ($f in $found) { [void]$sb.AppendLine("- ``$($f.Key)`` $($f.FriendlyName) LoadBehavior=$($f.LoadBehavior)") } }
else { [void]$sb.AppendLine('- (ninguno)') }
Set-Content -Path $reportFile -Value $sb.ToString() -Encoding UTF8

$missing = @($results | Where-Object Status -eq 'MISSING').Count
$partial = @($results | Where-Object Status -eq 'PARTIAL').Count
$skip    = @($results | Where-Object Status -eq 'SKIPPED').Count
$okCount = @($results | Where-Object Status -eq 'OK').Count
Out-Line '' 'INFO'
Out-Line "Resumen: OK=$okCount  PARTIAL=$partial  MISSING=$missing  SKIPPED=$skip" $(if ($missing -gt 0) { 'ERR' } elseif ($partial -gt 0) { 'WARN' } else { 'OK' })
Out-Line "Reporte: $reportFile" 'OK'
Out-Line "Log:     $logFile" 'OK'
if ($missing -gt 0) { exit 1 } else { exit 0 }
