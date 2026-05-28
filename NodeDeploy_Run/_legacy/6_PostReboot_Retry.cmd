@echo off
REM ============================================================
REM   NodeDeploy 6_PostReboot_Retry - reintento full post-reboot
REM   NO usa -ResumeOnly: SI reintenta apps fallidas (iManage WorkDesktop)
REM   State-aware: apps OK + presentes en OS = SKIP automaticamente
REM ============================================================
setlocal
set "HERE=%~dp0"
set "SOURCE=C:\Users\user\Desktop\1.Node_Preparation"
set "ENGINE=%SOURCE%\Sc3.0\NodeDeploy.ps1"
set "STATE=%HERE%state"

echo.
echo  [POST-REBOOT RETRY]
echo  Reintenta apps fallidas (state-aware: skipea ya instaladas).
echo  Esperado: solo iManage Work Desktop se reinstala (~1-2 min).
echo.
pause

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ENGINE%" -Source "%SOURCE%" -StatePath "%STATE%" -NoPreCache -SkipFinalize -MaxRetries 2
set RC=%ERRORLEVEL%

echo.
echo Retry finalizado (exit=%RC%).
echo.
pause
exit /b %RC%
