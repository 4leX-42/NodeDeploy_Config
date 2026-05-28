@echo off
REM ============================================================
REM   NodeDeploy 4_Resume - reanudar tras reboot/interrupcion
REM   No reintenta fallidos, solo procesa pendientes/no-validados
REM ============================================================
setlocal
set "HERE=%~dp0"
set "SOURCE=C:\Users\user\Desktop\1.Node_Preparation"
set "ENGINE=%SOURCE%\Sc3.0\NodeDeploy.ps1"
set "STATE=%HERE%state"

echo.
echo  [RESUME] %ENGINE%
echo.
pause

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ENGINE%" -Source "%SOURCE%" -StatePath "%STATE%" -ResumeOnly -NoPreCache -SkipFinalize
set RC=%ERRORLEVEL%

echo.
echo Resume finalizado (exit=%RC%).
echo.
pause
exit /b %RC%
