<#
.SYNOPSIS
    Copia espejo del repo en C:\NodeDeployLabSrc para usar el laboratorio con el M.2 desconectado.

.DESCRIPTION
    Ejecutalo desde D:\nodedeploy\Lab antes de desconectar el M.2; despues lanza las pruebas desde
    C:\NodeDeployLabSrc\Lab (la carpeta compartida de la VM sigue a la copia desde la que se ejecuta).
    No copia instaladores de antivirus/EDR, _Archivo, el payload de Office completo ni el estado.
    En el espejo se conservan lab.local.json, Lab\results y Lab\_build.
#>
param([string]$Mirror = 'C:\NodeDeployLabSrc')
$ErrorActionPreference = 'Stop'
$src = Split-Path -Parent $PSScriptRoot
if ((Convert-Path $src) -ieq $Mirror.TrimEnd('\')) { throw 'Ejecutalo desde la copia del M.2 (D:\nodedeploy\Lab), no desde el espejo.' }

$xd = @('.git', '.claude', '_Archivo', 'Office', 'state', 'results', '_build')
$xf = @('eset_msi.msi', 'MDR_Windows_Andersen_8_2_x64.msi', 'epi_win_live_installer.exe', 'install_config.ini', 'lab.local.json', '*.log')
& robocopy $src $Mirror /MIR /R:1 /W:1 /NP /NFL /NDL /MT:8 /XD @xd /XF @xf | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy rc=$LASTEXITCODE" }
Write-Host "Espejo actualizado: $Mirror (rc=$LASTEXITCODE)" -ForegroundColor Green
