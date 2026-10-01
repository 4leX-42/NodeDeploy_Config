# NodeDeploy PRO v5 — Quick Start

> Conecta, responde las preguntas del arranque y espera. Outlook en background, dos carriles de instalación en paralelo.

## 1) Equipo destino

Portátil Lenovo con Windows 10/11 x64 y su **Microsoft 365 de fábrica** (Word/Excel/PPT).
Conecta el M.2 con la carpeta `nodedeploy` (la ruta da igual).

```
nodedeploy\
├── 1.Node_Preparation\       <- instaladores
└── NodeDeploy_Run\PRO\
    ├── Deploy.bat            <- LANZAR AQUÍ
    ├── Deploy.ps1
    ├── Finalize.ps1          <- cierre: Administrador, usuario, dominio
    ├── Lenovo.ps1            <- controladores, firmware y BIOS de Lenovo
    ├── Optimize.ps1          <- limpieza, arranque y barra de tareas
    └── Validate.ps1
```

## 2) Ejecutar

- **Doble clic**: `NodeDeploy_Run\PRO\Deploy.bat` (o `Pincha_pa_instalar.bat` en la raíz). Acepta UAC.
- **CMD admin**: `Deploy.bat` · opciones: `Deploy.bat full -InstallFullOffice` (equipo sin Office), `-Serial`, `-SkipAV`, `-Domain no`, `-NoFinalize`.

Al arrancar pregunta (luego todo va solo):

```
  ══ NODEDEPLOY ══ cierre del equipo ══════════════════════ PC-123 ══
  se aplica al final y solo si todas las apps quedan OK:
  administrador local · usuario fuera de administradores · dominio

  dominio   ↑↓ mover · enter elegir · o pulsa el número

  ►  1  Sede 1          empresa.local          <- barra verde
     2  Sede 2          sede2.empresa.local
     ...
     8  Otro            escribirlo a mano
     0  Sin dominio     no unir el equipo

  » dominio empresa.local · Sede 1
  › usuario de empresa.local (con permiso para unir equipos)  tecnico
  › contraseña de empresa.local\tecnico  ********
  › contraseña para el administrador local  ********
  › repítela  ********
```

Flechas + Enter, o el número (y Enter). Si la consola no deja leer teclas, sale la lista y se escribe el número.

Las sedes salen de `NodeDeploy_Run\PRO\Dominios.txt` (una por línea: `Sede = dominio`). Ese fichero **no va a GitHub** (el repo es público): está en el M.2 y en el PC; si falta, se escribe el dominio a mano. Plantilla: `Dominios.ejemplo.txt`.

Al final, **solo si todas las apps quedan OK**: activa el Administrador local con esa contraseña, saca la cuenta `usuario` (o `user`; da igual mayúsculas) de Administradores y, lo último, une el equipo al dominio. Si algo falla, el cierre se pospone: arréglalo y relanza el script (salta lo ya instalado).

Nada más arrancar pone la hora bien (zona de España y reloj en hora; con la hora mal fallan descargas, AnyDesk y el dominio). Mientras tanto, en segundo plano: Windows Update (todo lo de "Descargar e instalar todo"), controladores, firmware y BIOS de Lenovo (**deja el cargador conectado**: sin él no se instala el firmware/BIOS) y la limpieza de Windows. Al final: arranque, barra de tareas (Outlook y Teams, sin Store) y PDF24 solo en local.

## 3) Esperar

La consola muestra cada carril e intento:

```
[OFFICE] ODT OutlookRetail sobre O365BusinessRetail v16.0.20026.20112 canal Current (MatchInstalled)
[MSI] >> AnyDesk (intento 1/3) [msi]
[EXE] >> Bit4id Middleware (intento 1/3) [exe]
[MSI] OK   AnyDesk (4s) [registry:AnyDesk ...]
[MSI] RETRY AqNet - msi_busy:1618. Nuevo intento en 15s      <- Windows Update ocupando el instalador: se espera solo
...
OK   Outlook clasico [odt, exit 0] (183s)
[MSI] >> iManage Work Desktop (intento 1/3) [installshield-imanage]
```

## 4) Resultado

```
  RESULT: SUCCESS   Phase=full   exit=0
```

Se abre `POSTVALIDATE_REPORT.md`: resultado en una línea, **Atención** (solo si hay algo que hacer) y la tabla App / Estado / **Tiempo** (minutos en negrita; ⚠ si pasa de 1 minuto, o de 5 en Outlook). `lusrmgr.msc` / `sysdm.cpl` solo se abren si hay algo de cuentas o dominio que revisar.

Al terminar, el zip de logs se sube a la carpeta de red (`NodeDeploy_Success` / `NodeDeploy_Errors`) y, si todo quedó listo, **la carpeta del escritorio se borra sola** (si las actualizaciones siguen, cuando terminen; `-KeepFolder` la conserva).

| Exit | Acción |
|---|---|
| 0 | Todo OK y nada pide reiniciar. |
| 1 | Alguna app falló (se cortó rápido y se siguió con las demás; cierre pospuesto). Mira "Atención": motivo, en qué se quedó y las últimas líneas de su log. Arréglalo y relanza el script (salta lo ya instalado). |
| 3 | Hace falta reiniciar (dominio, Lenovo, Windows Update o un instalador): **reinicia solo a los 15 s** (`shutdown /a` lo cancela; si el firmware pide apagar, apaga: enciéndelo luego), salvo que falte unir el dominio pedido. Si las actualizaciones siguen instalándose, reinicia el vigilante cuando terminen: no lo apagues. |

## 5) Validar a mano

```powershell
Get-Service AnyDesk,nebulaCERTagent,EraAgentSvc,cyserver | Format-Table Name,Status
Test-Path 'C:\Program Files\Microsoft Office\root\Office16\OUTLOOK.EXE'    # Outlook clásico
Test-Path 'C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE'    # Word de fábrica
Test-Path 'C:\Program Files\iManage\iManage Drive\iManageDrive.exe'
notepad NodeDeploy_Run\POSTVALIDATE_REPORT.md
```

Tras reiniciar: `Deploy.bat validate`. Outlook debe abrir con la cinta de iManage.

## Fases

| Fase | Qué hace |
|---|---|
| `full` | Instala todo lo pendiente + Validate (default). |
| `probe` | Solo inventario (ficheros, Office, Defender). No instala. |
| `resume` | Re-detecta y reintenta lo pendiente/fallido. |
| `validate` | Solo smoke tests. |
| `cleanup` | Mata procesos iManage residuales. |

## Si algo va mal

1. Abre `POSTVALIDATE_REPORT.md`: estado, intentos, exit y motivo por app.
2. Log maestro: `state\logs\Deploy_*.log` (busca `[ERROR]`, `RETRY`, `BLOCKED`).
3. Log del instalador concreto: `state\logs\msi_* / is_* / burn_* / inno_* / odt_outlook\`.
4. `Deploy.bat resume`.

_Detalle técnico: `README.md`. Pruebas sin tocar tu PC: `Lab\README.md`._
