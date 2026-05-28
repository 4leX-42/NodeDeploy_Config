@echo off
REM ============================================================
REM  NodeDeploy PRO v4.2 - Abrir Dashboard HTML
REM ============================================================
setlocal
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "HTML=%ROOT%\NodeDeploy_Run\PRO\NodeDeploy_v4.html"

if not exist "%HTML%" (
    echo [FATAL] No se encontro: %HTML%
    pause
    exit /b 2
)

start "" "%HTML%"
exit /b 0
