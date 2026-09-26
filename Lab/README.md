# NodeDeploy Lab — entorno de pruebas aislado

VM de **VMware Workstation** (`NodeDeploy-Lab`) para probar NodeDeploy **sin tocar el equipo del técnico**.
Todo lo que instala software se ejecuta dentro de la VM mediante `vmrun`. En el host no se instala nada.

## Cómo funciona

- Es una VM normal de VMware Workstation (la que ya hay instalada en el PC), en
  `Documentos\Virtual Machines\NodeDeploy-Lab\NodeDeploy-Lab.vmx` (ruta exacta en `lab.local.json`).
- Los scripts la controlan con `vmrun.exe` (viene con Workstation) **sin ventana** (`nogui`): por eso
  no aparece en la biblioteca de VMware. Para verla: con la VM apagada o suspendida,
  Workstation → *Archivo → Abrir* → `NodeDeploy-Lab.vmx`.
- La VM ve el repo por una carpeta compartida **solo lectura** (`\\vmware-host\Shared Folders\nodedeploy`)
  y lo copia a su `C:\nodedeploy`, como si fuera el M.2 conectado al portátil.
- Cada prueba vuelve primero a un snapshot limpio, así que da igual lo que haya pasado antes en la VM.

| Snapshot | Estado |
|---|---|
| `00-clean-os` | Windows 11 Pro 25H2 es-ES recién instalado, Defender activo. |
| `01-lenovo-baseline` | Como un Lenovo recién sacado de la caja: **Microsoft 365 Apps for business** (Word/Excel/PPT, Current Channel) **sin Outlook clásico**. |

Los instaladores de **ESET y Cortex XDR no se copian nunca a la VM** (`guest\Sync-NodeDeploy.ps1`) y todas las pruebas usan `-SkipAV`.

## Uso

```powershell
cd D:\nodedeploy\Lab

# Prueba completa (revierte snapshot, sincroniza, ejecuta, recoge) ~16 min
powershell -ExecutionPolicy Bypass -File .\Invoke-LabTest.ps1 -HoldMsiSeconds 60 -Label prueba

# Variantes
.\Invoke-LabTest.ps1 -ExtraArgs '-Serial'            # sin carriles paralelos
.\Invoke-LabTest.ps1 -ExtraArgs '-NoDefenderBoost'   # medir impacto de Defender
.\Invoke-LabTest.ps1 -ExtraArgs '-OutlookMethod odt' # Outlook por ODT en vez del instalador de Microsoft
.\Invoke-LabTest.ps1 -KeepRunning                     # dejar la VM encendida para inspeccionar
# -HoldMsiSeconds N: simula Windows Update ocupando Windows Installer N segundos al empezar

# Analizar resultados
.\Show-ProcTrace.ps1 -ResultDir .\results\<carpeta>     # que instalador lanza msiexec, hijos, MSI ocupado
.\Compare-LabResults.ps1 -Before .\results\<a> -After .\results\<b>

# Ver / controlar la VM aunque no haya VMware Tools (VNC solo en 127.0.0.1)
powershell -ExecutionPolicy Bypass -File .\Get-LabScreenshot.ps1
.\Send-LabKeys.ps1 -WinR 'notepad c:\lab_firstlogon.log'

# Crear la VM desde cero (solo si se borra; ~30-40 min, desatendido)
powershell -ExecutionPolicy Bypass -File .\New-NodeDeployLab.ps1 -Stage all
```

Resultados en `Lab\results\<fecha>_<etiqueta>\`: `POSTVALIDATE_REPORT.md` (cronograma por app),
`Validate_Report.md`, logs de cada instalador y `proc_trace.csv` (procesos creados + estado del mutex MSI segundo a segundo).

### Con el M.2 desconectado

Ejecuta los mismos scripts desde la copia completa del PC (`C:\testeo2.0\1.Node_deployMain\Lab`): la carpeta
compartida de la VM sigue a la copia desde la que se lanza la prueba. `lab.local.json` va en el `Lab\` de esa copia.

## Detalles

- Credenciales del invitado en `lab.local.json` (generadas al crear la VM, fuera de git).
- VMware Tools va embebido en la ISO desatendida (`vmtools\`): Workstation no monta `windows.iso` como CD normal y Tools 12.x ya no trae `setup64.exe` (solo `setup.exe`).
- Primer inicio: `templates\lab-firstlogon.ps1` (log en `C:\lab_firstlogon.log` dentro de la VM).
- La VM usa firmware BIOS (instalación sin "Press any key"), sin vTPM (no requiere cifrado), NAT, 4 vCPU / 4 GB.
- Dentro de la VM el UAC está desactivado (solo laboratorio) para que `vmrun` tenga token de administrador completo.
- Windows Update está pausado en la VM para que los tiempos sean comparables entre pruebas.
- `guest\Extract-iManage3.ps1` / `guest\Extract-WDSetupIss.ps1`: sacan el `setup.iss` de un paquete iManage nuevo (si cambia la versión).
- Borrar el laboratorio: apagar la VM y eliminar `Documentos\Virtual Machines\NodeDeploy-Lab` y `Lab\lab.local.json`.
