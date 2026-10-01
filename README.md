# NodeDeploy PRO v5 — despliegue desatendido de las apps corporativas (Lenovo)

## M.2 / USB — flujo de 4 pasos

1. Copia la **carpeta completa `nodedeploy\`** del M.2 al **Escritorio** del portátil (más rápido que ejecutarlo desde el M.2; al terminar bien, se borra sola).
2. Portátil Lenovo con Windows 10/11 x64 y su Microsoft 365 de fábrica, con red por cable y **cargador conectado** (sin él no se instala firmware/BIOS).
3. **Doble clic `nodedeploy\Pincha_pa_instalar.bat`** (o `NodeDeploy_Run\PRO\Deploy.bat`). Acepta UAC y responde las preguntas del arranque:
   - **dominio**: menú numerado con las sedes de `NodeDeploy_Run\PRO\Dominios.txt` (no va a GitHub), `Otro` para escribirlo a mano o `0` = sin dominio; si hay dominio, usuario con permiso para unir equipos + contraseña;
   - **contraseña del Administrador local** (dos veces).
   
   Si relanzas el script en un equipo ya terminado, no vuelve a preguntar lo ya hecho (Administrador activado, equipo en dominio).
4. Espera (~15-20 min; más si hay muchas actualizaciones de Lenovo o de Windows). Mientras instala, en segundo plano, **optimiza Windows** (quita apps de Store que sobran, publicidad, Bing, widgets), **actualiza controladores, firmware y BIOS de Lenovo** (como Commercial Vantage, sin abrirlo) e **instala las actualizaciones de Windows Update**. Al final deja sin arrancar con Windows PDFelement, PDF24, Everything, b4notify y Edge (AnyDesk siempre activo), ancla Outlook y Teams a la barra de tareas (sin Microsoft Store) y, si todas las apps quedan OK: Administrador local activado, la cuenta `usuario` (o `user`) fuera de Administradores y, lo último, unión al dominio.
5. **Reinicio**: si algo lo pide (dominio unido, Lenovo, Windows Update, instaladores), **reinicia solo a los 15 s** (`shutdown /a` lo cancela), siempre después del dominio; si un firmware de Lenovo pide apagar, apaga. Si las actualizaciones siguen instalándose, un **vigilante** reinicia en cuanto terminen. Una app con fallo no lo frena (sale en el informe); un dominio pedido y sin unir, sí.

**Si una app falla**: se corta rápido (tiempo límite realista por app; si se cuelga no se reintenta) y se sigue con las demás. El informe dice en qué se quedó (procesos y ventanas) y las últimas líneas de su log.

**Informe**: `NodeDeploy_Run\POSTVALIDATE_REPORT.md`, corto: resultado en una línea, "Atención" solo si hay algo que hacer, tabla App / Estado / **Tiempo** (minutos en negrita; ⚠ si pasa de 1 minuto, o de 5 en Outlook) y el equipo en pocas líneas.

**Logs**: al terminar, un zip con todo (informe, logs, equipo) se sube a la carpeta de red de `NodeDeploy_Run\PRO\Ajustes.local.txt` (fuera de git), en `NodeDeploy_Success` o `NodeDeploy_Errors`, con las credenciales del dominio. Sin red, queda en `LOGS_preparation\` al lado de la carpeta. Nunca frena nada.

**Carpeta del escritorio**: si TODO quedó listo (apps, cierre, sin errores), se borra sola al terminar (~6 GB de instaladores; si las actualizaciones siguen, cuando terminen). Nunca el M.2 ni una carpeta fuera de un Escritorio. `-KeepFolder` la conserva.

Solo se abren `lusrmgr.msc` / `sysdm.cpl` si hay algo de cuentas o dominio que revisar a mano.

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
| No unir a dominio sin que pregunte | `Deploy.bat full -Domain no` |
| Sin preguntas ni cierre (Administrador / usuario / dominio) | `Deploy.bat full -NoFinalize` |
| Sin optimización de Windows | `Deploy.bat full -NoOptimize` |
| Sin actualizaciones de Lenovo / solo sin BIOS ni firmware | `Deploy.bat full -NoLenovoUpdates` / `-NoBIOS` |
| Sin Windows Update | `Deploy.bat full -NoWindowsUpdate` |
| Conservar la carpeta del escritorio al terminar | `Deploy.bat full -KeepFolder` |
| Sin reinicio automático (pruebas) | `Deploy.bat full -NoAutoReboot` |
| Portátil de Canarias / no tocar la hora | `Deploy.bat full -TimeZone "GMT Standard Time"` / `-TimeZone no` |
| Repetir apps que fallaron | desinstalarlas y relanzar: el script salta lo ya instalado |
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
     │   iManage Drive → Drive Native → [espera Outlook] iManage Work Desktop →             │
     │   dnGrep → Everything → PDF24 → Adobe Reader (mientras WD espera) → Cortex (último)   │
     │                                                                                     │
     ├─ Carril EXE (NSIS/Inno/MSIX, en paralelo) ──────────────────────────────────────────┤
     │   Bit4id → PDFelement → Autofirma (después de Chrome) → NanaZip                     │
     │                                                                                     │
     ├─ Lenovo (background, Lenovo.ps1) ── controladores ya; red + firmware/BIOS al final ─┤
     │                                                                                     │
     └─ Windows Update (background, WindowsUpdate.ps1) ── software ya; drivers al final ───┘
```

