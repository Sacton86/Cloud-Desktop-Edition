@echo off
setlocal

set "INSTALL_DIR=C:\ImpactLED\CloudPlayer"
set "PLAYER_TASK=ImpactLED Cloud+ Desktop Player"
set "VERSION_FILE=%INSTALL_DIR%\version.txt"
set "CONFIG_FILE=%INSTALL_DIR%\player_config.json"
set "LAUNCHER=%INSTALL_DIR%\run_player.bat"
set "GITHUB_API=https://api.github.com/repos/Sacton86/Cloud-Desktop-Edition/releases/latest"
set "DOWNLOAD_URL=https://github.com/Sacton86/Cloud-Desktop-Edition/releases/latest/download/ImpactLED-Cloud-Player.zip"
set "TMP_ZIP=%TEMP%\impactled-update.zip"
set "TMP_EXTRACT=%TEMP%\impactled-update-extract"

:: ── Read installed version ────────────────────────────────────────
set "CURRENT=unknown"
if exist "%VERSION_FILE%" set /p CURRENT=<"%VERSION_FILE%"

:: ── Fetch latest release tag from GitHub ─────────────────────────
curl -sf "%GITHUB_API%" -o "%TEMP%\__impactled_rel.json" 2>nul
if %errorlevel% neq 0 exit /b 0

set "LATEST="
powershell -NoProfile -Command "try { $j = ConvertFrom-Json (Get-Content '%TEMP%\__impactled_rel.json' -Raw); [System.IO.File]::WriteAllText('%TEMP%\__impactled_tag.txt', $j.tag_name) } catch {}"
del /q "%TEMP%\__impactled_rel.json" 2>nul

if exist "%TEMP%\__impactled_tag.txt" (
    set /p LATEST=<"%TEMP%\__impactled_tag.txt"
    del /q "%TEMP%\__impactled_tag.txt" 2>nul
)

if not defined LATEST exit /b 0

:: ── Compare versions ─────────────────────────────────────────────
if "%CURRENT%"=="%LATEST%" exit /b 0

title ImpactLED Cloud+ Desktop Player  [Updating %CURRENT% ^> %LATEST%]
echo.
echo  ============================================================
echo   ImpactLED Cloud+ Desktop Player — Auto-Update
echo   Installed : %CURRENT%
echo   Available : %LATEST%
echo  ============================================================
echo.

:: ── Download new release ─────────────────────────────────────────
echo  [1/4]  Downloading %LATEST%...
curl -fL --progress-bar "%DOWNLOAD_URL%" -o "%TMP_ZIP%"
if %errorlevel% neq 0 (
    echo.
    echo  [ERROR]  Download failed. Player will continue with current version.
    exit /b 1
)
echo.

:: ── Stop player ──────────────────────────────────────────────────
echo  [2/4]  Stopping player...
schtasks /end /tn "%PLAYER_TASK%" >nul 2>&1
timeout /t 5 /nobreak >nul

:: ── Extract ──────────────────────────────────────────────────────
echo  [3/4]  Extracting update...
if exist "%TMP_EXTRACT%" rmdir /s /q "%TMP_EXTRACT%"
powershell -NoProfile -Command "try { Expand-Archive -Path '%TMP_ZIP%' -DestinationPath '%TMP_EXTRACT%' -Force } catch { exit 1 }"
if %errorlevel% neq 0 (
    echo.
    echo  [ERROR]  Extraction failed. Restarting player with current version.
    del /q "%TMP_ZIP%" 2>nul
    schtasks /run /tn "%PLAYER_TASK%" >nul 2>&1
    exit /b 1
)

:: ── Install (player_config.json and run_player.bat are not in the zip) ──
echo  [4/4]  Installing %LATEST%...
xcopy /e /i /y /q "%TMP_EXTRACT%\*" "%INSTALL_DIR%\"
del /q "%TMP_ZIP%" 2>nul
rmdir /s /q "%TMP_EXTRACT%" 2>nul

:: ── Record new version ───────────────────────────────────────────
powershell -NoProfile -Command "[System.IO.File]::WriteAllText('%INSTALL_DIR%\version.txt', '%LATEST%')"

:: ── Rewrite launcher if device_type is samsung ───────────────────
:: Reads device_type from player_config.json — if samsung, rewrites
:: run_player.bat with the System Matrix watchdog so it survives updates.
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
)

:: ── Restart player ───────────────────────────────────────────────
echo.
echo  Update complete. Restarting player...
echo.
schtasks /run /tn "%PLAYER_TASK%" >nul 2>&1

exit /b 0
