<#
.SYNOPSIS
    NodeDeploy Preflight - validacion pre-instalacion.
.DESCRIPTION
    Pre-checks no destructivos sobre el entorno antes del despliegue.
    Genera PREFLIGHT_REPORT.md y devuelve:
      0 = todo OK
      1 = warnings (deploy puede continuar con cuidado)
      2 = fatal (deploy NO debe ejecutarse)
.NOTES
    Disenado para correr standalone (no requiere NodeDeploy.ps1).
#>
[CmdletBinding()]
param(
    [string]$Source     = 'C:\Users\user\Desktop\1.Node_Preparation',
    [string]$WorkDir    = 'C:\Users\user\Desktop\NodeDeploy_Run',
    [switch]$SkipNet
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

# ----- Report buffer -----
$Report = [System.Collections.Generic.List[string]]::new()
$Findings = [System.Collections.Generic.List[pscustomobject]]::new()

function Add-Finding {
    param(
        [ValidateSet('OK','WARN','FAIL','INFO')][string]$Level,
        [string]$Area,
        [string]$Msg
    )
    $color = switch ($Level) { 'OK' {'Green'} 'WARN' {'Yellow'} 'FAIL' {'Red'} default {'DarkGray'} }
    Write-Host ('  [{0,-4}] {1,-22} {2}' -f $Level,$Area,$Msg) -ForegroundColor $color
    $Findings.Add([pscustomobject]@{ Level=$Level; Area=$Area; Msg=$Msg })
}

Write-Host ''
Write-Host '  ===== NodeDeploy PREFLIGHT =====' -ForegroundColor Cyan
Write-Host "  Source : $Source"
Write-Host "  Workdir: $WorkDir"
Write-Host ''

# 1. ADMIN
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) { Add-Finding OK   'Admin'         'Sesion elevada' }
else          { Add-Finding FAIL 'Admin'         'NO eres admin. Relanzar como administrador.' }

# 2. OS
$os = Get-CimInstance Win32_OperatingSystem
Add-Finding INFO 'OS' ("{0} {1} ({2})" -f $os.Caption, $os.Version, $os.OSArchitecture)
if ($os.Version -lt [version]'10.0.17763') {
    Add-Finding FAIL 'OS' 'Windows < 10 1809. No soportado por algunas apps (Cortex/iManage).'
}

# 3. PowerShell
Add-Finding INFO 'PowerShell' ("v{0}" -f $PSVersionTable.PSVersion)
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Add-Finding FAIL 'PowerShell' 'PowerShell < 5.0 no soportado.'
}

# 4. .NET
try {
    $netRel = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction Stop).Release
    if ($netRel -lt 461808) {
        Add-Finding WARN '.NET' "Release=$netRel (<4.7.2). Algunos installers pueden requerir update."
    } else {
        Add-Finding OK '.NET' "Release=$netRel (>=4.7.2)"
    }
} catch {
    Add-Finding WARN '.NET' '.NET Framework v4 no detectado.'
}

# 5. Disco
$drv = Get-PSDrive C
$freeGB = [Math]::Round($drv.Free/1GB,1)
if ($freeGB -lt 10) {
    Add-Finding FAIL 'Disco' "Solo $freeGB GB libres. Minimo 10 GB."
} elseif ($freeGB -lt 20) {
    Add-Finding WARN 'Disco' "$freeGB GB libres. Recomendado >20 GB."
} else {
    Add-Finding OK 'Disco' "$freeGB GB libres."
}

# 6. Pending reboot
$pending = $false
$reasons = @()
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
    $pending = $true; $reasons += 'CBS RebootPending'
}
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
    $pending = $true; $reasons += 'WindowsUpdate RebootRequired'
}
try {
    $pfo = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction Stop
    if ($pfo.PendingFileRenameOperations) { $pending = $true; $reasons += 'PendingFileRenameOperations' }
} catch {}
if ($pending) {
    Add-Finding WARN 'PendingReboot' ("Pendiente: " + ($reasons -join ', '))
} else {
    Add-Finding OK 'PendingReboot' 'Sin reinicios pendientes.'
}

# 7. Engine NodeDeploy.ps1
$engine = Join-Path $Source 'Sc3.0\NodeDeploy.ps1'
if (Test-Path $engine) {
    $sz = [Math]::Round((Get-Item $engine).Length/1KB,1)
    Add-Finding OK 'Engine' "NodeDeploy.ps1 presente ($sz KB)"
} else {
    Add-Finding FAIL 'Engine' "Engine no existe: $engine"
}

# 8. configuration.xml
$xml = Join-Path $Source 'Sc3.0\configuration.xml'
if (Test-Path $xml) {
    Add-Finding OK 'Office XML' 'configuration.xml presente.'
} else {
    Add-Finding FAIL 'Office XML' "Falta: $xml"
}