**Windows Update** (`WindowsUpdate.ps1`, el agente de Windows Update de Windows, sin módulos externos): lo mismo que "Descargar e instalar todo" de Configuración. Las de software (acumulativa, seguridad, .NET, herramienta de eliminación de software malintencionado, Defender) se descargan e instalan desde t=0, en paralelo a las apps; los controladores de Windows Update (también los opcionales), al terminar las apps y Lenovo (así no se pisan con los de Lenovo); firmware solo con cargador. La versión nueva de Windows solo si es un paquete de habilitación (p. ej. **26H2**, KB5121794: pequeño y un reinicio); un cambio de versión completo (horas) o una versión preliminar, nunca. El reinicio que pidan entra en el reinicio automático del final.

**Actualizaciones Lenovo** (`Lenovo.ps1`, módulo oficial `Lenovo.Client.Update`, el mismo catálogo por modelo que Commercial Vantage): solo lo aplicable al equipo, desatendido y crítico/recomendado. Los controladores se instalan mientras van las apps; los de red (LAN/WiFi/WWAN), cuando terminan las apps (no cortan descargas); firmware y BIOS, lo último, **solo con el cargador conectado** y con BitLocker en pausa: se graban en el reinicio final. Nunca instala lo que reinicia al momento (p. ej. firmware de docks) ni reinicia por su cuenta. Resultado en el informe, sección "Actualizaciones Lenovo".

- **Reintentos reales** (`-MaxRetries 2`): 1618 = Windows Installer ocupado (Windows Update, Lenovo Vantage, Store…) → espera y reintenta sin gastar intentos.
- **Dependencias**: Autofirma tras Chrome (configura Chrome al instalarse), Work Desktop tras Agent Services + Outlook + Word, Cortex XDR siempre el último.
- **Office**: los Lenovo traen Microsoft 365 (Word/Excel/PPT). Solo se añade **Outlook clásico**, lo primero en t=0 con ODT (`OutlookRetail`, `Version=MatchInstalled`): solo baja Outlook para la versión de Office que ya hay (**~3 min**). Plan B automático (si falla o pasa de 10 min): el instalador oficial de Microsoft (`OutlookClassic.exe`), que además actualiza todo el Office a la última versión (13-16 min). `-OutlookMethod bootstrap` invierte el orden. Office completo solo con `-InstallFullOffice`.
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
| dnGrep 5.0 | MSI (`LAUNCHAPPONEXIT=0`) | MSI |
| Everything 1.4.1 | MSI (valores por defecto: servicio + arranque con Windows + accesos directos) | MSI |
| PDF24 Creator 11.30.1 | MSI (`AUTOUPDATE=No REGISTERREADER=No FAXPRINTER=No`) + **solo local** por registro: sin conversor online, herramientas web, fax ni correo de PDF24. En el escritorio solo **PDF24 Toolbox** (se quita PDF24 Launcher, el de la publicidad de redes sociales). Evaluación para auditoría: `docs\PDF24_Evaluacion_Seguridad.txt` | MSI |
| Adobe Acrobat Reader 26.002 | punto de instalación administrativa (`AdobeReader_x64_*_AIP\AcroPro.msi`, parche ya aplicado: más rápido); si falta, paquete empresarial `setup.exe`. `EULA_ACCEPT=YES ENABLE_CHROMEEXT=0 LEAVE_PDFOWNERSHIP=YES` (sin licencia al abrir, sin extensión de Chrome, no quita los PDF a PDFelement; actualizador de Adobe activo por seguridad) | MSI |
| MDR Cortex XDR | MSI | MSI (último) |
| Bit4id Middleware, Autofirma 1.9 | NSIS | EXE |
| PDFelement Business 10.1.5 | Inno Setup (`/NOPAGE`, log propio) | EXE |
| NanaZip 7.0 | MSIX con DISM, para todos los usuarios (licencia `.xml` junto al paquete) | EXE |
| Outlook clásico | ODT `OfficeSetup.exe` con `MatchInstalled` (~3 min; plan B: `OutlookClassic.exe`) | background, t=0 |

---

## Optimización de Windows (`Optimize.ps1`)

