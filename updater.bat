@echo off
setlocal

set "INSTALL_DIR=C:\ImpactLED\CloudPlayer"
set "PLAYER_TASK=ImpactLED Cloud+ Desktop Player"
set "VERSION_FILE=%INSTALL_DIR%\version.txt"
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

:: ── Download new release ─────────────────────────────────────────
curl -fsSL "%DOWNLOAD_URL%" -o "%TMP_ZIP%"
if %errorlevel% neq 0 exit /b 1

:: ── Stop player ──────────────────────────────────────────────────
schtasks /end /tn "%PLAYER_TASK%" >nul 2>&1
timeout /t 5 /nobreak >nul

:: ── Extract ──────────────────────────────────────────────────────
if exist "%TMP_EXTRACT%" rmdir /s /q "%TMP_EXTRACT%"
powershell -NoProfile -Command "Expand-Archive -Path '%TMP_ZIP%' -DestinationPath '%TMP_EXTRACT%' -Force"
if %errorlevel% neq 0 (
    del /q "%TMP_ZIP%" 2>nul
    schtasks /run /tn "%PLAYER_TASK%" >nul 2>&1
    exit /b 1
)

:: ── Install (player_config.json is not in the zip - credentials safe) ──
xcopy /e /i /y /q "%TMP_EXTRACT%\*" "%INSTALL_DIR%\"
del /q "%TMP_ZIP%" 2>nul
rmdir /s /q "%TMP_EXTRACT%" 2>nul

:: ── Record new version ───────────────────────────────────────────
powershell -NoProfile -Command "[System.IO.File]::WriteAllText('%INSTALL_DIR%\version.txt', '%LATEST%')"

:: ── Restart player ───────────────────────────────────────────────
schtasks /run /tn "%PLAYER_TASK%" >nul 2>&1

exit /b 0
