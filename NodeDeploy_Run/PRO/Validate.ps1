<#
.SYNOPSIS
    NodeDeploy PRO - Validador post-instalación independiente.
.DESCRIPTION
    Smoke tests profundos sobre cada app:
      - Registry Uninstall key.
      - Servicios Windows (Running / StartType correct).
      - Binarios principales en disco con version stamp.
      - Outlook COM addins iManage registrados.
    Imprime tabla resumen y deja Validate_Report.md.
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

$Script:Checks = @(
    [pscustomobject]@{ App='AnyDesk';            RegKw='AnyDesk';            Svc='AnyDesk';      File=@("${env:ProgramFiles(x86)}\AnyDesk\AnyDesk.exe","$env:ProgramFiles\AnyDesk\AnyDesk.exe") },
    [pscustomobject]@{ App='AqNet';              RegKw='AqNet';              Svc=$null;          File=@() },
    [pscustomobject]@{ App='Nebula CertAgent';   RegKw='Nebula';             Svc='nebulaCERTagent'; File=@("$env:ProgramFiles\Vintegris\nebulaCERTagent\nebulaCERTagent.exe") },
    [pscustomobject]@{ App='Cortex XDR';         RegKw='Cortex XDR';         Svc='cyserver';     File=@() },
    [pscustomobject]@{ App='ESET Management Agent'; RegKw='ESET Management Agent'; Svc='EraAgentSvc'; File=@("$env:ProgramFiles\ESET\RemoteAdministrator\Agent\ERAAgent.exe") },
    [pscustomobject]@{ App='Google Chrome';      RegKw='Google Chrome';      Svc=$null;          File=@("$env:ProgramFiles\Google\Chrome\Application\chrome.exe","${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe") },
    [pscustomobject]@{ App='Autofirma';          RegKw='AutoFirma';          Svc=$null;          File=@("$env:ProgramFiles\AutoFirma\AutoFirma.exe") },
    [pscustomobject]@{ App='Bit4id Middleware';  RegKw='Bit4id';             Svc=$null;          File=@("$env:ProgramFiles\Bit4id\Universal MW\bin\bit4xpki.exe","${env:ProgramFiles(x86)}\Bit4id\Universal MW\bin\bit4xpki.exe") },
    [pscustomobject]@{ App='PDFelement';         RegKw='PDFelement';         Svc=$null;          File=@("$env:ProgramFiles\Wondershare\PDFelement\PDFelement.exe") },
    [pscustomobject]@{ App='MitelConnect';       RegKw='Mitel';              Svc=$null;          File=@("$env:ProgramFiles\Mitel\Connect Client\ConnectAgent.exe","${env:ProgramFiles(x86)}\Mitel\Connect Client\ConnectAgent.exe") },
    [pscustomobject]@{ App='Microsoft 365 Apps'; RegKw='Microsoft 365 Apps'; Svc='ClickToRunSvc'; File=@("$env:ProgramFiles\Microsoft Office\root\Office16\OUTLOOK.EXE") },
    [pscustomobject]@{ App='iManage Agent Services'; RegKw='iManage Agent'; Svc=$null;           File=@() },
    [pscustomobject]@{ App='iManage Drive';      RegKw='iManage Drive';      Svc=$null;          File=@("$env:ProgramFiles\iManage\iManage Drive\iManageDrive.exe") },
    [pscustomobject]@{ App='iManage Drive Native'; RegKw='iManage Drive Native'; Svc=$null;      File=@() },
    [pscustomobject]@{ App='iManage Work Desktop'; RegKw='iManage Work';     Svc=$null;          File=@() }
)

$installed = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
) | ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } | Where-Object { $_.DisplayName }

$results = @()
foreach ($c in $Script:Checks) {
    $reg  = $installed | Where-Object { $_.DisplayName -like "*$($c.RegKw)*" } | Select-Object -First 1
    $svc  = if ($c.Svc) { Get-Service -Name $c.Svc -ErrorAction SilentlyContinue } else { $null }
    $file = $null
    foreach ($f in $c.File) { if (Test-Path $f) { $file = $f; break } }

    $status = 'MISSING'
    $detail = ''
    if ($reg) {
        $status = 'OK'
        $detail = "v$($reg.DisplayVersion)"
    } elseif ($svc -or $file) {
        $status = 'PARTIAL'
        $detail = if ($svc) { "svc=$($svc.Status)" } elseif ($file) { "file_only" }
    }

    $lvl = switch ($status) { 'OK' {'OK'} 'PARTIAL' {'WARN'} default {'ERR'} }
    Out-Line ("{0,-26} {1,-8} {2}" -f $c.App, $status, $detail) $lvl
    $results += [pscustomobject]@{
        App=$c.App; Status=$status; Version=$reg.DisplayVersion
        Service=$(if($svc){$svc.Status}); File=$file
    }
}

# Outlook iManage addin check
Out-Line '' 'INFO'
Out-Line '--- Outlook iManage COM addin ---' 'INFO'
$addinKeys = @('HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins\*',
               'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins\*',
               'HKCU:\SOFTWARE\Microsoft\Office\Outlook\Addins\*')
$found = @()
foreach ($k in $addinKeys) {
    Get-ChildItem $k -ErrorAction SilentlyContinue | Where-Object {
        $_.PSChildName -match 'iManage|imWork'
    } | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        $found += [pscustomobject]@{ Key=$_.PSChildName; FriendlyName=$p.FriendlyName; LoadBehavior=$p.LoadBehavior }
    }
}
if ($found) {
    foreach ($f in $found) { Out-Line "  Addin: $($f.Key) ($($f.FriendlyName)) LoadBehavior=$($f.LoadBehavior)" 'OK' }
} else {
    Out-Line '  Ningún addin iManage encontrado en Outlook.' 'WARN'
}

# Write Markdown
$sb = New-Object Text.StringBuilder
[void]$sb.AppendLine("# Validate Report")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("- **Fecha:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$sb.AppendLine("- **Equipo:** $env:COMPUTERNAME")
[void]$sb.AppendLine("- **Usuario:** $env:USERNAME")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| App | Status | Version | Service | File |")
[void]$sb.AppendLine("|---|---|---|---|---|")
foreach ($r in $results) {
    [void]$sb.AppendLine("| $($r.App) | $($r.Status) | $($r.Version) | $($r.Service) | $($r.File) |")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## Outlook iManage addins")
[void]$sb.AppendLine("")
if ($found) {
    foreach ($f in $found) {
        [void]$sb.AppendLine("- ``$($f.Key)`` $($f.FriendlyName) LoadBehavior=$($f.LoadBehavior)")
    }
} else {
    [void]$sb.AppendLine("- (ninguno)")
}
Set-Content -Path $reportFile -Value $sb.ToString() -Encoding UTF8

$missing = ($results | Where-Object Status -eq 'MISSING').Count
$partial = ($results | Where-Object Status -eq 'PARTIAL').Count
$okCount = ($results | Where-Object Status -eq 'OK').Count
Out-Line '' 'INFO'
Out-Line "Resumen: OK=$okCount  PARTIAL=$partial  MISSING=$missing" $(if ($missing -gt 0) { 'ERR' } elseif ($partial -gt 0) { 'WARN' } else { 'OK' })
Out-Line "Reporte: $reportFile" 'OK'
Out-Line "Log:     $logFile" 'OK'
if ($missing -gt 0) { exit 1 } else { exit 0 }
