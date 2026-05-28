@echo off
REM ============================================================
REM   NodeDeploy 2_Quarantine - mueve apps no-config a Quarantine
REM   REVERSIBLE: usa Move-Item, no Remove-Item
REM ============================================================
setlocal
set "HERE=%~dp0"
set "SCRIPT=%HERE%Quarantine.ps1"
set "SOURCE=C:\Users\user\Desktop\1.Node_Preparation"
set "QUARANTINE=C:\Users\user\Desktop\1.Node_Preparation\_Quarantine"

echo.
echo  [QUARANTINE]
echo  Source     : %SOURCE%
echo  Quarantine : %QUARANTINE%
echo.
echo Apps NO incluidas en NodeDeploy_Config.html se moveran a Quarantine.
echo NO se borra nada. Reversible con Move-Item.
echo.
echo Pulsa tecla para mover, o Ctrl+C para abortar.
pause

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Source "%SOURCE%" -Quarantine "%QUARANTINE%"
set RC=%ERRORLEVEL%

echo.
echo Quarantine completado (exit=%RC%).
echo.
pause
exit /b %RC%
