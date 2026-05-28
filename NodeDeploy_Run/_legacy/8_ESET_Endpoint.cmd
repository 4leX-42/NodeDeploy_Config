@echo off
REM ============================================================
REM   Install ESET Endpoint Security desatendido
REM   MSI cazado del cache EPI con licencia preactivada
REM ============================================================
setlocal
set "MSI=C:\Users\user\Desktop\1.Node_Preparation\ESET_Endpoint\ees_nt64.msi"
set "LOG=C:\Users\user\Desktop\NodeDeploy_Run\state\logs\msi_ees_nt64.log"
set "TOKEN=token:665208b3-2ba0-7672-0b27-f6345cc78f2e"

echo Lanzando msiexec /qn ESET Endpoint Security...
msiexec.exe /i "%MSI%" /qn /norestart REBOOT=ReallySuppress INSTALLED_BY_ERA=1 ACTIVATION_DATA=%TOKEN% /l*v "%LOG%"
set RC=%ERRORLEVEL%
echo msiexec exit=%RC%

echo.
echo --- Registry check ---
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "ESET Endpoint Security" 2>nul | findstr /i "DisplayName DisplayVersion"
reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "ESET Endpoint Security" 2>nul | findstr /i "DisplayName DisplayVersion"

echo.
echo --- Services ---
sc query ekrn 2>nul | findstr STATE
sc query epfwwfp 2>nul | findstr STATE

echo.
echo Log: %LOG%
exit /b %RC%
