<#
    Se ejecuta DENTRO de la VM. Extrae (sin instalar) el payload de iManage Work Desktop 3.0
    con /extract_all y copia el setup.iss que trae el propio paquete a C:\LabRun\setup_wd.iss.
#>
$ErrorActionPreference = 'Stop'
$src = 'C:\nodedeploy\1.Node_Preparation\Imanage 3.0\(2)iManage Work Desktop for Windows 10.10.2.62 (x64 Office)\iManageWorkDesktopforWindowsx64.exe'
$work = 'C:\LabRun\wdext'
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $work | Out-Null
$exe = Join-Path $work 'wd.exe'
Copy-Item -LiteralPath $src -Destination $exe -Force
$sw = [Diagnostics.Stopwatch]::StartNew()
$p = Start-Process -FilePath $exe -ArgumentList "/s /extract_all:`"$work\ext`"" -Wait -PassThru
"extract exit=$($p.ExitCode) en $([int]$sw.Elapsed.TotalSeconds)s" | Set-Content C:\LabRun\wdext.log
Get-ChildItem "$work\ext" -Recurse | Select-Object @{n='Rel';e={$_.FullName.Replace("$work\ext\",'')}}, Length | Format-Table -AutoSize | Out-String -Width 200 | Add-Content C:\LabRun\wdext.log
$iss = Get-ChildItem "$work\ext" -Recurse -Filter 'setup.iss' | Select-Object -First 1
if (-not $iss) { 'setup.iss NO encontrado' | Add-Content C:\LabRun\wdext.log; exit 2 }
Copy-Item $iss.FullName 'C:\LabRun\setup_wd.iss' -Force
exit 0
