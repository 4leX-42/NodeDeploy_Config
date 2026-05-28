# NodeDeploy PRO v4.2 — Quick Start

> Copia, ejecuta, espera. 15-20 min. Office en background paralelo. Cero interaccion.

## 1) Equipo destino (Windows 11 Pro x64, snapshot creado)

Copia la carpeta `nodedeploy` completa al destino. Ruta sugerida: `C:\Users\Public\Desktop\nodedeploy\` o cualquier otra.

Estructura mínima:
```
nodedeploy\
├── 1.Node_Preparation\       <- instaladores
└── NodeDeploy_Run\PRO\
    ├── Deploy.bat            <- LANZAR AQUÍ
    ├── Deploy.ps1
    └── Validate.ps1
```

## 2) Ejecutar

**Opción A — doble clic**: `NodeDeploy_Run\PRO\Deploy.bat`. Acepta UAC.

**Opción B — CMD admin**:
```
cd C:\path\to\nodedeploy\NodeDeploy_Run\PRO
Deploy.bat
```

## 3) Esperar

15-25 minutos. La consola muestra progreso:
```
2026-05-26 14:02:13 [STEP] === GRUPO 1 ===
2026-05-26 14:02:23 [OK] AnyDesk  [registry:AnyDesk v7.0.15, service:AnyDesk(Running)]  (10s)
2026-05-26 14:02:32 [OK] AqNet    [registry:AqNet v4.7.2]  (9s)
...
```

## 4) Resultado

Al final aparece:

```
============================================================
  RESULT: SUCCESS   Phase=full   exit=0
============================================================
```

Y se abren automaticamente al terminar (full / install / resume / validate):
- `POSTVALIDATE_REPORT.md` en Notepad
- **Local Users and Groups** (`lusrmgr.msc`) — anadir usuarios locales
- **System Properties** (`sysdm.cpl`) — nombre PC / unirse a dominio

| Exit code | Acción |
|---|---|
| 0 | Todo OK. Reinicia opcional. |
| 1 | Fallos parciales. Revisa el reporte. |
| 3 | Reboot requerido. Reinicia + `Deploy.bat resume`. |

## 5) Validar manualmente

```powershell
# Servicios críticos
Get-Service cyserver,EraAgentSvc,AnyDesk,nebulaCERTagent

# Binarios principales
Test-Path 'C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE'
Test-Path 'C:\Program Files\Microsoft Office\root\Office16\OUTLOOK.EXE'
Test-Path 'C:\Program Files\iManage\iManage Drive\iManageDrive.exe'
Test-Path 'C:\Program Files\Google\Chrome\Application\chrome.exe'

# Reporte completo
notepad NodeDeploy_Run\Validate_Report.md
notepad NodeDeploy_Run\POSTVALIDATE_REPORT.md
```

## 6) Tras reinicio

Reiniciar el equipo. Tras login:

```
cd C:\path\NodeDeploy_Run\PRO
Deploy.bat validate
```

Verifica que todo sigue OK tras reboot. Outlook debería abrir y mostrar la cinta con iManage addins.

---

## Fases disponibles

| Fase | Qué hace | Cuándo usar |
|---|---|---|
| `full` | Probe + Install + Validate. Default. | Equipo nuevo / desde cero. |
| `probe` | Sólo verifica archivos presentes. No instala. | Antes del primer deploy real. |
| `install` | Sólo instala. | Si ya hiciste probe. |
| `validate` | Sólo smoke tests. Sin instalar. | Tras reboot o auditoría. |
| `resume` | Reintenta apps con `fail` o `deferred_reboot`. | Tras reboot intermedio. |
| `cleanup` | Mata procesos iManage residuales. | Antes de reintentar Work Desktop. |

---

## Logs (todos en `NodeDeploy_Run\state\`)

```
state\
├── nodedeploy_state.json         <- estado persistente
├── logs\
│   ├── Deploy_YYYYMMDD_HHMMSS.log    <- log maestro
│   ├── msi_<app>.log                 <- MSI verbose
│   ├── is_<app>.log                  <- InstallShield wrapper MSI
│   ├── burn_<app>.log                <- WiX Burn (iManage Drive)
│   └── Validate_YYYYMMDD_HHMMSS.log
└── reports\
    └── (reservado para futuras extensiones)
```

---

## Si algo va mal

1. Revisa el último `Deploy_*.log` en `state\logs\`.
2. Busca línea `[ERROR]` o `[FAIL]`.
3. Anota el `exit code` y el app afectada.
4. Mira el log MSI específico de esa app.
5. Aplica el workaround correspondiente (ver `README.md` sección Troubleshooting).

---

_Para detalle técnico completo → `NodeDeploy_v4.html` o `README.md`._
