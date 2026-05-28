# NodeDeploy PRO v4.2

> Despliegue desatendido production-grade para 15 aplicaciones corporativas Andersen.
> Office en background paralelo, snapshot-safe, resumible, validado, USB/Intune/Autopilot ready.

---

## TL;DR — uso en equipo nuevo

1. Copia toda la estructura `1.Node_Preparation\` + `NodeDeploy_Run\` al equipo destino. La ruta exacta no importa (todo es relativo).
2. Doble clic sobre `NodeDeploy_Run\PRO\Deploy.bat`.
3. Acepta el UAC.
4. Espera 15-20 min. Office instala en background mientras grupos 1-3 corren en paralelo.
5. El script abre Notepad con el reporte final cuando termine.

Si el reporte indica **REBOOT REQUIRED**, reinicia y ejecuta `Deploy.bat resume`.

---

## Root cause iManage Work Desktop -2147213312 (0x80042000) — RESUELTO en v4.2

iManage Work Desktop 10.9.4.39 (`iManageWorkDesktopforWindowsx64.exe`) tiene **dos prereqs hard** verificados por su InstallScript ANTES de mostrar UI. Si cualquiera falta, aborta con HRESULT `0x80042000` ("Aborted by user" silencioso). IS engine setup.log siempre dice `ResultCode=0` (porque dialogs aceptados); el InstallScript abort retorna -2147213312.

**Diagnostico real** (habilitar `HKLM:\SOFTWARE\InstallShield\29.0\Professional\DoVerboseLogging=1` y leer `%TEMP%\workdesktop_v109_*.log`):

```
### ERROR ###  Work Desktop install did not detect iManage Agent Services is installed.
### ERROR ###  Work Desktop install did not detect MS Office is installed.
```

**Causa raiz**:

1. **iManage Agent Services** debe estar preinstalado (mismo bundle, ejecutable propio `iManageAgentServices.exe`).
2. **Microsoft Office con Word presente** — Outlook solo NO basta. WD detecta Office via MsiQueryProductState + ClickToRun virtual reg que requiere Word/Excel registrados.

El XML `configuration.xml` v4.0/4.1 excluia Word/Excel/PowerPoint (perfil "Outlook only" ~600MB). Con ese perfil, WD aborta silenciosamente.

**Fixes v4.2 aplicados**:

| # | Fix | Detalle |
|---|---|---|
| 1 | `configuration.xml` Office completo | Word+Excel+PowerPoint+Outlook. Backup viejo en `configuration_OutlookOnly.xml.bak`. |
| 2 | Detect Office cambiado a WINWORD.EXE | Mejor proxy de "Office completo" que Outlook (que puede instalarse standalone). |
| 3 | Gate Work Desktop endurecido | Verifica explicito OUTLOOK.EXE + WINWORD.EXE + Agent Services antes de lanzar. Si falta cualquiera -> fail con error claro (no -2147213312 silencioso). |
| 4 | Smart bootstrap detection ajustado | OutlookClassic.exe bootstrap solo si Word presente AND Outlook ausente. |
| 5 | Office BACKGROUND paralelo (v4.1) | Office Grupo 4 via `Start-Process -PassThru` al inicio. Grupos 1-3 en paralelo. Wait antes Grupo 5. |
| 6 | Handler installshield-imanage | Sintaxis docs `/s setup.iss` positional. Path corto sin espacios. setup.iss bundled extraido del propio wrapper. |
| 7 | MDR Cortex XDR Grupo 6 | Ultimo grupo. Evita behavioral block del IS runtime iManage. |

---

## Estructura

```
nodedeploy\
├── 1.Node_Preparation\          ← 15 instaladores + Office XML + ESET INI
│   ├── *.msi, *.exe (15 apps)
│   ├── ESET_Endpoint\           ← Endpoint security pkg
│   ├── Sc3.0\
│   │   ├── configuration.xml                         (v4.2: Word+Excel+PPT+Outlook)
│   │   ├── configuration_OutlookOnly.xml.bak         (v4.0 backup, NO compatible WD)
│   │   └── addOfficeApps.xml                         (XML para anadir Word/Excel/PPT a baseline)
│   └── Imanage 2.0\
└── NodeDeploy_Run\
    ├── PRO\                     ← PRODUCTION v4.2
    │   ├── Deploy.bat           ← LAUNCHER (doble clic aqui)
    │   ├── Deploy.ps1           ← engine production-grade v4.2.0
    │   ├── Validate.ps1         ← smoke tests post-instalacion
    │   ├── Uninstall.ps1        ← helper de reset
    │   ├── README.md            ← este documento
    │   ├── QUICK_START.md       ← guia de 1 pagina
    │   ├── CHECKLIST.md         ← checklist deployment
    │   └── NodeDeploy_v4.html   ← dashboard tecnico
    ├── _legacy\                 ← v3.x deprecado
    ├── PERSIST\                 ← ESET endpoint bundle persistente
    └── state\                   ← generado al ejecutar
        ├── nodedeploy_state.json
        ├── logs\Deploy_*.log
        ├── logs\msi_*.log
        ├── logs\is_*.log
        └── logs\burn_*.log
