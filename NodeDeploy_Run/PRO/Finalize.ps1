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
        Write-Host ''
        Write-Host '================ CIERRE DEL EQUIPO ================' -ForegroundColor Cyan
        Write-Host ' Se aplica al final y solo si todas las apps quedan OK:' -ForegroundColor Cyan
        Write-Host ' Administrador local con contraseña, usuario fuera de Administradores y dominio.' -ForegroundColor Cyan
        Write-Host ''
    }
    if ($inDomain) { Write-Host "El equipo ya está en el dominio $inDomain`: no se pregunta el dominio." -ForegroundColor DarkGray }
    if ($adminReady) { Write-Host "El Administrador local ya está activado con contraseña: no se vuelve a pedir." -ForegroundColor DarkGray }

    # 1) Dominio (o "no")
    $Domain = "$Domain".Trim()
    if ($inDomain) { $Domain = 'no' }
    while (-not $Domain) { $Domain = "$(Read-Host 'Dominio al que unir el equipo (escribe no para no unirlo)')".Trim() }
    $cred = $null
    if ($Domain -ieq 'no') {
        $Domain = $null
    } else {
        $user = ''
        while (-not $user) { $user = "$(Read-Host "Usuario de $Domain con permiso para unir equipos")".Trim() }
        if ($user -notmatch '[\\@]') { $user = "$Domain\$user" }
        $pw = $null
        while (-not $pw -or $pw.Length -eq 0) { $pw = Read-Host "Contraseña de $user" -AsSecureString }
        $cred = New-Object System.Management.Automation.PSCredential($user, $pw)
    }

    # 2) Contraseña del Administrador local (dos veces), salvo que ya este activado con contraseña
    $adminPw = $null
    for ($i = 1; $needAdmin -and $i -le 3 -and -not $adminPw; $i++) {
        $a = Read-Host 'Contraseña para el Administrador local' -AsSecureString
        if ($a.Length -eq 0) { Write-Host '  No puede estar vacía.' -ForegroundColor Yellow; continue }
        $b = Read-Host 'Repite la contraseña' -AsSecureString
        if (Test-SecureStringEqual $a $b) { $adminPw = $a } else { Write-Host '  No coinciden.' -ForegroundColor Yellow }
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
    $Script:FinalizeStatus = @{ AdminOk = $false; UserOk = $false; DomainJoined = $false }
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
            $res['Dominio'] = "ya estaba en $($cs.Domain)"
            Write-Log "[CIERRE] El equipo ya pertenece a $($cs.Domain)" 'OK'
        } else {
            # Si Lenovo acaba de actualizar el controlador de red, la conexion tarda unos segundos en volver.
            for ($i = 0; $i -lt 18 -and -not (Resolve-DnsName -Name $Answers.Domain -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Seconds 5 }
            try {
                Add-Computer -DomainName $Answers.Domain -Credential $Answers.DomainCredential -Force -ErrorAction Stop -WarningAction SilentlyContinue
                $State.reboot_required = $true
                $Script:FinalizeStatus.DomainJoined = $true
                $res['Dominio'] = "unido a $($Answers.Domain) (reinicia para completar)"
                Write-Log "[CIERRE] Equipo unido al dominio $($Answers.Domain). Reinicia para completar." 'OK'
            } catch {
                $res['Dominio'] = "ERROR: $($_.Exception.Message)"
                Write-Log "[CIERRE] Union al dominio $($Answers.Domain): $($_.Exception.Message)" 'ERROR'
            }
        }
    } elseif ($Answers.InDomain) {
        $res['Dominio'] = "ya estaba en $($Answers.InDomain)"
    }
    return $res
}
