@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM ============================================================
REM  NodeDeploy PRO v5 - Launcher
REM  Uso:
REM     Deploy.bat                     -> full deploy (default)
REM     Deploy.bat probe               -> solo inventario de ficheros, no instala
REM     Deploy.bat validate            -> solo post-validate
REM     Deploy.bat resume              -> reintenta lo pendiente (post-reboot)
REM     Deploy.bat cleanup             -> mata procesos iManage residuales
REM  Parametros extra (se pasan tal cual a Deploy.ps1), p.ej.:
REM     Deploy.bat full -SkipAV              (sin ESET / Cortex: laboratorio)
REM     Deploy.bat full -InstallFullOffice   (equipo SIN Office de fabrica)
REM     Deploy.bat full -Serial              (sin carriles paralelos, diagnostico)
REM     Deploy.bat full -NoDefenderBoost     (sin exclusiones temporales de Defender)
REM     Deploy.bat full -Domain no           (responde "no" a la pregunta del dominio; -Domain 3 = sede 3 de Dominios.txt)
REM     Deploy.bat full -NoFinalize          (sin preguntas ni cierre: Administrador / usuario / dominio)
REM     Deploy.bat full -TimeZone "GMT Standard Time"   (zona horaria; por defecto Madrid si no es de Espana; no = no tocar)
REM     Deploy.bat full -NoWindowsUpdate     (sin Windows Update)   -NoLenovoUpdates / -NoBIOS (Lenovo)
REM     Deploy.bat full -NoMcAfee            (en LG, no quitar el McAfee de fabrica)
REM     Deploy.bat full -KeepFolder          (no borrar la carpeta del escritorio al terminar)
REM     Deploy.bat full -NoAutoReboot        (sin reinicio automatico: laboratorio / pruebas)
REM  Al arrancar pregunta dominio (o "no"), usuario del dominio y contrasena del Administrador local;
REM  al final, solo si todo queda OK: Administrador activo, "usuario" fuera de Administradores y dominio.
REM
REM  Requisitos: Windows 10/11 x64, admin, PowerShell 5.1+.
REM ============================================================

set "SELF=%~f0"
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "DEPLOY_PS1=%SCRIPT_DIR%\Deploy.ps1"
set "VALIDATE_PS1=%SCRIPT_DIR%\Validate.ps1"
set "STATE_DIR=%SCRIPT_DIR%\..\state"
set "ALL_ARGS=%*"

REM ---- Fase = primer argumento salvo que empiece por '-' ----
REM (las etiquetas no pueden ir dentro de bloques entre parentesis)
set "PHASE=%~1"
set "EXTRA="
if "%PHASE%"=="" (
    set "PHASE=full"
    goto :args_done
)
if "%PHASE:~0,1%"=="-" (
    set "PHASE=full"
    set "EXTRA=%*"
    goto :args_done
)
:collect
shift
if "%~1"=="" goto :args_done
set "EXTRA=!EXTRA! %1"
goto :collect
:args_done

set "VALID_PHASE=0"
for %%P in (full probe install validate resume cleanup) do (
    if /I "%PHASE%"=="%%P" set "VALID_PHASE=1"
)
if "%VALID_PHASE%"=="0" (
    echo [ERROR] Fase invalida: %PHASE%
    echo Uso: %~nx0 [full^|probe^|install^|validate^|resume^|cleanup] [-SkipAV] [-InstallFullOffice] [-Serial]
    set "RC=99"
    call :EARLY_NOTE "Fase invalida: !PHASE!"
    set "PAUSE_AT_END=1"
    goto :END
)

echo.
echo ============================================================
echo   NodeDeploy PRO v5   Phase: %PHASE% %EXTRA%
echo   Equipo: %COMPUTERNAME%   Usuario: %USERNAME%
echo   Fecha: %DATE% %TIME%
echo ============================================================
echo.

REM ---- Admin (si no, relanza con UAC conservando TODOS los argumentos) ----
net session >nul 2>&1
if errorlevel 1 (
    echo [INFO] Sin privilegios de administrador. Solicitando elevacion UAC...
    if defined ALL_ARGS (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%ALL_ARGS%' -Verb RunAs"
    ) else (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    )
    exit /b 0
)
echo [OK] Permisos administrativos confirmados.

