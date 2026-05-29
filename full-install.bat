@echo off
setlocal EnableDelayedExpansion
title ImpactLED Cloud+ Desktop Player - Full Device Installer

:: ================================================================
::  Impact LED Signs  |  ImpactLED Cloud+ Desktop Player
::  Full Device Installer
::
::  Run this ONCE on a fresh device. No Python required.
::  It will automatically:
::    1. Download the latest release from GitHub
::    2. Install to C:\ImpactLED\CloudPlayer\
::    3. Walk through device configuration (Terminal ID, Secret, etc.)
::    4. Register the player to launch automatically at logon
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
echo    No Python or software installation required.
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

set "INSTALL_DIR=C:\ImpactLED\CloudPlayer"
set "TMP_ZIP=%TEMP%\impactled-release.zip"
set "TMP_EXTRACT=%TEMP%\impactled-release-extract"
set "CONFIG_PATH=%INSTALL_DIR%\player_config.json"
set "LAUNCHER=%INSTALL_DIR%\run_player.bat"
set "TASK_NAME=ImpactLED Cloud+ Desktop Player"
set "DOWNLOAD_URL=https://github.com/Sacton86/Cloud-Desktop-Edition/releases/latest/download/ImpactLED-Cloud-Player.zip"
set "LAUNCHER_ONLY=0"

:: ================================================================
::  Existing install detection
:: ================================================================
if exist "%CONFIG_PATH%" (
    echo   [!]  Existing installation detected at %INSTALL_DIR%
    echo.
    echo   What would you like to do?
    echo.
    echo       1)  Update launcher / device type only
    echo           (keeps your existing credentials and config — use this
    echo            to add Samsung PrismView support to an existing device)
    echo.
    echo       2)  Full reinstall
    echo           (re-downloads the player and overwrites all settings)
    echo.
    echo       3)  Cancel
    echo.
    :existing_prompt
    set /p "_exist_choice=  ? Choice [1] : "
    if "!_exist_choice!"=="" set "_exist_choice=1"
    if "!_exist_choice!"=="1" (
        set "LAUNCHER_ONLY=1"
        echo.
        echo   [OK]  Launcher-only update selected -- credentials will not be changed.
        echo.
        goto :skip_download
    )
    if "!_exist_choice!"=="2" (
        echo.
        echo   [OK]  Full reinstall selected.
        echo.
        goto :do_download
    )
    if "!_exist_choice!"=="3" (
        echo.
        echo   Cancelled.
        pause
        exit /b 0
    )
    echo   [ERROR]  Please enter 1, 2, or 3.
    goto :existing_prompt
)

:: ================================================================
::  [1/5]  Download latest release from GitHub
:: ================================================================
:do_download
echo   [*]  [1/5]  Downloading Latest Release from GitHub...
echo   ----------------------------------------------------------------
echo.
echo   .  Downloading... please wait.
echo.

curl -fsSL "%DOWNLOAD_URL%" -o "%TMP_ZIP%"
if %errorlevel% neq 0 (
    echo   [ERROR]  Download failed. Check your internet connection and try again.
    pause
    exit /b 1
)
echo   [OK]  Download complete.
echo.

:: ================================================================
::  [2/5]  Extract and install files
:: ================================================================
echo   [*]  [2/5]  Installing to %INSTALL_DIR%...
echo   ----------------------------------------------------------------
echo.

if exist "%TMP_EXTRACT%" rmdir /s /q "%TMP_EXTRACT%"

powershell -NoProfile -Command "Expand-Archive -Path '%TMP_ZIP%' -DestinationPath '%TMP_EXTRACT%' -Force"
if %errorlevel% neq 0 (
    echo   [ERROR]  Could not extract the downloaded package.
    pause
    exit /b 1
)

if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
xcopy /e /i /y /q "%TMP_EXTRACT%\*" "%INSTALL_DIR%\"
if %errorlevel% neq 0 (
    echo   [ERROR]  Could not copy files to %INSTALL_DIR%
    pause
    exit /b 1
)

del /q "%TMP_ZIP%" 2>nul
rmdir /s /q "%TMP_EXTRACT%" 2>nul

:: Record installed version from GitHub API
set "GITHUB_API=https://api.github.com/repos/Sacton86/Cloud-Desktop-Edition/releases/latest"
curl -sf "%GITHUB_API%" -o "%TEMP%\__impactled_rel.json" 2>nul
powershell -NoProfile -Command "try { $j = ConvertFrom-Json (Get-Content '%TEMP%\__impactled_rel.json' -Raw); [System.IO.File]::WriteAllText('%INSTALL_DIR%\version.txt', $j.tag_name) } catch {}"
del /q "%TEMP%\__impactled_rel.json" 2>nul

