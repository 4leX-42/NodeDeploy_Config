<#
    Se ejecuta DENTRO de la VM: inventario de todo lo que arranca con Windows / con el inicio de sesion
    (Run, RunOnce, StartupApproved, carpetas de Inicio, tareas programadas, servicios, Active Setup).
    Uso: Get-StartupInventory.ps1 [etiqueta]  -> C:\LabRun\startup_<etiqueta>.txt
#>
param([string]$Tag = 'inv')
$Tag = $Tag.Trim()   # vmrun/cmd deja un espacio al final del ultimo argumento
$out = "C:\LabRun\startup_$Tag.txt"
New-Item -ItemType Directory -Force -Path 'C:\LabRun' | Out-Null
$lines = New-Object System.Collections.Generic.List[string]
function Add([string]$s) { $lines.Add($s) }

Add "== Inventario de arranque ($Tag) $(Get-Date -Format s) usuario=$env:USERNAME"
$runKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
)
foreach ($k in $runKeys) {
    Add "--- $k"
    $p = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
    if ($p) { $p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { Add ("  {0} = {1}" -f $_.Name, $_.Value) } }
}
foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
               'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32',
               'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder',
               'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
               'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32',
               'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder') {
    Add "--- $k"
    $p = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
    if ($p) { $p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { Add ("  {0} = {1}" -f $_.Name, (($_.Value | Select-Object -First 1) -as [string])) } }
}
foreach ($d in "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup") {
    Add "--- carpeta $d"
    Get-ChildItem -LiteralPath $d -ErrorAction SilentlyContinue | ForEach-Object { Add "  $($_.Name)" }
}
Add '--- tareas programadas no-Microsoft con disparador de inicio / sesion'
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } | ForEach-Object {
    $trig = ($_.Triggers | ForEach-Object { $_.CimClass.CimClassName -replace 'MSFT_Task','' -replace 'Trigger','' }) -join ','
    $act  = ($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)".Trim() }) -join ' | '
    Add ("  {0}{1} [{2}] trig={3} :: {4}" -f $_.TaskPath, $_.TaskName, $_.State, $trig, $act)
}
Add '--- servicios de las apps (y Edge)'
Get-CimInstance Win32_Service | Where-Object { $_.Name -match 'AnyDesk|Everything|Wondershare|WsApp|Elevation|PDF24|pdf24|Bit4id|b4|edgeupdate|MicrosoftEdge|Mitel|iManage|Nebula|nebula' -or $_.PathName -match 'Wondershare|PDF24|Bit4id|Everything|AnyDesk' } |
    ForEach-Object { Add ("  {0} [{1}/{2}] {3}" -f $_.Name, $_.StartMode, $_.State, $_.PathName) }
Add '--- Active Setup (por usuario al iniciar sesion) de las apps'
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Active Setup\Installed Components' -ErrorAction SilentlyContinue |
    ForEach-Object { $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue; if ("$($p.StubPath) $($p.'(default)')" -match 'Wondershare|PDF24|Bit4id|Everything|AnyDesk|Edge|b4') { Add ("  {0} :: {1} :: {2}" -f $_.PSChildName, $p.'(default)', $p.StubPath) } }
Add '--- procesos de las apps en marcha'
Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'AnyDesk|Everything|Wondershare|PDFelement|pdf24|b4|bit4|msedge|WsHelper|Notify' } |
    ForEach-Object { Add ("  {0} (sesion {1}) {2}" -f $_.ProcessName, $_.SessionId, $(try { $_.Path } catch { '' })) }
Add '--- Edge: politicas'
$pe = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -ErrorAction SilentlyContinue
if ($pe) { $pe.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { Add ("  {0} = {1}" -f $_.Name, $_.Value) } }
Add '--- directivas de publicidad / widgets / chat'
foreach ($k in 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent', 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat') {
    $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
    if ($p) { Add ("  {0}: {1}" -f (Split-Path $k -Leaf), (($p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' ')) }
}
Add '--- AnyDesk: boton Desinstalar (NoRemove) y recuperacion del servicio'
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue |
    ForEach-Object { $p = Get-ItemProperty $_.PSPath; if ($p.DisplayName -like 'AnyDesk*') { Add ("  {0}: NoRemove={1} NoModify={2}" -f $p.DisplayName, $p.NoRemove, $p.NoModify) } }
Get-Service -Name 'AnyDesk*' -ErrorAction SilentlyContinue | ForEach-Object { Add ("  servicio {0}: {1}/{2} | {3}" -f $_.Name, $_.StartType, $_.Status, ((& sc.exe qfailure $_.Name) -match 'REINICIAR|RESTART' | Select-Object -First 1)) }
$opt = 'C:\nodedeploy\NodeDeploy_Run\PRO\Optimize.ps1'
if (Test-Path $opt) {
    . $opt
    Add '--- apps de la lista de limpieza que SIGUEN instaladas / aprovisionadas'
    $all = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue); $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
    foreach ($pat in $Script:DebloatApps) {
        foreach ($x in @($all | Where-Object { $_.Name -like $pat } | Select-Object -ExpandProperty Name -Unique)) { Add "  instalada: $x" }
        foreach ($x in @($prov | Where-Object { $_.DisplayName -like $pat } | Select-Object -ExpandProperty DisplayName -Unique)) { Add "  aprovisionada: $x" }
    }
    Add '--- apps que NO deben quitarse (comprobacion)'
    foreach ($k in 'Microsoft.WindowsStore', 'Microsoft.WindowsCalculator', 'Microsoft.Windows.Photos', 'Microsoft.WindowsTerminal', 'Microsoft.DesktopAppInstaller', '40174MouriNaruto.NanaZip') {
        Add ("  {0}: {1}" -f $k, $(if ($all | Where-Object { $_.Name -eq $k }) { 'presente' } elseif ($prov | Where-Object { $_.DisplayName -eq $k }) { 'aprovisionada' } else { 'NO ESTA' }))
    }
}
$lines | Set-Content -Path $out -Encoding UTF8
exit 0
