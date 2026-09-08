@echo off
setlocal

set "INSTALL_DIR=C:\ImpactLED\CloudPlayer"
set "WATCHDOG_TASK=ImpactLED Player Watchdog Toolbar"
set "WATCHDOG_DIR=%INSTALL_DIR%\Watchdog"
set "WATCHDOG_INI=%WATCHDOG_DIR%\watchdog.ini"
set "VERSION_FILE=%INSTALL_DIR%\version.txt"
set "CONFIG_FILE=%INSTALL_DIR%\player_config.json"

:: Legacy names from the pre-watchdog two-task setup -- only used by the
:: one-time field migration below to detect and retire them.
set "LEGACY_PLAYER_TASK=ImpactLED Cloud+ Desktop Player"
set "LEGACY_GUARD_TASK=ImpactLED Process Guard"
set "LEGACY_LAUNCHER=%INSTALL_DIR%\run_player.bat"
set "LEGACY_GUARD_BAT=%INSTALL_DIR%\process_guard.bat"

:: Clean up any stale updating sentinel left by a previously interrupted run.
del /q "%INSTALL_DIR%\_updating.flag" 2>nul
set "GITHUB_API=https://api.github.com/repos/Sacton86/Cloud-Desktop-Edition/releases/latest"
set "DOWNLOAD_URL=https://github.com/Sacton86/Cloud-Desktop-Edition/releases/latest/download/ImpactLED-Cloud-Player.zip"
set "TMP_ZIP=%TEMP%\impactled-update.zip"
set "TMP_EXTRACT=%TEMP%\impactled-update-extract"

title ImpactLED Cloud+ Desktop Player  [Updater]
echo.
echo  ============================================================
echo   ImpactLED Cloud+ Desktop Player -- Updater
echo  ============================================================
echo.

:: ---- Read installed version -----------------------------------------
set "CURRENT=unknown"
if exist "%VERSION_FILE%" set /p CURRENT=<"%VERSION_FILE%"
echo  Installed version : %CURRENT%

:: ---- Fetch latest release tag from GitHub ---------------------------
echo  Checking GitHub for latest release...
curl -sf "%GITHUB_API%" -o "%TEMP%\__impactled_rel.json" 2>nul
if %errorlevel% neq 0 (
    echo.
    echo  [ERROR]  Could not reach GitHub. Check your internet connection.
    echo.
    pause
    exit /b 0
)

set "LATEST="
powershell -NoProfile -Command "try { $j = ConvertFrom-Json (Get-Content '%TEMP%\__impactled_rel.json' -Raw); [System.IO.File]::WriteAllText('%TEMP%\__impactled_tag.txt', $j.tag_name) } catch {}"
del /q "%TEMP%\__impactled_rel.json" 2>nul

if exist "%TEMP%\__impactled_tag.txt" (
    set /p LATEST=<"%TEMP%\__impactled_tag.txt"
    del /q "%TEMP%\__impactled_tag.txt" 2>nul
)

if not defined LATEST (
    echo.
    echo  [ERROR]  Could not read latest release tag from GitHub API response.
    echo.
    pause
    exit /b 0
)

echo  Latest release    : %LATEST%
echo.

:: ---- Compare versions -----------------------------------------------
if "%CURRENT%"=="%LATEST%" (
    echo  Already up to date. No update needed.
    echo.
    pause
    exit /b 0
)

title ImpactLED Cloud+ Desktop Player  [Updating %CURRENT% to %LATEST%]
echo  ============================================================
echo   Update available: %CURRENT% -- ^> %LATEST%
echo  ============================================================
echo.

:: ---- Download new release -------------------------------------------
echo  [1/4]  Downloading %LATEST%...
if exist "%TMP_ZIP%" del /q "%TMP_ZIP%"

powershell -NoProfile -Command ^
    "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $wc = New-Object System.Net.WebClient; $wc.DownloadFile('%DOWNLOAD_URL%', '%TMP_ZIP%'); exit 0 } catch { Write-Host ('  [ERROR] ' + $_); exit 1 }"

