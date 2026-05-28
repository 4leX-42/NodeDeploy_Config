# NodeDeploy — Despliegue desatendido 15 apps corporativas (v4.2.1)

## USB — Flujo de 4 pasos

1. Copia la **carpeta completa `nodedeploy\`** a la raiz del USB.
2. Conecta USB al PC destino (Windows 10/11 x64).
3. **Doble click `nodedeploy\Deploy.bat`** (atajo raiz). Acepta UAC.
4. Espera ~12-15 min (Office bg + Grupo 2 paralelo). Si pide reboot (exit 3): reinicia → `Deploy.bat resume`.

**Listo. Valida con**: `NodeDeploy_Run\POSTVALIDATE_REPORT.md` → debe poner `OK=15 FAIL=0`.

Al terminar (full / install / resume / validate), Deploy.bat abre automaticamente:
- **Local Users and Groups** (`lusrmgr.msc`) — para anadir usuarios locales.
- **System Properties** (`sysdm.cpl`) — para nombre PC / dominio.

> ⚠️ USB debe ser escribible (no read-only). El script escribe state/logs en `nodedeploy\NodeDeploy_Run\state\`.

---

## Atajos

| Quiero... | Comando |
|---|---|
| **Deploy completo** | `NodeDeploy_Run\PRO\Deploy.bat` |
| Solo validar instalacion | `NodeDeploy_Run\PRO\Deploy.bat validate` |
| Reanudar tras reboot | `NodeDeploy_Run\PRO\Deploy.bat resume` |
| Probe (no instala) | `NodeDeploy_Run\PRO\Deploy.bat probe` |
| Cleanup procs iManage | `NodeDeploy_Run\PRO\Deploy.bat cleanup` |
| Reset/desinstalar | `NodeDeploy_Run\PRO\Uninstall.ps1 -ConfirmReset` |
| Office sequential (sin bg) | `powershell -File Deploy.ps1 -Phase full -SequentialOffice` |
| Skip Office | `powershell -File Deploy.ps1 -Phase full -NoOffice` |
| Documentacion completa | `NodeDeploy_Run\PRO\README.md` |
| Dashboard HTML | `NodeDeploy_Run\PRO\NodeDeploy_v4.html` |

---

## Orden de instalacion (PRO v4.2 — Office bg paralelo)

```
[START] Office Grupo 4 lanzado en BACKGROUND (Start-Process -PassThru)
                |
                v
   Grupos 1-3 corren en paralelo con Office download/install
                |
                v
   GATE: Wait Office (poll WINWORD.EXE + C2R service exit)
                |
                v
   Grupo 5 (iManage stack)
                |
                v
   Grupo 6 (Cortex XDR)
                |
                v
   [Validate] + [Open lusrmgr.msc] + [Open sysdm.cpl]
```

| Grupo | Apps |
|---|---|
| 1 | AnyDesk, AqNet, Nebula CertAgent, ESET Mgmt Agent |
| 2 | Chrome, Autofirma, Bit4id Middleware |
| 3 | PDFelement Business, MitelConnect |
| 4 **(bg)** | **Microsoft 365 Apps** (Word+Excel+PPT+Outlook via XML, requerido para iManage WD) |
| 5 | iManage Agent Services, iManage Drive, iManage Drive Native, **iManage Work Desktop** |
| 6 | **MDR Cortex XDR** (ultimo — evita bloqueo behavioral InstallScript) |

### Deteccion Office inteligente

El handler `office` detecta baseline:
- **Si Word presente y Outlook ausente** → lanza `OutlookClassic.exe` bootstrap (7 MB, rapido).
- **Si Word ausente** → C2R full via `Sc3.0\configuration.xml` (~1.5GB descarga).

> **Cambio v4.2**: antes detectaba via Excel/PowerPoint/Word. Ahora solo Word — Word es el prereq hard de iManage Work Desktop.

---

## Estructura

```
nodedeploy\
├── 1.Node_Preparation\          ← 15 instaladores + Office XML + ESET INI
│   ├── *.msi, *.exe (15 apps)
│   ├── OutlookClassic.exe       ← Office Bootstrapper para baseline scenarios
│   ├── ESET_Endpoint\           ← Endpoint security pkg
│   ├── Sc3.0\
│   │   ├── configuration.xml                      ← v4.2: Word+Excel+PPT+Outlook
│   │   ├── configuration_OutlookOnly.xml.bak      ← v4.0 backup (NO compatible WD)
│   │   └── addOfficeApps.xml                      ← XML add Word/Excel/PPT a baseline
│   └── Imanage 2.0\
│       ├── iManage Work Desktop for Windows 10.9.4.39 (x64 Office)\
│       │   ├── iManageAgentServices.exe   (2 MB)
│       │   └── iManageWorkDesktopforWindowsx64.exe  (70 MB, pure InstallScript)
│       └── iManage Drive for Windows 10.10.0.410\
│           ├── iManage Drive for Windows 10.10.0.410\iManageDriveSetup.exe (242 MB)
│           └── iManageDrive Native 10.6.1.15\iManageDriveNative.exe (0.7 MB)
└── NodeDeploy_Run\
    ├── PRO\                       ← *** PRODUCTION v4.2 ***
    │   ├── Deploy.bat             ← LAUNCHER (doble clic aqui)
    │   ├── Deploy.ps1             ← engine v4.2.0
    │   ├── Validate.ps1
    │   ├── Uninstall.ps1
    │   ├── README.md, QUICK_START.md, CHECKLIST.md
    │   └── NodeDeploy_v4.html     ← Dashboard tecnico
    ├── _legacy\                   ← v3.x deprecado
    ├── PERSIST\                   ← ESET endpoint pkg
    └── state\                     ← logs + nodedeploy_state.json (regenerado)
