<#
    Se ejecuta DENTRO de la VM: prueba el cierre del equipo (Finalize.ps1). Nunca en el host.
    Simula el portatil (cuenta 'usuario' administradora) y comprueba:
      1) Administrador integrado activado con la contraseña indicada (se valida la contraseña)
      2) 'usuario' fuera de Administradores
      3) segunda pasada idempotente
      4) dominio inexistente -> error controlado, sin tocar nada mas
    Las contraseñas se generan al azar aqui (nunca van al repo).
#>
$ErrorActionPreference = 'Stop'
$out = 'C:\LabRun\finalize_test.txt'
New-Item -ItemType Directory -Force -Path 'C:\LabRun' | Out-Null
Set-Content -Path $out -Value "== Test-Finalize $(Get-Date -Format 's')" -Encoding UTF8
function Write-Log { param([string]$Message, [string]$Level = 'INFO') Add-Content -Path $out -Value "   [$Level] $Message" -Encoding UTF8 }
function Out-Check { param([string]$Name, [bool]$Ok, [string]$Info = '') Add-Content -Path $out -Value ("CHECK {0,-4} {1} {2}" -f $(if ($Ok) { 'OK' } else { 'FAIL' }), $Name, $Info) -Encoding UTF8 }
function New-RandomPassword { 'Lb' + [guid]::NewGuid().ToString('N').Substring(0, 12) + '!7a' }
function Test-UsuarioAdmin { @(Get-LocalGroupMember -SID 'S-1-5-32-544' | Where-Object { $_.Name -match '\\usuario$' }).Count -gt 0 }

try {
    if (-not (Get-LocalUser -Name 'usuario' -ErrorAction SilentlyContinue)) {
        New-LocalUser -Name 'usuario' -Password (ConvertTo-SecureString (New-RandomPassword) -AsPlainText -Force) | Out-Null
    }
    try { Add-LocalGroupMember -SID 'S-1-5-32-544' -Member 'usuario' -ErrorAction Stop } catch {}
    Out-Check 'usuario es administrador antes' (Test-UsuarioAdmin)

    . 'C:\nodedeploy\NodeDeploy_Run\PRO\Finalize.ps1'
    $plain = New-RandomPassword
    $pw    = ConvertTo-SecureString $plain -AsPlainText -Force
    $state = [pscustomobject]@{ reboot_required = $false }

    $r1 = Invoke-Finalize -Answers @{ Domain = $null; DomainCredential = $null; AdminPassword = $pw } -State $state -StandardUser 'usuario'
    $r1.GetEnumerator() | ForEach-Object { Add-Content -Path $out -Value "   1) $($_.Key): $($_.Value)" }
    $adm = Get-LocalUser | Where-Object { $_.SID.Value -match '-500$' }
    Out-Check 'Administrador activado' ([bool]$adm.Enabled) $adm.Name
    Add-Type -AssemblyName System.DirectoryServices.AccountManagement
    $ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('Machine')
    Out-Check 'contraseña del Administrador valida' ($ctx.ValidateCredentials($adm.Name, $plain))
    Out-Check 'usuario fuera de Administradores' (-not (Test-UsuarioAdmin))
    Out-Check 'sin reinicio pendiente (sin dominio)' (-not $state.reboot_required)

    # Relanzar el script en un equipo ya terminado: no debe volver a pedir la contraseña del Administrador
    function Read-Host { throw 'Read-Host: no deberia preguntar nada' }
    $ans = Read-FinalizeAnswers -Domain 'no'
    Out-Check 'relanzar: no pide la contraseña del Administrador' ([bool]$ans.AdminReady -and -not $ans.AdminPassword)
    $r4 = Invoke-Finalize -Answers $ans -State $state -StandardUser 'usuario'
    $r4.GetEnumerator() | ForEach-Object { Add-Content -Path $out -Value "   R) $($_.Key): $($_.Value)" }
    Out-Check 'relanzar: Administrador ya estaba activado' ("$($r4['Administrador local'])" -like '*ya estaba activado*')
    Remove-Item -Path function:\Read-Host

    $r2 = Invoke-Finalize -Answers @{ Domain = $null; DomainCredential = $null; AdminPassword = $pw } -State $state -StandardUser 'usuario'
    $r2.GetEnumerator() | ForEach-Object { Add-Content -Path $out -Value "   2) $($_.Key): $($_.Value)" }
    Out-Check 'segunda pasada idempotente' ("$($r2['Usuario estandar'])" -like '*ya no era administrador*')

    $cred = New-Object System.Management.Automation.PSCredential('inexistente\nadie', (ConvertTo-SecureString (New-RandomPassword) -AsPlainText -Force))
    $r3 = Invoke-Finalize -Answers @{ Domain = 'dominio-inexistente.local'; DomainCredential = $cred; AdminPassword = $pw } -State $state -StandardUser 'usuario'
    $r3.GetEnumerator() | ForEach-Object { Add-Content -Path $out -Value "   3) $($_.Key): $($_.Value)" }
    Out-Check 'dominio inexistente -> error controlado' ("$($r3['Dominio'])" -like 'ERROR:*')
    Out-Check 'el equipo sigue fuera de dominio' (-not (Get-CimInstance Win32_ComputerSystem).PartOfDomain)
    exit 0
} catch {
    Add-Content -Path $out -Value "EXCEPCION: $($_.Exception.Message)"
    exit 1
}