if %errorlevel% neq 0 (
    echo.
    echo  [ERROR]  Download failed. Check your connection and try again.
    echo.
    pause
    exit /b 1
)

:: Verify the download is a real ZIP and not an error page (must be >500 KB)
set "ZIP_SIZE=0"
for %%A in ("%TMP_ZIP%") do set "ZIP_SIZE=%%~zA"
if %ZIP_SIZE% LSS 500000 (
    echo.
    echo  [ERROR]  Downloaded file is too small (%ZIP_SIZE% bytes^) -- likely a failed redirect.
    echo           Delete %TMP_ZIP% and try again.
    echo.
    del /q "%TMP_ZIP%" 2>nul
    pause
    exit /b 1
)
echo  Download OK (%ZIP_SIZE% bytes^)
echo.

:: ---- Stop player ----------------------------------------------------
echo  [2/4]  Stopping player...
:: Signal that an install is running. The watchdog is killed outright below
:: (simplest way to guarantee it can't race the file replacement or try to
:: relaunch the player mid-update) -- this flag is now just a diagnostic
:: marker, kept for backward compat with anything that still checks it.
echo. > "%INSTALL_DIR%\_updating.flag"
:: Stop the watchdog first so it doesn't relaunch the player out from under us.
schtasks /end /tn "%WATCHDOG_TASK%" >nul 2>&1
taskkill /f /im ImpactLED-Watchdog.exe >nul 2>&1
taskkill /f /im ImpactLED-Cloud-Player.exe >nul 2>&1
:: Also kill any leftover legacy cmd.exe launcher loop from a pre-watchdog
:: install -- it holds run_player.bat open for reading, which would block
:: the migration cleanup below from deleting it.
schtasks /end /tn "%LEGACY_PLAYER_TASK%" >nul 2>&1
taskkill /f /fi "WINDOWTITLE eq ImpactLED Cloud+ Desktop Player" /im cmd.exe >nul 2>&1
taskkill /f /fi "WINDOWTITLE eq ImpactLED Cloud+ Desktop Player  [Samsung PrismView]" /im cmd.exe >nul 2>&1

:: Wait until the process is fully gone -- taskkill returns before Windows
:: releases file handles, so a fixed 3s sleep was not always enough.
:wait_exit
tasklist /fi "imagename eq ImpactLED-Cloud-Player.exe" 2>nul | find /i "ImpactLED-Cloud-Player.exe" >nul
if %errorlevel% equ 0 (
    timeout /t 2 /nobreak >nul
    goto wait_exit
)
:: Extra 2s after process list clears to let Windows release file handles
timeout /t 2 /nobreak >nul

:: ---- Extract --------------------------------------------------------
echo  [3/4]  Extracting update...
if exist "%TMP_EXTRACT%" rmdir /s /q "%TMP_EXTRACT%"
powershell -NoProfile -Command ^
    "try { Expand-Archive -Path '%TMP_ZIP%' -DestinationPath '%TMP_EXTRACT%' -Force } catch { Write-Host ('  [ERROR] ' + $_) }"

:: Verify the exe was actually extracted -- don't rely on errorlevel alone
if not exist "%TMP_EXTRACT%\ImpactLED-Cloud-Player.exe" (
    echo.
    echo  [ERROR]  Extraction failed -- exe not found in extracted files.
    echo           The downloaded ZIP may be corrupt. Restarting with current version.
    del /q "%TMP_ZIP%" 2>nul
    if exist "%TMP_EXTRACT%" rmdir /s /q "%TMP_EXTRACT%" 2>nul
    goto restart_player
)

:: ---- Install --------------------------------------------------------
:: robocopy /XF excludes updater.bat by filename so it is never overwritten
:: while this script is still running.  CMD reads batch files by byte offset --
:: overwriting the file mid-execution shifts offsets and causes random
:: re-execution of earlier sections.
:: The new updater.bat is staged as updater.bat.new and swapped in AFTER
:: this script exits (the swap is launched just before exit /b 0).
echo  [4/4]  Installing %LATEST%...
robocopy "%TMP_EXTRACT%" "%INSTALL_DIR%" /E /IS /IT /XF updater.bat /NFL /NDL /NJH /NJS /NP >nul 2>&1

