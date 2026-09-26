# NodeDeploy PRO v5 — despliegue desatendido de las apps corporativas (Lenovo)

## M.2 / USB — flujo de 4 pasos

1. Copia la **carpeta completa `nodedeploy\`** al M.2 (o úsalo directamente desde él).
2. Conecta el M.2 al portátil Lenovo (Windows 10/11 x64, con su Microsoft 365 de fábrica).
3. **Doble clic `nodedeploy\Pincha_pa_instalar.bat`** (o `NodeDeploy_Run\PRO\Deploy.bat`). Acepta UAC.
4. Espera (~7 min). Si pide reboot (exit 3): reinicia → `Deploy.bat resume`.

**Valida con**: `NodeDeploy_Run\POSTVALIDATE_REPORT.md` (estado + cronograma por app, duraciones en min y s) y `Validate_Report.md`.

Al terminar (full / install / resume / validate) se abren `lusrmgr.msc` y `sysdm.cpl` para usuarios locales, nombre y dominio.

> El M.2 debe ser escribible: el script guarda estado y logs en `nodedeploy\NodeDeploy_Run\state\`.

---

## Atajos

| Quiero... | Comando |
|---|---|
| **Deploy completo** | `NodeDeploy_Run\PRO\Deploy.bat` |
| Solo validar instalación | `Deploy.bat validate` |
| Reanudar tras reboot / reintentar fallos | `Deploy.bat resume` |
| Probe (no instala) | `Deploy.bat probe` |
| Equipo SIN Office de fábrica | `Deploy.bat full -InstallFullOffice` |
| Sin antivirus (pruebas) | `Deploy.bat full -SkipAV` |
| Solo algunas apps (p. ej. repetir las que fallaron) | `Deploy.bat full -OnlyApps Mitel+Desktop+Cortex` (nombre o parte, separadas por `+`) |
| Sin paralelismo (diagnóstico) | `Deploy.bat full -Serial` |
| Sin exclusiones temporales de Defender | `Deploy.bat full -NoDefenderBoost` |
| Cleanup procesos iManage | `Deploy.bat cleanup` |
| Reset / desinstalar (no toca el Office de fábrica) | `NodeDeploy_Run\PRO\Uninstall.ps1 -ConfirmReset` |
| **Probar sin tocar este PC** | `Lab\README.md` (VM VMware desechable) |

---

## Cómo instala v5

```
t=0  ┌─ Outlook clásico (background) ── instalador oficial de Microsoft; plan B: ODT ──────┐
     │                                                                                     │
     ├─ Carril MSI (serializado, espera mutex _MSIExecute) ────────────────────────────────┤
     │   AnyDesk → AqNet → Nebula → ESET agent → Chrome MSI → Mitel → iManage AS →          │
     │   iManage Drive → Drive Native → [espera Outlook] iManage Work Desktop → Cortex XDR  │
     │                                                                                     │
     └─ Carril EXE (NSIS/Inno, en paralelo) ───────────────────────────────────────────────┘
         Bit4id → PDFelement → Autofirma (después de Chrome)
