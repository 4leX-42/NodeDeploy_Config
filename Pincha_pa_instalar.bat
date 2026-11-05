@echo off
REM ============================================================
REM  NodeDeploy PRO v5 - Root shortcut launcher (acepta los mismos parametros que Deploy.bat)
REM  Delega a NodeDeploy_Run\PRO\Deploy.bat
REM ============================================================
setlocal
set "SELF=%~f0"
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "TARGET=%ROOT%\NodeDeploy_Run\PRO\Deploy.bat"

if not exist "%TARGET%" goto :FALTA
call "%TARGET%" %*
exit /b %ERRORLEVEL%

:FALTA
REM Expansion retardada solo aqui: arriba %* se pasa tal cual a Deploy.bat (una "!" en un argumento se perderia)
setlocal EnableDelayedExpansion
echo [FATAL] No se encontro: !TARGET!
echo Verifica que NodeDeploy_Run\PRO\Deploy.bat existe ^(este .bat va DENTRO de la carpeta de NodeDeploy, no suelto^).
REM Nota en el Escritorio, LOGS_ERRORES\<equipo>_ARRANQUE.txt (el mismo fichero que usan Deploy.bat y Deploy.ps1)
set "DESK="
for /f "skip=2 tokens=2,*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" /v Desktop 2^>nul') do set "DESK=%%B"
if defined DESK call set "DESK=!DESK!"
if not defined DESK set "DESK=%USERPROFILE%\Desktop"
set "NOTE=!DESK!\LOGS_ERRORES\%COMPUTERNAME%_ARRANQUE.txt"
if not exist "!DESK!\LOGS_ERRORES" mkdir "!DESK!\LOGS_ERRORES" >nul 2>&1
>>"!NOTE!" (
    echo.
    echo ==== !DATE! !TIME! ^| Pincha_pa_instalar.bat ^| exit 2
    echo Fallo     : no se encontro NodeDeploy_Run\PRO\Deploy.bat al lado de este .bat
    echo Script    : !SELF!
    echo Buscado   : !TARGET!
) 2>nul
if exist "!NOTE!" echo [INFO] Anotado en: !NOTE!
pause
exit /b 2
