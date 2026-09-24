<#
.SYNOPSIS
    NodeDeploy PRO v5 - Reset / Uninstall helper (para iterar pruebas).
.DESCRIPTION
    Desinstala las apps gestionadas por NodeDeploy en orden inverso.
    NO toca el SO, drivers ni perfiles.

    Office: solo se quita el producto que anade NodeDeploy (OutlookRetail = Outlook clasico).
    El Microsoft 365 de fabrica del portatil (Word/Excel/PPT) NUNCA se desinstala.

    Antivirus/EDR (ESET Management Agent, Cortex XDR) solo con -IncludeAV (suelen exigir
    contrasena de desinstalacion y no deben quitarse por accidente).

        .\Uninstall.ps1 -ConfirmReset
        .\Uninstall.ps1 -ConfirmReset -IncludeAV
#>
[CmdletBinding()]
param(
    [switch]$ConfirmReset,
    [switch]$IncludeAV,
    [string]$Source
)

$ErrorActionPreference = 'Continue'

if (-not $ConfirmReset) {
    Write-Host 'Uso: .\Uninstall.ps1 -ConfirmReset [-IncludeAV]' -ForegroundColor Yellow
    Write-Host 'Esto desinstalara las apps gestionadas por NodeDeploy (no el Office de fabrica).' -ForegroundColor Yellow
    exit 0
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '[FATAL] Requiere admin' -ForegroundColor Red
    exit 4
}

if (-not $Source) {
    $Source = Resolve-Path (Join-Path $PSScriptRoot '..\..\1.Node_Preparation') -ErrorAction SilentlyContinue
}

function Get-UninstallEntry {
    param([string]$Keyword, [string[]]$Exclude = @())
    Get-ItemProperty @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    ) -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "*$Keyword*" } |
        Where-Object { $n = $_.DisplayName; -not ($Exclude | Where-Object { $n -like "*$_*" }) } |
        Sort-Object DisplayName | Select-Object -First 1
}

function Uninstall-App {
    param([string]$Name, [string]$Keyword, [string[]]$KillFirst = @(), [string[]]$Exclude = @())
    $entry = Get-UninstallEntry -Keyword $Keyword -Exclude $Exclude
    if (-not $entry) {
        Write-Host "[SKIP] $Name (no instalado)" -ForegroundColor DarkGray
        return
    }
    Write-Host "[UNINSTALL] ${Name}: $($entry.DisplayName) v$($entry.DisplayVersion)" -ForegroundColor Cyan
    foreach ($k in $KillFirst) {
        Get-Process -Name $k -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    if ($KillFirst) { Start-Sleep -Seconds 2 }

    if ($entry.UninstallString -match 'msiexec' -and $entry.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$') {
        $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/x $($entry.PSChildName) /qn /norestart" -Wait -PassThru
        Write-Host "  msiexec /x exit $($p.ExitCode)"
        return
    }
    $uns = if ($entry.QuietUninstallString) { $entry.QuietUninstallString } else { $entry.UninstallString }
    if (-not $uns) { Write-Host '  Sin uninstall string' -ForegroundColor Yellow; return }
    Write-Host "  Cmd: $uns"
    & cmd.exe /c $uns 2>&1 | Out-Null
    Write-Host "  exit $LASTEXITCODE"
}

function Remove-OutlookClassic {
    # Quita SOLO el producto OutlookRetail que anade NodeDeploy, con todos sus idiomas.
    $cfg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
    if (-not $cfg -or ("$($cfg.ProductReleaseIds)" -split ',') -notcontains 'OutlookRetail') {
        Write-Host '[SKIP] Outlook clasico (OutlookRetail no instalado)' -ForegroundColor DarkGray
        return
    }
    $cultures = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\ProductReleaseIDs' -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.PSParentPath -like '*OutlookRetail.16' -and $_.PSChildName -ne 'x-none' } |
        ForEach-Object { $_.PSChildName } | Sort-Object -Unique)
    if (-not $cultures) { $cultures = @($cfg.ClientCulture) }
    $langs = ($cultures | ForEach-Object { "      <Language ID=`"$_`" />" }) -join "`r`n"
    $xml = @"
<Configuration>
  <Remove>
    <Product ID="OutlookRetail">
$langs
    </Product>
  </Remove>
  <Display Level="None" AcceptEULA="TRUE" />
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
</Configuration>
"@
    $xmlPath = Join-Path $env:TEMP 'nodedeploy_remove_outlook.xml'
    Set-Content -Path $xmlPath -Value $xml -Encoding UTF8
    $odt = Join-Path $Source 'OfficeSetup.exe'
    if (-not (Test-Path $odt)) { Write-Host "  OfficeSetup.exe no encontrado en $Source" -ForegroundColor Yellow; return }
    Write-Host "[UNINSTALL] Outlook clasico (OutlookRetail: $($cultures -join ', '))" -ForegroundColor Cyan
    $p = Start-Process -FilePath $odt -ArgumentList "/configure `"$xmlPath`"" -Wait -PassThru
    Write-Host "  ODT exit $($p.ExitCode)"
}

Write-Host '=== NodeDeploy Uninstall ===' -ForegroundColor Magenta
if ($IncludeAV) { Uninstall-App 'MDR Cortex XDR' 'Cortex XDR' }
Uninstall-App 'iManage Work Desktop' 'iManage Work Desktop' @('iManageWorkDesktop','iManageStayExec','OUTLOOK','WINWORD')
Uninstall-App 'iManage Drive Native' 'iManage Drive Native'
Uninstall-App 'iManage Drive' 'iManage Drive' @('iManageDrive') @('Native')
Uninstall-App 'iManage Agent Services' 'iManage Agent'
Remove-OutlookClassic
Uninstall-App 'Autofirma' 'Autofirma' @('Autofirma')
Uninstall-App 'PDFelement Business' 'PDFelement' @('PDFelement')
Uninstall-App 'Bit4id Middleware' 'Bit4id'
Uninstall-App 'MitelConnect' 'Mitel Connect'
Uninstall-App 'Google Chrome' 'Google Chrome' @('chrome')
if ($IncludeAV) { Uninstall-App 'ESET Management Agent' 'ESET Management Agent' }
Uninstall-App 'Nebula CertAgent' 'nebulaCERTagent'
Uninstall-App 'AqNet' 'AqNet'
Uninstall-App 'AnyDesk' 'AnyDesk' @('AnyDesk')

Write-Host ''
Write-Host '=== Uninstall completo ===' -ForegroundColor Magenta
Write-Host 'Estado: borra NodeDeploy_Run\state\nodedeploy_state.json para empezar de cero.' -ForegroundColor Yellow
exit 0
