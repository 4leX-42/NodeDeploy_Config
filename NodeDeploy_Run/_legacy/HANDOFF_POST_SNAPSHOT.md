# HANDOFF — Post-Snapshot Rerun

**Sesion previa:** `a60b6fe1` + reintento `9116860f`
**Fecha trabajo:** 2026-05-26
**Estado final:** 15/16 apps OK · 1/16 FAIL (iManage Work Desktop)

---

## ⚠️ ANTES DE REVERTIR — Backup obligatorio

Snapshot va a eliminar **todo** lo del Escritorio. Hacer backup externo (USB / share) de:

```
C:\Users\user\Desktop\NodeDeploy_Run\          <- ESTE folder completo
C:\Users\user\Desktop\1.Node_Preparation\      <- folder fuente entero
```

`NodeDeploy_Run\PERSIST\ESET_Endpoint\` contiene el MSI cazado del cache EPI + token de licencia. Sin este folder no se puede reinstalar ESET Endpoint silent.

---

## Apps OK confirmadas (15) — se reinstalan automaticas

NodeDeploy state-aware las redetecta tras revert (registry vacio) y reinstala todas. Ninguna intervencion manual.

| App | Tech | Tiempo | Notas |
|---|---|---|---|
| AnyDesk | MSI | 8s | — |
| AqNet | MSI | 7s | — |
| Nebula CertAgent | MSI | 7s | — |
| MDR / Cortex XDR | MSI | 22s | `REBOOT=ReallySuppress` |
| ESET Management Agent | MSI | 14s | INI inline 9 props |
| Google Chrome | EXE stub | 91s | descarga online |
| Autofirma | NSIS | 30s | `/S` |
| Bit4id Middleware | NSIS | 16s | `/S` |
| PDFelement Business | Inno | 107s | `/VERYSILENT` |
| MitelConnect | IS wrapper | 74s | `/s /SMS /v"/qn"` |
| Microsoft 365 Apps (Outlook Classic) | C2R | 973s bg | XML existente sirve |
| iManage Agent Services | IS | 14s | — |
| iManage Drive | Burn | 70s | — |
| iManage Drive Native | Burn | 10s | — |
| **ESET Endpoint Security** ⭐ NUEVO | MSI | ~60s | requiere bundle PERSIST |

---

## App pendiente (1) — iManage Work Desktop

**Sintoma:** Exit `-2147213312` (0x80042000) inmediato, sin generar log MSI ni log wrapper. InstallShield bootstrap muere pre-MSI.

**Intentos hechos:**
1. Wrapper `/s /SMS /v"/qn REBOOT=ReallySuppress"` → fail
2. Reboot + retry mismo comando → fail
3. Stop service `imUpdateManagerService` + kill `iManageStayExec` + retry → fail (script `7_WorkDesktop_Direct.cmd`)

**Hipotesis vivas:**
- iManage Agent/Drive ya instalados generan locks en `C:\Program Files\iManage` que el bootstrap WorkDesktop no acepta
- Wrapper InstallShield necesita TEMP limpio (DELETED previous extract residuos)
- Posible falta de runtime (VC++ 2017+) no detectado

**Estrategias proximas a probar (en orden):**

### A. Instalar Work Desktop ANTES que Agent/Drive
Cambiar orden en NodeDeploy: Work Desktop primero, luego Agent Services, luego Drive. La hipotesis es que Work Desktop no acepta convivir con instalaciones previas.

### B. Extraer MSI del wrapper manualmente
```cmd
"C:\...\iManageWorkDesktopforWindowsx64.exe" /a /s
:: O bien:
"C:\...\iManageWorkDesktopforWindowsx64.exe" /extract_all:"C:\Temp\imwd_extract"
```
Luego `msiexec /i extract\setup.msi /qn REBOOT=ReallySuppress /l*v log.log`. Si genera log MSI veremos error real.

### C. Limpieza TEMP + reintento
```cmd
del /q /s "%TEMP%\{*}\*.*"
rd /s /q "%TEMP%\iManage*"
rd /s /q "%TEMP%\setup*"
:: luego wrapper
```

### D. Procmon trace
Lanzar Procmon → filtrar `iManageWorkDesktop*` → ejecutar wrapper → analizar Result `ACCESS DENIED` / `NAME NOT FOUND` previo al exit.

### E. Verificar runtimes
```powershell
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64' -ErrorAction SilentlyContinue
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X86' -ErrorAction SilentlyContinue
```
Si faltan VC redist, instalar `vc_redist.x64.exe /quiet /norestart` antes.

### F. Usar variante MSI directa
iManage publica `iManage Work Desktop x64.msi` separado (sin wrapper). Pedir a admin/Conesa o bajar de iManage Help portal.

---

## Notas adicionales

### ESET Management Agent — enrollment fingerprint
Trace log al final mostraba:
```
Error: CFingerprintReader: fingerprint reading failed
Error: DeviceEnrollmentCommand: HW fingerprint could not be obtained
Warning: session token temporarily unavailable, device is not enrolled yet
```
- Tras instalar **ESET Endpoint Security**, HW fingerprint suele completarse en siguiente ciclo (5-10 min) porque Endpoint expone el WMI provider que Agent estaba esperando.
- Verificar post-deploy en `C:\ProgramData\ESET\RemoteAdministrator\Agent\EraAgentApplicationData\Logs\status.html`. Buscar `enrolled` true y last connection reciente.
- Si persiste error tras 15 min: `Restart-Service EraAgentSvc` elevated.

### Conflicto AV (Cortex XDR + ESET Endpoint)
Ambos quedan activos simultaneos. Estado actual del nodo previo a revert. Decision pendiente:
- **Opcion A:** Cortex primary → ESET Endpoint en passive mode (deshabilitar Real-time desde consola PROTECT con policy)
- **Opcion B:** ESET primary → desinstalar Cortex XDR (`msiexec /x {CortexProductCode} /qn`)
- **Opcion C:** dejar ambos → riesgo BSOD / lentitud (no recomendado)

Pregunta a admin antes de re-deploy.

---

## Orden de ejecucion post-revert

Asumiendo snapshot = clean Windows + `1.Node_Preparation\` listo.

1. **Restaurar backup externo** de `NodeDeploy_Run\` al Escritorio.
2. **Copiar bundle ESET Endpoint a folder fuente** (engine lo detectara recursivo):
   ```cmd
   robocopy "C:\Users\user\Desktop\NodeDeploy_Run\PERSIST\ESET_Endpoint" ^
            "C:\Users\user\Desktop\1.Node_Preparation\ESET_Endpoint" /E /XO
   ```
3. **Pre-fix iManage Work Desktop:**
   - Editar `Sc3.0\NodeDeploy.ps1` o usar `-Order` flag si existe para forzar Work Desktop ANTES de Agent/Drive (Estrategia A).
   - O dejar igual y aceptar que falla → usar `7_WorkDesktop_Direct.cmd` post-engine para retry con limpieza TEMP previa.
4. **Ejecutar NodeDeploy completo:**
   ```cmd
   C:\Users\user\Desktop\NodeDeploy_Run\3_Deploy_REAL.cmd
   ```
5. **Si iManage Work Desktop falla otra vez:**
   ```cmd
   C:\Users\user\Desktop\NodeDeploy_Run\7_WorkDesktop_Direct.cmd
   ```
   (incluye stop services + extract + msiexec directo)
6. **Validar:**
   ```cmd
   C:\Users\user\Desktop\NodeDeploy_Run\5_PostValidate.cmd
   ```

---

## Scripts guardados en NodeDeploy_Run

| Script | Funcion | Estado |
|---|---|---|
| `0_Preflight.cmd` | Checks ambiente | original |
| `1_ProbeOnly.cmd` | Fingerprint sin instalar | original |
| `2_Quarantine.cmd` | Cuarentena duplicados | original |
| `3_Deploy_REAL.cmd` | Deploy completo | original |
| `4_Resume.cmd` | Resume sesion previa | original |
| `5_PostValidate.cmd` | Validacion post-install | original |
| `6_PostReboot_Retry.cmd` | Retry post-reboot | original |
| `7_WorkDesktop_Direct.cmd` | Retry dirigido iManage WorkDesktop (stop svc + extract + msiexec) | **nuevo 2026-05-26** |
| `8_ESET_Endpoint.cmd` | Install ESET Endpoint con token cazado | **nuevo 2026-05-26** |
| `Preflight.ps1` / `PostValidate.ps1` / `Quarantine.ps1` | Engines | originales |

---

## Estado actual VM (pre-revert)

- ESET Management Agent v13.1.1110.0 — **OK** + enrolled (con warning fingerprint pendiente)
- ESET Endpoint Security v12.1.2057.3 — **OK** + GUI activa (`egui.exe` PID 7832)
- Cortex XDR — **OK** activo
- 13 apps NodeDeploy originales — **OK**
- iManage Work Desktop — **FAIL** sin instalar

---

_Generado 2026-05-26 17:40 / session a60b6fe1+9116860f_
