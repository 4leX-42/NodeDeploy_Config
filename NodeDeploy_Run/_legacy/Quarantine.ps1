<#
.SYNOPSIS
    Mueve archivos NO listados en NodeDeploy_Config.html a Quarantine\
.DESCRIPTION
    Reversible: usa Move-Item, no Remove-Item.
    Conserva estructura relativa.
    Tras deploy OK, usuario decide si borrar Quarantine\.
#>
[CmdletBinding()]
param(
    [string]$Source     = 'C:\Users\user\Desktop\1.Node_Preparation',
    [string]$Quarantine = 'C:\Users\user\Desktop\1.Node_Preparation\_Quarantine',
    [switch]$WhatIf
)

# Lista de paths/archivos NO incluidos en config (segun NodeDeploy_Config.html)
# Patrones se evaluan con -like. Carpetas se mueven enteras.
$candidates = @(
    'KeePassXC-2.7.10-Win64.msi',
    'NanaZip.msixbundle',
    'NanaZip Installer.exe',
    'Instalar_D2_2025.exe',
    'epi_win_live_installer.exe',
    'OutlookClassic.exe',
    'debug.log',
    'AqNet Instalacion Andersen',
    'eset',
    'SCRIPT-INSTALACION'
)

if (-not (Test-Path $Quarantine)) {
    if (-not $WhatIf) { New-Item -ItemType Directory -Path $Quarantine -Force | Out-Null }
    Write-Host "  Quarantine creada: $Quarantine" -ForegroundColor Cyan
}

$moved = 0
$skipped = 0
foreach ($c in $candidates) {
    $src = Join-Path $Source $c
    if (Test-Path $src) {
        $dst = Join-Path $Quarantine $c
        if (Test-Path $dst) {
            Write-Host "  [SKIP] ya en quarantine: $c" -ForegroundColor DarkYellow
            $skipped++
            continue
        }
        $sz = if ((Get-Item $src).PSIsContainer) {
            $b = (Get-ChildItem $src -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            [Math]::Round($b/1MB,1)
        } else {
            [Math]::Round((Get-Item $src).Length/1MB,1)
        }
        Write-Host ("  [MV] {0,-50} ({1,5} MB)" -f $c, $sz) -ForegroundColor Yellow
        if (-not $WhatIf) {
            try {
                Move-Item -Path $src -Destination $dst -Force -ErrorAction Stop
                $moved++
            } catch {
                Write-Host "  [ERR] $c : $_" -ForegroundColor Red
            }
        } else {
            $moved++
        }
    } else {
        Write-Host "  [NF] no presente: $c" -ForegroundColor DarkGray
    }
}

Write-Host ''
Write-Host "  Movidos: $moved   Skipped: $skipped" -ForegroundColor Cyan
if ($WhatIf) { Write-Host '  (WHAT-IF mode: nada modificado)' -ForegroundColor Magenta }
Write-Host "  Para revertir: Move-Item '$Quarantine\<item>' '$Source\'" -ForegroundColor DarkGray
exit 0
