<#
.SYNOPSIS
    Optimización de Windows de NodeDeploy (se carga desde Deploy.ps1; la limpieza también corre sola en segundo plano).

.DESCRIPTION
    Invoke-Debloat (segundo plano desde t=0, no alarga el despliegue):
      - quita las apps de Microsoft Store que sobran en el despacho, del usuario actual y de los futuros
        (lista $Script:DebloatApps; nunca Store, Calculadora, Fotos, Terminal, códecs, winget ni apps de Lenovo);
      - corta publicidad, instalación automática de apps, sugerencias de Bing, widgets y chat
        (directivas del equipo + perfil del usuario actual + perfil por defecto de los usuarios nuevos).
    Set-StartupPolicy (al final, cuando las apps ya están instaladas):
      - deja DESHABILITADAS en "Aplicaciones de arranque" PDFelement (Wondershare), PDF24, Everything y b4notify
        (igual que el Administrador de tareas: StartupApproved de HKLM, un usuario sin admin no puede reactivarlas);
      - Edge sin arranque en segundo plano (directivas StartupBoostEnabled / BackgroundModeEnabled);
      - AnyDesk obligatorio: servicio automático y arrancado, reinicio si se cae, entrada de inicio habilitada
        y sin botón Desinstalar.
    Get-OptimizeChecks: TRIM del SSD, software del fabricante que conviene revisar (no se toca Lenovo Vantage)
    y lo que sigue arrancando con Windows. Start-WindowsUpdateScan: lanza la búsqueda de actualizaciones sin esperar.

    Uso suelto (lo lanza Deploy.ps1): Optimize.ps1 -OptimizeMode debloat -OptimizeOutJson <ruta>
#>
param(
    [ValidateSet('', 'debloat')][string]$OptimizeMode = '',
    [string]$OptimizeOutJson
)

# Apps de Store que sobran en el despacho (patrón = nombre del paquete). Ajustable.
# Se quedan a petición del usuario: Spotify, Outlook nuevo y Teams personal.
$Script:DebloatApps = @(
    'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch', 'Microsoft.GamingApp', 'Microsoft.XboxApp',
    'Microsoft.XboxGamingOverlay', 'Microsoft.Xbox.TCUI', 'Microsoft.MicrosoftSolitaireCollection',
    'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo', 'Microsoft.People', 'Microsoft.GetHelp', 'Microsoft.Getstarted',
    'Microsoft.WindowsFeedbackHub', 'Clipchamp.Clipchamp', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.549981C3F5F10',
    'MicrosoftCorporationII.QuickAssist', 'MicrosoftCorporationII.MicrosoftFamily', 'Microsoft.WindowsMaps',
    'Microsoft.YourPhone', 'Microsoft.Windows.DevHome',
    '*Disney*', '*TikTok*', '*CandyCrush*', '*Netflix*', '*Facebook*', '*Instagram*', '*AmazonAlexa*'
)
# Nunca se tocan aunque algún patrón coincidiera
$Script:DebloatKeep = 'Microsoft\.WindowsStore|WindowsCalculator|Windows\.Photos|WindowsTerminal|Extension$|DesktopAppInstaller|Lenovo|^E046963F|^E0469640|NanaZip|VCLibs|\.NET\.|UI\.Xaml|MSTeams$'

function Set-RegValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Set-UserDebloatValues {
    # Ajustes por usuario (publicidad, apps instaladas solas, Bing en la búsqueda) bajo la raíz indicada.
    param([string]$Root)
    $cdm = "$Root\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    foreach ($n in 'SilentInstalledAppsEnabled', 'SystemPaneSuggestionsEnabled', 'SubscribedContent-338388Enabled',
                   'SubscribedContent-338389Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled',
                   'SoftLandingEnabled', 'PreInstalledAppsEnabled', 'OemPreInstalledAppsEnabled') {
        Set-RegValue $cdm $n 0
    }
    Set-RegValue "$Root\Software\Policies\Microsoft\Windows\Explorer" 'DisableSearchBoxSuggestions' 1
    Set-RegValue "$Root\Software\Microsoft\Windows\CurrentVersion\Search" 'BingSearchEnabled' 0
    Set-RegValue "$Root\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" 'TaskbarMn' 0
}