```

- **Reintentos reales** (`-MaxRetries 2`): 1618 = Windows Installer ocupado (Windows Update, Lenovo Vantage, Store…) → espera y reintenta sin gastar intentos.
- **Dependencias**: Autofirma tras Chrome (configura Chrome al instalarse), Work Desktop tras Agent Services + Outlook + Word, Cortex XDR siempre el último.
- **Office**: los Lenovo traen Microsoft 365 (Word/Excel/PPT). Solo se añade **Outlook clásico**, lo primero en t=0 con el instalador oficial de Microsoft (`OutlookClassic.exe`); si falla, ODT (`OutlookRetail`, `Version=MatchInstalled`). `-OutlookMethod odt` invierte el orden. Office completo solo con `-InstallFullOffice`.
- **Consola**: se desactiva QuickEdit al arrancar (un clic en la ventana ya no congela el despliegue).
- **Defender**: exclusiones temporales solo para los procesos instaladores pesados y sus carpetas destino; se retiran al terminar (y al arrancar si un run anterior murió).

| App | Instalador | Carril |
|---|---|---|
| AnyDesk, AqNet, Nebula CertAgent, ESET Mgmt Agent | MSI | MSI |
| Google Chrome | **Enterprise MSI offline** (fallback: `ChromeSetup.exe` online) | MSI |
| MitelConnect, iManage Agent Services | InstallShield + MSI | MSI |
| iManage Drive 10.13.0.416 | InstallScript (`/s setup.iss`) — la 10.10 era WiX Burn | MSI |
| iManage Drive Native 10.6.1.15 | WiX Burn | MSI |
| iManage Work Desktop 10.10.2.62 | InstallScript (`/s setup.iss`) | MSI (tras Outlook) |
| MDR Cortex XDR | MSI | MSI (último) |
| Bit4id Middleware, Autofirma 1.9 | NSIS | EXE |
| PDFelement Business 10.1.5 | Inno Setup (`/NOPAGE`, log propio) | EXE |
| Outlook clásico | `OutlookClassic.exe` (plan B: ODT `OfficeSetup.exe`) | background, t=0 |

---

## Estructura

```
nodedeploy\
├── Pincha_pa_instalar.bat     ← doble clic: lanza NodeDeploy_Run\PRO\Deploy.bat
├── README.md                  ← esta guía
├── 1.Node_Preparation\        ← SOLO los instaladores que usa v5
│   ├── *.msi / *.exe            15 apps (+ ChromeSetup.exe de reserva)
│   ├── install_config.ini       certificado del agente ESET (nunca va a git)
│   ├── OutlookClassic.exe       Outlook clásico (instalador de Microsoft)
│   ├── OfficeSetup.exe          ODT: plan B de Outlook y Office completo (-InstallFullOffice)
│   ├── configuration.xml        Office completo (solo -InstallFullOffice)
│   ├── Office\Data\             payload local de Office completo (solo -InstallFullOffice)
│   └── Imanage 3.0\             Drive 10.13 · Work Desktop 10.10.2.62 + Agent Services · Native 10.6.1.15
│                                (cada InstallScript lleva su setup.iss: respuesta silenciosa del propio paquete)
├── NodeDeploy_Run\
│   ├── PRO\                     Deploy.bat · Deploy.ps1 · Validate.ps1 · Uninstall.ps1 · Diag-iManageWD.ps1
│   │                            README.md (técnico) · QUICK_START.md · CHECKLIST.md
│   └── state\                   se crea al ejecutar: logs y estado (los informes quedan en NodeDeploy_Run\)
├── Lab\                       ← laboratorio VMware: pruebas sin tocar el PC
├── docs\                      ← HANDOFF: decisiones, pruebas y pendientes
└── _Archivo\                  ← versiones antiguas e instaladores sin uso; ningún script lo usa (ver LEEME.md)
```

## Documentación

- `NodeDeploy_Run\PRO\README.md` — detalle técnico (Office, iManage, logs, Intune).
- `NodeDeploy_Run\PRO\QUICK_START.md` — guía rápida del técnico.
- `NodeDeploy_Run\PRO\CHECKLIST.md` — checklist antes/durante/después.
- `docs\HANDOFF_2026-09-24.md` — diagnóstico, cambios de v5, resultados de las pruebas y pendientes.
- `Lab\README.md` — laboratorio (VM de pruebas).

---

## Exit codes

| Código | Significado |
|---|---|
| 0 | OK total |
| 1 | Fallos parciales (tras reintentos) — revisar `POSTVALIDATE_REPORT.md` |
| 2 | Source / config inválidos |
| 3 | Reboot requerido — `Deploy.bat resume` tras reiniciar |
| 4 | Sin permisos admin |
| 5 | Prereq missing (PowerShell < 5.1) |

---

_Última actualización: 2026-09-26 — NodeDeploy PRO v5.0.2_
