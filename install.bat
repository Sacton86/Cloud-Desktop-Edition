@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1
title ImpactLED Cloud+ Desktop Player - Installer

:: ================================================================
::  Impact LED Signs  |  ImpactLED Cloud+ Desktop Player  |  Windows Installer
::
::  Non-interactive (bulk / env-var) mode -- set before running:
::    VSN_TERMINAL_ID  VSN_TERMINAL_SECRET  VSN_CMS_SERVER
::    VSN_WIDTH        VSN_HEIGHT           VSN_FULLSCREEN
:: ================================================================

:: --- Banner ------------------------------------------------------
echo.
echo    ##############################################################
echo      ImpactLED Cloud+ Desktop Player  --  Impact LED Signs  --  Installer
echo    ##############################################################
echo.

:: --- Administrator check -----------------------------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo   [ERROR]  This installer must be run as Administrator.
    echo            Right-click install.bat and choose "Run as administrator".
    echo.
    pause
    exit /b 1
)

:: --- Locate install directory ------------------------------------
set "INSTALL_DIR=%~dp0"
if "%INSTALL_DIR:~-1%"=="\" set "INSTALL_DIR=%INSTALL_DIR:~0,-1%"
set "CONFIG_PATH=%INSTALL_DIR%\player_config.json"
set "DOWNLOADS_DIR=%INSTALL_DIR%\downloads"
set "LAUNCHER=%INSTALL_DIR%\run_player.bat"

echo   Install directory :  %INSTALL_DIR%
echo   Running as user   :  %USERNAME%
echo   ----------------------------------------------------------------
echo.

:: --- Python 3.12 check -------------------------------------------
py -3.12 --version >nul 2>&1
if %errorlevel% neq 0 (
    echo   [ERROR]  Python 3.12 not found.
    echo            The full-install.bat script installs it automatically.
    echo            Or install manually from https://www.python.org/downloads/releases/
    echo            and re-run this installer.
    echo.
    pause
    exit /b 1
)
for /f "delims=" %%v in ('py -3.12 --version 2^>^&1') do set "PY_VER=%%v"
echo   [OK]  Found %PY_VER%

py -3.12 -m pip --version >nul 2>&1
if %errorlevel% neq 0 (
    echo   [ERROR]  pip not found.  Run:  py -3.12 -m ensurepip --upgrade
    pause
    exit /b 1
)
echo   [OK]  pip ready
echo.

:: ================================================================
::  Configuration
:: ================================================================
echo   [*]  Device Configuration
echo   ----------------------------------------------------------------
echo.
echo   Enter your device and Cloud+ credentials.
echo   Press Enter to accept the value shown in [brackets].
echo.

:: -- Terminal ID --------------------------------------------------
if defined VSN_TERMINAL_ID (
    echo   Terminal ID           :  [provided via environment]
) else (
    set /p "VSN_TERMINAL_ID=  ? Terminal ID : "
)
if not defined VSN_TERMINAL_ID (
    echo   [ERROR]  Terminal ID is required.
    pause
    exit /b 1
)

:: -- Terminal Secret -----------------------------------------------
if defined VSN_TERMINAL_SECRET (
    echo   Terminal Secret       :  [provided via environment]
) else (
    set /p "VSN_TERMINAL_SECRET=  ? Terminal Secret : "
)
if not defined VSN_TERMINAL_SECRET (
    echo   [ERROR]  Terminal Secret is required.
    pause
    exit /b 1
)

:: -- Cloud+ server ------------------------------------------------
if defined VSN_CMS_SERVER (
    echo   Cloud+ server URL     :  [provided via environment]
) else (
    set /p "_tmp=  ? Cloud+ server URL  [https://access.impactledsigns.com/] : "
    if "!_tmp!"=="" (
        set "VSN_CMS_SERVER=https://access.impactledsigns.com/"
    ) else (
        set "VSN_CMS_SERVER=!_tmp!"
    )
)

echo.
echo   [*]  Display Settings
echo   ----------------------------------------------------------------
echo.

:: -- Display width ------------------------------------------------
if defined VSN_WIDTH (
    echo   Display width         :  [provided via environment]
) else (
    set /p "_tmp=  ? Display width  [1920] : "
    if "!_tmp!"=="" (set "VSN_WIDTH=1920") else (set "VSN_WIDTH=!_tmp!")
)

:: -- Display height -----------------------------------------------
if defined VSN_HEIGHT (
    echo   Display height        :  [provided via environment]
) else (
    set /p "_tmp=  ? Display height [1080] : "
    if "!_tmp!"=="" (set "VSN_HEIGHT=1080") else (set "VSN_HEIGHT=!_tmp!")
)

:: -- Fullscreen ---------------------------------------------------
if defined VSN_FULLSCREEN (
    echo   Fullscreen mode       :  [provided via environment]
) else (
    set /p "_tmp=  ? Fullscreen mode (true/false) [false] : "
    if "!_tmp!"=="" (set "VSN_FULLSCREEN=false") else (set "VSN_FULLSCREEN=!_tmp!")
)

set "FULLSCREEN_JSON=false"
if /i "!VSN_FULLSCREEN!"=="true"  set "FULLSCREEN_JSON=true"
if   "!VSN_FULLSCREEN!"=="1"      set "FULLSCREEN_JSON=true"

