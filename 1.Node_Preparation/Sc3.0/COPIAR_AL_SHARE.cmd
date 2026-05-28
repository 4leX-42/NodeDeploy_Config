@echo off
REM ============================================================
REM   Sync C:\testeo2.0\Sc3.0\ -> \\192.168.2.8\utilidades\1.Node_Preparation\Sc3.0\
REM   Ejecutar desde maquina admin con conectividad al share.
REM ============================================================

set "LOCAL=%~dp0"
set "REMOTE=\\192.168.2.8\utilidades\1.Node_Preparation\Sc3.0"

echo Source: %LOCAL%
echo Target: %REMOTE%
echo.

if not exist "%REMOTE%" (
    echo Creando carpeta destino...
    mkdir "%REMOTE%" 2>nul
    if errorlevel 1 (
        echo [ERROR] No se puede crear destino. Verifica permisos.
        pause
        exit /b 2
    )
)

robocopy "%LOCAL%" "%REMOTE%" *.ps1 *.cmd *.xml *.lnk *.md /XF COPIAR_AL_SHARE.cmd /R:2 /W:5 /NP

echo.
echo Tras esto, opcional: distribuir el shortcut al escritorio publico
echo de la imagen base mediante:
echo   copy "%REMOTE%\Node_Preparation.lnk" "C:\Users\Public\Desktop\"
echo.
pause
