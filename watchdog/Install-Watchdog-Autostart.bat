@echo off
title Install ImpactLED Watchdog Autostart
cd /d "%~dp0"
echo Installing logon task...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Watchdog-Autostart.ps1"
if errorlevel 1 (
    echo.
    echo PowerShell returned an error.
    echo Open autostart-install.log in this folder.
    pause
)
