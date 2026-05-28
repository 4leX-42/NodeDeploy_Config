# MEMORIA TECNICA - Despliegue Desatendido NodeDeploy v3.3 (Local Run)

> **Fecha**: 2026-05-26
> **Operador**: support@es.andersen.com
> **Maquina**: VM Windows 11 Pro x64 (snapshot-capable)
> **Source**: `C:\Users\user\Desktop\1.Node_Preparation` (local, no UNC)
> **Workdir**: `C:\Users\user\Desktop\NodeDeploy_Run`
> **State + logs**: `C:\Users\user\Desktop\NodeDeploy_Run\state` (override del default `C:\testeo2.0\state`)

---

## 1. Resumen ejecutivo

El entorno ya dispone del **engine de despliegue NodeDeploy v3.3** (production-grade) en `1.Node_Preparation\Sc3.0\NodeDeploy.ps1` (1473 lineas). Es resumible, snapshot-safe, multi-fase, con state JSON + reports markdown + logs MSI verbosos. **No procede reescribir el engine**: se construye una capa de orquestacion local (launchers + preflight + quarantine + post-validate) que reutiliza el engine apuntando a la fuente local en vez de UNC.

**Estado del entorno (snapshot 2026-05-26 13:30)**:

| Check | Resultado |
|---|---|
| Privilegios admin | OK (`IsInRole: True`) |
| Disco libre C: | 34.9 GB (suficiente, ~6-8 GB instalacion) |
| OS | Windows 11 Pro 10.0.26200 x64 |
| Engine NodeDeploy.ps1 | Presente, v3.3, 1473 lineas |
| 15 instaladores config | Presentes (todos los archivos requeridos) |
| `configuration.xml` Office | Presente en `Sc3.0\` |
| **`install_config.ini` ESET** | **AUSENTE -> ESET se instalara unenrolled** |
| Conectividad Office CDN | Pendiente validar (Chrome/Office descargan online) |

---

## 2. Inventario apps (15 segun NodeDeploy_Config.html)

| # | App | Version | Archivo | Tech | Args silent | Tiempo esperado |
|---|---|---|---|---|---|---|
| 1 | AnyDesk | 7.0.15 | `AnyDesk.msi` (8 MB) | MSI | `/qn /norestart` | 12 s |
| 2 | AqNet | 4.7.2 | `AqNetInstalacion.msi` (66 MB) | MSI | `/qn /norestart` | 17 s |
| 3 | Nebula CertAgent | 5.0.0 (Vintegris) | `nebula-certAgent-winx64-5.0.0.msi` (25 MB) | MSI | `/qn /norestart` | 12 s |
| 4 | MDR / Cortex XDR | 8.2.2.49708 (Palo Alto) | `MDR_Windows_Andersen_8_2_x64.msi` (42 MB) | MSI | `/qn /norestart REBOOT=ReallySuppress` | 39 s |
| 5 | ESET Mgmt Agent | 13.1.1110 | `eset_msi.msi` (52 MB) + `install_config.ini` | MSI | `/qn /norestart` + ~6137 chars `P_*` props | 45 s |
| 6 | Google Chrome | (online stub) | `ChromeSetup.exe` (10 MB) | Bootstrap | `/silent /install` | 73 s (descarga ~80 MB) |
| 7 | Autofirma | 64 v1.9 | `Autofirma_64_v1_9_installer.exe` (130 MB) | NSIS | `/S` | 125 s |
| 8 | Bit4id Middleware | - | `Bit4id_Middleware.exe` (48 MB) | NSIS | `/S` | 29 s |
| 9 | PDFelement Business | 10.1.5 (Wondershare) | `pdfelement_business-15066_10.1.5.exe` (571 MB) | Inno Setup | `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /NOCANCEL /NOCLOSEAPPLICATIONS /CLOSEAPPLICATIONS` | 306 s |
| 10 | MitelConnect | - | `MitelConnect.exe` (151 MB) | InstallShield | `/s /v"/qn REBOOT=ReallySuppress"` | 87 s |
| 11 | Microsoft 365 Apps (Outlook Classic) | C2R Current | `OfficeSetup.exe` + `configuration.xml` | Office C2R | `/configure configuration.xml` | 300-480 s (descarga 600-800 MB) |
| 12 | iManage Agent Services | 10.9.4.39 | `Imanage 2.0\iManage Work Desktop...\iManageAgentServices.exe` (2 MB) | InstallShield | `/s /SMS /v"/qn REBOOT=ReallySuppress"` | 20 s |
| 13 | iManage Drive | 10.10.0.410 | `Imanage 2.0\...\iManageDriveSetup.exe` (242 MB) | WiX Burn | `/quiet /norestart /log <log>` | 97 s |
| 14 | iManage Drive Native | 10.6.1.15 | `Imanage 2.0\...\iManageDriveNative.exe` (0.7 MB) | WiX Burn | `/quiet /norestart /log <log>` | 10 s |
| 15 | iManage Work Desktop | 10.9.4.39 | `Imanage 2.0\...\iManageWorkDesktopforWindowsx64.exe` (70 MB) | InstallShield | `/s /SMS /v"/qn REBOOT=ReallySuppress"` | 59 s |

**Total local payload**: ~1.4 GB instaladores + ~700 MB descargas online (Office + Chrome).
**Tiempo total estimado**: 15-25 minutos (Office descarga en background paralelo).

---

## 3. Orden de instalacion (Grupos engine)

El engine procesa apps por grupo (numerico ascendente). Office C2R va a background al inicio (Phase 0c) -> descarga ~600 MB en paralelo mientras MSI/EXE corren.

| Grupo | Tipo | Apps |
|---|---|---|
| 1 | MSI Packages | AnyDesk, AqNet, Nebula, MDR/Cortex, ESET |
| 2 | EXE silent (NSIS/Chrome) | Chrome, Autofirma, Bit4id |
| 3 | Complex (Inno + IS) | PDFelement, MitelConnect |
| 4 | Office C2R | Microsoft 365 Apps (background, sincroniza al final) |
| 5 | iManage stack | Agent Services, Drive, Drive Native, Work Desktop |

**Razon del orden**:
- AV (Cortex/ESET) primero -> evita que detecten EXEs posteriores como sospechosos.
- iManage al final -> requiere Outlook (Office) ya instalado para integracion.
- Office en background -> aprovecha descarga lenta en paralelo con MSIs rapidos.

---

## 4. Dependencias y prerequisitos

### Runtime / SO
- Windows 10 1809+ o Windows 11 (validado en 11 Pro 10.0.26200).
- Arquitectura x64.
- PowerShell 5.1+ (default Windows 11).
- .NET Framework 4.7.2+ (default Windows 11).
- VC++ Redistributables 2015-2022 (la mayoria de installers incluyen los suyos).

### Permisos
- Cuenta admin local (UAC se auto-eleva via NodeDeploy.cmd).
- Acceso a internet HTTPS:
  - `*.officecdn.microsoft.com` (Office C2R)
  - `*.google.com / *.gvt1.com` (Chrome bootstrap)
  - ESET PROTECT Cloud FQDN (P_HOSTNAME del INI ausente)
  - PaloAlto Cortex cloud endpoint (se configura en MSI)

### Archivos requeridos presentes
- 15 instaladores: **OK**.
- `Sc3.0\configuration.xml`: **OK** (Outlook Classic only profile).
- `install_config.ini` ESET: **AUSENTE** -> ver seccion riesgos.

---

## 5. Validacion post-instalacion (por app)

Modelo `Test-InstalledStrict`: requiere al menos UNA evidencia entre `registry+appx+service+file`.

| App | Registry keyword | Servicio | Fichero |
|---|---|---|---|
| AnyDesk | AnyDesk | AnyDesk | `%ProgramFiles(x86)%\AnyDesk\AnyDesk.exe` |
| AqNet | AqNet/Aqnet/Deposito Digital/AQNET | - | - |
| Nebula CertAgent | Nebula/CertAgent | nebulaCERTagent/nebulaCERT | `%ProgramFiles%\Vintegris\nebulaCERTagent\nebulaCERTagent.exe` |
| MDR / Cortex XDR | Cortex XDR/Palo Alto/Traps | cyserver/CyveraService | - |
| ESET Mgmt Agent | ESET Management Agent | EraAgentSvc/ekrn | `%ProgramFiles%\ESET\RemoteAdministrator\Agent\ERAAgent.exe` |
| Google Chrome | Google Chrome | - | `%ProgramFiles%\Google\Chrome\Application\chrome.exe` |
| Autofirma | AutoFirma | - | `%ProgramFiles%\AutoFirma\AutoFirma.exe` |
| Bit4id Middleware | Bit4id/Universal Middleware | - | `%ProgramFiles%\Bit4id\Universal MW\bin\bit4xpki.exe` |
| PDFelement Business | PDFelement/Wondershare | - | `%ProgramFiles%\Wondershare\PDFelement\PDFelement.exe` |
| MitelConnect | Mitel/MiCollab/Mitel Connect | - | `%ProgramFiles%\Mitel\Connect Client\ConnectAgent.exe` |
| Microsoft 365 Apps | Microsoft 365 Apps/Office/Outlook | - | `%ProgramFiles%\Microsoft Office\root\Office16\OUTLOOK.EXE` |
| iManage Agent Services | iManage Agent/iManageAgent | - | - |
| iManage Drive | iManage Drive | - | `%ProgramFiles%\iManage\iManage Drive\iManageDrive.exe` |
| iManage Drive Native | iManage Drive Native | - | - |
| iManage Work Desktop | iManage Work Desktop/iManage Work | - | - |

**Smoke test extra post-deploy** (PostValidate.ps1):
- `Get-Service` estado de servicios criticos (Cortex `cyserver`, ESET `EraAgentSvc`).
- `Get-AuthenticodeSignature` sobre EXEs principales.
- Test lanzamiento headless de Chrome (`chrome.exe --version`).

---

## 6. Riesgos e incompatibilidades

| Riesgo | Severidad | Mitigacion |
|---|---|---|
| **`install_config.ini` ESET ausente** | ALTA | ESET se instalara unenrolled. Para enrolamiento: generar INI desde ESMC (Quick Links -> Installers -> Create Installer -> Download). Colocar en `C:\Users\user\Desktop\1.Node_Preparation\install_config.ini` ANTES de la fase real. Sin INI, el servicio EraAgentSvc arranca pero no conecta a ESET PROTECT Cloud. |
| Cortex XDR exit 1603 (reboot pending) | MEDIA | Engine detecta exit 3010/1641 como OK. Tras reboot, usar `Resume_LOCAL.cmd`. |
| Office download timeout (firewall) | MEDIA | Verificar conectividad a `*.officecdn.microsoft.com:443`. Timeout default 1800s. |
| Chrome stub falla offline | MEDIA | Stub requiere internet. Sin red, fall al MSI corporativo (no incluido). |
| PDFelement (571 MB Inno) lento o falla extraccion | BAJA | Engine tiene FallbackUI para PDFelement (UIPattern). Timeout 900s. |
| iManage Work Desktop hang por UAC | BAJA | KillProcesses + FallbackUI configurado. |
| Coexistencia Outlook Classic + New Outlook | INFO | Default C2R 16.0+ permite ambos. configuration.xml no fuerza ninguno. |
| Concurrencia con Windows Update | MEDIA | Recomendado pausar updates: `sc config wuauserv start= disabled` antes de deploy (revertir despues). |
| Snapshot revert mid-deploy | BAJA | State file en `C:\Users\user\Desktop\NodeDeploy_Run\state` sobrevive si fuera del scope del snapshot; engine re-valida contra OS real en relanzamiento. |

### Apps en folder NO incluidas en config (candidatas a quarantine)

| Archivo | Tamano | Motivo |
|---|---|---|
| `KeePassXC-2.7.10-Win64.msi` | 33 MB | No en config |
| `NanaZip.msixbundle` | 11 MB | No en config |
| `NanaZip Installer.exe` | 1 MB | No en config |
| `Instalar_D2_2025.exe` | 16 MB | No en config |
| `epi_win_live_installer.exe` | 16 MB | No en config |
| `OutlookClassic.exe` | 7 MB | No en config (Office C2R usa OfficeSetup.exe + XML) |
| `AqNet Instalacion Andersen\` (carpeta) | 67 MB | Duplicado de AqNetInstalacion.msi |
| `eset\agent_x64.msi` | 52 MB | Duplicado de eset_msi.msi |
| `eset\Sin confirmar 291089.crdownload` | 6 KB | Descarga incompleta |
| `SCRIPT-INSTALACION\` (carpeta) | 0.3 MB | Version antigua de NodeDeploy (abr 2026) |
| `debug.log` | 627 B | Log residual |

**Estrategia**: mover a `Quarantine\` (no borrar inmediato). Tras deploy OK, decidir delete.

---

## 7. Espacio en disco

| Concepto | GB |
|---|---|
| Libre actual C: | 34.9 |
| Payload instaladores local | ~1.4 |
| Instalado tras deploy (estimado) | ~6-8 |
| Office descarga + cache | ~1.5 |
| State + logs + reports | <0.1 |
| **Margen tras deploy** | ~25 GB |

Suficiente. No requiere limpieza previa.

---

## 8. Servicios y reinicios

### Servicios creados (deberian quedar Running tras instalacion)
- `AnyDesk` (AnyDesk)
- `cyserver` / `CyveraService` (Cortex XDR)
- `EraAgentSvc` (ESET Mgmt Agent)
- `nebulaCERTagent` (Nebula)

### Reinicio requerido?
- Cortex XDR puede pedir reboot (engine acepta exit 3010/1641 como OK).
- Mitel puede pedir reboot.
- Otros: no.
- **Recomendado**: 1 reboot post-deploy + `Resume_LOCAL.cmd` para revalidar.

---

## 9. Sistema de logs y state

```
C:\Users\user\Desktop\NodeDeploy_Run\
    MEMORIA_TECNICA.md            <- este archivo
    PREFLIGHT_REPORT.md           <- generado por Preflight.ps1
    Preflight.ps1                 <- pre-checks
    Quarantine.ps1                <- mueve extras a Quarantine\
    PostValidate.ps1              <- validacion profunda post-install
    0_Preflight.cmd               <- ejecutar PRIMERO
    1_ProbeOnly.cmd               <- dry-run probe (sin instalar)
    2_Quarantine.cmd              <- mover extras a Quarantine
    3_Deploy_REAL.cmd             <- DESPUES DEL SNAPSHOT
    4_Resume.cmd                  <- reanudar tras reboot
    5_PostValidate.cmd            <- validacion final
    state\
        nodedeploy_state.json     <- state engine
        logs\
            NodeDeploy_*.log      <- log maestro per sesion
            msi_*.log             <- /l*v per MSI
            burn_*.log            <- per WiX Burn
        reports\
            INDEX.md              <- tabla resumen
            <App>.md              <- per app
    Quarantine\                   <- creada por Quarantine.ps1
