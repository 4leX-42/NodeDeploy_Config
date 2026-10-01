<#
.SYNOPSIS
    Cierre del equipo de NodeDeploy (se carga desde Deploy.ps1).

.DESCRIPTION
    Al arrancar, Read-FinalizeAnswers pregunta:
      - dominio al que unir el equipo ("no" = no unirlo) y, si hay dominio, un usuario con permiso
        para unir equipos;
      - la contraseña para el Administrador local.
    Al terminar, SOLO si todas las apps han quedado OK, Invoke-Finalize hace en este orden:
      1) activa el Administrador integrado (SID ...-500, "Administrador" en Windows en español) con esa contraseña;
      2) saca la cuenta estandar (usuario / Usuario / user / User) del grupo Administradores (SID S-1-5-32-544), solo si 1) ha ido bien:
         nunca se deja el equipo sin administrador local;
      3) lo ultimo, une el equipo al dominio (hace falta reiniciar).
    Las contraseñas solo viven en memoria: nunca se escriben en log, state ni informe.
#>

function Test-SecureStringEqual {
    param([Security.SecureString]$A, [Security.SecureString]$B)
    $pa = (New-Object System.Net.NetworkCredential('', $A)).Password
    $pb = (New-Object System.Net.NetworkCredential('', $B)).Password
    return ($pa -ceq $pb)
}

function Get-BuiltinAdmin {
    Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.SID.Value -match '^S-1-5-21-.+-500$' } | Select-Object -First 1
}

function Get-DomainList {
    # Dominios del menú: Dominios.txt junto a los scripts, una sede por línea ("Madrid = empresa.local"; # = comentario).
    # No va a git (el repo es público): si no está, el dominio se escribe a mano. Plantilla: Dominios.ejemplo.txt.
    $dir = if ($PSScriptRoot) { $PSScriptRoot } else { $Script:ScriptDir }
    $f = Join-Path $dir 'Dominios.txt'
    if (-not (Test-Path -LiteralPath $f)) { return @() }
    @(Get-Content -LiteralPath $f -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notlike '#*' } | ForEach-Object {
        if ($_ -match '^(.+?)\s*[=|-]\s*([A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+)$') { [pscustomobject]@{ Name = $matches[1].Trim(); Domain = $matches[2].ToLower() } }
    })
}

function Resolve-DomainAnswer {
    # Respuesta del menú: número de la lista -> ese dominio; 0 / no -> 'no'; número de "Otro" -> '*manual';
    # un dominio escrito (con punto) -> ese dominio; lo demás -> $null (se vuelve a preguntar).
    param([string]$Answer, $List)
    $a = "$Answer".Trim(); $n = @($List).Count
    if (-not $a) { return $null }
    if ($a -ieq 'no' -or $a -eq '0') { return 'no' }
    if ($a -match '^\d+$') {
        $k = [int]$a
        if ($k -ge 1 -and $k -le $n) { return @($List)[$k - 1].Domain }
        if ($k -eq $n + 1) { return '*manual' }
        return $null
    }
    if ($a -match '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$') { return $a.ToLower() }
    return $null
}

