<#
    Se ejecuta DENTRO de la VM. Extrae SIN instalar los paquetes InstallShield de iManage 3.0
    (/extract_all) y deja inventario: MSI internos, setup.iss incluidos, tipo de proyecto.
#>
$ErrorActionPreference = 'Continue'
$share = '\\vmware-host\Shared Folders\nodedeploy\1.Node_Preparation\Imanage 3.0'
$out   = 'C:\LabRun\im3'
$log   = 'C:\LabRun\im3_extract.log'
Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $out | Out-Null
"$(Get-Date -Format 'HH:mm:ss') inicio" | Set-Content $log

$pkgs = @{
    drive = Get-ChildItem $share -Recurse -Filter 'iManageDriveSetup.exe' | Select-Object -First 1
    wd    = Get-ChildItem $share -Recurse -Filter 'iManageWorkDesktopforWindowsx64.exe' | Select-Object -First 1
    as    = Get-ChildItem $share -Recurse -Filter 'iManageAgentServices.exe' | Select-Object -First 1
}
foreach ($k in $pkgs.Keys) {
    $src = $pkgs[$k]
    if (-not $src) { "$k no encontrado" | Add-Content $log; continue }
    $dir = Join-Path $out $k
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $exe = Join-Path $dir 'pkg.exe'
    Copy-Item -LiteralPath $src.FullName -Destination $exe -Force
    "== $k : $($src.Name) desc='$($src.VersionInfo.FileDescription)' ver=$($src.VersionInfo.FileVersion)" | Add-Content $log
    $p = Start-Process -FilePath $exe -ArgumentList "/s /extract_all:`"$dir\ext`"" -PassThru
    if (-not $p.WaitForExit(600000)) { $p.Kill(); "   extract TIMEOUT" | Add-Content $log }
    else { "   extract exit=$($p.ExitCode)" | Add-Content $log }
    Remove-Item $exe -Force -ErrorAction SilentlyContinue
    Get-ChildItem "$dir\ext" -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.msi','.iss','.inx','.ini','.hdr','.mst','.exe' -or $_.Name -like 'data*.cab' } |
        ForEach-Object { "   {0,12:N0}  {1}" -f $_.Length, $_.FullName.Replace("$dir\ext\", '') } | Add-Content $log
}
"$(Get-Date -Format 'HH:mm:ss') fin" | Add-Content $log
exit 0
