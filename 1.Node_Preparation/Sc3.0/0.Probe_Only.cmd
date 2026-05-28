@echo off
REM Probe + reports sin instalar nada. Util para validar share + fingerprint.
setlocal
set "HERE=%~dp0"
set "SCRIPT=%HERE%NodeDeploy.ps1"
set "SOURCE=\\192.168.2.8\utilidades\1.Node_Preparation"
set "STATE=C:\testeo2.0\state"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Source "%SOURCE%" -StatePath "%STATE%" -ProbeOnly
pause
