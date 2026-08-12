@echo off
setlocal
set "INSTALL_DIR=C:\ImpactLED\CloudPlayer"
set "LAUNCHER=%INSTALL_DIR%\run_player.bat"
set "LOG=%INSTALL_DIR%\process_guard.log"

:: Skip while an update is in progress -- updater.bat writes this flag before
:: killing the player so the guard does not race with the installer.
if exist "%INSTALL_DIR%\_updating.flag" exit /b 0

:: Player exe running? Nothing to do.
tasklist /fi "imagename eq ImpactLED-Cloud-Player.exe" 2>nul | find /i "ImpactLED-Cloud-Player.exe" >nul
if %errorlevel% equ 0 exit /b 0

:: Launcher cmd running? Player may be mid-restart -- nothing to do.
tasklist /fi "WINDOWTITLE eq ImpactLED Cloud+ Desktop Player" /fi "imagename eq cmd.exe" 2>nul | find /i "cmd.exe" >nul
if %errorlevel% equ 0 exit /b 0
tasklist /fi "WINDOWTITLE eq ImpactLED Cloud+ Desktop Player  [Samsung PrismView]" /fi "imagename eq cmd.exe" 2>nul | find /i "cmd.exe" >nul
if %errorlevel% equ 0 exit /b 0

:: Neither player nor launcher found -- restart the launcher and log it.
echo [%date% %time%] Process guard: player and launcher both gone -- restarting. >> "%LOG%"
if exist "%LAUNCHER%" (
    start "" "%LAUNCHER%"
) else (
    start "" "%INSTALL_DIR%\ImpactLED-Cloud-Player.exe"
)
endlocal