:: Stage new updater for post-exit swap
if exist "%TMP_EXTRACT%\updater.bat" (
    copy /y "%TMP_EXTRACT%\updater.bat" "%INSTALL_DIR%\updater.bat.new" >nul 2>&1
)

del /q "%TMP_ZIP%" 2>nul
rmdir /s /q "%TMP_EXTRACT%" 2>nul

:: ---- Record new version ---------------------------------------------
powershell -NoProfile -Command "[System.IO.File]::WriteAllText('%INSTALL_DIR%\version.txt', '%LATEST%')"

:: ---- Determine device type (drives WatchSystemMatrix in watchdog.ini) ---
set "DEVICE_TYPE=windows"
if exist "%CONFIG_FILE%" (
    powershell -NoProfile -Command "try { $j = ConvertFrom-Json (Get-Content '%CONFIG_FILE%' -Raw); if ($j.device_type) { [System.IO.File]::WriteAllText('%TEMP%\__impactled_dt.txt', $j.device_type) } } catch {}"
    if exist "%TEMP%\__impactled_dt.txt" (
        set /p DEVICE_TYPE=<"%TEMP%\__impactled_dt.txt"
        del /q "%TEMP%\__impactled_dt.txt" 2>nul
    )
)

:: ---- Watchdog migration -----------------------------------------------
:: Runs on every update, idempotent. Brings devices still on the old
:: run_player.bat + process_guard.bat setup onto the watchdog, and keeps an
:: already-migrated device's watchdog.ini/task in sync with this device.
:: Written with goto/labels rather than nested if-blocks on purpose: this
:: script does not use setlocal EnableDelayedExpansion, so a variable set
:: and then read with %...% inside the *same* parenthesized if-block would
:: still see its pre-block value. Every set below is its own top-level
:: statement so plain %VAR% expansion in a later statement is safe.
if not exist "%WATCHDOG_DIR%\ImpactLED-Watchdog.exe" goto watchdog_missing

echo  Migrating to watchdog toolbar...

:: Figure out which user the AtLogOn trigger should target: prefer the
:: already-registered watchdog task (steady state), then the legacy player
:: task (first migration on this device), then whoever is currently logged
:: into the console (last resort -- this script runs as SYSTEM, so
:: $env:USERNAME here is not the kiosk user).
powershell -NoProfile -Command ^
    "$u = $null; try { $t = Get-ScheduledTask -TaskName '%WATCHDOG_TASK%' -ErrorAction Stop; $u = $t.Principal.UserId } catch {}; if (-not $u) { try { $t = Get-ScheduledTask -TaskName '%LEGACY_PLAYER_TASK%' -ErrorAction Stop; $u = $t.Principal.UserId } catch {} }; if (-not $u) { try { $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop; if ($cs.UserName) { $u = $cs.UserName } } catch {} }; if ($u) { [System.IO.File]::WriteAllText('%TEMP%\__impactled_wduser.txt', $u) }"
set "WD_USER="
if exist "%TEMP%\__impactled_wduser.txt" set /p WD_USER=<"%TEMP%\__impactled_wduser.txt"
if exist "%TEMP%\__impactled_wduser.txt" del /q "%TEMP%\__impactled_wduser.txt" 2>nul

:: Retire the old two-task setup.
schtasks /delete /tn "%LEGACY_PLAYER_TASK%" /f >nul 2>&1
schtasks /delete /tn "%LEGACY_GUARD_TASK%" /f >nul 2>&1
del /q "%LEGACY_LAUNCHER%" 2>nul
del /q "%LEGACY_GUARD_BAT%" 2>nul
del /q "%INSTALL_DIR%\process_guard.log" 2>nul

