# NodeDeploy PRO v5

> Despliegue desatendido de las apps corporativas Andersen en portátiles Lenovo.
> Dos carriles en paralelo (MSI + EXE), Outlook clásico en background, reintentos reales, resumible y validado.

---

## TL;DR — equipo nuevo

1. Conecta el M.2 con `nodedeploy\` (la ruta da igual, todo es relativo).
2. Doble clic sobre `NodeDeploy_Run\PRO\Deploy.bat` y acepta el UAC.
3. Responde las preguntas del arranque: dominio (o `no`) + usuario del dominio, y contraseña del Administrador local.
4. Espera: Notepad abre `POSTVALIDATE_REPORT.md` al terminar. Si todo quedó OK, el equipo ya tiene el Administrador local activo, `usuario` (o `user`) sin permisos de administrador y está unido al dominio.
5. Si el reporte indica **REBOOT REQUIRED** (siempre tras unir al dominio), reinicia.

---

## Qué cambia en v5 (frente a v4.2.x)

| # | Cambio | Por qué |
|---|---|---|
| 1 | **Reintentos reales** (`-MaxRetries 2`, antes declarado pero sin usar) | En v4 cualquier fallo transitorio obligaba a una segunda pasada manual. |
| 2 | **Espera al mutex `_MSIExecute`** + reintento de 1618 sin gastar intentos | En el primer arranque de un Lenovo, Windows Update / Vantage / Store ocupan Windows Installer: los MSI devolvían 1618 de golpe (varias apps fallaban a la vez). |
| 3 | **Carriles en paralelo**: MSI serializado + EXE (NSIS/Inno) a la vez | Antes todo en serie salvo el grupo 2. |
| 4 | **Solo iManage Work Desktop espera a Outlook** | Antes todo el grupo iManage esperaba a Office. |
| 5 | **Outlook clásico primero (t=0)** con el instalador oficial `OutlookClassic.exe`; plan B ODT (`OutlookRetail`, `Version=MatchInstalled`) | En el primer Lenovo real ODT falló tras ~2 min en silencio y retrasó Outlook. `-OutlookMethod odt` invierte el orden. Office completo solo con `-InstallFullOffice`. |
| 6 | Ya no se matan `OfficeClickToRun`/`OfficeC2RClient`/`setup` antes de Work Desktop | Podía romper un Outlook que aún se estaba integrando. |
| 7 | **Chrome Enterprise MSI offline** | El stub `ChromeSetup.exe` descargaba ~110 MB en el momento (lento y dependiente de la red). |
| 8 | **PDFelement con `/NOPAGE`** + log Inno + sin redirección de stdout | Wondershare indica `/NOPAGE` como obligatorio en silencioso. La redirección de v4 podía dejar el script esperando a procesos hijos. |
| 9 | **Autofirma después de Chrome** | Autofirma configura Chrome al instalarse; en v4 se lanzaban a la vez (carrera). |
| 10 | **iManage 3.0** (Drive 10.13.0.416, Work Desktop 10.10.2.62, Drive Native 10.6.1.15) | Nuevos instaladores. **Drive 10.13 ya no es WiX Burn sino InstallScript**: `/quiet` abría la GUI → ahora `/s setup.iss` con la respuesta que trae el propio paquete (pre-empaquetada junto al exe). |
| 10b | **QuickEdit de consola desactivado** | Un clic en la ventana congelaba el script hasta pulsar Enter (visto en el primer Lenovo real). |
| 11 | **Defender boost** acotado y trazado en el state | Defender escanea cada fichero que escriben los instaladores pesados (medido: WD 46 s → 398 s, PDFelement 53 s → 306 s). |
| 12 | Secretos ESET enmascarados en log y state | `P_CERT_*` y passwords ya no se escriben en claro. |
| 13 | `-DryRun` | Simula instaladores (no instala nada) para probar el planificador en cualquier PC. |
| 14 | `Uninstall.ps1` arreglado | No parseaba (error de sintaxis) y habría quitado `O365ProPlusRetail`; ahora solo quita `OutlookRetail`. |
| 15 | **v5.1: cierre del equipo** (`Finalize.ps1`) | Administrador local, `usuario` fuera de Administradores y dominio, preguntados al arrancar y aplicados al final si todo queda OK. |
| 16 | **v5.2: PDF24 Creator, Everything, dnGrep** (MSI) y **NanaZip** (MSIX con DISM, para todos los usuarios) | Nuevas apps del catálogo. Los nombres de instalador admiten comodín: para actualizar basta con sustituir el fichero. |
| 17 | **v5.3: optimización de Windows** (`Optimize.ps1`) | Limpieza de apps y publicidad en segundo plano, arranque (apps deshabilitadas, AnyDesk obligatorio), TRIM, Windows Update. |
| 18 | **v5.4: Adobe Acrobat Reader** | Paquete empresarial silencioso; no quita los PDF a PDFelement. Spotify, Outlook nuevo y Teams personal se quedan. |
| 19 | **v5.5: actualizaciones Lenovo** (`Lenovo.ps1`) | Controladores, firmware y BIOS del catálogo del modelo (como Commercial Vantage, sin abrirlo), en paralelo a las apps. |
| 20 | **v5.5: Adobe desde su punto de instalación administrativa** | Parche ya aplicado: no descomprime ni parchea al instalar (lab: 86 s frente a 111 s). |
| 21 | **v5.5: PDF24 solo local** + barra de tareas | Claves del manual oficial (sin conversor online, herramientas web, fax ni correo); en el escritorio solo PDF24 Toolbox. Outlook y Teams anclados, sin Microsoft Store. Evaluación: `docs\PDF24_Evaluacion_Seguridad.txt`. |
| 22 | **v5.5: reinicio automático** (15 s) | Solo con todo verificado; completa la unión al dominio y graba firmware/BIOS. Desde v5.5.2 también sin dominio (`no`) si algo pide reiniciar. |

---

## Office: qué hace exactamente

| Estado del equipo | Acción |
|---|---|
| Word + Outlook clásico presentes | Nada. |
| Word presente, Outlook ausente (**Lenovo de fábrica**) | En t=0 `OutlookClassic.exe` (instalador oficial "classic Outlook", añade el producto C2R `OutlookRetail`). Si falla → ODT `OutlookRetail` con la **misma versión, canal e idiomas** del Office instalado. `-OutlookMethod odt` para probar ODT primero. |
| Word ausente | Error claro: el equipo no trae Office. Work Desktop queda bloqueado. Para instalar Microsoft 365 completo: `-InstallFullOffice` (usa `1.Node_Preparation\configuration.xml` y el payload local `Office\Data`). |

XML generado (ejemplo real en un equipo con Microsoft 365 for business, Current Channel):

```xml
<Add OfficeClientEdition="64" Channel="Current" Version="MatchInstalled" AllowCdnFallback="TRUE">
  <Product ID="OutlookRetail">
    <Language ID="MatchInstalled" TargetProduct="O365BusinessRetail" />
    <ExcludeApp ID="Groove" />
  </Product>