function Invoke-Debloat {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $res = [ordered]@{ removed = @(); errors = @(); policies = @(); seconds = 0 }

    # 1) Apps de Store: usuarios actuales + aprovisionadas (usuarios futuros). Una sola consulta de cada tipo.
    $all  = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
    foreach ($pat in $Script:DebloatApps) {
        foreach ($p in @($all | Where-Object { $_.Name -like $pat -and $_.Name -notmatch $Script:DebloatKeep } | Sort-Object PackageFullName -Unique)) {
            try { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop; $res.removed += $p.Name }
            catch { $res.errors += "$($p.Name): $($_.Exception.Message)" }
        }
        foreach ($p in @($prov | Where-Object { $_.DisplayName -like $pat -and $_.DisplayName -notmatch $Script:DebloatKeep })) {
            try { Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null; $res.removed += "$($p.DisplayName) (aprovisionada)" }
            catch { if ($_.Exception.HResult -eq -2147024893) { $res.removed += "$($p.DisplayName) (aprovisionada)" } else { $res.errors += "$($p.DisplayName) (aprovisionada): $($_.Exception.Message)" } }
        }
    }
    $res.removed = @($res.removed | Select-Object -Unique)

    # 2) Directivas del equipo: publicidad / apps sugeridas, widgets, chat, sugerencias de Bing
    try {
        $cc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
        foreach ($n in 'DisableWindowsConsumerFeatures', 'DisableSoftLanding', 'DisableCloudOptimizedContent', 'DisableConsumerAccountStateContent') { Set-RegValue $cc $n 1 }
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat' 'ChatIcon' 3
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
        $res.policies += 'equipo: sin publicidad ni apps sugeridas, sin widgets, sin chat, sin sugerencias de Bing'
    } catch { $res.errors += "directivas del equipo: $($_.Exception.Message)" }

    # 3) Usuario actual + perfil por defecto (lo heredan los usuarios nuevos, p. ej. los del dominio)
    try { Set-UserDebloatValues 'HKCU:'; $res.policies += "usuario actual ($env:USERNAME)" } catch { $res.errors += "usuario actual: $($_.Exception.Message)" }
    $hive = Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT'
    if (Test-Path $hive) {
        & reg.exe load 'HKU\NDDefault' $hive 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            try { Set-UserDebloatValues 'Registry::HKEY_USERS\NDDefault'; $res.policies += 'perfil por defecto (usuarios nuevos)' }
            catch { $res.errors += "perfil por defecto: $($_.Exception.Message)" }
            finally { [gc]::Collect(); [gc]::WaitForPendingFinalizers(); & reg.exe unload 'HKU\NDDefault' 2>&1 | Out-Null }
        } else { $res.errors += 'perfil por defecto: no se pudo cargar NTUSER.DAT' }
    }
    Invoke-RegistryFlush
    $res.seconds = [int]$sw.Elapsed.TotalSeconds
    return $res
}

function Invoke-RegistryFlush {
    # Windows guarda el registro en disco con retraso: si el equipo se apaga de golpe justo despues, los
    # ultimos cambios se pierden (visto en el laboratorio). RegFlushKey los escribe ya.
    foreach ($k in 'SOFTWARE', 'SYSTEM') {
        try { $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($k); $key.Flush(); $key.Close() } catch {}
    }
    try { [Microsoft.Win32.Registry]::CurrentUser.Flush() } catch {}
}

function Set-StartupApprovedState {
    # Mismo formato que el Administrador de tareas: 02 = habilitado, 03 + FILETIME = deshabilitado.
    param([string]$Key, [string]$Name, [bool]$Enabled)
    $val = if ($Enabled) { [byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) } else { [byte[]](@(3, 0, 0, 0) + [BitConverter]::GetBytes([DateTime]::UtcNow.ToFileTimeUtc())) }
    Set-RegValue $Key $Name $val 'Binary'
}

function Set-StartupPolicy {
    $res = [ordered]@{}
    $sa  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    $off = 'b4notify|Bit4id|Everything\.exe|\\PDF24\\|pdf24\.exe|Wondershare|PDFelement'
    # Run de todo el equipo (64 y 32 bits)
    foreach ($spec in @(@{ Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Approved = 'Run' },
                        @{ Key = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = 'Run32' })) {
        $p = Get-ItemProperty -Path $spec.Key -ErrorAction SilentlyContinue
        if (-not $p) { continue }
        foreach ($v in @($p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })) {
            if ("$($v.Name) $($v.Value)" -match 'AnyDesk') { Set-StartupApprovedState "$sa\$($spec.Approved)" $v.Name $true; $res[$v.Name] = 'habilitado (obligatorio)' }
            elseif ("$($v.Name) $($v.Value)" -match $off) { Set-StartupApprovedState "$sa\$($spec.Approved)" $v.Name $false; $res[$v.Name] = 'deshabilitado' }
        }
    }
    # Carpeta Inicio común (todos los usuarios)
    $folder = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp'
    foreach ($f in @(Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue)) {
        if ($f.Name -match 'AnyDesk') { Set-StartupApprovedState "$sa\StartupFolder" $f.Name $true; $res[$f.Name] = 'habilitado (obligatorio)' }
        elseif ($f.Name -match $off -or $f.Name -match 'PDF24') { Set-StartupApprovedState "$sa\StartupFolder" $f.Name $false; $res[$f.Name] = 'deshabilitado' }
    }
    # Edge: sin "startup boost" ni seguir en segundo plano al cerrarlo (todos los usuarios)
    try {
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'StartupBoostEnabled' 0
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'BackgroundModeEnabled' 0
        $res['Microsoft Edge'] = 'sin arranque ni segundo plano (directiva)'
    } catch { $res['Microsoft Edge'] = "ERROR: $($_.Exception.Message)" }
    # AnyDesk obligatorio en segundo plano
    $svcs = @(Get-Service -Name 'AnyDesk*' -ErrorAction SilentlyContinue)
    if (-not $svcs) { $res['AnyDesk'] = 'AVISO: servicio no encontrado' }
    foreach ($s in $svcs) {
        try {
            Set-Service -Name $s.Name -StartupType Automatic -ErrorAction Stop
            if ((Get-Service -Name $s.Name).Status -ne 'Running') { Start-Service -Name $s.Name -ErrorAction Stop }
            & sc.exe failure $s.Name 'reset=' 86400 'actions=' 'restart/5000/restart/5000/restart/10000' | Out-Null
            $res["servicio $($s.Name)"] = "automatico, $((Get-Service -Name $s.Name).Status), reinicio si se cae"
        } catch { $res["servicio $($s.Name)"] = "ERROR: $($_.Exception.Message)" }
    }
    foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') {
        foreach ($k in @(Get-ChildItem -Path $root -ErrorAction SilentlyContinue)) {
            $dn = (Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue).DisplayName
            if ($dn -like 'AnyDesk*') { Set-RegValue $k.PSPath 'NoRemove' 1; Set-RegValue $k.PSPath 'NoModify' 1; $res['AnyDesk (desinstalar)'] = 'sin boton Desinstalar' }
        }
    }
    Invoke-RegistryFlush
    return $res
}