# 9. Instaladores (15)
$expected = @(
    @{ Name='AnyDesk';                  Rel='AnyDesk.msi' },
    @{ Name='AqNet';                    Rel='AqNetInstalacion.msi' },
    @{ Name='Nebula CertAgent';         Rel='nebula-certAgent-winx64-5.0.0.msi' },
    @{ Name='MDR / Cortex XDR';         Rel='MDR_Windows_Andersen_8_2_x64.msi' },
    @{ Name='ESET Mgmt Agent';          Rel='eset_msi.msi' },
    @{ Name='Google Chrome';            Rel='ChromeSetup.exe' },
    @{ Name='Autofirma';                Rel='Autofirma_64_v1_9_installer.exe' },
    @{ Name='Bit4id Middleware';        Rel='Bit4id_Middleware.exe' },
    @{ Name='PDFelement Business';      Rel='pdfelement_business-15066_10.1.5.exe' },
    @{ Name='MitelConnect';             Rel='MitelConnect.exe' },
    @{ Name='Microsoft 365 Apps';       Rel='OfficeSetup.exe' },
    @{ Name='iManage Agent Services';   Rel='Imanage 2.0\iManage Work Desktop for Windows 10.9.4.39 (x64 Office)\iManageAgentServices.exe' },
    @{ Name='iManage Drive';            Rel='Imanage 2.0\iManage Drive for Windows 10.10.0.410\iManage Drive for Windows 10.10.0.410\iManageDriveSetup.exe' },
    @{ Name='iManage Drive Native';     Rel='Imanage 2.0\iManage Drive for Windows 10.10.0.410\iManageDrive Native 10.6.1.15\iManageDriveNative.exe' },
    @{ Name='iManage Work Desktop';     Rel='Imanage 2.0\iManage Work Desktop for Windows 10.9.4.39 (x64 Office)\iManageWorkDesktopforWindowsx64.exe' }
)
$invList = [System.Collections.Generic.List[pscustomobject]]::new()
$missing = 0
foreach ($e in $expected) {
    $p = Join-Path $Source $e.Rel
    if (Test-Path $p) {
        $f = Get-Item $p
        $sig = (Get-AuthenticodeSignature -FilePath $p -ErrorAction SilentlyContinue)
        $sigStatus = if ($sig) { $sig.Status } else { 'unknown' }
        $sigSubj = if ($sig -and $sig.SignerCertificate) { ($sig.SignerCertificate.Subject -replace 'CN=','' -replace ',.*$','').Trim() } else { '-' }
        $hash = (Get-FileHash -Path $p -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
        if (-not $hash) { $hash = 'n/a' }
        $invList.Add([pscustomobject]@{
            App=$e.Name; File=$e.Rel; MB=[Math]::Round($f.Length/1MB,1); SigStatus=$sigStatus; Signer=$sigSubj; SHA256=$hash
        })
        $sigCol = switch ($sigStatus) { 'Valid' {'OK'} 'NotSigned' {'WARN'} default {'WARN'} }
        Add-Finding $sigCol 'Installer' ("{0,-26} {1,5} MB  sig={2}" -f $e.Name, [Math]::Round($f.Length/1MB,1), $sigStatus)
    } else {
        $missing++
        Add-Finding FAIL 'Installer' "MISSING: $($e.Name) -> $($e.Rel)"
    }
}
if ($missing -eq 0) { Add-Finding OK 'Inventory' "Los 15 instaladores presentes." }

# 10. ESET INI
$ini = Join-Path $Source 'install_config.ini'
if (Test-Path $ini) {
    $len = (Get-Item $ini).Length
    Add-Finding OK 'ESET INI' "install_config.ini presente ($len bytes)"
} else {
    Add-Finding WARN 'ESET INI' 'install_config.ini AUSENTE. ESET instalara unenrolled.'
}

# 11. Conectividad
if (-not $SkipNet) {
    $endpoints = @(
        @{ Host='officecdn.microsoft.com';        Port=443; Need='Office C2R'      },
        @{ Host='download.microsoft.com';         Port=443; Need='Microsoft updates'},
        @{ Host='dl.google.com';                  Port=443; Need='Chrome bootstrap'},
        @{ Host='www.google.com';                 Port=443; Need='Generic egress'  }
    )
    foreach ($e in $endpoints) {
        $r = Test-NetConnection -ComputerName $e.Host -Port $e.Port -WarningAction SilentlyContinue -InformationLevel Quiet
        if ($r) {
            Add-Finding OK 'Net' ("{0}:{1} alcanzable ({2})" -f $e.Host, $e.Port, $e.Need)
        } else {
            Add-Finding WARN 'Net' ("{0}:{1} NO alcanzable ({2})" -f $e.Host, $e.Port, $e.Need)
        }
    }
}

# 12. AV / Defender
try {
    $def = Get-MpComputerStatus -ErrorAction Stop
    Add-Finding INFO 'Defender' ("RealTime={0} AVEngine={1}" -f $def.RealTimeProtectionEnabled, $def.AMEngineVersion)
    if ($def.RealTimeProtectionEnabled) {
        Add-Finding WARN 'Defender' 'Real-Time activo: puede ralentizar instaladores grandes (PDFelement 571MB).'
    }
} catch {
    Add-Finding INFO 'Defender' 'No detectado o sin permisos.'
}

# 13. Apps ya instaladas
$installed = @()
@(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
) | ForEach-Object {
    $installed += Get-ItemProperty $_ -ErrorAction SilentlyContinue | Where-Object DisplayName
}
$keywords = @{
    'AnyDesk'='AnyDesk'; 'AqNet'='AqNet|Deposito Digital'; 'Nebula'='Nebula|CertAgent';
    'Cortex XDR'='Cortex XDR|Palo Alto|Traps'; 'ESET'='ESET Management Agent';
    'Chrome'='Google Chrome'; 'Autofirma'='AutoFirma'; 'Bit4id'='Bit4id';
    'PDFelement'='PDFelement|Wondershare'; 'Mitel'='Mitel';
    'Office'='Microsoft 365|Microsoft Office'; 'iManage'='iManage'
}
foreach ($k in $keywords.GetEnumerator()) {
    $hit = $installed | Where-Object { $_.DisplayName -match $k.Value } | Select-Object -First 1
    if ($hit) {
        Add-Finding INFO 'Pre-installed' ("{0,-12} -> {1} {2}" -f $k.Key, $hit.DisplayName, $hit.DisplayVersion)
    }
}

# 14. Workdir
foreach ($d in @($WorkDir, (Join-Path $WorkDir 'state'), (Join-Path $WorkDir 'state\logs'), (Join-Path $WorkDir 'state\reports'))) {
    if (-not (Test-Path $d)) {
        try { New-Item -ItemType Directory -Path $d -Force | Out-Null; Add-Finding OK 'Workdir' "Creado: $d" }
        catch { Add-Finding FAIL 'Workdir' "No se puede crear: $d ($_)" }
    }
}

# ----- Report MD -----
$reportFile = Join-Path $WorkDir 'PREFLIGHT_REPORT.md'
$nl = [Environment]::NewLine
$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine('# NodeDeploy Preflight Report')
[void]$md.AppendLine('')
[void]$md.AppendLine("- **Fecha**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$md.AppendLine("- **Source**: ``$Source``")
[void]$md.AppendLine("- **Workdir**: ``$WorkDir``")
[void]$md.AppendLine("- **Maquina**: $env:COMPUTERNAME / $env:USERNAME")
[void]$md.AppendLine('')

$cntOk   = ($Findings | Where-Object Level -eq 'OK').Count
$cntWarn = ($Findings | Where-Object Level -eq 'WARN').Count
$cntFail = ($Findings | Where-Object Level -eq 'FAIL').Count
[void]$md.AppendLine("## Resumen")
[void]$md.AppendLine('')
[void]$md.AppendLine("- OK   : $cntOk")
[void]$md.AppendLine("- WARN : $cntWarn")
[void]$md.AppendLine("- FAIL : $cntFail")
[void]$md.AppendLine('')

[void]$md.AppendLine("## Findings")
[void]$md.AppendLine('')
[void]$md.AppendLine('| Level | Area | Detalle |')
[void]$md.AppendLine('|-------|------|---------|')
foreach ($f in $Findings) {
    [void]$md.AppendLine(("| {0} | {1} | {2} |" -f $f.Level, $f.Area, ($f.Msg -replace '\|','\|')))
}
[void]$md.AppendLine('')

if ($invList.Count -gt 0) {
    [void]$md.AppendLine("## Inventario instaladores")
    [void]$md.AppendLine('')
    [void]$md.AppendLine('| App | Archivo | MB | Firma | Signer | SHA256 |')
    [void]$md.AppendLine('|-----|---------|----|-------|--------|--------|')
    foreach ($i in $invList) {
        [void]$md.AppendLine(("| {0} | ``{1}`` | {2} | {3} | {4} | ``{5}`` |" -f $i.App, $i.File, $i.MB, $i.SigStatus, $i.Signer, ($i.SHA256.Substring(0,16) + '...')))
    }
    [void]$md.AppendLine('')
}

[void]$md.AppendLine("## Veredicto")
[void]$md.AppendLine('')
$verdict = if ($cntFail -gt 0) { 'FATAL - no continuar deploy' }
           elseif ($cntWarn -gt 0) { 'WARN - revisar warnings, continuar con precaucion' }
           else { 'OK - listo para deploy' }
[void]$md.AppendLine("**$verdict**")

Set-Content -Path $reportFile -Value $md.ToString() -Encoding UTF8
Write-Host ''
Write-Host "  Report: $reportFile" -ForegroundColor Cyan
Write-Host "  Resumen: OK=$cntOk WARN=$cntWarn FAIL=$cntFail" -ForegroundColor Magenta
Write-Host "  Veredicto: $verdict" -ForegroundColor $(if($cntFail){'Red'}elseif($cntWarn){'Yellow'}else{'Green'})

if ($cntFail -gt 0) { exit 2 }
elseif ($cntWarn -gt 0) { exit 1 }
else { exit 0 }
