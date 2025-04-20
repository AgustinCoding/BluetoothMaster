@echo off
chcp 65001 > nul
setlocal enabledelayedexpansion

:: Obtener ruta del script
set "ruta_script=%~dp0BTMaster.ps1"

:: Verificar existencia del archivo
if not exist "%ruta_script%" (
    echo Error: No se encuentra BTMaster.ps1 en la carpeta actual.
    pause
    exit
)

:: Comando para ejecutar con privilegios
set "cmd=powershell -ExecutionPolicy Bypass -NoExit -File "%ruta_script%""

:: Ejecutar como administrador usando PowerShell
echo Solicitando permisos de administrador...
PowerShell -Command "Start-Process -Verb RunAs -FilePath 'powershell.exe' -ArgumentList '-ExecutionPolicy Bypass -NoExit -Command \"%cmd%\"'"

exit