</Add>
```

Log ODT: `state\logs\odt_outlook\`.

---

## Root cause iManage Work Desktop -2147213312 (0x80042000)

Work Desktop (InstallScript) tiene **dos prerrequisitos duros** que comprueba antes de mostrar UI; si falta cualquiera aborta con `0x80042000`:

1. **iManage Agent Services** instalado (ejecutable propio `iManageAgentServices.exe`).
2. **Office con Word y Outlook** presentes. Outlook solo NO basta.

v5 lo garantiza por dependencias (`Requires = Agent Services + @office`); si no se cumplen, Work Desktop queda `blocked` con el motivo en el reporte en vez de fallar en silencio.

Desde v5.0.2, además:
- Antes de lanzar Work Desktop espera (máx. 2 min) a que Office esté **registrado** (ProgID `Word.Application`, lo que comprueba iManage). `OfficeC2RClient` no sirve de indicador: sigue activo varios minutos después de que Outlook esté listo.
- Si aun así falla, el informe incluye el `ResultCode` del `setup.log` de InstallScript (p. ej. `-12` = el `setup.iss` no coincide con los diálogos) y las líneas `### ERROR ###` del log propio de iManage (`%TEMP%\workdesktop_*.log`); ambos logs se copian a `state\logs`.

Diagnóstico adicional: `reg add "HKLM\SOFTWARE\InstallShield\29.0\Professional" /v DoVerboseLogging /t REG_DWORD /d 1 /f` y leer `%TEMP%\workdesktop_*.log`.

---

