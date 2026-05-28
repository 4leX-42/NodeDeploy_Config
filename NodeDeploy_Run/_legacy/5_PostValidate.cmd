@echo off
REM ============================================================
REM   NodeDeploy 5_PostValidate - validacion profunda post-install
REM ============================================================
setlocal
set "HERE=%~dp0"
set "SCRIPT=%HERE%PostValidate.ps1"

echo.
echo  [POST-VALIDATE]
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -WorkDir "%HERE%"
set RC=%ERRORLEVEL%

echo.
echo PostValidate finalizado (exit=%RC%).
echo Report: %HERE%POSTVALIDATE_REPORT.md
echo.
pause
exit /b %RC%
