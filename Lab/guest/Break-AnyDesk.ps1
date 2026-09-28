<#
    Se ejecuta DENTRO de la VM: simula un AnyDesk instalado "a medias" (registro presente, servicio borrado) para
    probar que Deploy.ps1 lo repara. Antes apunta el ID que tenia. Resultado en C:\LabRun\anydesk_break.txt.
#>
$out = 'C:\LabRun\anydesk_break.txt'
$svc = Get-CimInstance Win32_Service -Filter "Name LIKE 'AnyDesk%'" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $svc) { 'sin servicio de AnyDesk: nada que romper' | Set-Content -Path $out -Encoding UTF8; exit 1 }
$exe = if ("$($svc.PathName)" -match '^\s*"([^"]+)"') { $matches[1] } else { ("$($svc.PathName)" -split '\s+--')[0].Trim() }
$idBefore = "$(& $exe --get-id 2>$null | Out-String)".Trim()
Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($exe)) -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
& sc.exe delete $svc.Name | Out-Null
Start-Sleep -Seconds 3
"antes: servicio=$($svc.Name) exe=$exe id=$idBefore | despues: servicio existe=$([bool](Get-Service -Name $svc.Name -ErrorAction SilentlyContinue))" | Set-Content -Path $out -Encoding UTF8
exit 0
