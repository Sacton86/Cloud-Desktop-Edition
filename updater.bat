@echo off
setlocal

set "INSTALL_DIR=C:\ImpactLED\CloudPlayer"
set "PLAYER_TASK=ImpactLED Cloud+ Desktop Player"
set "GUARD_TASK=ImpactLED Process Guard"
set "VERSION_FILE=%INSTALL_DIR%\version.txt"
set "CONFIG_FILE=%INSTALL_DIR%\player_config.json"
set "LAUNCHER=%INSTALL_DIR%\run_player.bat"

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
:: Signal the process guard to stand down while the install is running.
echo. > "%INSTALL_DIR%\_updating.flag"
schtasks /end /tn "%PLAYER_TASK%" >nul 2>&1
taskkill /f /im ImpactLED-Cloud-Player.exe >nul 2>&1
:: Also kill the cmd.exe launcher loop -- it holds run_player.bat open for
:: reading, which blocks the > redirect that rewrites it (both Samsung and
:: standard Windows launchers are now always regenerated during updates).
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

:: ---- Rewrite launcher if device_type is samsung ---------------------
set "DEVICE_TYPE=windows"
if exist "%CONFIG_FILE%" (
    powershell -NoProfile -Command "try { $j = ConvertFrom-Json (Get-Content '%CONFIG_FILE%' -Raw); if ($j.device_type) { [System.IO.File]::WriteAllText('%TEMP%\__impactled_dt.txt', $j.device_type) } } catch {}"
    if exist "%TEMP%\__impactled_dt.txt" (
        set /p DEVICE_TYPE=<"%TEMP%\__impactled_dt.txt"
        del /q "%TEMP%\__impactled_dt.txt" 2>nul
    )
)

if /i "%DEVICE_TYPE%"=="samsung" (
    (
        echo @echo off
        echo title ImpactLED Cloud+ Desktop Player  [Samsung PrismView]
        echo set "SM_EXE=C:\Program Files\Prismview\System Matrix\System Matrix.exe"
        echo.
        echo :: Startup delay -- display driver may not be ready immediately at logon
        echo timeout /t 20 /nobreak ^>nul
        echo.
        echo :: Ensure System Matrix is running before the player starts
        echo :check_sm
        echo tasklist /fi "imagename eq System Matrix.exe" 2^>nul ^| find /i "System Matrix.exe" ^>nul
        echo if %%errorlevel%% neq 0 ^(
        echo     echo   [System Matrix] Not running -- starting...
        echo     start "" "%%SM_EXE%%"
        echo     timeout /t 5 /nobreak ^>nul
        echo ^)
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
        echo if %%errorlevel%% neq 0 ^(
        echo     echo   [System Matrix] Crashed -- restarting System Matrix...
        echo     start "" "%%SM_EXE%%"
        echo     timeout /t 5 /nobreak ^>nul
        echo ^)
        echo goto loop
    ) > "%LAUNCHER%"
) else (
    :: Standard Windows -- always rewrite the launcher so the startup delay
    :: is present even on devices that were installed before this fix.
    :: Safe to write here: the cmd launcher was killed above for Samsung; for
    :: standard devices the old cmd was also killed (taskkill step above).
    (
        echo @echo off
        echo title ImpactLED Cloud+ Desktop Player
        echo :: Startup delay -- display driver may not be ready immediately at logon
        echo timeout /t 20 /nobreak ^>nul
        echo :loop
        echo cd /d "%INSTALL_DIR%"
        echo "%INSTALL_DIR%\ImpactLED-Cloud-Player.exe"
        echo echo.
        echo echo   [ImpactLED Cloud+ Desktop Player exited -- restarting in 5 seconds...]
        echo timeout /t 5 /nobreak ^>nul
        echo goto loop
    ) > "%LAUNCHER%"
)

:: Remove sentinel -- process guard may now restart the player if needed.
del /q "%INSTALL_DIR%\_updating.flag" 2>nul

echo.
echo  ============================================================
echo   Update complete -- now running %LATEST%
echo  ============================================================
echo.

:restart_player
echo  Restarting player...
echo.
schtasks /run /tn "%PLAYER_TASK%" >nul 2>&1
if %errorlevel% neq 0 (
    :: Scheduled task not found or failed -- launch directly via the launcher
    if exist "%LAUNCHER%" (
        start "" "%LAUNCHER%"
    ) else (
        start "" "%INSTALL_DIR%\ImpactLED-Cloud-Player.exe"
    )
)

:: schtasks /run returns 0 even when the task was accepted but didn't actually
:: execute.  Wait 15 s and verify the player process appeared.  This is a
:: diagnostic check only -- if the player didn't start, the tech is told to
:: run the launcher manually (automated fallback from SYSTEM session is not
:: reliable on modern Windows due to Session 0 isolation).
timeout /t 15 /nobreak >nul
tasklist /fi "imagename eq ImpactLED-Cloud-Player.exe" 2>nul | find /i "ImpactLED-Cloud-Player.exe" >nul
if %errorlevel% neq 0 (
    echo.
    echo  [WARN]  Player process not detected 15s after restart attempt.
    echo  [WARN]  If the sign stays blank, run manually:
    echo  [WARN]    %LAUNCHER%
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
