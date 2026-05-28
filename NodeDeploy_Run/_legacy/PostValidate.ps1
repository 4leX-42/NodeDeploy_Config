<#
.SYNOPSIS
    Validacion profunda post-instalacion.
.DESCRIPTION
    Confirma:
      - Cada app en registro Uninstall.
      - Servicios criticos Running.
      - Ficheros principales existen.
      - Smoke test ligero (version --query) en apps clave.
    Genera POSTVALIDATE_REPORT.md.
#>
[CmdletBinding()]
param(
    [string]$WorkDir = 'C:\Users\user\Desktop\NodeDeploy_Run'
)
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$Findings = [System.Collections.Generic.List[pscustomobject]]::new()
function Add-F {
    param([string]$Level,[string]$App,[string]$Check,[string]$Detail)
    $color = switch ($Level) { 'OK' {'Green'} 'WARN' {'Yellow'} 'FAIL' {'Red'} default {'DarkGray'} }
    Write-Host ('  [{0,-4}] {1,-26} {2,-18} {3}' -f $Level,$App,$Check,$Detail) -ForegroundColor $color
    $Findings.Add([pscustomobject]@{ Level=$Level; App=$App; Check=$Check; Detail=$Detail })
}

Write-Host ''
Write-Host '  ===== NodeDeploy POST-VALIDATE =====' -ForegroundColor Cyan
Write-Host ''

# Registry installed
$installed = @()
@(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
) | ForEach-Object {
    $installed += Get-ItemProperty $_ -ErrorAction SilentlyContinue | Where-Object DisplayName
}

# Check matrix
$apps = @(
    @{ Name='AnyDesk'; Reg=@('AnyDesk'); Svc=@('AnyDesk'); Files=@("${env:ProgramFiles(x86)}\AnyDesk\AnyDesk.exe","$env:ProgramFiles\AnyDesk\AnyDesk.exe"); Smoke=$null },
    @{ Name='AqNet'; Reg=@('AqNet','Deposito Digital'); Svc=@(); Files=@(); Smoke=$null },
    @{ Name='Nebula CertAgent'; Reg=@('Nebula','CertAgent'); Svc=@('nebulaCERTagent','nebulaCERT'); Files=@("$env:ProgramFiles\Vintegris\nebulaCERTagent\nebulaCERTagent.exe"); Smoke=$null },
    @{ Name='Cortex XDR'; Reg=@('Cortex XDR','Palo Alto','Traps'); Svc=@('cyserver','CyveraService'); Files=@(); Smoke=$null },
    @{ Name='ESET Management Agent'; Reg=@('ESET Management Agent','ESET Remote Administrator'); Svc=@('EraAgentSvc'); Files=@("$env:ProgramFiles\ESET\RemoteAdministrator\Agent\ERAAgent.exe"); Smoke=$null },
    @{ Name='Google Chrome'; Reg=@('Google Chrome'); Svc=@(); Files=@("$env:ProgramFiles\Google\Chrome\Application\chrome.exe","${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"); Smoke='--version' },
    @{ Name='AutoFirma'; Reg=@('AutoFirma','Autofirma'); Svc=@(); Files=@("$env:ProgramFiles\AutoFirma\AutoFirma.exe"); Smoke=$null },
    @{ Name='Bit4id Middleware'; Reg=@('Bit4id','Universal Middleware'); Svc=@(); Files=@("$env:ProgramFiles\Bit4id\Universal MW\bin\bit4xpki.exe","${env:ProgramFiles(x86)}\Bit4id\Universal MW\bin\bit4xpki.exe"); Smoke=$null },
    @{ Name='PDFelement Business'; Reg=@('PDFelement','Wondershare'); Svc=@(); Files=@("$env:ProgramFiles\Wondershare\PDFelement\PDFelement.exe","${env:ProgramFiles(x86)}\Wondershare\PDFelement\PDFelement.exe"); Smoke=$null },
    @{ Name='MitelConnect'; Reg=@('Mitel','MiCollab','Mitel Connect'); Svc=@(); Files=@("$env:ProgramFiles\Mitel\Connect Client\ConnectAgent.exe","${env:ProgramFiles(x86)}\Mitel\Connect Client\ConnectAgent.exe"); Smoke=$null },
    @{ Name='Microsoft 365 Apps'; Reg=@('Microsoft 365 Apps','Microsoft Office'); Svc=@(); Files=@("$env:ProgramFiles\Microsoft Office\root\Office16\OUTLOOK.EXE"); Smoke=$null },
    @{ Name='iManage Agent Services'; Reg=@('iManage Agent'); Svc=@(); Files=@(); Smoke=$null },
    @{ Name='iManage Drive'; Reg=@('iManage Drive'); Svc=@(); Files=@("$env:ProgramFiles\iManage\iManage Drive\iManageDrive.exe"); Smoke=$null },
    @{ Name='iManage Drive Native'; Reg=@('iManage Drive Native','iManageDriveNative'); Svc=@(); Files=@(); Smoke=$null },
    @{ Name='iManage Work Desktop'; Reg=@('iManage Work Desktop','iManage Work'); Svc=@(); Files=@(); Smoke=$null }
)