```

---

## Modos de ejecucion

| Comando | Accion |
|---|---|
| `Deploy.bat` | Full deploy (default). Probe + Install + Validate. |
| `Deploy.bat probe` | Solo verifica archivos presentes. No instala nada. |
| `Deploy.bat install` | Instala asumiendo que ya validaste con probe. |
| `Deploy.bat resume` | Reintenta apps con status `fail` o `deferred_reboot`. |
| `Deploy.bat validate` | Smoke tests sobre lo instalado. Sin tocar nada. |
| `Deploy.bat cleanup` | Mata procesos iManage residuales (para reintentos). |

**Flags PowerShell directo (Deploy.ps1)**:

| Flag | Efecto |
|---|---|
| `-Phase full\|probe\|install\|validate\|resume\|cleanup` | Selecciona fase. |
| `-Source <path>` | Carpeta de instaladores. Default: relativo al script. |
| `-StatePath <path>` | Persistencia state + logs. Default: relativo. |
| `-SkipApps 'name1','name2'` | Excluye apps por display name. |
| `-NoOffice` | Salta Office (test rapido). |
| `-SequentialOffice` | Office bloqueante en su turno (revierte modo v4.0). |
| `-ForceReinstall` | Ignora detect cache. |
| `-MaxRetries N` | Reintentos por app (default 2). |

**Exit codes**:

| Code | Significado |
|---|---|
| 0 | Todo OK |
| 1 | Fallos parciales — revisa `POSTVALIDATE_REPORT.md` |
| 2 | Source / configuracion invalida |
| 3 | Reboot requerido — relanza con `resume` tras reiniciar |
| 4 | Sin permisos administrativos |
| 5 | Falta prerrequisito (PowerShell <5.1) |
| 99 | Fase invalida |

---

## Permisos requeridos

- Cuenta administradora local (UAC se solicita automaticamente desde `Deploy.bat`).
- Acceso HTTPS a:
  - `*.officecdn.microsoft.com` (Office C2R, ~1.5GB descarga con Word+Excel+PPT+Outlook).
  - `*.google.com` + `*.gvt1.com` (Chrome bootstrap).
  - ESET PROTECT Cloud endpoint (configurado en `install_config.ini`).
  - Endpoint Cortex XDR Cloud (configurado en el MSI Andersen).

---

## Flujo interno v4.2

```text
[1] Pre-checks
    - Admin? PSh 5.1+? Disco libre >8GB? Pending reboot?
    - Inventario archivos (15 apps + Office XML).

[2] Office BACKGROUND kickoff (si no -SequentialOffice ni instalado)
    Start-Process OfficeSetup.exe /configure configuration.xml -PassThru
    -> PID guardado. Continua sin esperar.

[3] Phase=full -> Grupos 1,2,3 EN PARALELO con Office bg

    GRUPO 1 (MSIs serial):
        msiexec /i <pkg> /qn /norestart /l*v <log> [extra]
        Apps: AnyDesk, AqNet, Nebula CertAgent, ESET Mgmt Agent

    GRUPO 2 (EXE silent serial):
        <exe> /silent /S
        Apps: Google Chrome, Autofirma, Bit4id

    GRUPO 3 (EXE complejos serial):
        <exe> /VERYSILENT ...    (Inno Setup)
        <exe> /s /SMS /v"/qn ..."  (InstallShield)
        Apps: PDFelement, MitelConnect

[4] WAIT Office background ANTES de Grupo 5
    Complete-OfficeBackground: poll proc.HasExited, validate WINWORD.EXE
    Timeout 40 min. Si bootstrap exit 0 sin Word: poll C2R service.