| Qué | Cómo | Cuándo |
|---|---|---|
| Apps de Store que sobran (Xbox, Solitario, Noticias, Tiempo, Clipchamp, TikTok, Disney+, Candy Crush…) | se quitan del usuario actual y de los futuros. **Nunca** Store, Calculadora, Fotos, Terminal, códecs, winget, apps de Lenovo (Vantage), NanaZip, ni Spotify / Outlook nuevo / Teams personal (se quedan) | segundo plano desde t=0 |
| Publicidad, apps que se instalan solas, sugerencias de Bing, widgets, chat | directivas del equipo + perfil del usuario actual + perfil por defecto (usuarios nuevos del dominio) | segundo plano desde t=0 |
| Arranque | **deshabilitados** en "Aplicaciones de arranque": PDFelement (Wondershare), PDF24, Everything, b4notify; Edge sin arranque ni segundo plano (directiva). Los servicios de PDF24 (impresora) y Everything (índice) siguen | al final |
| Hora del equipo | zona horaria de España (Madrid; Canarias se respeta; `-TimeZone` para otra) y reloj en hora con la hora de un servidor web (Windows no corrige solo desfases grandes y muchas redes cortan NTP). Con la hora mal fallan las descargas seguras, AnyDesk no recibe ID y la unión al dominio falla | al arrancar |
| AnyDesk | servicio automático y en marcha, reinicio si se cae, entrada de inicio habilitada y **sin botón Desinstalar** (un usuario sin admin no puede quitarlo ni desactivarlo) | al final |
| AnyDesk entero y con ID | comprueba servicio, ejecutable y conexión a la red de AnyDesk (`--get-id`); si quedó a medias repara el MSI, si no hay ID reinicia el servicio, y reabre la ventana que abrió el instalador. **El ID sale en el informe** | al terminar las apps (también con `-NoOptimize`) |
| Barra de tareas | Explorador, Edge, **Outlook clásico y Teams**; **sin Microsoft Store**. XML + directiva "Diseño de inicio" (método de Microsoft): todos los usuarios, también los del dominio, al iniciar sesión | al final |
| Comprobaciones | TRIM del SSD (se activa si estuviera apagado), software del fabricante a revisar (antivirus de prueba = choca con ESET/Cortex), lo que sigue arrancando con Windows | al final, en el informe |

No se hace, a propósito: `winget upgrade --all` (cambiaría versiones validadas de las apps corporativas y alarga mucho), actualizaciones de características de Windows (cambio de versión: horas y riesgo), cambiar el plan de energía (son portátiles), desinstalar solo el software del fabricante (se informa para revisarlo). La lista de apps a quitar está al principio de `Optimize.ps1`.

---

## Estructura

```
nodedeploy\
├── Pincha_pa_instalar.bat     ← doble clic: lanza NodeDeploy_Run\PRO\Deploy.bat
├── README.md                  ← esta guía
├── 1.Node_Preparation\        ← SOLO los instaladores que usa v5
│   ├── *.msi / *.exe / *.msixbundle   20 apps (+ ChromeSetup.exe de reserva; Adobe Reader en su carpeta). Nombres con versión:
│   │                            para actualizar PDF24, Everything, dnGrep o NanaZip basta con sustituir el fichero
│   ├── install_config.ini       certificado del agente ESET (nunca va a git)
│   ├── OutlookClassic.exe       Outlook clásico (instalador de Microsoft)
│   ├── OfficeSetup.exe          ODT: plan B de Outlook y Office completo (-InstallFullOffice)
│   ├── configuration.xml        Office completo (solo -InstallFullOffice)
│   ├── Office\Data\             payload local de Office completo (solo -InstallFullOffice)
│   └── Imanage 3.0\             Drive 10.13 · Work Desktop 10.10.2.62 + Agent Services · Native 10.6.1.15
│                                (cada InstallScript lleva su setup.iss: respuesta silenciosa del propio paquete)
├── NodeDeploy_Run\
│   ├── PRO\                     Deploy.bat · Deploy.ps1 · Finalize.ps1 (cierre) · Optimize.ps1 (optimización) · Validate.ps1 · Uninstall.ps1 · Diag-iManageWD.ps1
│   │                            README.md (técnico) · QUICK_START.md · CHECKLIST.md
│   └── state\                   se crea al ejecutar: logs y estado (los informes quedan en NodeDeploy_Run\)
├── Lab\                       ← laboratorio VMware: pruebas sin tocar el PC
└── docs\                      ← HANDOFF (decisiones, pruebas, pendientes) · evaluación de seguridad de PDF24
```

## Documentación

- `NodeDeploy_Run\PRO\README.md` — detalle técnico (Office, iManage, logs, Intune).
- `NodeDeploy_Run\PRO\QUICK_START.md` — guía rápida del técnico.
- `NodeDeploy_Run\PRO\CHECKLIST.md` — checklist antes/durante/después.
- `docs\HANDOFF_2026-09-24.md` — diagnóstico, cambios de v5, resultados de las pruebas y pendientes.
- `docs\PDF24_Evaluacion_Seguridad.txt` — evaluación de seguridad de PDF24 (firma, hash, antivirus, CVE, configuración) para ISO 27001.
- `Lab\README.md` — laboratorio (VM de pruebas).

---

## Exit codes

| Código | Significado |
|---|---|
| 0 | OK total |
| 1 | Fallos parciales (tras reintentos) — revisar `POSTVALIDATE_REPORT.md` |
| 2 | Source / config inválidos |
| 3 | Reinicio requerido (instaladores o unión al dominio). Si quedó algo pendiente, tras reiniciar: `Deploy.bat resume` |
| 4 | Sin permisos admin |
| 5 | Prereq missing (PowerShell < 5.1) |

---

_Última actualización: 2026-10-01 — NodeDeploy PRO v5.7.0_
