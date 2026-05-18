@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1
title ImpactLED Cloud+ Desktop Player - Full Device Installer

:: ================================================================
::  Impact LED Signs  |  ImpactLED Cloud+ Desktop Player
::  Full Device Installer
::
::  Run this ONCE on a fresh device. It will automatically:
::    1. Install Python if not already present
::    2. Download the full software package from GitHub
::    3. Install everything to C:\ImpactLED\CloudPlayer\
::    4. Walk through device configuration (Terminal ID, Secret, etc.)
::    5. Register the player to launch automatically at logon
::
::  Technician usage (Admin Command Prompt):
::    curl -fsSL https://raw.githubusercontent.com/Sacton86/Cloud-Desktop-Edition/main/full-install.bat -o %TEMP%\full-install.bat && %TEMP%\full-install.bat
:: ================================================================

echo.
echo    ##############################################################
echo      ImpactLED Cloud+ Desktop Player
echo      Full Device Installer  --  Impact LED Signs
echo    ##############################################################
echo.
echo    This script will download and install everything needed.
echo    You will be prompted for credentials near the end.
echo.
echo    ----------------------------------------------------------------
echo.

:: --- Administrator check -----------------------------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo   [ERROR]  Must be run as Administrator.
    echo.
    echo            How to open an Admin Command Prompt:
    echo              1. Click Start
    echo              2. Type:  cmd
    echo              3. Right-click "Command Prompt"
    echo              4. Click "Run as administrator"
    echo              5. Paste the install command and press Enter.
    echo.
    pause
    exit /b 1
)

echo   Device      :  %COMPUTERNAME%
echo   User        :  %USERNAME%
echo   Install to  :  C:\ImpactLED\CloudPlayer
echo.

:: ================================================================
::  [1/4]  Python
:: ================================================================
echo   [*]  [1/4]  Checking for Python...
echo   ----------------------------------------------------------------
echo.

py -3.12 --version >nul 2>&1
if %errorlevel% equ 0 (
    echo   [OK]  Python 3.12 is already installed.
    goto python_ready
)

echo   .  Python 3.12 not found -- installing automatically via winget...
echo   .  This may take a minute. Please wait.
echo   .  (Other Python versions on this machine will not be affected.)
echo.

winget install -e --id Python.Python.3.12 --accept-source-agreements --accept-package-agreements --silent
if %errorlevel% neq 0 (
    echo.
    echo   [ERROR]  Automatic Python 3.12 install failed.
    echo           Please install it manually:
    echo             1. Go to https://www.python.org/downloads/releases/
    echo             2. Download Python 3.12 and run the installer
    echo             3. IMPORTANT: tick "Add Python to PATH"
    echo             4. Re-run this script when done.
    echo.
    pause
    exit /b 1
)

:: Reload PATH in this session so py launcher sees Python 3.12
for /f "usebackq delims=" %%p in (`powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User')"`) do set "PATH=%%p"

echo   [OK]  Python 3.12 installed successfully.

:python_ready
echo.

:: ================================================================
::  [2/4]  Download
:: ================================================================
echo   [*]  [2/4]  Downloading Software Package from GitHub...
echo   ----------------------------------------------------------------
echo.

set "INSTALL_DIR=C:\ImpactLED\CloudPlayer"
set "TMP_ZIP=%TEMP%\impactled-full-install.zip"
set "TMP_EXTRACT=%TEMP%\impactled-full-install-extract"
set "GITHUB_ZIP=https://github.com/Sacton86/Cloud-Desktop-Edition/archive/refs/heads/main.zip"

echo   .  Downloading from github.com/Sacton86/Cloud-Desktop-Edition
echo   .  Please wait...
echo.

curl -fsSL "%GITHUB_ZIP%" -o "%TMP_ZIP%"
if %errorlevel% neq 0 (
    echo   [ERROR]  Download failed.
    echo           Check that this device has an internet connection and try again.
    pause
    exit /b 1
)
echo   [OK]  Download complete.
echo.

:: ================================================================
::  [3/4]  Extract and copy files
:: ================================================================
echo   [*]  [3/4]  Installing Files to %INSTALL_DIR%...
echo   ----------------------------------------------------------------
echo.

if exist "%TMP_EXTRACT%" rmdir /s /q "%TMP_EXTRACT%"

powershell -NoProfile -Command "Expand-Archive -Path '%TMP_ZIP%' -DestinationPath '%TMP_EXTRACT%' -Force"
if %errorlevel% neq 0 (
    echo   [ERROR]  Could not extract the downloaded package.
    pause
    exit /b 1
)

:: GitHub zips always extract to one subfolder (e.g. Cloud-Desktop-Edition-main)
set "EXTRACTED_DIR="
for /d %%d in ("%TMP_EXTRACT%\*") do set "EXTRACTED_DIR=%%d"
if not defined EXTRACTED_DIR (
    echo   [ERROR]  Extracted folder not found -- the download may be corrupt.
    echo           Delete %TMP_ZIP% and run this script again.
    pause
    exit /b 1
)

if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
xcopy /e /i /y /q "%EXTRACTED_DIR%\*" "%INSTALL_DIR%\"
if %errorlevel% neq 0 (
    echo   [ERROR]  Could not copy files to %INSTALL_DIR%
    pause
    exit /b 1
)

del /q "%TMP_ZIP%" 2>nul
rmdir /s /q "%TMP_EXTRACT%" 2>nul

echo   [OK]  All files installed to %INSTALL_DIR%
echo.

:: ================================================================
::  [4/4]  Configure and register
:: ================================================================
echo    ==============================================================
echo      [4/4]  Device Configuration
echo    ==============================================================
echo.
echo    The next steps will ask for your Terminal ID, Secret, and
echo    display settings. Have these ready before continuing.
echo.
pause

cd /d "%INSTALL_DIR%"
call "%INSTALL_DIR%\install.bat"