if not exist "%INSTALL_DIR%\ImpactLED-Cloud-Player.exe" (
    echo   [ERROR]  ImpactLED-Cloud-Player.exe not found after extraction.
    echo           The release package may be corrupt. Please try again.
    pause
    exit /b 1
)

echo   [OK]  Files installed to %INSTALL_DIR%
echo.

:skip_download

:: ================================================================
::  [3/5]  Device Type
:: ================================================================
echo   [*]  [3/5]  Device Type
echo   ----------------------------------------------------------------
echo.
echo   Select the type of device being installed:
echo.
echo       1)  Windows 10/11       (standard PC or mini-PC)
echo       2)  Samsung PrismView   (Prismview hardware with System Matrix)
echo.

set "VSN_DEVICE_TYPE_NUM="
if defined VSN_DEVICE_TYPE (
    echo   Device type : [provided via environment: %VSN_DEVICE_TYPE%]
    goto :device_type_set
)

:device_type_prompt
set /p "VSN_DEVICE_TYPE_NUM=  ? Device type [1] : "
if "!VSN_DEVICE_TYPE_NUM!"=="" set "VSN_DEVICE_TYPE_NUM=1"
if "!VSN_DEVICE_TYPE_NUM!"=="1" (
    set "VSN_DEVICE_TYPE=windows"
    goto :device_type_set
)
if "!VSN_DEVICE_TYPE_NUM!"=="2" (
    set "VSN_DEVICE_TYPE=samsung"
    goto :device_type_set
)
echo   [ERROR]  Please enter 1 or 2.
goto :device_type_prompt

:device_type_set
echo   [OK]  Device type : %VSN_DEVICE_TYPE%
echo.

:: Skip credentials and config write when updating launcher only
if "%LAUNCHER_ONLY%"=="1" goto :write_launcher

:: ================================================================
::  [4/5]  Device Configuration
:: ================================================================
echo   [*]  [4/5]  Device Configuration
echo   ----------------------------------------------------------------
echo.
echo   Enter your Terminal ID, Secret, and display settings.
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

:: -- Terminal Secret ----------------------------------------------
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
    set /p "_tmp=  ? Fullscreen mode (true/false) [true] : "
    if "!_tmp!"=="" (set "VSN_FULLSCREEN=true") else (set "VSN_FULLSCREEN=!_tmp!")
)

echo.
echo    ==============================================================
echo      Beginning installation...
echo    ==============================================================
echo.

:: ================================================================
::  Write player_config.json via PowerShell (no Python needed)
:: ================================================================
echo   .  Writing player_config.json...

powershell -NoProfile -Command "$fs = ($env:VSN_FULLSCREEN -eq 'true'); $cfg = [ordered]@{ width = [int]$env:VSN_WIDTH; height = [int]$env:VSN_HEIGHT; fullscreen = $fs; fit_mode = 'native'; fps = 60; bar_color = '0xFF000000'; loop = $true; show_hud = $false; show_fps = $false; last_dir = ''; brightness = 100; timezone = ''; locale_code = ''; cms_enabled = $true; cms_server = $env:VSN_CMS_SERVER; cms_username = $env:VSN_TERMINAL_ID; cms_password = $env:VSN_TERMINAL_SECRET; cms_interval = 30; cms_dl_dir = ''; device_type = $env:VSN_DEVICE_TYPE }; $json = ConvertTo-Json $cfg; [System.IO.File]::WriteAllText($env:CONFIG_PATH, $json)"

if %errorlevel% neq 0 (
    echo   [ERROR]  Failed to write player_config.json.
    pause
    exit /b 1
)
echo   [OK]  Config written  -^>  %CONFIG_PATH%

:: Create downloads folder
if not exist "%INSTALL_DIR%\downloads" mkdir "%INSTALL_DIR%\downloads"
echo   [OK]  Downloads dir  -^>  %INSTALL_DIR%\downloads
echo.

:: ================================================================
::  [5/5]  Launcher + Task Scheduler
:: ================================================================
:write_launcher
:: In launcher-only mode: patch device_type in the existing config JSON
if "%LAUNCHER_ONLY%"=="1" (
    powershell -NoProfile -Command "try { $f = '%CONFIG_PATH%'; $j = ConvertFrom-Json (Get-Content $f -Raw); $j | Add-Member -Force -NotePropertyName 'device_type' -NotePropertyValue '%VSN_DEVICE_TYPE%'; [System.IO.File]::WriteAllText($f, (ConvertTo-Json $j)) } catch { Write-Host 'Config patch failed: ' $_ }"
    echo   [OK]  device_type updated in existing config  -^>  %VSN_DEVICE_TYPE%
    echo.
)

echo   [*]  [5/5]  Startup Task (Task Scheduler)
echo   ----------------------------------------------------------------
echo.