#region Consola de las preguntas del cierre
# Estilo terminal: verde sobre negro, menú con flechas. Solo caracteres WGL4 (están en Consolas y Lucida Console).
function Write-UiRule {
    param([string]$Title)
    $w = 70; try { $w = [Math]::Min(70, [Console]::WindowWidth - 3) } catch {}
    $pc = "$env:COMPUTERNAME"
    $fill = [Math]::Max(3, $w - 2 - 3 - 10 - 4 - $Title.Length - 2 - $pc.Length - 3)
    Write-Host ''
    Write-Host '  ══ ' -ForegroundColor DarkGreen -NoNewline
    Write-Host 'NODEDEPLOY' -ForegroundColor Green -NoNewline
    Write-Host ' ══ ' -ForegroundColor DarkGreen -NoNewline
    Write-Host $Title -ForegroundColor Gray -NoNewline
    Write-Host (' ' + ('═' * $fill) + ' ') -ForegroundColor DarkGreen -NoNewline
    Write-Host $pc -ForegroundColor Green -NoNewline
    Write-Host ' ══' -ForegroundColor DarkGreen
}
function Write-UiNote([string]$Text) { Write-Host "  $Text" -ForegroundColor DarkGray }
function Write-UiWarn([string]$Text) { Write-Host "  ! $Text" -ForegroundColor Yellow }
function Write-UiOk {
    param([string]$Label, [string]$Value)
    Write-Host '  » ' -ForegroundColor Green -NoNewline
    Write-Host "$Label " -ForegroundColor Gray -NoNewline
    Write-Host $Value -ForegroundColor Green
}
function Read-UiText {
    # Pregunta en una línea: "  › etiqueta  respuesta". -Secret: con asteriscos (SecureString).
    param([string]$Label, [switch]$Secret)
    Write-Host '  › ' -ForegroundColor Green -NoNewline
    Write-Host "$Label  " -ForegroundColor Gray -NoNewline
    if ($Secret) { return (Read-Host -AsSecureString) }
    return "$(Read-Host)".Trim()
}
function Select-UiOption {
    # Menú con flechas: ↑↓ (Inicio / Fin) mueven, el número salta a esa línea, Enter elige. Devuelve el índice
    # elegido, o $null si la consola no deja leer teclas (entonces se pregunta escribiendo, como antes).
    # $Script:UiKeys: cola de teclas ([ConsoleKeyInfo]; un [int] = pausa en ms), solo para probarlo en el laboratorio.
    param([object[]]$Rows, [string]$Title, [int]$Default = 0)
    # Hace falta consola de verdad (entrada y salida): si no, se pregunta escribiendo
    try {
        if ([Console]::IsOutputRedirected) { return $null }
        if (-not ($Script:UiKeys -and $Script:UiKeys.Count)) { if ([Console]::IsInputRedirected) { return $null }; $null = [Console]::KeyAvailable }
        $null = [Console]::CursorTop
    } catch { return $null }
    $nameW = 2 + (@($Rows | ForEach-Object { "$($_.Text)".Length }) | Measure-Object -Maximum).Maximum
    $hintW = (@($Rows | ForEach-Object { "$($_.Hint)".Length }) | Measure-Object -Maximum).Maximum
    $W = 5 + 2 + 2 + $nameW + $hintW + 3
    try { $W = [Math]::Min($W, [Console]::WindowWidth - 1) } catch {}
    Write-Host ''
    Write-Host "  $Title" -ForegroundColor Green -NoNewline
    Write-Host '   ↑↓ mover · enter elegir · o pulsa el número' -ForegroundColor DarkGreen
    Write-Host ''
    # Cada línea ocupa justo $W columnas (recortada si la ventana es estrecha): al redibujar, la barra y las
    # líneas normales se pisan enteras y nunca saltan de línea
    $cut = { param([string]$s, [int]$n) if ($n -le 0) { '' } elseif ($s.Length -gt $n) { $s.Substring(0, $n) } else { $s.PadRight($n) } }
    $draw = {
        param([int]$S)
        for ($i = 0; $i -lt $Rows.Count; $i++) {
            $r = $Rows[$i]
            if ($i -eq $S) {
                Write-Host '  ' -NoNewline
                Write-Host (& $cut (' ► {0,2}  {1}{2}' -f $r.Key, "$($r.Text)".PadRight($nameW), $r.Hint) ($W - 2)) -ForegroundColor Black -BackgroundColor Green
            } else {
                $line = & $cut ('{0,2}  {1}{2}' -f $r.Key, "$($r.Text)".PadRight($nameW), $r.Hint) ($W - 5)
                Write-Host '     ' -NoNewline
                Write-Host $line.Substring(0, [Math]::Min(4, $line.Length)) -ForegroundColor DarkGreen -NoNewline
                if ($line.Length -gt 4) {
                    $nm = $line.Substring(4, [Math]::Min($nameW, $line.Length - 4))
                    Write-Host $nm -ForegroundColor Green -NoNewline
                    Write-Host $line.Substring(4 + $nm.Length) -ForegroundColor DarkGray
                } else { Write-Host '' }
            }
        }
    }
    $sel = [Math]::Max(0, [Math]::Min($Default, $Rows.Count - 1))
    $cv = $null; try { $cv = [Console]::CursorVisible; [Console]::CursorVisible = $false } catch {}
    # Primero se reserva el sitio (si hace falta, la pantalla corre ahora) y se vuelve arriba: si la pantalla
    # corría mientras se dibujaba, la posición quedaba desplazada y al redibujar salían líneas repetidas
    # (en campo: "dos Madrid" al bajar)
    Write-Host ("`n" * ($Rows.Count - 1))
    [Console]::SetCursorPosition(0, [Math]::Max(0, [Console]::CursorTop - $Rows.Count))
    $top = [Console]::CursorTop
    & $draw $sel
    $buf = ''; $last = [datetime]::MinValue
    try {
        while ($true) {
            if ($Script:UiKeys -and $Script:UiKeys.Count) {
                $k = $Script:UiKeys.Dequeue()
                if ($k -is [int]) { Start-Sleep -Milliseconds $k; continue }
            } else { $k = [Console]::ReadKey($true) }
            $new = $sel
            switch ($k.Key) {
                'UpArrow'   { $new = ($sel - 1 + $Rows.Count) % $Rows.Count }
                'DownArrow' { $new = ($sel + 1) % $Rows.Count }
                'Home'      { $new = 0 }
                'End'       { $new = $Rows.Count - 1 }
                'Enter'     { return $sel }
                default {
                    # Número: salta a esa línea (dos cifras seguidas si la lista llega a 10)
                    if ("$($k.KeyChar)" -match '^\d$') {
                        if (((Get-Date) - $last).TotalMilliseconds -gt 900) { $buf = '' }
                        $buf += "$($k.KeyChar)"; $last = Get-Date
                        $j = -1
                        foreach ($cand in @($buf, "$($k.KeyChar)")) {
                            for ($i = 0; $i -lt $Rows.Count -and $j -lt 0; $i++) { if ("$($Rows[$i].Key)" -eq $cand) { $j = $i } }
                            if ($j -ge 0) { break }
                        }
                        if ($j -ge 0) { $new = $j }
                    }
                }
            }
            if ($new -ne $sel) { $sel = $new; [Console]::SetCursorPosition(0, $top); & $draw $sel }
        }
    } finally {
        try { if ($null -ne $cv) { [Console]::CursorVisible = $cv } } catch {}
        try { [Console]::SetCursorPosition(0, $top + $Rows.Count) } catch {}
    }
}
#endregion

