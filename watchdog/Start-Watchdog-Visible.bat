@echo off
title ImpactLED Player Watchdog  (debug console)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ImpactLED-Watchdog.ps1" -StartIfMissing
pause