:: Write launcher — Samsung gets System Matrix watchdog, standard gets simple restart loop
if /i "%VSN_DEVICE_TYPE%"=="samsung" (
    echo   .  Writing Samsung launcher with System Matrix watchdog...
    (
        echo @echo off
        echo title ImpactLED Cloud+ Desktop Player  [Samsung PrismView]
        echo set "SM_EXE=C:\Program Files\Prismview\System Matrix\System Matrix.exe"
        echo.
        echo :: Ensure System Matrix is running before the player starts
        echo :check_sm
        echo tasklist /fi "imagename eq System Matrix.exe" 2^>nul ^| find /i "System Matrix.exe" ^>nul
        echo if %%errorlevel%% neq 0 (
        echo     echo   [System Matrix] Not running -- starting...
        echo     start "" "%%SM_EXE%%"
        echo     timeout /t 5 /nobreak ^>nul
        echo )
        echo.
        echo :loop
        echo cd /d "%INSTALL_DIR%"
        echo "%INSTALL_DIR%\ImpactLED-Cloud-Player.exe"
        echo echo.
        echo echo   [ImpactLED Cloud+ Desktop Player exited -- restarting in 5 seconds...]
        echo timeout /t 5 /nobreak ^>nul
        echo.
        echo :: Re-check System Matrix on every restart
        echo tasklist /fi "imagename eq System Matrix.exe" 2^>nul ^| find /i "System Matrix.exe" ^>nul
        echo if %%errorlevel%% neq 0 (
        echo     echo   [System Matrix] Crashed -- restarting System Matrix...
        echo     start "" "%%SM_EXE%%"
        echo     timeout /t 5 /nobreak ^>nul
        echo )
        echo goto loop
    ) > "%LAUNCHER%"
) else (
    echo   .  Writing standard launcher...
    (
        echo @echo off
        echo title ImpactLED Cloud+ Desktop Player
        echo :loop
        echo cd /d "%INSTALL_DIR%"
        echo "%INSTALL_DIR%\ImpactLED-Cloud-Player.exe"
        echo echo.
        echo echo   [ImpactLED Cloud+ Desktop Player exited -- restarting in 5 seconds...]
        echo timeout /t 5 /nobreak ^>nul
        echo goto loop
    ) > "%LAUNCHER%"
)
echo   [OK]  Launcher written  -^>  %LAUNCHER%

:: Register with Task Scheduler
schtasks /delete /tn "%TASK_NAME%" /f >nul 2>&1
schtasks /create /tn "%TASK_NAME%" ^
    /tr "cmd /c \"%LAUNCHER%\"" ^
    /sc ONLOGON ^
    /ru "%USERNAME%" ^
    /f

if %errorlevel% neq 0 (
    echo   [WARN]  Could not register startup task.
    echo          Run the player manually:  %LAUNCHER%
) else (
    echo   [OK]  Startup task registered -- player will launch at every logon.
)
echo.

:: Register auto-updater task (runs as SYSTEM, 5 min after each boot)
set "UPDATER_TASK=ImpactLED Cloud+ Updater"
schtasks /delete /tn "%UPDATER_TASK%" /f >nul 2>&1
schtasks /create /tn "%UPDATER_TASK%" ^
    /tr "cmd /c \"%INSTALL_DIR%\updater.bat\"" ^
    /sc ONSTART ^
    /delay 0005:00 ^
    /ru SYSTEM ^
    /f
if %errorlevel% neq 0 (
    echo   [WARN]  Could not register updater task.
) else (
    echo   [OK]  Auto-updater registered -- checks for updates 5 min after each boot.
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
if "%LAUNCHER_ONLY%"=="1" (
    echo     [OK]  Launcher update complete!
) else (
    echo     [OK]  Installation complete!
)
echo   ==============================================================
echo.
echo     Device type    :  %VSN_DEVICE_TYPE%
if "%LAUNCHER_ONLY%"=="0" (
    echo     Terminal ID    :  %VSN_TERMINAL_ID%
    echo     Display        :  %VSN_WIDTH% x %VSN_HEIGHT%  (fullscreen: %VSN_FULLSCREEN%)
    echo     Cloud+ server  :  %VSN_CMS_SERVER%
)
echo     Install dir    :  %INSTALL_DIR%
echo     Config file    :  %CONFIG_PATH%
echo.
echo     Useful commands:
echo       schtasks /query /tn "ImpactLED Cloud+ Desktop Player"      -- check status
echo       schtasks /run   /tn "ImpactLED Cloud+ Desktop Player"      -- start now
echo       schtasks /end   /tn "ImpactLED Cloud+ Desktop Player"      -- stop
echo       schtasks /delete /tn "ImpactLED Cloud+ Desktop Player" /f  -- remove autostart
echo.
echo   ==============================================================
echo               Impact LED Signs  .  impactledsigns.com
echo   ==============================================================
echo.
pause
endlocal