function Read-DomainChoice {
    # Menú de Dominios.txt: 1..N = sedes, N+1 = otro (a mano), 0 = sin dominio; con flechas o el número.
    # Si la consola no deja leer teclas: lista y número escrito. Sin lista: se escribe el dominio.
    param($List)
    $n = @($List).Count
    $r = $null
    if ($n) {
        $rows = @(for ($i = 0; $i -lt $n; $i++) { [pscustomobject]@{ Key = "$($i + 1)"; Text = $List[$i].Name; Hint = $List[$i].Domain } }) +
                @([pscustomobject]@{ Key = "$($n + 1)"; Text = 'Otro'; Hint = 'escribirlo a mano' },
                  [pscustomobject]@{ Key = '0'; Text = 'Sin dominio'; Hint = 'no unir el equipo' })
        $ix = Select-UiOption -Rows $rows -Title 'dominio'
        if ($null -ne $ix) {
            $r = Resolve-DomainAnswer -Answer $rows[$ix].Key -List $List
        } else {
            for ($i = 0; $i -lt $rows.Count; $i++) { Write-Host ('     {0,2}  {1,-15} {2}' -f $rows[$i].Key, $rows[$i].Text, $rows[$i].Hint) -ForegroundColor Green }
            while (-not $r) {
                $r = Resolve-DomainAnswer -Answer (Read-UiText 'número') -List $List
                if (-not $r) { Write-UiWarn 'no válido: el número de la lista' }
            }
        }
    }
    while (-not $r -or $r -eq '*manual') {
        $r = Resolve-DomainAnswer -Answer (Read-UiText 'dominio (p. ej. empresa.local; no = sin dominio)') -List @()
        if (-not $r) { Write-UiWarn 'no válido: el dominio con punto, o no' }
    }
    $sel = @($List | Where-Object { $_.Domain -eq $r }) | Select-Object -First 1
    Write-Host ''
    Write-UiOk 'dominio' $(if ($r -eq 'no') { 'sin dominio' } elseif ($sel) { "$r · $($sel.Name)" } else { $r })
    return $r
}