$totalOK = 0; $totalFail = 0
foreach ($a in $apps) {
    $found = $false
    # Registry
    foreach ($k in $a.Reg) {
        $hit = $installed | Where-Object { $_.DisplayName -like "*$k*" } | Select-Object -First 1
        if ($hit) { Add-F OK $a.Name 'Registry' "$($hit.DisplayName) $($hit.DisplayVersion)"; $found = $true; break }
    }
    if (-not $found) { Add-F FAIL $a.Name 'Registry' 'no detectado en Uninstall' }

    # Services
    foreach ($s in $a.Svc) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc) {
            if ($svc.Status -eq 'Running') { Add-F OK $a.Name "Svc:$s" 'Running' }
            else { Add-F WARN $a.Name "Svc:$s" $svc.Status }
        } else {
            Add-F WARN $a.Name "Svc:$s" 'no presente'
        }
    }

    # Files
    foreach ($f in $a.Files) {
        if (Test-Path $f) {
            $fi = Get-Item $f
            $ver = (Get-Item $f).VersionInfo.FileVersion
            Add-F OK $a.Name 'File' ("{0} v{1}" -f $fi.Name, $ver)
            $found = $true
            break
        }
    }

    # Smoke
    if ($a.Smoke) {
        foreach ($f in $a.Files) {
            if (Test-Path $f) {
                try {
                    $out = & $f $a.Smoke 2>$null
                    if ($LASTEXITCODE -eq 0 -or $out) {
                        Add-F OK $a.Name 'Smoke' ($out -join ' ' | Out-String).Trim().Substring(0,[Math]::Min(60,($out -join ' ').Length))
                    } else {
                        Add-F WARN $a.Name 'Smoke' "exit=$LASTEXITCODE"
                    }
                } catch {
                    Add-F WARN $a.Name 'Smoke' "$_"
                }
                break
            }
        }
    }

    if ($found) { $totalOK++ } else { $totalFail++ }
}

# Reboot pending check
$rebootPending = $false
$reasons = @()
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $rebootPending=$true; $reasons+='CBS' }
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $rebootPending=$true; $reasons+='WU' }
if ($rebootPending) {
    Add-F WARN '[GLOBAL]' 'PendingReboot' ($reasons -join ',')
} else {
    Add-F OK '[GLOBAL]' 'PendingReboot' 'no'
}

# Master report
$reportFile = Join-Path $WorkDir 'POSTVALIDATE_REPORT.md'
$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine('# NodeDeploy Post-Validate Report')
[void]$md.AppendLine('')
[void]$md.AppendLine("- **Fecha**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$md.AppendLine("- **Maquina**: $env:COMPUTERNAME / $env:USERNAME")
[void]$md.AppendLine('')
$ok = ($Findings | Where-Object Level -eq 'OK').Count
$wn = ($Findings | Where-Object Level -eq 'WARN').Count
$fl = ($Findings | Where-Object Level -eq 'FAIL').Count
[void]$md.AppendLine("**Resumen findings:** OK=$ok WARN=$wn FAIL=$fl")
[void]$md.AppendLine('')
[void]$md.AppendLine("**Apps detectadas OK:** $totalOK / $($apps.Count)")
[void]$md.AppendLine('')
[void]$md.AppendLine('| Level | App | Check | Detalle |')
[void]$md.AppendLine('|-------|-----|-------|---------|')
foreach ($f in $Findings) {
    [void]$md.AppendLine("| $($f.Level) | $($f.App) | $($f.Check) | $($f.Detail -replace '\|','\|') |")
}

Set-Content -Path $reportFile -Value $md.ToString() -Encoding UTF8

Write-Host ''
Write-Host "  Apps OK: $totalOK / $($apps.Count)" -ForegroundColor $(if($totalFail){'Red'}else{'Green'})
Write-Host "  Report : $reportFile" -ForegroundColor Cyan

if ($totalFail -gt 0) { exit 1 } else { exit 0 }
