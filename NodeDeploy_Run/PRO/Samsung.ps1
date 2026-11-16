<#
.SYNOPSIS
    Paso propio de los Samsung (Galaxy Book) en NodeDeploy. Lo lanza Deploy.ps1 solo en equipos Samsung, despues de
    Windows Update y antes del cierre.
.DESCRIPTION
    Samsung no tiene un modulo como Lenovo.Client.Update: sus controladores, firmware y BIOS llegan por Windows
    Update (WindowsUpdate.ps1 ya los instala en todas las marcas, el firmware con cargador y BitLocker en pausa) y la
    app Samsung Update no tiene modo desatendido documentado. Su "BIOS Command Tool" solo cambia ajustes de BIOS
    (modelos Business), no actualiza.
    Como los Samsung ni terminaban de actualizar ni reiniciaban solos, de momento este paso deja el diagnostico del
    equipo (Recoger-Equipo.ps1 -Rapido, ~30 s, solo lee) en los logs del despliegue, que suben con el zip de logs,
    y pasa sus claves al log de Deploy. Con eso se decide que arreglar aqui para Samsung.
    No reinicia ni cambia nada. Resultado en JSON.
    Solo ASCII: Windows PowerShell 5.1 lee los .ps1 sin BOM como ANSI.
#>
param(
    [ValidateSet('', 'run')][string]$SamsungMode = '',
    [string]$OutJson,
    [string]$OutDir = (Join-Path $env:ProgramData 'NodeDeploy')
)

function Invoke-Samsung {
    $sw  = [Diagnostics.Stopwatch]::StartNew()
    $cs  = Get-CimInstance Win32_ComputerSystem
    $res = [ordered]@{ model = "$($cs.SystemFamily) ($($cs.Model))"; zip = ''; claves = @(); notes = @(); seconds = 0 }
    if ($cs.Manufacturer -notmatch 'SAMSUNG' -and -not $env:NODEDEPLOY_TEST_VENDOR) { $res.notes += "no es un Samsung ($($cs.Manufacturer))"; return $res }

    # Software de Samsung presente (Samsung Update, Settings...): para el informe
    $sam = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Samsung' } | ForEach-Object { $_.Name })
    if ($sam) { $res.notes += "apps de Samsung: $($sam -join ', ')" }

    $rec = Join-Path $PSScriptRoot 'Recoger-Equipo.ps1'
    if (-not (Test-Path $rec)) { $res.notes += 'falta Recoger-Equipo.ps1: sin diagnostico'; return $res }
    $cj = Join-Path $env:TEMP "nodedeploy_samsung_claves_$PID.json"
    & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $rec -Rapido -Desatendido -Salida $OutDir -ClavesJson $cj *> $null
    if (Test-Path $cj) {
        $c = Get-Content -LiteralPath $cj -Raw | ConvertFrom-Json
        $res.zip = "$($c.zip)"; $res.claves = @($c.claves)
        Remove-Item -LiteralPath $cj -Force -ErrorAction SilentlyContinue
    } else { $res.notes += 'el diagnostico no dejo resultado' }
    $res.seconds = [int]$sw.Elapsed.TotalSeconds
    return $res
}

if ($SamsungMode -eq 'run') {
    $r = try { Invoke-Samsung } catch { [ordered]@{ model = ''; zip = ''; claves = @(); notes = @("excepcion: $($_.Exception.Message)"); seconds = 0 } }
    if ($OutJson) { $r | ConvertTo-Json -Depth 4 | Set-Content -Path $OutJson -Encoding UTF8 }
    exit 0
}
