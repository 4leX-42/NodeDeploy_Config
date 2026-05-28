# Checklist validación manual post-deploy

> Tras `Deploy.bat full` exitoso, ejecutar estas comprobaciones antes de considerar el equipo listo.

## Servicios Windows (deben estar Running)

```powershell
Get-Service -Name @(
    'AnyDesk',
    'cyserver',          # Cortex XDR
    'CyveraService',     # Cortex XDR (alt)
    'EraAgentSvc',       # ESET Mgmt Agent
    'nebulaCERTagent',
    'ClickToRunSvc'      # Office C2R
) | Format-Table Name,Status,StartType,DisplayName
```

Resultado esperado: TODOS `Status=Running, StartType=Automatic`.

## Binarios en disco

```powershell
@(
    'C:\Program Files\Microsoft Office\root\Office16\OUTLOOK.EXE',
    'C:\Program Files\iManage\iManage Drive\iManageDrive.exe',
    'C:\Program Files\Google\Chrome\Application\chrome.exe',
    'C:\Program Files\AutoFirma\AutoFirma.exe',
    'C:\Program Files\Bit4id\Universal MW\bin\bit4xpki.exe',
    'C:\Program Files\Mitel\Connect Client\ConnectAgent.exe',
    'C:\Program Files\Wondershare\PDFelement\PDFelement.exe',
    'C:\Program Files\Vintegris\nebulaCERTagent\nebulaCERTagent.exe',
    'C:\Program Files\ESET\RemoteAdministrator\Agent\ERAAgent.exe'
) | ForEach-Object {
    if (Test-Path $_) { "OK  $_" } else { "MISS $_" }
}
```

## Registry Uninstall keys

```powershell
$keys = @('iManage Work','iManage Drive','iManage Agent',
          'Microsoft 365','Cortex XDR','ESET','AnyDesk','AqNet',
          'Nebula','AutoFirma','Bit4id','Chrome','PDFelement','Mitel')
$installed = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                              'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' `
                              -ErrorAction SilentlyContinue
foreach ($k in $keys) {
    $hit = $installed | Where-Object DisplayName -like "*$k*" | Select-Object -First 1
    if ($hit) { "OK   $k => $($hit.DisplayName) v$($hit.DisplayVersion)" }
    else      { "MISS $k" }
}
```

## Outlook iManage COM addin

```powershell
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins\*',
              'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins\*' `
              -ErrorAction SilentlyContinue |
    Where-Object PSChildName -match 'iManage' |
    ForEach-Object {
        $p = Get-ItemProperty $_.PSPath
        "$($_.PSChildName) -> $($p.FriendlyName) LoadBehavior=$($p.LoadBehavior)"
    }
```

LoadBehavior esperado: `3` (load at startup, connected).

## Reboot recommendation

Tras instalación de:
- Cortex XDR (filtros kernel)
- ESET (driver `ekrnEpfw`)
- iManage Drive (driver de filesystem)

Es **recomendado** reiniciar el equipo una vez al final. Si `Deploy.bat full` terminó con `exit 0` sin pedir reboot, esto es opcional pero buena práctica.

```powershell
# Forzar reboot inmediato (cierra sesión sin guardar)
shutdown /r /t 0 /f

# Reboot suave (60s warning)
shutdown /r /t 60 /c "NodeDeploy: reboot programado"
```

## Test post-reboot

Tras reiniciar, login → abrir Outlook:
1. Outlook arranca sin errores.
2. Cinta superior muestra **pestañas iManage** (Send & File, Save Attachments, etc.).
3. En la cinta hay un icono iManage para conectar al server (DMS).

Si la pestaña no aparece:
```powershell
# Verificar el addin carga
Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Office\Outlook\Addins\iManage.OEAddIn*' `
                 -ErrorAction SilentlyContinue
# LoadBehavior debe ser 3.

# Si LoadBehavior=2 o 1, forzar:
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins\iManage.OEAddIn' `
                 -Name LoadBehavior -Value 3
```

## ESET PROTECT enrollment

ESET Mgmt Agent debería aparecer en la consola ESMC/PROTECT Cloud en ~5 min:
- Servicio `EraAgentSvc` Running
- `C:\Program Files\ESET\RemoteAdministrator\Agent\Logs\status.html` muestra `Connected=true`
- Equipo aparece en https://eba.eset.com/ tras login

## Cortex XDR enrollment

- Servicio `cyserver` Running
- `C:\ProgramData\Cyvera\LocalSystem\Logs\` con logs activos
- Equipo aparece en Cortex Hub Andersen tras ~5 min

---

## Quick smoke test todo-en-uno

```powershell
# Ejecutar desde NodeDeploy_Run\PRO\
.\Validate.ps1
```

Si reporta `OK=15  PARTIAL=0  MISSING=0`, todo está validado.

---

_Generado: NodeDeploy PRO v4.0_