function Get-OptimizeChecks {
    $res = [ordered]@{}
    # TRIM del SSD (0 = activo). Si estuviera desactivado, se activa.
    $q = (& fsutil behavior query DisableDeleteNotify 2>&1) -join ' '
    if ($q -match 'NTFS DisableDeleteNotify\s*=\s*(\d)') {
        if ([int]$matches[1] -eq 0) { $res['TRIM (SSD)'] = 'activo' }
        else { & fsutil behavior set DisableDeleteNotify 0 | Out-Null; $res['TRIM (SSD)'] = 'estaba desactivado: activado' }
    } else { $res['TRIM (SSD)'] = "no se pudo leer ($q)" }
    # Software del fabricante / de prueba que conviene revisar (no se desinstala solo; Lenovo se respeta)
    $bloat = 'McAfee|Norton|WildTangent|Booking|ExpressVPN|Dropbox|HP Wolf|SupportAssist|MyASUS|Avast|AVG|CCleaner|Amazon|Netflix|Spotify|Candy|Keeper|Trend Micro|Kaspersky'
    $found = @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match $bloat -and $_.DisplayName -notmatch 'Lenovo' } | ForEach-Object { $_.DisplayName } | Sort-Object -Unique)
    $res['Preinstalado a revisar'] = if ($found) { ($found -join '; ') + $(if ($found -match 'McAfee|Norton|Avast|AVG|Kaspersky|Trend Micro') { '  <- antivirus de prueba: choca con ESET/Cortex, quitalo' }) } else { 'nada' }
    # Lo que sigue arrancando con Windows (todo el equipo)
    $sa = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    $on = @()
    foreach ($spec in @(@{ Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Approved = 'Run' },
                        @{ Key = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = 'Run32' })) {
        $p = Get-ItemProperty -Path $spec.Key -ErrorAction SilentlyContinue
        if (-not $p) { continue }
        foreach ($v in @($p.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })) {
            $st = (Get-ItemProperty -Path "$sa\$($spec.Approved)" -Name $v.Name -ErrorAction SilentlyContinue).($v.Name)
            if (-not $st -or ($st[0] % 2) -eq 0) { $on += $v.Name }
        }
    }
    $folder = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp'
    foreach ($f in @(Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue)) {
        $st = (Get-ItemProperty -Path "$sa\StartupFolder" -Name $f.Name -ErrorAction SilentlyContinue).($f.Name)
        if (-not $st -or ($st[0] % 2) -eq 0) { $on += $f.BaseName }
    }
    $res['Sigue arrancando con Windows'] = if ($on) { ($on | Sort-Object -Unique) -join ', ' } else { 'nada' }
    return $res
}

function Start-WindowsUpdateScan {
    # Solo lanza la búsqueda (no espera ni reinicia): Windows descarga e instala en su horario.
    try {
        $uso = Join-Path $env:SystemRoot 'System32\UsoClient.exe'
        if (Test-Path $uso) { Start-Process -FilePath $uso -ArgumentList 'StartScan' -WindowStyle Hidden; return 'busqueda lanzada en segundo plano' }
        (New-Object -ComObject Microsoft.Update.AutoUpdate).DetectNow()
        return 'busqueda lanzada en segundo plano'
    } catch { return "no se pudo lanzar: $($_.Exception.Message)" }
}

# Modo suelto: limpieza en segundo plano lanzada por Deploy.ps1
if ($OptimizeMode -eq 'debloat') {
    $r = try { Invoke-Debloat } catch { [ordered]@{ removed = @(); errors = @("excepcion: $($_.Exception.Message)"); policies = @(); seconds = 0 } }
    if ($OptimizeOutJson) { $r | ConvertTo-Json -Depth 4 | Set-Content -Path $OptimizeOutJson -Encoding UTF8 }
    exit 0
}
