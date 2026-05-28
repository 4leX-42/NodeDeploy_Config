@echo off
REM ============================================================
REM   Reintento dirigido iManage Work Desktop
REM   1. Para imUpdateManagerService + kill iManageStayExec
REM   2. Intenta wrapper con /s /SMS /v"/qn /l*v LOG REBOOT=ReallySuppress"
REM   3. Si falla -2147213312 -> extrae MSI con /extract y lo invoca directo
REM ============================================================
setlocal
set "WRAPPER=C:\Users\user\Desktop\1.Node_Preparation\Imanage 2.0\iManage Work Desktop for Windows 10.9.4.39 (x64 Office)\iManageWorkDesktopforWindowsx64.exe"
set "LOGDIR=C:\Users\user\Desktop\NodeDeploy_Run\state\logs"
set "WRAPLOG=%LOGDIR%\imWorkDesktop_wrapper.log"
set "MSILOG=%LOGDIR%\imWorkDesktop_msi.log"
set "EXTRACT=%TEMP%\imWorkDesktop_extract"

echo [1/4] Parando servicio imUpdateManagerService...
sc stop imUpdateManagerService >nul 2>&1
sc config imUpdateManagerService start= disabled >nul 2>&1

echo [2/4] Matando procesos iManage residuales...
taskkill /F /IM iManageStayExec.exe >nul 2>&1
taskkill /F /IM iManageUpdateManagerService.exe >nul 2>&1
taskkill /F /IM iManageDrive.exe >nul 2>&1
taskkill /F /IM iManageWorkDesktop.exe >nul 2>&1
timeout /t 3 /nobreak >nul

echo [3/4] Intento 1: wrapper con logging completo...
"%WRAPPER%" /s /SMS /v"/qn REBOOT=ReallySuppress /l*v \"%WRAPLOG%\""
set RC=%ERRORLEVEL%
echo Wrapper exit=%RC%

if %RC% EQU 0 goto VERIFY
if %RC% EQU 3010 goto VERIFY

echo [4/4] Intento 2: extraer MSI y llamar msiexec directo...
if exist "%EXTRACT%" rmdir /s /q "%EXTRACT%"
mkdir "%EXTRACT%"
"%WRAPPER%" /s /extract_all:"%EXTRACT%"
timeout /t 5 /nobreak >nul
dir /b /s "%EXTRACT%\*.msi"
for /r "%EXTRACT%" %%F in (*.msi) do (
  echo Llamando msiexec /i "%%F"
  msiexec.exe /i "%%F" /qn /norestart REBOOT=ReallySuppress /l*v "%MSILOG%"
  set RC=!ERRORLEVEL!
  echo msiexec exit=!RC!
)

:VERIFY
echo.
echo --- Verificacion registry ---
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "iManage Work Desktop" 2>nul | findstr /i "DisplayName DisplayVersion"
reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" /s /f "iManage Work Desktop" 2>nul | findstr /i "DisplayName DisplayVersion"

echo.
echo Final exit=%RC%
echo Logs:
echo   %WRAPLOG%
echo   %MSILOG%
pause
endlocal
exit /b %RC%