where powershell >nul 2>&1
if errorlevel 1 (
    echo [FATAL] powershell.exe no encontrado en PATH
    set "RC=5"
    call :EARLY_NOTE "powershell.exe no encontrado en PATH"
    set "PAUSE_AT_END=1"
    goto :END
)
for /f "tokens=*" %%V in ('powershell -NoProfile -Command "$PSVersionTable.PSVersion.ToString()"') do set "PS_VER=%%V"
echo [INFO] PowerShell version: !PS_VER!

if not exist "%DEPLOY_PS1%" (
    echo [FATAL] No se encontro Deploy.ps1 en !SCRIPT_DIR!
    set "RC=2"
    call :EARLY_NOTE "No se encontro Deploy.ps1 en la carpeta del .bat"
    set "PAUSE_AT_END=1"
    goto :END
)

if /I "%PHASE%"=="validate" (
    echo [STEP] Ejecutando Validate.ps1 ...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%VALIDATE_PS1%" -StatePath "%STATE_DIR%"
    set "RC=!ERRORLEVEL!"
    goto :SHOW_RESULT
)

echo [STEP] Ejecutando Deploy.ps1 -Phase %PHASE% %EXTRA%
echo [INFO] Log en: %STATE_DIR%\logs\Deploy_yyyyMMdd_HHmmss.log
echo.
del /f /q "%TEMP%\NodeDeploy_inicio.flag" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File "%DEPLOY_PS1%" -Phase %PHASE% -StatePath "%STATE_DIR%" %EXTRA%
set "RC=!ERRORLEVEL!"

REM ---- Deploy.ps1 deja %TEMP%\NodeDeploy_inicio.flag al crear su log (o al anotar un fallo de arranque). Sin ella no
REM      llego ni a ejecutarse (parametro mal escrito, error de sintaxis): nota en el Escritorio, LOGS_ERRORES, y fin
REM      (sin Validate ni reinicio: las marcas de state\ podrian ser de una ejecucion anterior).
if not exist "%TEMP%\NodeDeploy_inicio.flag" (
    echo.
    echo [ERROR] Deploy.ps1 fallo antes de crear su log ^(exit !RC!^). El motivo es el texto rojo de arriba.
    if "!RC!"=="0" set "RC=9"
    if "!RC!"=="3" set "RC=9"
    call :EARLY_NOTE "Deploy.ps1 fallo antes de crear su log - exit !RC!" PARSE
    set "PAUSE_AT_END=1"
    goto :END
)

REM ---- Deploy.ps1 borra state\en_curso.txt al terminar: si sigue ahi, murio a mitad. Logs al Escritorio (LOGS_ERRORES).
if exist "%STATE_DIR%\en_curso.txt" (
    echo.
    echo [ERROR] Deploy.ps1 se ha cortado a mitad ^(exit !RC!^). Guardando los logs en el Escritorio, LOGS_ERRORES...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\Save-ErrorLogs.ps1" -StatePath "%STATE_DIR%" -Motivo "Deploy.ps1 salio sin terminar (exit !RC!)"
    if "!RC!"=="0" set "RC=9"
    if "!RC!"=="3" set "RC=9"
)

REM Validate tambien con exit 3 (reinicio pendiente por instaladores o por la union al dominio)
set "VRC="
set "RUN_VALIDATE=0"
if "!RC!"=="0" set "RUN_VALIDATE=1"
if "!RC!"=="3" set "RUN_VALIDATE=1"
if "!RUN_VALIDATE!"=="1" (
    if /I not "%PHASE%"=="probe" (
        if /I not "%PHASE%"=="cleanup" (
            echo.
            echo [STEP] Ejecutando Validate.ps1 ^(smoke tests^) ...
            powershell -NoProfile -ExecutionPolicy Bypass -File "%VALIDATE_PS1%" -StatePath "%STATE_DIR%"
            set "VRC=!ERRORLEVEL!"
            if not "!VRC!"=="0" if not "!RC!"=="3" set "RC=!VRC!"
        )
    )
)