echo.
echo    ==============================================================
echo      Beginning installation...
echo    ==============================================================
echo.

:: ================================================================
::  [1/4]  Python requirements
:: ================================================================
echo   [*]  [1/4]  Python Requirements
echo   ----------------------------------------------------------------
echo.
echo   .  Installing packages from requirements.txt...
py -3.12 -m pip install -r "%INSTALL_DIR%\requirements.txt"
if %errorlevel% neq 0 (
    echo.
    echo   [ERROR]  pip install failed -- see output above.
    pause
    exit /b 1
)
echo   [OK]  Python packages installed.
echo.

:: ================================================================
::  [2/4]  Write player_config.json
:: ================================================================
echo   [*]  [2/4]  Player Configuration
echo   ----------------------------------------------------------------
echo.

python -c "
import json, os

fs   = os.environ.get('FULLSCREEN_JSON', 'false') == 'true'
cfg  = {
    'width':        int(os.environ.get('VSN_WIDTH',  '1920')),
    'height':       int(os.environ.get('VSN_HEIGHT', '1080')),
    'fullscreen':   fs,
    'fit_mode':     'native',
    'fps':          60,
    'bar_color':    '0xFF000000',
    'loop':         True,
    'show_hud':     False,
    'last_dir':     '',
    'brightness':   100,
    'timezone':     '',
    'locale_code':  '',
    'cms_enabled':  True,
    'cms_server':   os.environ.get('VSN_CMS_SERVER',      ''),
    'cms_username': os.environ.get('VSN_TERMINAL_ID',     ''),
    'cms_password': os.environ.get('VSN_TERMINAL_SECRET', ''),
    'cms_interval': 30,
    'cms_dl_dir':   '',
}
path = os.environ['CONFIG_PATH']
with open(path, 'w') as f:
    json.dump(cfg, f, indent=2)
print('   [OK]  Config written  ->  ' + path)
"
if %errorlevel% neq 0 (
    echo   [ERROR]  Failed to write player_config.json.
    pause
    exit /b 1
)

mkdir "%DOWNLOADS_DIR%" 2>nul
echo   [OK]  Downloads dir  ->  %DOWNLOADS_DIR%
echo.

:: ================================================================
::  [3/4]  Crash-restarting launcher script
:: ================================================================
echo   [*]  [3/4]  Launcher Script
echo   ----------------------------------------------------------------
echo.

(
    echo @echo off
    echo title ImpactLED Cloud+ Desktop Player
    echo :loop
    echo cd /d "%INSTALL_DIR%"
    echo py -3.12 player.py
    echo echo.
    echo echo   [ImpactLED Cloud+ Desktop Player exited -- restarting in 5 seconds...]
    echo timeout /t 5 /nobreak ^>nul
    echo goto loop
) > "%LAUNCHER%"
echo   [OK]  Launcher written  ->  %LAUNCHER%
echo.

:: ================================================================
::  [4/4]  Windows Task Scheduler  (autostart at logon)
:: ================================================================
echo   [*]  [4/4]  Startup Task (Task Scheduler)
echo   ----------------------------------------------------------------
echo.

set "TASK_NAME=ImpactLED Cloud+ Desktop Player"

:: Remove existing task so /create /f works cleanly
schtasks /delete /tn "%TASK_NAME%" /f >nul 2>&1

schtasks /create /tn "%TASK_NAME%" ^
    /tr "cmd /c \"%LAUNCHER%\"" ^
    /sc ONLOGON ^
    /ru "%USERNAME%" ^
    /f

if %errorlevel% neq 0 (
    echo   [WARN]  Could not register Task Scheduler entry.
    echo          The player will not autostart on login.
    echo          Run it manually at any time:
    echo            %LAUNCHER%
) else (
    echo   [OK]  Task registered : "%TASK_NAME%"
    echo         The player will start automatically at each logon.
)
echo.

:: ================================================================
::  Launch player now
:: ================================================================
echo   ==============================================================
echo     Launching player...
echo   ==============================================================
echo.
start "ImpactLED Cloud+ Desktop Player" cmd /c "%LAUNCHER%"
echo   [OK]  Player started in a new window.
echo.

:: ================================================================
::  Summary
:: ================================================================
echo   ==============================================================
echo     [OK]  Installation complete!
echo   ==============================================================
echo.
echo     Terminal ID    :  %VSN_TERMINAL_ID%
echo     Display        :  %VSN_WIDTH% x %VSN_HEIGHT%  (fullscreen: %FULLSCREEN_JSON%)
echo     Cloud+ server  :  %VSN_CMS_SERVER%
echo     Config file    :  %CONFIG_PATH%
echo     Launcher       :  %LAUNCHER%
echo.
echo     Useful commands:
echo       schtasks /query /tn "ImpactLED Cloud+ Desktop Player"      -- check task status
echo       schtasks /run   /tn "ImpactLED Cloud+ Desktop Player"      -- start player task
echo       schtasks /end   /tn "ImpactLED Cloud+ Desktop Player"      -- stop player task
echo       schtasks /delete /tn "ImpactLED Cloud+ Desktop Player" /f  -- remove autostart
echo.
echo   ==============================================================
echo               Impact LED Signs  .  impactledsigns.com
echo   ==============================================================
echo.
pause
endlocal