## Cierre del equipo (v5.1, `Finalize.ps1`)

Al arrancar (fases `full` / `install` / `resume`) se pregunta:

1. **Dominio**: menú numerado con las sedes de `Dominios.txt` (junto a los scripts; una por línea `Sede = dominio`; **fuera de git** porque el repo es público; plantilla `Dominios.ejemplo.txt`), `N+1` = otro (escribirlo a mano), `0` = sin dominio. Sin `Dominios.txt`, se escribe a mano. `-Domain` admite el número, el dominio o `no`. Con dominio: usuario con permiso para unir equipos (si se escribe sin dominio, se usa `DOMINIO\usuario`) y su contraseña.
2. **Contraseña del Administrador local** (dos veces).

Al final, **solo si ninguna app quedó en fallo** (si no, se pospone y se hace al relanzar el script):

| Orden | Acción | Notas |
|---|---|---|
| 1 | Activa el Administrador integrado (SID `-500`, "Administrador") con esa contraseña | |
| 2 | Saca la cuenta estándar del grupo Administradores (SID `S-1-5-32-544`): `usuario`, `Usuario`, `user` o `User` (todas las que existan) | Solo si el paso 1 fue bien: nunca deja el equipo sin administrador local. |
| 3 | Une el equipo al dominio | Lo último. Pide reinicio (exit 3). Si ya estaba en ese dominio, no hace nada. |
| 4 | **Reinicio automático** (15 s de aviso; `shutdown /a` lo cancela) | Lo último, después del paso del dominio. Solo si quedó TODO verificado (todas las apps `ok`, validación final sin fallos, Administrador activo, cuenta estándar fuera de Administradores, paso del dominio hecho: unido, ya estaba o `no`, y Lenovo sin fallos) **y algo pide reiniciar**: unión al dominio, firmware/BIOS de Lenovo, un instalador o Windows. Si un firmware de Lenovo pide apagar, apaga (`shutdown /s`). Si falta algo, no reinicia y el informe dice por qué; si nada lo pide, "no hace falta". |

Las contraseñas solo están en memoria: no van a log, state ni informe. El resultado sale en la sección **Cierre del equipo** del informe. Probado en la VM (`Lab\guest\Test-Finalize.ps1`); nunca en el PC del técnico.

---

## Optimización de Windows (v5.3, `Optimize.ps1`)

- **Segundo plano desde t=0** (no alarga el despliegue): quita las apps de Store que sobran (lista `$Script:DebloatApps` al principio del fichero) para usuarios actuales y futuros, y aplica directivas contra publicidad, apps que se instalan solas, sugerencias de Bing, widgets y chat (equipo + usuario actual + perfil por defecto). Nunca toca Store, Calculadora, Fotos, Terminal, códecs, winget, apps de Lenovo ni NanaZip.
- **Al final:** "Aplicaciones de arranque" con PDFelement, PDF24, Everything y b4notify **deshabilitados** (mismo sitio que el Administrador de tareas, en HKLM: un usuario sin admin no puede reactivarlos); Edge sin startup boost ni segundo plano (directiva); AnyDesk obligatorio (servicio automático y en marcha, reinicio si se cae, entrada habilitada y sin botón Desinstalar). Los servicios de PDF24 (impresora) y Everything (índice) se mantienen.
- **Comprobaciones en el informe:** TRIM, software del fabricante a revisar (no se desinstala solo; Lenovo se respeta), lo que sigue arrancando con Windows. Windows Update no se toca (desde v5.5): el portátil ya se actualiza solo al iniciar.
- **Barra de tareas** (al final): Explorador, Edge, Outlook clásico y Teams (el de empresa `MSTeams`; si solo está el personal, ese), **sin Microsoft Store**. XML `C:\ProgramData\NodeDeploy\TaskbarLayout.xml` + directiva "Diseño de inicio" del equipo (`LockedStartLayout` / `StartLayoutFile`, método documentado por Microsoft para Windows 11): vale para todos los usuarios, también los del dominio, al iniciar sesión. El usuario puede anclar o desanclar después.
- El registro se vuelca a disco nada más aplicar los cambios (un apagado brusco justo después los perdía; visto en el laboratorio).

---

## Actualizaciones Lenovo (v5.5, `Lenovo.ps1`)

