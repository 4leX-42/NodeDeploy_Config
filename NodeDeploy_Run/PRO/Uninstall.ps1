<#
.SYNOPSIS
    NodeDeploy PRO - Reset / Uninstall helper.
.DESCRIPTION
    Desinstala las 15 apps en orden inverso. Útil para iterar tests.
    NO toca el SO ni los drivers. NO toca usuario/perfil.

    Por seguridad, requiere flag -ConfirmReset:
        .\Uninstall.ps1 -ConfirmReset

.NOTES
    Office C2R se desinstala con su propio uninstall.xml.
    Cortex XDR + ESET requieren password en algunas configuraciones.
#>
[CmdletBinding()]
param(
    [switch]$ConfirmReset,
    [string]$Source
)

$ErrorActionPreference = 'Continue'

if (-not $ConfirmReset) {
    Write-Host "Uso: .\Uninstall.ps1 -ConfirmReset" -ForegroundColor Yellow
    Write-Host "Esto desinstalara TODAS las apps gestionadas por NodeDeploy." -ForegroundColor Yellow
    exit 0
}

# Admin
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '[FATAL] Requiere admin' -ForegroundColor Red
    exit 4
}

# Source for Office uninstall.xml (optional)
if (-not $Source) {
    $Source = Resolve-Path (Join-Path $PSScriptRoot '..\..\1.Node_Preparation') -ErrorAction SilentlyContinue
}

function Get-UninstallString {
    param([string]$Keyword)
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "*$Keyword*" } |
        Sort-Object DisplayName | Select-Object -First 1
}

function Uninstall-App {
    param([string]$Name, [string]$Keyword, [string[]]$KillFirst = @())
    $entry = Get-UninstallString $Keyword
    if (-not $entry) {
        Write-Host "[SKIP] $Name (no entry)" -ForegroundColor DarkGray
        return
    }
    Write-Host "[UNINSTALL] $Name: $($entry.DisplayName) v$($entry.DisplayVersion)" -ForegroundColor Cyan
    if ($KillFirst) {
        foreach ($k in $KillFirst) {
            Get-Process -Name $k -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2
    }

    # MSI uninstall via ProductCode
    if ($entry.UninstallString -match 'msiexec') {
        if ($entry.PSChildName -match '^\{[0-9A-F-]{36}\}$') {
            $code = $entry.PSChildName
            Write-Host "  MSI ProductCode: $code"
            Start-Process -FilePath 'msiexec.exe' -ArgumentList "/x $code /qn /norestart" -Wait -NoNewWindow -PassThru | Out-Null
            return
        }
    }
    # EXE uninstall
    $uns = $entry.QuietUninstallString
    if (-not $uns) { $uns = $entry.UninstallString }
    if (-not $uns) {
        Write-Host "  No uninstall string" -ForegroundColor Yellow
        return
    }
    Write-Host "  Cmd: $uns"
    try {
        & cmd.exe /c $uns 2>&1 | Out-Null
    } catch {
        Write-Host "  Failed: $_" -ForegroundColor Red
    }
}

# Orden inverso al install
Write-Host '=== NodeDeploy Uninstall ===' -ForegroundColor Magenta
Uninstall-App 'iManage Work Desktop' 'iManage Work' @('iManageWorkDesktop','iManageStayExec')
Uninstall-App 'iManage Drive Native' 'iManage Drive Native'
Uninstall-App 'iManage Drive' 'iManage Drive' @('iManageDrive')
Uninstall-App 'iManage Agent Services' 'iManage Agent'

# Office C2R: usa configuration-uninstall.xml o el OfficeC2RClient
$officeUninstallXml = Join-Path $Source 'Sc3.0\configuration-uninstall.xml'
if (Test-Path $officeUninstallXml) {
    Write-Host "[UNINSTALL] Office (XML)" -ForegroundColor Cyan
    & (Join-Path $Source 'OfficeSetup.exe') /configure $officeUninstallXml
} else {
    $c2r = "$env:CommonProgramFiles\microsoft shared\ClickToRun\OfficeClickToRun.exe"
    if (Test-Path $c2r) {
        Write-Host "[UNINSTALL] Office (C2R remove)" -ForegroundColor Cyan
        & $c2r scenario=install scenariosubtype=ARP sourcetype=None productstoremove=O365ProPlusRetail.16_es-es_x-none culture=es-es DisplayLevel=False
    }
}

Uninstall-App 'MitelConnect' 'Mitel'
Uninstall-App 'PDFelement Business' 'PDFelement' @('PDFelement')
Uninstall-App 'Bit4id Middleware' 'Bit4id'
Uninstall-App 'Autofirma' 'AutoFirma'
Uninstall-App 'Google Chrome' 'Google Chrome' @('chrome')
Uninstall-App 'ESET Management Agent' 'ESET Management Agent'
Uninstall-App 'MDR Cortex XDR' 'Cortex XDR'
Uninstall-App 'Nebula CertAgent' 'Nebula'
Uninstall-App 'AqNet' 'AqNet'
Uninstall-App 'AnyDesk' 'AnyDesk' @('AnyDesk')

Write-Host ''
Write-Host '=== Uninstall complete ===' -ForegroundColor Magenta
Write-Host 'Para limpiar state file: rm NodeDeploy_Run\state\nodedeploy_state.json' -ForegroundColor Yellow
Write-Host 'Para limpiar logs: rm NodeDeploy_Run\state\logs\*' -ForegroundColor Yellow
exit 0
