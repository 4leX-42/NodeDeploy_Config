# NodeDeploy v3.1 - Production rollout

Despliegue desatendido de 15 aplicaciones corporativas para equipos Andersen.

## Ubicacion produccion

```
\\192.168.2.8\utilidades\1.Node_Preparation\
    Sc3.0\
        NodeDeploy.ps1               <- engine principal
        configuration.xml            <- Office Outlook Classic only
        NodeDeploy.cmd               <- LAUNCHER (doble-click esto)
        1.Node_Preparation_RESUME.cmd<- reanudar tras reboot
        0.Probe_Only.cmd             <- validar sin instalar
        README.md                    <- este archivo
    AnyDesk.msi
    AqNetInstalacion.msi
    nebula-certAgent-winx64-5.0.0.msi
    MDR_Windows_Andersen_8_2_x64.msi
    eset_msi.msi
    install_config.ini               <- NECESARIO para ESET enrolamiento
    MitelConnect.exe
    pdfelement_business-15066_10.1.5.exe
    Bit4id_Middleware.exe
    ChromeSetup.exe
    Autofirma_64_v1_9_installer.exe
    OfficeSetup.exe
    Imanage 2.0\
        iManage Drive for Windows 10.10.0.410\...
        iManage Work Desktop for Windows 10.9.4.39 (x64 Office)\...
```

## Procedimiento tecnico (equipo nuevo)

1. Login con cuenta admin local.
2. Doble-click `NodeDeploy.cmd` desde el share (o desde shortcut desktop `Node_Preparation.lnk`).
3. Aceptar UAC.
4. Esperar ~25-45 min (Office C2R Outlook-only ~5-8min + resto).
5. Al final se abren automaticamente:
   - **sysdm.cpl** -> renombrar PC + Domain Join
   - **lusrmgr.msc** -> habilitar admin local
6. Reboot manual si el deploy lo marca pendiente (Cortex XDR + Mitel suelen pedirlo).

## Apps instaladas (15)

| App | Tipo | Args |
|---|---|---|
| AnyDesk | MSI | /qn /norestart |
| AqNet | MSI | /qn /norestart |
| Nebula CertAgent | MSI | /qn /norestart |
| MDR / Cortex XDR | MSI | /qn /norestart REBOOT=ReallySuppress |
| ESET Mgmt Agent | MSI | /qn /norestart + install_config.ini |
| Google Chrome | EXE | /silent /install |
| Autofirma | NSIS | /S |
| Bit4id Middleware | NSIS | /S |
| PDFelement Business | Inno Setup | /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- |
| MitelConnect | InstallShield | /s /v"/qn REBOOT=ReallySuppress" |
| Office Outlook Classic | C2R | /configure configuration.xml |
| iManage Agent Services | InstallShield | /s /SMS /v"/qn REBOOT=ReallySuppress" |
| iManage Drive | WiX Burn | /quiet /norestart |
| iManage Drive Native | WiX Burn | /quiet /norestart |
| iManage Work Desktop | InstallShield | /s /SMS /v"/qn REBOOT=ReallySuppress" |

## State + logs (local por equipo)

```
C:\testeo2.0\state\
    nodedeploy_state.json    <- estado actual + historico per app
    logs\
        NodeDeploy_*.log     <- log maestro de sesion
        msi_*.log            <- log verboso por MSI
        burn_*.log           <- log WiX Burn
    reports\
        INDEX.md             <- tabla resumen
        <App>.md             <- informe tecnico per app
```

## Resume tras snapshot revert / reboot

NodeDeploy es resumible. Al relanzarlo:
1. Lee `state.json` si existe.
2. Re-valida cada app contra registro real (Test-InstalledStrict).
3. Apps OK + presentes en OS -> SKIP.
4. Apps OK en state pero ausentes en OS (post-revert) -> reinstala.
5. Apps fail -> reintenta hasta -MaxRetries (default 2).
6. Apps pendientes -> instala.

## Flags PowerShell

```
NodeDeploy.ps1
  -Source <path>          Override UNC (default \\192.168.2.8\utilidades\1.Node_Preparation)
  -StatePath <path>       Override state local (default C:\testeo2.0\state)
  -ProbeOnly              Fingerprint + reports, no instala
  -ResumeOnly             No reintenta fallidos
  -MaxRetries <n>         Default 2
  -SkipFinalize           Suprime Phase 4 (sysdm.cpl + lusrmgr.msc)
```

## Mantenimiento

### Anadir nueva app

Editar `$Script:Apps` en `NodeDeploy.ps1`:

```powershell
@{
    Name      = 'MiApp'
    File      = 'MiApp.msi'        # o Path = 'subdir\MiApp.exe'
    Type      = 'msi'              # msi|nsis|inno|installshield|burn|chrome|office|msixbundle
    Args      = '/qn /norestart'   # ignorado para 'msi' (auto)
    Detect    = @('MiApp','Mi App')
    FilePaths = @("$env:ProgramFiles\MiApp\miapp.exe")
    Group     = 1   # 1=MSI, 2=EXE silent, 3=Complex, 4=Office, 5=iManage
}
```

### Cambiar perfil Office

Editar `configuration.xml` -> `ExcludeApp` para anadir/quitar apps. Tras editar, reinstalar Office:
```
& '\\192.168.2.8\utilidades\1.Node_Preparation\OfficeSetup.exe' /configure '\\192.168.2.8\utilidades\1.Node_Preparation\Sc3.0\configuration.xml'
```

### ESET sin INI

ESET Mgmt Agent FAILa sin `install_config.ini`. Genera el INI desde ESMC:
**Quick Links -> Installers -> Install Agent -> Create Installer -> Download installer + config**.
Pega `install_config.ini` en `\\192.168.2.8\utilidades\1.Node_Preparation\` (mismo nivel que `eset_msi.msi`). MSI lo detecta auto via OriginalDatabase property.

## Phase 4 final - controles manuales

Tras instalacion, el script abre:

- **sysdm.cpl** (System Properties):
  - Boton "Change..." -> Computer name = `AND-XXXX`
  - Member of: Domain `andersen.es` (o el que aplique)
  - Credenciales de Domain Admin

- **lusrmgr.msc** (Local Users and Groups):
  - Users -> Administrador -> Properties -> uncheck "Account is disabled"
  - Set password
  - (opcional) Agregar usuario admin local secundario

## Troubleshooting

| Sintoma | Causa probable | Fix |
|---|---|---|
| `FATAL Source no existe` | UNC unreachable | `net use Y: \\192.168.2.8\utilidades` con cred dominio |
| Office timeout 1800s | descarga lenta/firewall | revisar proxy + ports 80/443 a *.officecdn.microsoft.com |
| Cortex XDR exit 1603 | reboot pending de install previo | reboot equipo + relanzar `1.Node_Preparation_RESUME.cmd` |
| iManage Work Desktop hang | UAC prompt oculto | matar `iManage*` y relanzar |
| Todo SKIP de inmediato | state file pre-existente con OK | borrar `C:\testeo2.0\state\nodedeploy_state.json` |

## Version

v3.1 - 2026-05-12 - Production rollout para `\\192.168.2.8\utilidades\1.Node_Preparation\Sc3.0`
