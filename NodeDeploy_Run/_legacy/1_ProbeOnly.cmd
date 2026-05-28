@echo off
REM ============================================================
REM   NodeDeploy 1_ProbeOnly - dry-run probe + reports (NO instala)
REM ============================================================
setlocal
set "HERE=%~dp0"
set "SOURCE=C:\Users\user\Desktop\1.Node_Preparation"
set "ENGINE=%SOURCE%\Sc3.0\NodeDeploy.ps1"
set "STATE=%HERE%state"

if not exist "%ENGINE%" (
    echo [ERROR] Engine no encontrado: %ENGINE%
    pause
    exit /b 2
)

echo.
echo  [PROBE-ONLY] %ENGINE%
echo  Source: %SOURCE%
echo  State : %STATE%
echo.
echo Esto NO instala nada. Solo genera reports en %STATE%\reports\
echo.
pause

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ENGINE%" -Source "%SOURCE%" -StatePath "%STATE%" -ProbeOnly -NoPreCache -NoOfficeBackground -SkipFinalize
set RC=%ERRORLEVEL%

echo.
echo ProbeOnly finalizado (exit=%RC%).
echo Reports: %STATE%\reports
echo Logs:    %STATE%\logs
echo.
pause
exit /b %RC%
