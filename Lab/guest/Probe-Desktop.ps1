<#
    Se ejecuta DENTRO de la VM: escritorio, barra de tareas y PDF24 tal como quedan -> C:\LabRun\desktop_probe.txt.
    Incluye los AppID reales (Get-StartApps) para comprobar los del XML de la barra de tareas.
#>
$out = 'C:\LabRun\desktop_probe.txt'
$l = @("== Escritorio y barra de tareas $(Get-Date -Format s) usuario=$env:USERNAME")
$l += '--- Apps (Get-StartApps):'
$l += @(Get-StartApps | Where-Object { $_.Name -match 'Outlook|Teams|Edge|Explorador|Explorer|Store|PDF24' } | ForEach-Object { "  $($_.Name) => $($_.AppID)" })
$l += '--- Teams instalados:'
$l += @(Get-AppxPackage -AllUsers -Name '*Teams*' -ErrorAction SilentlyContinue | ForEach-Object { "  $($_.Name) $($_.Version)" })
$l += '--- Escritorio comun:'
$l += @(Get-ChildItem ([Environment]::GetFolderPath('CommonDesktopDirectory')) -ErrorAction SilentlyContinue | ForEach-Object { "  $($_.Name)" })
$l += '--- HKLM\SOFTWARE\PDF24:'
$p = Get-ItemProperty 'HKLM:\SOFTWARE\PDF24' -ErrorAction SilentlyContinue
if ($p) { $l += @($p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { "  $($_.Name) = $($_.Value)" }) }
$l += '--- Directiva de la barra de tareas:'
$e = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' -ErrorAction SilentlyContinue
$l += "  LockedStartLayout=$($e.LockedStartLayout) StartLayoutFile=$($e.StartLayoutFile)"
if ($e.StartLayoutFile -and (Test-Path $e.StartLayoutFile)) { $l += @(Get-Content $e.StartLayoutFile | Where-Object { $_ -match 'taskbar:(UWA|DesktopApp)|PinListPlacement' } | ForEach-Object { "  $($_.Trim())" }) }
$l += '--- Anclados del usuario (User Pinned\TaskBar):'
$l += @(Get-ChildItem "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar" -ErrorAction SilentlyContinue | ForEach-Object { "  $($_.Name)" })
$l += "--- WebView2 del sistema (pv): $((Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' -ErrorAction SilentlyContinue).pv)"
$l += "--- Windows: $((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion) build $([Environment]::OSVersion.Version.Build).$((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR)"
$l | Set-Content -Path $out -Encoding UTF8
exit 0
