# NodeDeploy Lab — entorno de pruebas aislado

VM de VMware Workstation (`NodeDeploy-Lab`) para probar NodeDeploy **sin tocar el equipo del técnico**.
Todo lo que instala software se ejecuta dentro de la VM mediante `vmrun`. En el host no se instala nada.

## Qué simula

| Snapshot | Estado |
|---|---|
| `00-clean-os` | Windows 11 Pro 25H2 es-ES recién instalado, Defender activo. |
| `01-lenovo-baseline` | Como un Lenovo recién sacado de la caja: **Microsoft 365 Apps for business** (Word/Excel/PPT, Current Channel 2605) **sin Outlook clásico** + repo ya copiado en `C:\nodedeploy`. |

Los instaladores de **ESET y Cortex XDR no se copian nunca a la VM** (`guest\Sync-NodeDeploy.ps1`) y todas las pruebas usan `-SkipAV`.

## Uso

```powershell
cd D:\nodedeploy\Lab

# 1) Crear la VM (una sola vez, ~30-40 min, desatendido)
powershell -ExecutionPolicy Bypass -File .\New-NodeDeployLab.ps1 -Stage all

# 2) Prueba completa de la versión actual (revierte snapshot, sincroniza, ejecuta, recoge)
powershell -ExecutionPolicy Bypass -File .\Invoke-LabTest.ps1

# Comparar con la versión anterior (v4.2.11, sacada de git)
powershell -ExecutionPolicy Bypass -File .\Invoke-LabTest.ps1 -Version v4 -Label antes

# Variantes
.\Invoke-LabTest.ps1 -ExtraArgs '-Serial'            # sin carriles paralelos
.\Invoke-LabTest.ps1 -ExtraArgs '-NoDefenderBoost'   # medir impacto de Defender
.\Invoke-LabTest.ps1 -KeepRunning                     # dejar la VM encendida para inspeccionar

.\Invoke-LabTest.ps1 -HoldMsiSeconds 90              # simula Windows Update ocupando Windows Installer

# Analizar resultados
.\Show-ProcTrace.ps1 -ResultDir .\results\<carpeta>     # que instalador lanza msiexec, hijos, MSI ocupado
.\Compare-LabResults.ps1 -Before .\results\<a> -After .\results\<b>

# Ver / controlar la VM aunque no haya VMware Tools (VNC solo en 127.0.0.1)
powershell -ExecutionPolicy Bypass -File .\Get-LabScreenshot.ps1
.\Send-LabKeys.ps1 -WinR 'notepad c:\lab_firstlogon.log'
```

Resultados en `Lab\results\<fecha>_<etiqueta>\`: `POSTVALIDATE_REPORT.md` (cronograma por app),
`Validate_Report.md`, logs de cada instalador y `proc_trace.csv` (procesos creados + estado del mutex MSI segundo a segundo).

## Detalles

- Credenciales del invitado en `lab.local.json` (generadas al crear la VM, fuera de git).
- VMware Tools va embebido en la ISO desatendida (`vmtools\`): Workstation no monta `windows.iso` como CD normal y Tools 12.x ya no trae `setup64.exe` (solo `setup.exe`).
- Primer inicio: `templates\lab-firstlogon.ps1` (log en `C:\lab_firstlogon.log` dentro de la VM).
- La VM usa firmware BIOS (instalación sin "Press any key"), sin vTPM (no requiere cifrado), NAT, 4 vCPU / 4 GB.
- Carpeta compartida **solo lectura** con el repo: `\\vmware-host\Shared Folders\nodedeploy`.
- Dentro de la VM el UAC está desactivado (solo laboratorio) para que `vmrun` tenga token de administrador completo.
- Windows Update está pausado en la VM para que los tiempos sean comparables entre pruebas.
- Para abrir la VM en la interfaz de VMware: `vmrun -T ws stop "<vmx>" soft` y abrir el `.vmx` desde Workstation.
- Borrar el laboratorio: apagar la VM y eliminar `Documents\Virtual Machines\NodeDeploy-Lab` + `Lab\lab.local.json`.
