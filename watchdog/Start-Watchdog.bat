@echo off
title ImpactLED Player Watchdog
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Unblock-File -LiteralPath '%~dp0ImpactLED-Watchdog.exe' } catch {}"

if exist "%~dp0ImpactLED-Watchdog.exe" (
    start "" "%~dp0ImpactLED-Watchdog.exe"
    timeout /t 3 /nobreak >nul
    tasklist /fi "imagename eq ImpactLED-Watchdog.exe" | find /i "ImpactLED-Watchdog.exe" >nul
    if not errorlevel 1 (
        echo Watchdog EXE is running. Look next to the clock for the tray icon.
        echo Move the mouse to the BOTTOM of the screen to show the bar.
        timeout /t 4 >nul
        exit /b 0
    )
    echo EXE did not stay running. Starting PowerShell fallback...
    echo Check watchdog-startup.log in this folder.
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ImpactLED-Watchdog.ps1" -StartIfMissing
pause