```

---

## 10. Plan de ejecucion (orden estricto)

1. **`0_Preflight.cmd`** -> valida prerequisitos + reporta estado. NO instala. NO modifica nada (excepto crear logs).
2. **`2_Quarantine.cmd`** -> mueve archivos no-config a `Quarantine\` (reversible, no borra).
3. **`1_ProbeOnly.cmd`** -> ejecuta NodeDeploy en modo `-ProbeOnly` -> genera reports sin instalar.
4. **REVISION HUMANA** del preflight + reports. Si OK -> avisar para snapshot.
5. **GATE SNAPSHOT** -> usuario crea snapshot VM. **Pausa explicita**.
6. **`3_Deploy_REAL.cmd`** -> ejecucion real (~15-25 min).
7. **`5_PostValidate.cmd`** -> valida servicios + lanza apps headless. Reporte final.
8. **Reinicio recomendado**.
9. **`4_Resume.cmd`** post-reboot -> revalida + reinstala faltantes.

---

## 11. Decisiones tecnicas

- **NO se reescribe el engine**: `NodeDeploy.ps1` v3.3 es production-grade. Se reutiliza tal cual via override de parametros (`-Source`, `-StatePath`).
- **State path fuera del UNC**: `C:\Users\user\Desktop\NodeDeploy_Run\state` para que sobreviva snapshot revert si el snapshot incluye Desktop. Si el snapshot revierte TODO el disco, el state se pierde y el engine arranca limpio (esperado).
- **NoPreCache**: con fuente local no aplica robocopy UNC->local; engine lo skipea automaticamente.
- **SkipFinalize por default en `3_Deploy_REAL.cmd`**: NO se lanza sysdm.cpl ni lusrmgr.msc (no aplica si la VM no se va a unir a dominio en este ciclo). Comentar en `.cmd` para revertir.
- **MaxRetries 2** (default engine): suficiente para errores transitorios.
- **Quarantine antes que delete**: usuario tiene snapshot, pero quarantine es zero-risk extra.

---

_Generado: 2026-05-26 / Sesion preflight: pendiente_
