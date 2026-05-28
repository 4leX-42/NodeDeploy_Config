@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM ============================================================
REM  NodeDeploy PRO v4.1 - Launcher .bat (Office en background paralelo)
REM  Uso:
REM     Deploy.bat              -> full deploy (default)
REM     Deploy.bat probe        -> sólo fingerprint, no instala
REM     Deploy.bat validate     -> sólo post-validate
REM     Deploy.bat resume       -> reintenta lo pendiente (post-reboot)
REM     Deploy.bat cleanup      -> mata procesos iManage residuales
REM
REM  Requisitos: Windows 10/11 x64, admin, PowerShell 5.1+.
REM ============================================================

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "DEPLOY_PS1=%SCRIPT_DIR%\Deploy.ps1"
set "VALIDATE_PS1=%SCRIPT_DIR%\Validate.ps1"
set "STATE_DIR=%SCRIPT_DIR%\..\state"
set "PHASE=%~1"
if "%PHASE%"=="" set "PHASE=full"

REM ---- Validar fase ----
set "VALID_PHASE=0"
for %%P in (full probe install validate resume cleanup) do (
    if /I "%PHASE%"=="%%P" set "VALID_PHASE=1"
)
if "%VALID_PHASE%"=="0" (
    echo [ERROR] Fase invalida: %PHASE%
    echo Uso: %~nx0 [full^|probe^|install^|validate^|resume^|cleanup]
    exit /b 99
)

REM ---- Banner ----
echo.
echo ============================================================
echo   NodeDeploy PRO v4.1   Phase: %PHASE%
echo   Equipo: %COMPUTERNAME%   Usuario: %USERNAME%
echo   Fecha: %DATE% %TIME%
echo ============================================================
echo.

REM ---- Comprobar admin (intenta abrir HKLM\SOFTWARE en modo escritura) ----
net session >nul 2>&1
if errorlevel 1 (
    echo [INFO] Sin privilegios de administrador. Solicitando elevacion UAC...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%PHASE%' -Verb RunAs"
    exit /b 0
)
echo [OK] Permisos administrativos confirmados.

REM ---- Comprobar PowerShell ----
where powershell >nul 2>&1
if errorlevel 1 (
    echo [FATAL] powershell.exe no encontrado en PATH
    exit /b 5
)
for /f "tokens=*" %%V in ('powershell -NoProfile -Command "$PSVersionTable.PSVersion.ToString()"') do set "PS_VER=%%V"
echo [INFO] PowerShell version: !PS_VER!

REM ---- Comprobar Deploy.ps1 ----
if not exist "%DEPLOY_PS1%" (
    echo [FATAL] No se encontro Deploy.ps1 en %SCRIPT_DIR%
    exit /b 2
)

REM ---- Routing ----
if /I "%PHASE%"=="validate" (
    echo [STEP] Ejecutando Validate.ps1 ...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%VALIDATE_PS1%" -StatePath "%STATE_DIR%"
    set "RC=!ERRORLEVEL!"
    goto :SHOW_RESULT
)

echo [STEP] Ejecutando Deploy.ps1 Phase=%PHASE% ...
echo [INFO] Log en: %STATE_DIR%\logs\Deploy_yyyyMMdd_HHmmss.log
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%DEPLOY_PS1%" -Phase %PHASE% -StatePath "%STATE_DIR%"
set "RC=!ERRORLEVEL!"

REM ---- Si fue 'full' o 'install' y termino sin reboot, ejecutar Validate ----
if "!RC!"=="0" (
    if /I not "%PHASE%"=="probe" (
        if /I not "%PHASE%"=="cleanup" (
            echo.
            echo [STEP] Ejecutando Validate.ps1 ^(smoke tests^) ...
            powershell -NoProfile -ExecutionPolicy Bypass -File "%VALIDATE_PS1%" -StatePath "%STATE_DIR%"
            set "VRC=!ERRORLEVEL!"
            if not "!VRC!"=="0" set "RC=!VRC!"
        )
    )
)

:SHOW_RESULT
echo.
echo ============================================================
if "!RC!"=="0" (
    echo   RESULT: SUCCESS   Phase=%PHASE%   exit=0
) else if "!RC!"=="1" (
    echo   RESULT: PARTIAL   Phase=%PHASE%   exit=1
    echo   Algunas aplicaciones fallaron. Revisa POSTVALIDATE_REPORT.md
) else if "!RC!"=="3" (
    echo   RESULT: REBOOT REQUIRED   Phase=%PHASE%   exit=3
    echo   Reinicia el equipo y ejecuta: Deploy.bat resume
) else if "!RC!"=="2" (
    echo   RESULT: CONFIG ERROR   exit=2
    echo   Fuente o configuracion invalidos.
) else if "!RC!"=="4" (
    echo   RESULT: ADMIN REQUIRED   exit=4
) else if "!RC!"=="5" (
    echo   RESULT: PREREQ MISSING   exit=5
) else (
    echo   RESULT: FAIL   Phase=%PHASE%   exit=!RC!
)
echo ============================================================
echo   Reportes y logs en: %STATE_DIR%
echo   - POSTVALIDATE_REPORT.md  (resumen instalacion)
echo   - Validate_Report.md      (smoke tests)
echo   - logs\Deploy_*.log       (log maestro)
echo   - logs\msi_*.log          (MSI verbose por app)
echo ============================================================
echo.

if /I "%PHASE%"=="probe" goto :END
if /I "%PHASE%"=="cleanup" goto :END

REM ---- Abrir el reporte si existe ----
set "REPORT=%STATE_DIR%\..\POSTVALIDATE_REPORT.md"
if exist "!REPORT!" (
    echo [INFO] Abriendo reporte: !REPORT!
    start "" notepad.exe "!REPORT!"
)

REM ---- Lanzar herramientas de configuracion manual post-deploy ----
REM Para full / install / resume / validate: abrir Local Users y System Properties
REM para que admin pueda hacer ajustes finales (usuarios locales, nombre PC, dominio).
if /I "%PHASE%"=="full"     goto :LAUNCH_TOOLS
if /I "%PHASE%"=="install"  goto :LAUNCH_TOOLS
if /I "%PHASE%"=="resume"   goto :LAUNCH_TOOLS
if /I "%PHASE%"=="validate" goto :LAUNCH_TOOLS
goto :END

:LAUNCH_TOOLS
echo.
echo [STEP] Abriendo herramientas de configuracion manual...
echo   - Local Users and Groups  (lusrmgr.msc)
echo   - System Properties       (sysdm.cpl)
start "" lusrmgr.msc
start "" sysdm.cpl

:END
if "!RC!"=="" set "RC=0"
set "FINAL_RC=!RC!"
endlocal & exit /b %FINAL_RC%

