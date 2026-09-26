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
      2) saca a 'usuario' del grupo Administradores (SID S-1-5-32-544), solo si 1) ha ido bien:
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

function Read-FinalizeAnswers {
    param([string]$Domain)
    if ([Console]::IsInputRedirected) {
        Write-Log 'Consola sin entrada interactiva: se omite el cierre del equipo (Administrador / usuario / dominio)' 'WARN'
        return $null
    }
    Write-Host ''
    Write-Host '================ CIERRE DEL EQUIPO ================' -ForegroundColor Cyan
    Write-Host ' Se aplica al final y solo si todas las apps quedan OK:' -ForegroundColor Cyan
    Write-Host ' Administrador local con contraseña, usuario fuera de Administradores y dominio.' -ForegroundColor Cyan
    Write-Host ''

    # 1) Dominio (o "no")
    $Domain = "$Domain".Trim()
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

    # 2) Contraseña del Administrador local (dos veces)
    $adminPw = $null
    for ($i = 1; $i -le 3 -and -not $adminPw; $i++) {
        $a = Read-Host 'Contraseña para el Administrador local' -AsSecureString
        if ($a.Length -eq 0) { Write-Host '  No puede estar vacía.' -ForegroundColor Yellow; continue }
        $b = Read-Host 'Repite la contraseña' -AsSecureString
        if (Test-SecureStringEqual $a $b) { $adminPw = $a } else { Write-Host '  No coinciden.' -ForegroundColor Yellow }
    }
    if (-not $adminPw) { Write-Log 'Sin contraseña valida para el Administrador: no se tocaran las cuentas locales' 'WARN' }

    $domTxt = if ($Domain) { "$Domain (usuario $($cred.UserName))" } else { 'no' }
    $admTxt = if ($adminPw) { 'contraseña recibida' } else { 'omitido' }
    Write-Log "Cierre del equipo al final: dominio=$domTxt | Administrador local=$admTxt" 'INFO'
    Write-Host ''
    return @{ Domain = $Domain; DomainCredential = $cred; AdminPassword = $adminPw }
}

function Invoke-Finalize {
    param($Answers, $State, [string]$StandardUser = 'usuario')
    $res = [ordered]@{ 'Administrador local' = 'omitido (sin contraseña)'; 'Usuario estandar' = 'omitido'; 'Dominio' = 'no solicitado' }

    # 1) Administrador integrado activado con contraseña
    $adminOk = $false
    if ($Answers.AdminPassword) {
        try {
            $adm = Get-LocalUser | Where-Object { $_.SID.Value -match '^S-1-5-21-.+-500$' } | Select-Object -First 1
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

    # 2) Usuario estandar fuera de Administradores (solo con el Administrador ya activo)
    if ($adminOk) {
        $u = Get-LocalUser -Name $StandardUser -ErrorAction SilentlyContinue
        if (-not $u) {
            $res['Usuario estandar'] = "no existe la cuenta local '$StandardUser'"
            Write-Log "[CIERRE] No existe la cuenta local '$StandardUser'" 'WARN'
        } else {
            try {
                # -Member espera un LocalPrincipal: se pasa la cuenta (un SecurityIdentifier no se convierte).
                Remove-LocalGroupMember -SID 'S-1-5-32-544' -Member $u -ErrorAction Stop
                $res['Usuario estandar'] = "'$($u.Name)' quitado de Administradores"
                Write-Log "[CIERRE] '$($u.Name)' quitado del grupo Administradores" 'OK'
            } catch {
                if ("$($_.FullyQualifiedErrorId)" -like 'MemberNotFound*') {
                    $res['Usuario estandar'] = "'$($u.Name)' ya no era administrador"
                    Write-Log "[CIERRE] '$($u.Name)' ya no estaba en Administradores" 'OK'
                } else {
                    $res['Usuario estandar'] = "ERROR: $($_.Exception.Message)"
                    Write-Log "[CIERRE] Quitar '$($u.Name)' de Administradores: $($_.Exception.Message)" 'ERROR'
                }
            }
        }
    } elseif ($Answers.AdminPassword) {
        $res['Usuario estandar'] = 'omitido: el Administrador no se pudo activar (no se deja el equipo sin administrador local)'
    }

    # 3) Dominio: lo ultimo
    if ($Answers.Domain) {
        $cs = Get-CimInstance Win32_ComputerSystem
        if ($cs.PartOfDomain -and $cs.Domain -ieq $Answers.Domain) {
            $res['Dominio'] = "ya estaba en $($cs.Domain)"
            Write-Log "[CIERRE] El equipo ya pertenece a $($cs.Domain)" 'OK'
        } else {
            try {
                Add-Computer -DomainName $Answers.Domain -Credential $Answers.DomainCredential -Force -ErrorAction Stop -WarningAction SilentlyContinue
                $State.reboot_required = $true
                $res['Dominio'] = "unido a $($Answers.Domain) (reinicia para completar)"
                Write-Log "[CIERRE] Equipo unido al dominio $($Answers.Domain). Reinicia para completar." 'OK'
            } catch {
                $res['Dominio'] = "ERROR: $($_.Exception.Message)"
                Write-Log "[CIERRE] Union al dominio $($Answers.Domain): $($_.Exception.Message)" 'ERROR'
            }
        }
    }
    return $res
}
