@echo off
REM ============================================================
REM   NodeDeploy v3.1 - Production launcher
REM   Lanza NodeDeploy.ps1 con auto-elevacion via UAC.
REM   Source UNC + state local.
REM ============================================================

setlocal
set "HERE=%~dp0"
set "SCRIPT=%HERE%NodeDeploy.ps1"
set "SOURCE=\\192.168.2.8\utilidades\1.Node_Preparation"
set "STATE=C:\testeo2.0\state"

REM Conectividad share (UNC). Si falla, abortar limpio.
if not exist "%SOURCE%\OfficeSetup.exe" (
    echo [ERROR] No se puede acceder al share: %SOURCE%
    echo Verifica conexion de red y credenciales de dominio.
    echo Mapeo manual: net use Y: %SOURCE% /persistent:no
    pause
    exit /b 2
)

if not exist "%STATE%" mkdir "%STATE%" 2>nul

echo.
echo  N0DE_DEPL0Y v3.1 launcher
echo  ---------------------------------
echo   Script:  %SCRIPT%
echo   Source:  %SOURCE%
echo   State :  %STATE%
echo.
echo  Pulsa cualquier tecla para iniciar (UAC pedira elevacion)...
pause >nul

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Source "%SOURCE%" -StatePath "%STATE%"
set RC=%ERRORLEVEL%

echo.
echo NodeDeploy ha terminado (exit code %RC%).
echo.
echo Reports: %STATE%\reports
echo Logs:    %STATE%\logs
echo.
pause
exit /b %RC%