function Read-FinalizeAnswers {
    param([string]$Domain)
    # Lo ya hecho en una pasada anterior no se vuelve a preguntar.
    $adm = Get-BuiltinAdmin
    $adminReady = [bool]($adm -and $adm.Enabled -and $adm.PasswordLastSet)
    $cs = Get-CimInstance Win32_ComputerSystem
    $inDomain = if ($cs.PartOfDomain) { $cs.Domain } else { $null }
    $needDomain = -not $inDomain -and -not "$Domain".Trim()
    $needAdmin  = -not $adminReady
    if (($needDomain -or $needAdmin) -and [Console]::IsInputRedirected) {
        Write-Log 'Consola sin entrada interactiva: no se puede preguntar; se omite lo que falte del cierre del equipo' 'WARN'
        $needDomain = $false; $needAdmin = $false
        if (-not "$Domain".Trim()) { $Domain = 'no' }
    }
    if ($needDomain -or $needAdmin) {
        Write-UiRule 'cierre del equipo'
        Write-UiNote 'se aplica al final y solo si todas las apps quedan OK:'
        Write-UiNote 'administrador local · usuario fuera de administradores · dominio'
    }
    if ($inDomain) { Write-UiNote "· ya está en el dominio $inDomain`: no se pregunta" }
    if ($adminReady) { Write-UiNote '· el administrador local ya tiene contraseña: no se vuelve a pedir' }

    # 1) Dominio (o "no"): menú numerado con Dominios.txt. -Domain también admite el número de la lista.
    $list = @(Get-DomainList)
    $Domain = "$Domain".Trim()
    if ($inDomain) { $Domain = 'no' }
    if ($Domain) { $r = Resolve-DomainAnswer -Answer $Domain -List $list; $Domain = if ($r -and $r -ne '*manual') { $r } else { '' } }
    if (-not $Domain) { $Domain = Read-DomainChoice -List $list }
    $cred = $null
    if ($Domain -ieq 'no') {
        $Domain = $null
    } else {
        $user = ''
        while (-not $user) { $user = Read-UiText "usuario de $Domain (con permiso para unir equipos)" }
        if ($user -notmatch '[\\@]') { $user = "$Domain\$user" }
        $pw = $null
        while (-not $pw -or $pw.Length -eq 0) { $pw = Read-UiText "contraseña de $user" -Secret }
        $cred = New-Object System.Management.Automation.PSCredential($user, $pw)
    }

    # 2) Contraseña del Administrador local (dos veces), salvo que ya este activado con contraseña
    $adminPw = $null
    for ($i = 1; $needAdmin -and $i -le 3 -and -not $adminPw; $i++) {
        $a = Read-UiText 'contraseña para el administrador local' -Secret
        if ($a.Length -eq 0) { Write-UiWarn 'no puede estar vacía'; continue }
        $b = Read-UiText 'repítela' -Secret
        if (Test-SecureStringEqual $a $b) { $adminPw = $a } else { Write-UiWarn 'no coinciden' }
    }
    if ($needAdmin -and -not $adminPw) { Write-Log 'Sin contraseña valida para el Administrador: no se tocaran las cuentas locales' 'WARN' }

    $domTxt = if ($Domain) { "$Domain (usuario $($cred.UserName))" } elseif ($inDomain) { "ya en $inDomain" } else { 'no' }
    $admTxt = if ($adminPw) { 'contraseña recibida' } elseif ($adminReady) { 'ya activado con contraseña' } else { 'omitido' }
    Write-Log "Cierre del equipo al final: dominio=$domTxt | Administrador local=$admTxt" 'INFO'
    Write-Host ''
    return @{ Domain = $Domain; DomainCredential = $cred; AdminPassword = $adminPw; AdminReady = $adminReady; InDomain = $inDomain }
}