Proceso aparte desde t=0, solo en equipos Lenovo, con el módulo oficial `Lenovo.Client.Update` (copia local en `1.Node_Preparation\Lenovo\` o PowerShell Gallery). Mismo catálogo por modelo que Commercial Vantage; solo lo **aplicable, desatendido y crítico/recomendado**:

| Qué | Cuándo |
|---|---|
| Controladores y utilidades que solo piden reinicio | mientras se instalan las apps |
| Controladores de red (LAN / WiFi / WWAN) | al terminar las apps (no cortan descargas en marcha) |
| Firmware y BIOS (reinicio tipo 5) | lo último, **solo con cargador**; BitLocker en pausa hasta el reinicio, que es cuando se graban |
| Reinicio forzado inmediato (tipo 1, p. ej. firmware de docks) o no desatendidas | nunca |

No reinicia a mitad: informa de lo pendiente en la sección **Actualizaciones Lenovo** del informe y el reinicio (o apagado, si el firmware lo pide) lo hace el reinicio automático del final, después del dominio. Deploy.ps1 espera a que acabe (máx. 30 min) antes del cierre del equipo. `-NoLenovoUpdates` lo omite; `-NoBIOS` deja fuera firmware y BIOS.

## Hora del equipo (v5.5.1, al arrancar)

Antes de descargar nada: zona horaria de España (si la del equipo no es Madrid ni Canarias, se pone `-TimeZone`, por defecto Madrid) y reloj en hora con la cabecera `Date` de `www.msftconnecttest.com` (plan B `www.google.com`) por HTTP, que no depende del reloj local. Windows no corrige solo un desfase grande (límite `MaxPhaseCorrection`) y muchas redes cortan NTP; con la hora mal fallan las conexiones seguras (descargas, AnyDesk sin ID) y la unión al dominio (Kerberos). Deja el servicio de hora de Windows (W32Time) automático; en el dominio sincroniza con el controlador. Sale en la cabecera del informe (**Hora:**).

## Configuración de apps (v5.5, campo `Policy` del catálogo)

**AnyDesk** (`Test-AnyDeskHealth`, en cada pasada): servicio `AnyDesk-<id>_msi` automático y en marcha, ejecutable presente y conectado a la red de AnyDesk (`AnyDesk-<id>_msi.exe --get-id`, hasta 60 s). Si falta el servicio o el ejecutable (instalación a medias) reinstala el MSI (`REINSTALL=ALL REINSTALLMODE=amus`); si no hay ID reinicia el servicio y vuelve a esperar. La ventana que abre el instalador al terminar (antes de que el servicio conecte, podía quedarse a medias) se cierra y se reabre como usuario normal. El **ID** sale en la sección **Configuracion de apps** del informe y en `Validate_Report.md`; si no hay ID, el informe dice si responde `boot.net.anydesk.com:443` y los últimos errores de `ad_svc.trace` (hora del equipo, red, proxy o antivirus: puertos 80, 443 y 6568).

Tras las instalaciones, en cada pasada (también si la app ya estaba), se escriben los valores de registro del catálogo. Hoy, PDF24 (`HKLM\SOFTWARE\PDF24`, manual oficial v11; `!` = el valor del equipo manda sobre el del usuario): sin conversor online, enlaces a herramientas web, fax ni correo de PDF24; sin JavaScript en su lector; sin actualizaciones ni botones de actualizar; WebView2 del sistema; y en el escritorio solo PDF24 Toolbox. Sale en la sección **Configuracion de apps** del informe y lo comprueba `Validate.ps1`.

---

## Modos y parámetros

| Comando | Acción |
|---|---|
| `Deploy.bat` | Full deploy (default) + Validate. |
| `Deploy.bat probe` | Solo inventario de ficheros y estado de Office/Defender. No instala. |
| `Deploy.bat resume` | Re-detecta y reintenta lo pendiente o fallido. |
| `Deploy.bat validate` | Smoke tests sin tocar nada. |
| `Deploy.bat cleanup` | Mata procesos iManage residuales y retira exclusiones Defender huérfanas. |

Los parámetros extra se pasan tal cual a `Deploy.ps1` (`Deploy.bat full -SkipAV -Serial`):

| Parámetro | Efecto |
|---|---|
| `-SkipAV` | No instala ESET Management Agent ni Cortex XDR (laboratorio). |
| `-SkipApps A,B` | Excluye apps por nombre. |
| `-InstallFullOffice` | Si falta Word, instala Microsoft 365 completo. |
| `-OutlookMethod bootstrap\|odt` | Método principal para Outlook clásico (default `bootstrap`; el otro queda de plan B). |
| `-NoOffice` | No toca Office. |
| `-SequentialOffice` | Espera a Outlook antes de empezar el resto (diagnóstico). |
| `-Serial` | Un solo carril, todo en serie (diagnóstico). También `NODEDEPLOY_SERIAL=1`. |
| `-MaxRetries N` | Reintentos por app (default 2 → 3 intentos). |
| `-NoDefenderBoost` | Sin exclusiones temporales de Defender. |
| `-ForceReinstall` | Ignora la detección de "ya instalado". |
| `-DryRun` | Simula (no instala nada, no pregunta, no toca cuentas). `NODEDEPLOY_DRYRUN_SCALE`, `NODEDEPLOY_DRYRUN_FAIL="AqNet:1618:2"`. |
| `-Domain nombre` / `-Domain no` | Responde de antemano la pregunta del dominio. |
| `-StandardUser a,b` | Cuenta(s) que salen de Administradores (default `usuario,user`; da igual mayúsculas: `Usuario`, `User`…). |
| `-NoFinalize` | Sin preguntas ni cierre del equipo (laboratorio / pruebas). |
| `-NoOptimize` | Sin optimización de Windows (`Optimize.ps1`: limpieza de apps, publicidad, arranque, barra de tareas, TRIM). |
| `-NoLenovoUpdates` | Sin actualizaciones de Lenovo (`Lenovo.ps1`). |
| `-NoBIOS` | Actualizaciones de Lenovo sin firmware ni BIOS. |
| `-TimeZone id` / `-TimeZone no` | Zona horaria (por defecto `Romance Standard Time`, Madrid, solo si la del equipo no es de España; Canarias = `GMT Standard Time`). `no` = no tocar la hora. |

---

## Estados en el reporte

| Estado | Significado |
|---|---|
| `ok` / `ok_reboot` | Instalado y verificado (registro / servicio / binario). |
| `ok_unverified` | Exit 0 sin evidencia; se revalida al final. |
| `fail` / `fail_timeout` | Falló tras todos los reintentos. Ver log del instalador. |
| `blocked` | No se instaló porque falló un prerrequisito (p.ej. Drive Native sin Drive, Work Desktop sin Outlook). |
| `skipped_by_user` | Excluida con `-SkipApps` / `-SkipAV`. |

---

## Logs (`NodeDeploy_Run\state\`)

```
state\
├── nodedeploy_state.json        ← estado persistente (secretos enmascarados)
└── logs\
    ├── Deploy_YYYYMMDD_HHMMSS.log   ← log maestro con carril, intento y cronograma
    ├── msi_<app>.log / is_<app>.log / burn_<app>.log / inno_<app>.log
    ├── outlook_classic.xml + odt_outlook\   ← Outlook clásico (ODT)
    └── Validate_*.log
```

---

## Troubleshooting

- **Varias apps con 1618**: Windows Installer ocupado. v5 espera hasta 10 min al mutex y reintenta; si persiste, deja terminar Windows Update y `Deploy.bat resume`.
- **Outlook clásico no se instala**: revisar `logs\odt_outlook\` (ODT) y conectividad a `officecdn.microsoft.com`. El fallback `OutlookClassic.exe` se lanza solo.
- **Work Desktop `blocked`**: el reporte dice qué falta (Agent Services / Outlook / Word).
- **PDFelement lento**: comprobar que el boost de Defender se aplicó (línea `Defender boost` en el log) o que no hay otro antivirus escaneando.
- **Probar cambios**: nunca en un equipo de trabajo → `Lab\README.md`.

---

## Intune Win32App (referencia)

| Campo | Valor |
|---|---|
| Install command | `NodeDeploy_Run\PRO\Deploy.bat full` |
| Uninstall command | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File NodeDeploy_Run\PRO\Uninstall.ps1 -ConfirmReset` |
| Install behavior | System |
| Return codes | 0=Success, 1=Failed, 3=SoftReboot |
| Detection rule | Registry `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\iManageWorkDesktopForWindows` → `DisplayVersion` exists |

---

_NodeDeploy PRO v5.4.1 · 2026-09-28_