:SHOW_RESULT
echo.
echo ============================================================
if "!RC!"=="0" (
    echo   RESULT: SUCCESS   Phase=%PHASE%   exit=0
) else if "!RC!"=="1" (
    echo   RESULT: PARTIAL   Phase=%PHASE%   exit=1
    echo   Algunas aplicaciones fallaron. Revisa POSTVALIDATE_REPORT.md
) else if "!RC!"=="3" (
    echo   RESULT: REBOOT REQUIRED   Phase=%PHASE%   exit=3
    echo   Reinicia el equipo para completar ^(union al dominio, firmware/BIOS de Lenovo y/o instaladores^).
    echo   Si quedo alguna app pendiente, tras reiniciar: Deploy.bat resume
) else if "!RC!"=="2" (
    echo   RESULT: CONFIG ERROR   exit=2
    echo   Fuente o configuracion invalidos.
) else if "!RC!"=="4" (
    echo   RESULT: ADMIN REQUIRED   exit=4
) else if "!RC!"=="5" (
    echo   RESULT: PREREQ MISSING   exit=5
) else (
    echo   RESULT: FAIL   Phase=%PHASE%   exit=!RC!
)
echo ============================================================
echo   Reportes y logs en: %STATE_DIR%
echo   - POSTVALIDATE_REPORT.md  (resumen + cronograma por app)
echo   - Validate_Report.md      (smoke tests)
echo   - logs\Deploy_*.log       (log maestro)
echo   - logs\msi_*.log / is_*.log / burn_*.log / inno_*.log / odt_outlook\
echo ============================================================
echo.

REM ---- Reinicio / apagado automatico. Deploy.ps1 deja la marca cuando algo pide reiniciar (dominio unido, Lenovo,
REM      Windows Update, instaladores o Windows) y no hay nada en contra (dominio pedido sin unir o actualizaciones
REM      aun instalandose; para eso queda el vigilante). Una app con fallo no lo frena: sale en el informe.
REM      Linea 1 de la marca: reiniciar / apagar (algun firmware de Lenovo se graba al apagar). Linea 2: el motivo.
set "AUTO_ACT="
set "AUTO_WHY="
if exist "%STATE_DIR%\reinicio_automatico.flag" (
    set /p AUTO_ACT=<"%STATE_DIR%\reinicio_automatico.flag"
    for /f "usebackq skip=1 delims=" %%L in ("%STATE_DIR%\reinicio_automatico.flag") do if not defined AUTO_WHY set "AUTO_WHY=%%L"
)
REM ---- Carpeta pegada en el escritorio: Deploy.ps1 deja borrar_carpeta.flag solo si TODO quedo listo. La borra un
REM      ayudante desde %TEMP% en cuanto este .bat termina, y el reinicio (si hay) lo hace el ayudante despues.
if exist "%STATE_DIR%\borrar_carpeta.flag" goto :CLEANUP
if not defined AUTO_ACT goto :NO_AUTO
if /I "!AUTO_ACT!"=="apagar" goto :AUTO_OFF
echo [STEP] Reinicio automatico en 15 s: !AUTO_WHY!. Para cancelarlo: shutdown /a
call :DO_SHUTDOWN r 15 "NodeDeploy: reinicio en 15 s: !AUTO_WHY!. Para cancelar: shutdown /a"
if errorlevel 1 set "PAUSE_AT_END=1"
goto :END
:AUTO_OFF
echo [STEP] Apagado automatico en 15 s: !AUTO_WHY!. El firmware de Lenovo se graba al apagar; luego enciende el equipo.
call :DO_SHUTDOWN s 15 "NodeDeploy: apagado en 15 s para grabar el firmware de Lenovo: !AUTO_WHY!. Enciendelo despues. Para cancelar: shutdown /a"
if errorlevel 1 set "PAUSE_AT_END=1"
goto :END
:CLEANUP
REM v5.7.6: primero se programa el reinicio (comprobado) y despues se lanza el borrado (sin reinicio propio). Antes
REM lo hacia Cleanup.ps1 al terminar de borrar, oculto y sin dejar rastro: si algo lo cortaba, el equipo no reiniciaba.
set "REPORT=%STATE_DIR%\..\POSTVALIDATE_REPORT.md"
if exist "!REPORT!" start "" /D "%TEMP%" notepad.exe "!REPORT!"
copy /y "%SCRIPT_DIR%\Cleanup.ps1" "%TEMP%\NodeDeploy_Cleanup.ps1" >nul
echo [OK] Todo listo: esta carpeta de NodeDeploy se borra sola en unos segundos ^(los logs ya estan guardados^).
if not defined AUTO_ACT goto :CLEANUP_GO
set "SD_M=r"
if /I "!AUTO_ACT!"=="apagar" set "SD_M=s"
echo [STEP] !AUTO_ACT! automatico en 30 s: !AUTO_WHY!. Para cancelarlo: shutdown /a
call :DO_SHUTDOWN !SD_M! 30 "NodeDeploy: !AUTO_ACT! en 30 s: !AUTO_WHY!. Para cancelar: shutdown /a"
:CLEANUP_GO
start "" /D "%TEMP%" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%TEMP%\NodeDeploy_Cleanup.ps1" -FlagFile "%STATE_DIR%\borrar_carpeta.flag" -NoReboot
cd /d "%TEMP%"
goto :END
:NO_AUTO
REM Sin reinicio ni borrado automatico queda trabajo a mano: la ventana espera a una tecla en vez de cerrarse sola
REM (si Deploy.ps1 muere a mitad, el motivo queda a la vista y en logs\Deploy_*_consola.txt).
set "PAUSE_AT_END=1"