:: Point watchdog.ini at this device's player exe and Samsung setting.
set "WD_SM=False"
if /i "%DEVICE_TYPE%"=="samsung" set "WD_SM=True"
powershell -NoProfile -Command "$ini = Get-Content -LiteralPath '%WATCHDOG_INI%' -Raw; $ini = $ini -replace '(?m)^PlayerPath=.*$', 'PlayerPath=%INSTALL_DIR%\ImpactLED-Cloud-Player.exe'; $ini = $ini -replace '(?m)^WatchSystemMatrix=.*$', 'WatchSystemMatrix=%WD_SM%'; [System.IO.File]::WriteAllText('%WATCHDOG_INI%', $ini)"

if not defined WD_USER goto watchdog_user_unknown
powershell -NoProfile -ExecutionPolicy Bypass -File "%WATCHDOG_DIR%\Install-Watchdog-Autostart.ps1" -TargetUser "%WD_USER%"
echo  [OK]  Watchdog registered for user "%WD_USER%".
goto watchdog_migration_done

:watchdog_user_unknown
echo  [WARN]  Could not determine which user to register the watchdog logon
echo  [WARN]  task for -- no console user found and no prior task to read.
echo  [WARN]  watchdog.ini was updated; the task itself was not touched.
echo  [WARN]  Run Watchdog\Install-Watchdog-Autostart.bat once as the kiosk
echo  [WARN]  user to finish setup.
goto watchdog_migration_done

:watchdog_missing
echo  [WARN]  Watchdog\ImpactLED-Watchdog.exe not found -- this release package
echo  [WARN]  is missing the watchdog. Skipping migration; player will still be
echo  [WARN]  restarted below via whatever autostart task already exists.

:watchdog_migration_done

:: Remove sentinel now that the watchdog (or the legacy launcher, if the
:: watchdog wasn't found above) is clear to restart the player.
del /q "%INSTALL_DIR%\_updating.flag" 2>nul

echo.
echo  ============================================================
echo   Update complete -- now running %LATEST%
echo  ============================================================
echo.

:restart_player
echo  Restarting player via watchdog...
echo.
schtasks /run /tn "%WATCHDOG_TASK%" >nul 2>&1
if %errorlevel% neq 0 (
    :: Scheduled task not found or failed -- launch the exe directly.
    :: (Only works if this branch happens to run in an interactive session;
    :: from the SYSTEM-context updater task, Session 0 isolation means the
    :: 15s check below is the real signal, same caveat as before.)
    if exist "%WATCHDOG_DIR%\ImpactLED-Watchdog.exe" (
        start "" "%WATCHDOG_DIR%\ImpactLED-Watchdog.exe"
    ) else (
        start "" "%INSTALL_DIR%\ImpactLED-Cloud-Player.exe"
    )
)

:: schtasks /run returns 0 even when the task was accepted but didn't actually
:: execute.  Wait 15 s and verify the player process appeared.  This is a
:: diagnostic check only -- if the player didn't start, the tech is told to
:: run the watchdog manually (automated fallback from SYSTEM session is not
:: reliable on modern Windows due to Session 0 isolation).
timeout /t 15 /nobreak >nul
tasklist /fi "imagename eq ImpactLED-Cloud-Player.exe" 2>nul | find /i "ImpactLED-Cloud-Player.exe" >nul
if %errorlevel% neq 0 (
    echo.
    echo  [WARN]  Player process not detected 15s after restart attempt.
    echo  [WARN]  If the sign stays blank, run manually:
    echo  [WARN]    %WATCHDOG_DIR%\Start-Watchdog.bat
    echo.
)

pause

:: Swap in new updater.bat now that the script is about to exit.
:: Launching this after pause (not before) ensures CMD has finished reading
:: this file before it is replaced -- the 2-second delay is just insurance.
if exist "%INSTALL_DIR%\updater.bat.new" (
    start /b cmd /c "timeout /t 2 /nobreak >nul && move /y ""%INSTALL_DIR%\updater.bat.new"" ""%INSTALL_DIR%\updater.bat"" >nul 2>&1"
)
exit /b 0
