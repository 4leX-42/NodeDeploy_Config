<#
    Se ejecuta DENTRO de la VM: deja las cuentas como en un portatil a medio preparar, para poder lanzar
    Deploy.bat entero sin preguntas: cuenta 'usuario' administradora y Administrador integrado ya activado
    con contrasena (aleatoria, generada aqui). Nunca en el host.
#>
$ErrorActionPreference = 'Stop'
$out = 'C:\LabRun\prep_accounts.txt'
New-Item -ItemType Directory -Force -Path 'C:\LabRun' | Out-Null
function New-RandomPassword { 'Lb' + [guid]::NewGuid().ToString('N').Substring(0, 12) + '!7a' }
try {
    if (-not (Get-LocalUser -Name 'usuario' -ErrorAction SilentlyContinue)) {
        New-LocalUser -Name 'usuario' -Password (ConvertTo-SecureString (New-RandomPassword) -AsPlainText -Force) | Out-Null
    }
    try { Add-LocalGroupMember -SID 'S-1-5-32-544' -Member 'usuario' -ErrorAction Stop } catch {}
    $adm = Get-LocalUser | Where-Object { $_.SID.Value -match '-500$' }
    Set-LocalUser -SID $adm.SID -Password (ConvertTo-SecureString (New-RandomPassword) -AsPlainText -Force)
    Enable-LocalUser -SID $adm.SID
    "usuario administrador; $($adm.Name) activado con contrasena" | Set-Content -Path $out -Encoding UTF8
    exit 0
} catch {
    "EXCEPCION: $($_.Exception.Message)" | Set-Content -Path $out -Encoding UTF8
    exit 1
}