function Invoke-Finalize {
    param($Answers, $State, [string[]]$StandardUser = @('usuario', 'user'))
    # Resultado verificable de cada paso (lo usa Deploy.ps1 para decidir el reinicio automatico)
    # DomainJoined = unido en esta pasada (pide reinicio); DomainDone = paso del dominio hecho (unido, ya estaba o "no").
    $Script:FinalizeStatus = @{ AdminOk = $false; UserOk = $false; DomainJoined = $false; DomainDone = $false }
    $res = [ordered]@{ 'Administrador local' = 'omitido (sin contraseña)'; 'Usuario estandar' = 'omitido'; 'Dominio' = 'no solicitado' }

    # 1) Administrador integrado activado con contraseña (si ya lo estaba de una pasada anterior, no se toca)
    $adminOk = $false
    if (-not $Answers.AdminPassword -and $Answers.AdminReady) {
        $adm = Get-BuiltinAdmin
        $adminOk = [bool]($adm -and $adm.Enabled)
        if ($adminOk) {
            $res['Administrador local'] = "'$($adm.Name)' ya estaba activado con contraseña"
            Write-Log "[CIERRE] Administrador local '$($adm.Name)' ya estaba activado con contraseña" 'OK'
        }
    }
    if ($Answers.AdminPassword) {
        try {
            $adm = Get-BuiltinAdmin
            if (-not $adm) { throw 'no se encuentra la cuenta Administrador integrada (SID -500)' }
            Set-LocalUser -SID $adm.SID -Password $Answers.AdminPassword -ErrorAction Stop
            Enable-LocalUser -SID $adm.SID -ErrorAction Stop
            $adminOk = $true
            $res['Administrador local'] = "'$($adm.Name)' activado con contraseña"
            Write-Log "[CIERRE] Administrador local '$($adm.Name)' activado con contraseña" 'OK'
        } catch {
            $res['Administrador local'] = "ERROR: $($_.Exception.Message)"
            Write-Log "[CIERRE] Administrador local: $($_.Exception.Message)" 'ERROR'
        }
    }

    # 2) Cuenta estandar fuera de Administradores (solo con el Administrador ya activo). Segun el portatil se
    #    llama usuario / Usuario / user / User: se buscan todos los nombres (Windows no distingue mayusculas).
    if ($adminOk) {
        $names = @($StandardUser | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $seen = @{}
        $accounts = @(foreach ($n in $names) {
            $u = Get-LocalUser -Name $n -ErrorAction SilentlyContinue
            if ($u -and -not $seen.ContainsKey($u.SID.Value)) { $seen[$u.SID.Value] = $true; $u }
        })
        if (-not $accounts) {
            $res['Usuario estandar'] = "no existe ninguna cuenta local ($($names -join ' / '))"
            Write-Log "[CIERRE] No existe ninguna cuenta local ($($names -join ' / '))" 'WARN'
        } else {
            $msgs = @()
            foreach ($u in $accounts) {
                try {
                    # -Member espera un LocalPrincipal: se pasa la cuenta (un SecurityIdentifier no se convierte).
                    Remove-LocalGroupMember -SID 'S-1-5-32-544' -Member $u -ErrorAction Stop
                    $msgs += "'$($u.Name)' quitado de Administradores"
                    Write-Log "[CIERRE] '$($u.Name)' quitado del grupo Administradores" 'OK'
                } catch {
                    if ("$($_.FullyQualifiedErrorId)" -like 'MemberNotFound*') {
                        $msgs += "'$($u.Name)' ya no era administrador"
                        Write-Log "[CIERRE] '$($u.Name)' ya no estaba en Administradores" 'OK'
                    } else {
                        $msgs += "ERROR '$($u.Name)': $($_.Exception.Message)"
                        Write-Log "[CIERRE] Quitar '$($u.Name)' de Administradores: $($_.Exception.Message)" 'ERROR'
                    }
                }
            }
            $res['Usuario estandar'] = $msgs -join '; '
            $Script:FinalizeStatus.UserOk = -not ($msgs -match '^ERROR')
        }
    } elseif ($Answers.AdminPassword) {
        $res['Usuario estandar'] = 'omitido: el Administrador no se pudo activar (no se deja el equipo sin administrador local)'
    }

    $Script:FinalizeStatus.AdminOk = [bool]$adminOk

    # 3) Dominio: lo ultimo
    if ($Answers.Domain) {
        $cs = Get-CimInstance Win32_ComputerSystem
        if ($cs.PartOfDomain -and $cs.Domain -ieq $Answers.Domain) {
            $Script:FinalizeStatus.DomainDone = $true
            $res['Dominio'] = "ya estaba en $($cs.Domain)"
            Write-Log "[CIERRE] El equipo ya pertenece a $($cs.Domain)" 'OK'
        } else {
            # Si Lenovo acaba de actualizar el controlador de red, la conexion tarda unos segundos en volver.
            for ($i = 0; $i -lt 18 -and -not (Resolve-DnsName -Name $Answers.Domain -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Seconds 5 }
            try {
                Add-Computer -DomainName $Answers.Domain -Credential $Answers.DomainCredential -Force -ErrorAction Stop -WarningAction SilentlyContinue
                $State.reboot_required = $true
                $Script:FinalizeStatus.DomainJoined = $true
                $Script:FinalizeStatus.DomainDone = $true
                $res['Dominio'] = "unido a $($Answers.Domain) (reinicia para completar)"
                Write-Log "[CIERRE] Equipo unido al dominio $($Answers.Domain). Reinicia para completar." 'OK'
            } catch {
                $res['Dominio'] = "ERROR: $($_.Exception.Message)"
                Write-Log "[CIERRE] Union al dominio $($Answers.Domain): $($_.Exception.Message)" 'ERROR'
            }
        }
    } elseif ($Answers.InDomain) {
        $Script:FinalizeStatus.DomainDone = $true
        $res['Dominio'] = "ya estaba en $($Answers.InDomain)"
    } else {
        $Script:FinalizeStatus.DomainDone = $true   # se contesto "no": sin dominio
    }
    return $res
}