if /I "%PHASE%"=="probe" goto :END
if /I "%PHASE%"=="cleanup" goto :END

set "REPORT=%STATE_DIR%\..\POSTVALIDATE_REPORT.md"
if exist "!REPORT!" (
    echo [INFO] Abriendo reporte: !REPORT!
    start "" notepad.exe "!REPORT!"
)

REM ---- Herramientas de configuracion manual post-deploy ----
if /I "%PHASE%"=="full"     goto :LAUNCH_TOOLS
if /I "%PHASE%"=="install"  goto :LAUNCH_TOOLS
if /I "%PHASE%"=="resume"   goto :LAUNCH_TOOLS
if /I "%PHASE%"=="validate" goto :LAUNCH_TOOLS
goto :END

:LAUNCH_TOOLS
REM Deploy.ps1 deja en state\herramientas.txt solo lo que hay que revisar a mano (lusrmgr = cuentas, sysdm =
REM dominio). Vacio = cierre comprobado: no se abre nada. Sin el fichero (p. ej. "validate"), se abren las dos.
set "T_USR=1"
set "T_SYS=1"
if exist "%STATE_DIR%\herramientas.txt" (
    set "T_USR=0"
    set "T_SYS=0"
    findstr /i /x "lusrmgr" "%STATE_DIR%\herramientas.txt" >nul 2>&1 && set "T_USR=1"
    findstr /i /x "sysdm" "%STATE_DIR%\herramientas.txt" >nul 2>&1 && set "T_SYS=1"
)
if "!T_USR!!T_SYS!"=="00" (
    echo [OK] Cierre comprobado: Administrador, cuenta estandar y dominio. No hace falta abrir nada.
    goto :END
)
echo.
echo [STEP] Abriendo lo que hay que revisar a mano...
if "!T_USR!"=="1" (
    echo   - Usuarios y grupos locales  ^(lusrmgr.msc^)
    start "" lusrmgr.msc
)
if "!T_SYS!"=="1" (
    echo   - Propiedades del sistema / dominio  ^(sysdm.cpl^)
    start "" sysdm.cpl
)

:END
if defined PAUSE_AT_END (
    echo.
    echo Pulsa una tecla para cerrar esta ventana...
    pause >nul
)
if "!RC!"=="" set "RC=0"
set "FINAL_RC=!RC!"
endlocal & exit /b %FINAL_RC%

