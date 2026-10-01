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
- Windows Update está pausado en la VM (actualizaciones automáticas de Windows); NodeDeploy instala igualmente lo pendiente con su `WindowsUpdate.ps1`.
- Arranque con `Start-LabVm` (LabCommon): aplica en el `.vmx`, con la VM apagada, memoria sin fichero `.vmem` en disco, sin compartición de páginas e ISO desconectada. Hay que aplicarlo cada vez: al revertir, el snapshot devuelve su configuración (y `vmrun` no crea un snapshot si el disco no cambió).
- Pruebas de fallos: `Run-DeployBat.ps1 ... ENV:NODEDEPLOY_TEST_HANG=Everything:60` cambia el instalador de esa app por un proceso colgado (corte por tiempo, diagnóstico y que el resto siga); `App:40:freeze` deja el instalador real y a los 8 s congela Windows Installer (un MSI colgado de verdad, con el mutex retenido por el msiexec del servicio) para probar que se libera y las demás MSI siguen. Nombres sin espacios (los argumentos llegan sueltos): p. ej. `dnGrep`. `Break-AnyDesk.ps1` / `Break-Clock.ps1` rompen AnyDesk y la hora; `Test-Cleanup.ps1` prueba el borrado de la carpeta del escritorio con carpetas de mentira (escritorio, fuera de `C:\Users`, vigilante con y sin fallos; cancela los reinicios con `shutdown /a`) y `Test-CleanupBat.ps1` el camino real (doble clic en `Pincha_pa_instalar.bat` desde el Escritorio); usan `Cleanup.ps1` / `RebootMonitor.ps1` de `C:\LabRun` si el host los copia (2 min, sin sincronizar el kit); `Start-E2E.ps1` (tras sincronizar y `Prep-LaptopAccounts.ps1`, con `-Interactive -NoWait`) hace la prueba de punta a punta como el técnico: mueve el kit al Escritorio y lanza `Pincha_pa_instalar.bat` sin `-NoAutoReboot` (logs a `LOGS_preparation`, carpeta borrada y reinicio); `Get-E2E.ps1`, después del reinicio, deja el resumen y el zip de logs en `C:\LabRun`; `Probe-WU.ps1` lista lo pendiente en Windows Update; `Get-Reports.ps1` / `Get-Diag.ps1` traen informes y diagnóstico sin zip.
- Las pruebas pasan `-NoAutoReboot` (que la VM no se reinicie sola) y la sincronización no copia `Ajustes.local.txt` (los logs del laboratorio no van a la carpeta de red real).
- Si `Deploy.ps1` cambia la hora del invitado (salto de días), `vmrun` deja de esperar al programa: lanzar con `-NoWait` y esperar a una marca (`fileExistsInGuest`).
- `guest\Extract-iManage3.ps1` / `guest\Extract-WDSetupIss.ps1`: sacan el `setup.iss` de un paquete iManage nuevo (si cambia la versión).
- Borrar el laboratorio: apagar la VM y eliminar `Documentos\Virtual Machines\NodeDeploy-Lab` y `Lab\lab.local.json`.
