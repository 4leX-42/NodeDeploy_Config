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
    └── Validate.ps1
```

## 2) Ejecutar

- **Doble clic**: `NodeDeploy_Run\PRO\Deploy.bat` (o `Pincha_pa_instalar.bat` en la raíz). Acepta UAC.
- **CMD admin**: `Deploy.bat` · opciones: `Deploy.bat full -InstallFullOffice` (equipo sin Office), `-Serial`, `-SkipAV`, `-Domain no`, `-NoFinalize`.

Al arrancar pregunta (luego todo va solo):

```
Dominio al que unir el equipo (escribe no para no unirlo): andersen.local
Usuario de andersen.local con permiso para unir equipos: tecnico
Contraseña de andersen.local	ecnico: ********
Contraseña para el Administrador local: ********
Repite la contraseña: ********
```

Al final, **solo si todas las apps quedan OK**: activa el Administrador local con esa contraseña, saca a `usuario` de Administradores y, lo último, une el equipo al dominio. Si algo falla, el cierre se pospone: arréglalo y relanza el script (salta lo ya instalado).

## 3) Esperar

La consola muestra cada carril e intento:

```
[OFFICE] Word presente, Outlook ausente -> OutlookClassic.exe (instalador Microsoft 'classic Outlook') en t=0
[MSI] >> AnyDesk (intento 1/3) [msi]
[EXE] >> Bit4id Middleware (intento 1/3) [exe]
[MSI] OK   AnyDesk (4s) [registry:AnyDesk ...]
[MSI] RETRY AqNet - msi_busy:1618. Nuevo intento en 15s      <- Windows Update ocupando el instalador: se espera solo
...
OK   Outlook clasico [bootstrap, exit 0] (300s)
[MSI] >> iManage Work Desktop (intento 1/3) [installshield-imanage]
```

## 4) Resultado

```
  RESULT: SUCCESS   Phase=full   exit=0
```

Se abren: `POSTVALIDATE_REPORT.md` (estado + cronograma), **Local Users and Groups** y **System Properties**.

| Exit | Acción |
|---|---|
| 0 | Todo OK (sin dominio). Reinicio recomendado. |
| 1 | Algo falló tras 3 intentos (cierre pospuesto). Revisa el reporte; desinstala lo que quede a medias y relanza el script. |
| 3 | Reinicio requerido (unión al dominio o un instalador lo pide). Reinicia. |

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