```

---

## Fixes activos v4.2.1 (2026-05-28)

1. **Office BACKGROUND paralelo (v4.1)** — `Start-Process -PassThru` al inicio. Grupos 1-3 corren mientras Office descarga/instala. Flag `-SequentialOffice` revierte.
2. **Grupo 2 PARALELO (v4.2.1)** — Chrome+Autofirma+Bit4id (NSIS, sin lock MSI) lanzados juntos. Ahorro ~2 min. Disable: `NODEDEPLOY_NO_PARALLEL_G2=1`.
3. **setup.iss pre-bundled (v4.2.1)** — Bundled junto a wrapper iManage WD. Skip extract step (~50s ahorrados).
4. **Cache InstalledApps (v4.2.1)** — Pre-check Install-App sin -Refresh. Ahorro ~2-3s.
5. **Diagnostico WD -2147213312 RESUELTO (v4.2)** — WD requiere Word presente + Agent Services. configuration.xml default Word+Excel+PPT+Outlook.
6. **Detect Microsoft 365 Apps WINWORD.EXE** — mejor proxy de "Office completo".
7. **Gate WD endurecido** — verifica Outlook + Word + Agent Services antes lanzar.
8. **Smart bootstrap detection** — OutlookClassic.exe solo si Word presente + Outlook ausente.
9. **Post-deploy auto-launch** — `lusrmgr.msc` + `sysdm.cpl` al terminar.
10. **Root shortcuts (v4.2.1)** — `nodedeploy\Deploy.bat` + `nodedeploy\Dashboard.bat` en raiz.
11. **MDR Cortex XDR Grupo 6** — ultimo, evita bloqueo behavioral InstallScript.
12. **Handler installshield-imanage** — sintaxis docs iManage 10.9.x (`/s setup.iss` positional). Path corto sin espacios.

---

## Codes exit

| Codigo | Significado |
|---|---|
| 0 | OK total |
| 1 | Fallos parciales — revisar `POSTVALIDATE_REPORT.md` |
| 2 | Source / config invalidos |
| 3 | Reboot requerido — relanzar `Deploy.bat resume` |
| 4 | Sin permisos admin |
| 5 | Prereq missing (.NET, PSh < 5.1) |

---

## Intune Win32App quick reference

```
IntuneWinAppUtil.exe -c "C:\path\nodedeploy" -s "NodeDeploy_Run\PRO\Deploy.bat" -o "C:\Output" -q
```

| Campo | Valor |
|---|---|
| Install command | `NodeDeploy_Run\PRO\Deploy.bat full` |
| Uninstall command | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File NodeDeploy_Run\PRO\Uninstall.ps1 -ConfirmReset` |
| Install behavior | System |
| Return codes | 0=Success, 1=Failed, 3=SoftReboot, 1707=Success, 3010=HardReboot |
| Detection rule | Registry `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\iManageWorkDesktopForWindows` Value `DisplayVersion` Exists |
| Requirements | Win 10 1809+, x64, 15 GB free, 4 GB RAM |

Ver `NodeDeploy_v4.html` seccion 7 para tabla completa Win32App por app (Opcion B suite).

---

_Ultima actualizacion: 2026-05-28 — NodeDeploy PRO v4.2.0_
