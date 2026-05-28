@echo off
REM ============================================================
REM   NodeDeploy 3_Deploy_REAL - DESPLIEGUE PRODUCTIVO DESATENDIDO
REM   *** SOLO EJECUTAR DESPUES DEL SNAPSHOT ***
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
echo  ===========================================================
echo                NodeDeploy v3.3 - DEPLOY REAL
echo  ===========================================================
echo.
echo  Engine : %ENGINE%
echo  Source : %SOURCE%
echo  State  : %STATE%
echo.
echo  Apps a instalar : 15 (~15-25 min total)
echo  Pre-cache       : OFF (source es local)
echo  Office bg       : ON  (descarga en paralelo)
echo  Finalize        : SKIP (sin sysdm.cpl / lusrmgr.msc)
echo  MaxRetries      : 2
echo.
echo  HAS REALIZADO EL SNAPSHOT DE LA VM?
echo  Esta accion instalara 15 apps y modificara el sistema.
echo.
echo  Pulsa CTRL+C para ABORTAR, o cualquier tecla para CONTINUAR.
pause

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ENGINE%" -Source "%SOURCE%" -StatePath "%STATE%" -NoPreCache -SkipFinalize -MaxRetries 2
set RC=%ERRORLEVEL%

echo.
echo  ===========================================================
echo    NodeDeploy finalizado (exit=%RC%)
echo  ===========================================================
echo.
echo  0 = OK total
echo  1 = OK con fallos parciales (revisa reports)
echo 99 = exception no controlada
echo.
echo  Reports: %STATE%\reports\INDEX.md
echo  Logs   : %STATE%\logs
echo.
echo  Siguiente paso recomendado: 5_PostValidate.cmd
echo.
pause
exit /b %RC%
