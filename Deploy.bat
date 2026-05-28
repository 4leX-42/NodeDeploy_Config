@echo off
REM ============================================================
REM  NodeDeploy PRO v4.2 - Root shortcut launcher
REM  Delega a NodeDeploy_Run\PRO\Deploy.bat
REM ============================================================
setlocal
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "TARGET=%ROOT%\NodeDeploy_Run\PRO\Deploy.bat"

if not exist "%TARGET%" (
    echo [FATAL] No se encontro: %TARGET%
    echo Verifica que NodeDeploy_Run\PRO\Deploy.bat existe.
    pause
    exit /b 2
)

call "%TARGET%" %*
exit /b %ERRORLEVEL%