[5] GRUPO 5 (iManage stack - requiere Office completo + AS):
    iManageAgentServices.exe       /quiet /norestart
    iManageDriveSetup.exe          /quiet /norestart /log
    iManageDriveNative.exe         /quiet /norestart /log
    iManageWorkDesktopforWindowsx64.exe /s setup.iss
        (extract /s /extract_all primero, run desde extractDir)

[6] GRUPO 6 (AV behavioral - post iManage):
    MDR Cortex XDR  /qn /norestart REBOOT=ReallySuppress

[7] Validate.ps1 smoke tests
    - Registry Uninstall keys + version
    - Servicios Windows (state + StartType)
    - Binarios en disco
    - Outlook iManage COM addins

[8] Report final
    - POSTVALIDATE_REPORT.md  (tabla per-app)
    - Validate_Report.md      (smoke tests)
    - logs\Deploy_*.log
```

---

## Validacion fin de instalacion

1. `Deploy.bat` deja **exit 0** en consola.
2. `POSTVALIDATE_REPORT.md` muestra `OK=15 FAIL=0 DEFERRED=0`.
3. `Validate_Report.md` lista todas las apps con `Status=OK` y version.
4. **Tras reiniciar el equipo**:
   - Outlook abre y carga el addin iManage (icono en cinta).
   - Chrome arranca.
   - Servicios `cyserver`, `EraAgentSvc`, `nebulaCERTagent`, `AnyDesk` en estado Running.
   - `Deploy.bat validate` confirma todo OK desde estado limpio post-reboot.

Validacion manual rapida:

```powershell
Get-Service cyserver,EraAgentSvc,AnyDesk,nebulaCERTagent | Format-Table Name,Status,StartType
Test-Path 'C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE'
Test-Path 'C:\Program Files\iManage\iManage Drive\iManageDrive.exe'
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\iManageWorkDesktopForWindows' | Select DisplayName, DisplayVersion
```

---

## Intune Win32App — DESPLIEGUE PRODUCTIVO

### Opcion A: Win32App unico (bundle suite)

Empaqueta toda la carpeta `nodedeploy\` como un solo `.intunewin`:

```powershell
# Descargar Microsoft Win32 Content Prep Tool:
# https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool

IntuneWinAppUtil.exe `
  -c "C:\path\nodedeploy" `
  -s "NodeDeploy_Run\PRO\Deploy.bat" `
  -o "C:\Intune\Output" `
  -q
```

Configuracion Intune:

| Campo | Valor |
|---|---|
| Install command | `NodeDeploy_Run\PRO\Deploy.bat full` |
| Uninstall command | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File NodeDeploy_Run\PRO\Uninstall.ps1 -ConfirmReset` |
| Install behavior | System |
| Device restart behavior | App install may force a device restart |
| Return codes | `0=Success · 1=Failed · 3=SoftReboot · 1707=Success · 3010=HardReboot` |
| Detection rule | Registry: `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\iManageWorkDesktopForWindows` Value `DisplayVersion` Exists |
| Requirements | OS Win 10 1809+, Architecture x64, Disk 15 GB free, RAM 4 GB |
| Assignment | Required · grupo AAD `Andersen-NodeDeploy-Target` |

### Opcion B: Suite de Win32Apps individuales con dependencias

Cada app como Win32App separado con detection rule especifica + dependency tree. Ver `NodeDeploy_v4.html` seccion 7 para tabla completa de comandos por app.

Dependencias clave:
- Microsoft 365 Apps → SIN dependencias
- iManage Agent Services → depende de Microsoft 365 Apps
- iManage Drive → depende de iManage Agent Services
- iManage Drive Native → depende de iManage Drive
- iManage Work Desktop → depende de Microsoft 365 Apps + iManage Agent Services
- MDR Cortex XDR → depende de iManage Work Desktop (post)

### Autopilot ESP

1. Importar HW hash del equipo a Intune Autopilot.
2. Asignar a grupo AAD con perfil Autopilot configurado.
3. Configurar ESP (Enrollment Status Page) con "Block device use until required apps installed".
4. Anadir los 15 Win32Apps (o el bundle unico) a "Required Apps" del ESP.
5. Equipo arranca -> OOBE -> Autopilot enrolment -> ESP instala apps -> escritorio listo.

