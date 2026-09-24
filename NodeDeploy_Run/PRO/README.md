# NodeDeploy PRO v5

> Despliegue desatendido de las apps corporativas Andersen en portátiles Lenovo.
> Dos carriles en paralelo (MSI + EXE), Outlook clásico en background, reintentos reales, resumible y validado.

---

## TL;DR — equipo nuevo

1. Conecta el M.2 con `nodedeploy\` (la ruta da igual, todo es relativo).
2. Doble clic sobre `NodeDeploy_Run\PRO\Deploy.bat` y acepta el UAC.
3. Espera: Notepad abre `POSTVALIDATE_REPORT.md` al terminar.
4. Si el reporte indica **REBOOT REQUIRED**, reinicia y ejecuta `Deploy.bat resume`.

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

---

## Office: qué hace exactamente

| Estado del equipo | Acción |
|---|---|
| Word + Outlook clásico presentes | Nada. |
| Word presente, Outlook ausente (**Lenovo de fábrica**) | En t=0 `OutlookClassic.exe` (instalador oficial "classic Outlook", añade el producto C2R `OutlookRetail`). Si falla → ODT `OutlookRetail` con la **misma versión, canal e idiomas** del Office instalado. `-OutlookMethod odt` para probar ODT primero. |
| Word ausente | Error claro: el equipo no trae Office. Work Desktop queda bloqueado. Para instalar Microsoft 365 completo: `-InstallFullOffice` (usa `Sc3.0\configuration.xml` y el payload local `Office\Data`). |

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
Diagnóstico adicional: `reg add "HKLM\SOFTWARE\InstallShield\29.0\Professional" /v DoVerboseLogging /t REG_DWORD /d 1 /f` y leer `%TEMP%\workdesktop_*.log`.

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
| `-DryRun` | Simula (no instala nada). `NODEDEPLOY_DRYRUN_SCALE`, `NODEDEPLOY_DRYRUN_FAIL="AqNet:1618:2"`. |

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

_NodeDeploy PRO v5.0.0 · 2026-09-24_