:DO_SHUTDOWN
REM %1 = r (reiniciar) / s (apagar), %2 = segundos, %3 = aviso. Comprueba que shutdown.exe lo acepta:
REM   1190 = ya habia uno programado (se cancela y se programa el nuestro); 1115 = ya se esta apagando (vale).
REM   Otro codigo: reintento con /f; si tampoco, tarea de SYSTEM a 2 min y nota en el Escritorio (LOGS_ERRORES).
REM Registro en ProgramData\NodeDeploy\reinicio.log (va en el zip de logs de la siguiente ejecucion). errorlevel 1 = fallo.
set "SD_MODE=%~1"
set "SD_T=%~2"
set "SD_MSG=%~3"
set "SD_LOG=%ProgramData%\NodeDeploy\reinicio.log"
if not exist "%ProgramData%\NodeDeploy" mkdir "%ProgramData%\NodeDeploy" >nul 2>&1
shutdown /!SD_MODE! /t !SD_T! /c "!SD_MSG!" >nul 2>&1
set "SD_RC=!ERRORLEVEL!"
if "!SD_RC!"=="1190" (
    shutdown /a >nul 2>&1
    shutdown /!SD_MODE! /t !SD_T! /c "!SD_MSG!" >nul 2>&1
    set "SD_RC=!ERRORLEVEL!"
)
if not "!SD_RC!"=="0" if not "!SD_RC!"=="1115" (
    shutdown /!SD_MODE! /f /t !SD_T! /c "!SD_MSG!" >nul 2>&1
    set "SD_RC=!ERRORLEVEL!"
)
>>"!SD_LOG!" echo !DATE! !TIME! Deploy.bat: shutdown /!SD_MODE! /t !SD_T! -^> codigo !SD_RC!
if "!SD_RC!"=="0" exit /b 0
if "!SD_RC!"=="1115" exit /b 0
set "SD_AT="
for /f "delims=" %%T in ('powershell -NoProfile -Command "$t=(Get-Date).AddMinutes(2); try { [void](Register-ScheduledTask -TaskName NodeDeployReinicio -Action (New-ScheduledTaskAction -Execute shutdown.exe -Argument '/!SD_MODE! /f /t 0') -Trigger (New-ScheduledTaskTrigger -Once -At $t) -User SYSTEM -RunLevel Highest -Force -ErrorAction Stop); $t.ToString('HH:mm') } catch { 'NO' }"') do set "SD_AT=%%T"
if defined SD_AT if not "!SD_AT!"=="NO" (
    echo [WARN] shutdown.exe devolvio !SD_RC!: plan B, tarea NodeDeployReinicio a las !SD_AT!
    >>"!SD_LOG!" echo !DATE! !TIME! Deploy.bat: plan B, tarea NodeDeployReinicio a las !SD_AT!
    call :EARLY_NOTE "shutdown.exe devolvio !SD_RC! al programar el reinicio; plan B: tarea NodeDeployReinicio a las !SD_AT!"
    exit /b 0
)
echo [ERROR] No se pudo programar el reinicio ^(shutdown !SD_RC!^). REINICIA A MANO.
>>"!SD_LOG!" echo !DATE! !TIME! Deploy.bat: SIN REINICIO ^(shutdown !SD_RC!, tarea tampoco^)
call :EARLY_NOTE "No se pudo programar el reinicio (shutdown !SD_RC!, tarea tampoco): reinicia a mano"
exit /b 1

:EARLY_NOTE
REM Fallo antes de que exista el log: bloque en el Escritorio, LOGS_ERRORES\<equipo>_ARRANQUE.txt (Deploy.ps1 escribe
REM en el mismo fichero los suyos). %1 = motivo; %2 = PARSE para anadir los errores de sintaxis de Deploy.ps1.
REM Escritorio real del usuario (puede estar en OneDrive), no siempre %USERPROFILE%\Desktop.
set "NOTE_MSG=%~1"
set "DESK="
for /f "skip=2 tokens=2,*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" /v Desktop 2^>nul') do set "DESK=%%B"
if defined DESK call set "DESK=!DESK!"
if not defined DESK set "DESK=%USERPROFILE%\Desktop"
set "NOTE_DIR=!DESK!\LOGS_ERRORES"
if not exist "!NOTE_DIR!" mkdir "!NOTE_DIR!" >nul 2>&1
set "NOTE=!NOTE_DIR!\%COMPUTERNAME%_ARRANQUE.txt"
>>"!NOTE!" (
    echo.
    echo ==== !DATE! !TIME! ^| Deploy.bat ^| exit !RC!
    echo Fallo     : !NOTE_MSG!
    echo Usuario   : !USERDOMAIN!\!USERNAME!
    echo Script    : !SELF!
    echo Parametros: !ALL_ARGS!
) 2>nul
if /I not "%~2"=="PARSE" goto :EARLY_NOTE_SHOW
set "ND_PS1=!DEPLOY_PS1!"
>>"!NOTE!" echo Errores de sintaxis de Deploy.ps1:
powershell -NoProfile -Command "$e = $null; [void][Management.Automation.Language.Parser]::ParseFile($env:ND_PS1, [ref]$null, [ref]$e); if ($e) { $e | ForEach-Object { '  linea {0}: {1}' -f $_.Extent.StartLineNumber, $_.Message } } else { '  ninguno: fallo de parametros o de PowerShell (el texto rojo de la consola)' }" >>"!NOTE!" 2>&1
:EARLY_NOTE_SHOW
if exist "!NOTE!" (
    echo [INFO] Anotado en: !NOTE!
) else (
    echo [WARN] No se pudo escribir en !NOTE_DIR!
)
exit /b 0