---

## Troubleshooting

### iManage Work Desktop exit -2147213312 (CRITICO — v4.2 RESUELTO)

1. **Verifica Office completo (no solo Outlook)**:
   ```powershell
   Test-Path 'C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE'
   ```
   Si `False`: el `configuration.xml` esta excluyendo Word. Usa la version v4.2 default (Word+Excel+PPT+Outlook), NO la backup OutlookOnly.

2. **Verifica iManage Agent Services instalado**:
   ```powershell
   Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' |
     Where-Object DisplayName -eq 'iManage Agent Services'
   ```
   Si vacio: lanza solo `iManageAgentServices.exe /quiet` primero.

3. **Habilita IS verbose** (revela log iManage propio):
   ```
   reg add "HKLM\SOFTWARE\InstallShield\29.0\Professional" /v DoVerboseLogging /t REG_DWORD /d 1 /f
   ```
   Log iManage en `%TEMP%\workdesktop_v109_*.log`.

4. **Cierra Office + procs iManage**:
   ```
   taskkill /F /IM OUTLOOK.EXE /IM WINWORD.EXE /IM EXCEL.EXE /IM POWERPNT.EXE /IM OfficeClickToRun.exe /IM iManageStayExec.exe
   ```

5. `Deploy.bat cleanup` → `Deploy.bat resume`.

### Office C2R timeout

Default 40 min. Si conexion <2 Mbps: editar `Deploy.ps1` `Timeout=2400` → aumentar.

### Sin acceso a internet

- Chrome: usa MSI corporativo offline.
- Office: ODT pre-cacheado en local (configurar `SourcePath` en configuration.xml).

### Bloqueo AV/EDR

Cortex XDR esta en Grupo 6 por diseno (post-iManage). Si ESET bloquea:
- `-SkipApps 'ESET Management Agent'` primer run.
- Resto se instala.
- Snapshot.
- Segundo run solo ESET.

### Reanudar tras snapshot revert

State file en `NodeDeploy_Run\state\` se pierde con snapshot revert, pero el script re-detecta el estado real del registro al arrancar y reanuda en la primera app no instalada.

---

## Workarounds aplicados (excepciones documentadas)

| App | Workaround | Razon |
|---|---|---|
| ESET Mgmt Agent | Parsea `install_config.ini` linea a linea y pasa cada `KEY=VALUE` como propiedad MSI inline | El MSI no auto-detecta el INI; sin propiedades inline se instala unenrolled. |
| iManage Work Desktop | Extract `/s /extract_all:` primero, luego run `/s setup.iss` desde dir corto | Sintaxis docs iManage 10.9.x. Path con espacios rompe IS engine. |
| iManage Work Desktop | Gate hard: Outlook + Word + Agent Services chequeados pre-launch | Sin estos, IS aborta con -2147213312 silencioso. Mejor fail explicito. |
| Office C2R | Background paralelo via `Start-Process -PassThru` | Permite Grupos 1-3 correr mientras Office descarga/instala. Wait antes Grupo 5. |
| Cortex XDR | Grupo 6 (ultimo) | Behavioral monitor de Cortex bloquea IS runtime iManage Work Desktop si Cortex se instala antes. |
| Cortex XDR | Acepta exit `3010` / `1641` como OK con reboot pendiente | Cortex registra filtros de driver kernel que requieren reboot. |

---

## Notas tecnicas

- **No usa Resolve-Path**: `Convert-Path` evita el prefijo provider que rompe `msiexec` (1619 error).
- **Sin self-elevation hack**: el `.bat` maneja UAC via `net session` check + `Start-Process Verb RunAs`. Mas predecible.
- **State JSON con UTF-8**: evita problemas con tildes en nombres de apps.
- **Sin dependencia de network share**: todo path es local, copia 1:1 entre equipos.
- **Cero `Read-Host`**: 100% no interactivo (apto para SCCM/Intune/PSExec/runspaces).
- **MSI logging verbose siempre activo**: `/l*v` en todos los MSIs y wrappers IS para diagnostico postmortem.
- **Office background con poll**: para bootstrap C2R que sale antes que C2R service termine, polling adicional hasta `App.Timeout`.

---

_Generado: 2026-05-28 · NodeDeploy PRO v4.2.0 · iManage Work Desktop -2147213312 root cause diagnosticado y corregido_
