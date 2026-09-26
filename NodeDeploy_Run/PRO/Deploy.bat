@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM ============================================================
REM  NodeDeploy PRO v5 - Launcher
REM  Uso:
REM     Deploy.bat                     -> full deploy (default)
REM     Deploy.bat probe               -> solo inventario de ficheros, no instala
REM     Deploy.bat validate            -> solo post-validate
REM     Deploy.bat resume              -> reintenta lo pendiente (post-reboot)
REM     Deploy.bat cleanup             -> mata procesos iManage residuales
REM  Parametros extra (se pasan tal cual a Deploy.ps1), p.ej.:
REM     Deploy.bat full -SkipAV              (sin ESET / Cortex: laboratorio)
REM     Deploy.bat full -InstallFullOffice   (equipo SIN Office de fabrica)
REM     Deploy.bat full -Serial              (sin carriles paralelos, diagnostico)
REM     Deploy.bat full -NoDefenderBoost     (sin exclusiones temporales de Defender)
REM     Deploy.bat full -Domain no           (responde "no" a la pregunta del dominio)
REM     Deploy.bat full -NoFinalize          (sin preguntas ni cierre: Administrador / usuario / dominio)
REM  Al arrancar pregunta dominio (o "no"), usuario del dominio y contrasena del Administrador local;
REM  al final, solo si todo queda OK: Administrador activo, "usuario" fuera de Administradores y dominio.
REM
REM  Requisitos: Windows 10/11 x64, admin, PowerShell 5.1+.
REM ============================================================

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "DEPLOY_PS1=%SCRIPT_DIR%\Deploy.ps1"
set "VALIDATE_PS1=%SCRIPT_DIR%\Validate.ps1"
set "STATE_DIR=%SCRIPT_DIR%\..\state"
set "ALL_ARGS=%*"

REM ---- Fase = primer argumento salvo que empiece por '-' ----
REM (las etiquetas no pueden ir dentro de bloques entre parentesis)
set "PHASE=%~1"
set "EXTRA="
if "%PHASE%"=="" (
    set "PHASE=full"
    goto :args_done
)
if "%PHASE:~0,1%"=="-" (
    set "PHASE=full"
    set "EXTRA=%*"
    goto :args_done
)
:collect
shift
if "%~1"=="" goto :args_done
set "EXTRA=!EXTRA! %1"
goto :collect
:args_done

set "VALID_PHASE=0"
for %%P in (full probe install validate resume cleanup) do (
    if /I "%PHASE%"=="%%P" set "VALID_PHASE=1"
)
if "%VALID_PHASE%"=="0" (
    echo [ERROR] Fase invalida: %PHASE%
    echo Uso: %~nx0 [full^|probe^|install^|validate^|resume^|cleanup] [-SkipAV] [-InstallFullOffice] [-Serial]
    exit /b 99
)

echo.
echo ============================================================
echo   NodeDeploy PRO v5   Phase: %PHASE% %EXTRA%
echo   Equipo: %COMPUTERNAME%   Usuario: %USERNAME%
echo   Fecha: %DATE% %TIME%
echo ============================================================
echo.

REM ---- Admin (si no, relanza con UAC conservando TODOS los argumentos) ----
net session >nul 2>&1
if errorlevel 1 (
    echo [INFO] Sin privilegios de administrador. Solicitando elevacion UAC...
    if defined ALL_ARGS (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%ALL_ARGS%' -Verb RunAs"
    ) else (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    )
    exit /b 0
)
echo [OK] Permisos administrativos confirmados.

where powershell >nul 2>&1
if errorlevel 1 (
    echo [FATAL] powershell.exe no encontrado en PATH
    exit /b 5
)
for /f "tokens=*" %%V in ('powershell -NoProfile -Command "$PSVersionTable.PSVersion.ToString()"') do set "PS_VER=%%V"
echo [INFO] PowerShell version: !PS_VER!

if not exist "%DEPLOY_PS1%" (
    echo [FATAL] No se encontro Deploy.ps1 en %SCRIPT_DIR%
    exit /b 2
)

if /I "%PHASE%"=="validate" (
    echo [STEP] Ejecutando Validate.ps1 ...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%VALIDATE_PS1%" -StatePath "%STATE_DIR%"
    set "RC=!ERRORLEVEL!"
    goto :SHOW_RESULT
)

echo [STEP] Ejecutando Deploy.ps1 -Phase %PHASE% %EXTRA%
echo [INFO] Log en: %STATE_DIR%\logs\Deploy_yyyyMMdd_HHmmss.log
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%DEPLOY_PS1%" -Phase %PHASE% -StatePath "%STATE_DIR%" %EXTRA%
set "RC=!ERRORLEVEL!"

REM Validate tambien con exit 3 (reinicio pendiente por instaladores o por la union al dominio)
set "RUN_VALIDATE=0"
if "!RC!"=="0" set "RUN_VALIDATE=1"
if "!RC!"=="3" set "RUN_VALIDATE=1"
if "!RUN_VALIDATE!"=="1" (
    if /I not "%PHASE%"=="probe" (
        if /I not "%PHASE%"=="cleanup" (
            echo.
            echo [STEP] Ejecutando Validate.ps1 ^(smoke tests^) ...
            powershell -NoProfile -ExecutionPolicy Bypass -File "%VALIDATE_PS1%" -StatePath "%STATE_DIR%"
            set "VRC=!ERRORLEVEL!"
            if not "!VRC!"=="0" if not "!RC!"=="3" set "RC=!VRC!"
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
    echo   Reinicia el equipo para completar ^(instaladores que lo piden y/o union al dominio^).
    echo   Si quedo alguna app pendiente, tras reiniciar: Deploy.bat resume
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
echo   - POSTVALIDATE_REPORT.md  (resumen + cronograma por app)
echo   - Validate_Report.md      (smoke tests)
echo   - logs\Deploy_*.log       (log maestro)
echo   - logs\msi_*.log / is_*.log / burn_*.log / inno_*.log / odt_outlook\
echo ============================================================
echo.

if /I "%PHASE%"=="probe" goto :END
if /I "%PHASE%"=="cleanup" goto :END

set "REPORT=%STATE_DIR%\..\POSTVALIDATE_REPORT.md"
if exist "!REPORT!" (
    echo [INFO] Abriendo reporte: !REPORT!
    start "" notepad.exe "!REPORT!"
)

REM ---- Herramientas de configuracion manual post-deploy ----
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
