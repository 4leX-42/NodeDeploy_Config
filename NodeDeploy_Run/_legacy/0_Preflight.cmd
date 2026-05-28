@echo off
REM ============================================================
REM   NodeDeploy 0_Preflight - validacion entorno (NO instala)
REM ============================================================
setlocal
set "HERE=%~dp0"
set "SCRIPT=%HERE%Preflight.ps1"
set "SOURCE=C:\Users\user\Desktop\1.Node_Preparation"

echo.
echo  [PREFLIGHT] %SCRIPT%
echo  Source: %SOURCE%
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Source "%SOURCE%" -WorkDir "%HERE%"
set RC=%ERRORLEVEL%

echo.
echo Preflight finalizado (exit=%RC%).
echo  0 = OK    1 = WARN (revisa)    2 = FATAL (no continuar)
echo Report: %HERE%PREFLIGHT_REPORT.md
echo.
pause
exit /b %RC%
