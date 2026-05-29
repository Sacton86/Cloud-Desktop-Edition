# ImpactLED Cloud+ Desktop Player

A software LED sign player for the **Impact Cloud+** platform. Runs on a standard Windows PC, mini-PC, or OrangePi SBC and renders sign programs received from the cloud directly to a connected display, replacing a dedicated hardware media player.

---

## Supported Device Types

| Device Type | OS | Notes |
|-------------|-----|-------|
| **Windows 10/11** | Windows 10/11 (64-bit) | Standard PC or mini-PC |
| **Samsung PrismView** | Windows 10/11 (64-bit) | Prismview hardware — includes System Matrix watchdog |
| **OrangePi (Linux)** | Debian/Ubuntu | SBC-based display player |

Device type is set during installation and stored in `player_config.json` as `device_type`. Samsung PrismView devices automatically monitor and restart `System Matrix.exe` if it crashes.

---

## Installation — Windows (one-liner)

Open **Command Prompt as Administrator** and run:

```cmd
curl -fsSL https://raw.githubusercontent.com/Sacton86/Cloud-Desktop-Edition/main/full-install.bat -o %TEMP%\full-install.bat && %TEMP%\full-install.bat
```

Or with **PowerShell as Administrator**:

```powershell
curl -fsSL https://raw.githubusercontent.com/Sacton86/Cloud-Desktop-Edition/main/full-install.bat -o "$env:TEMP\full-install.bat"; & "$env:TEMP\full-install.bat"
```

> `full-install.bat` requires no Python or software pre-installed. It downloads the latest release from GitHub, installs to `C:\ImpactLED\CloudPlayer\`, configures the device, and registers autostart.

The installer will prompt for:
1. **Device type** — `1) Windows 10/11` or `2) Samsung PrismView`
2. **Terminal ID** — your Cloud+ terminal identifier
3. **Terminal Secret** — your Cloud+ terminal secret
4. **Cloud+ server URL** — defaults to `https://access.impactledsigns.com/`
5. **Display resolution** and fullscreen preference

### Updating an Existing Device (adding Samsung watchdog)

If a device was previously installed without Samsung PrismView support, re-run the installer and choose **option 1 — Update launcher / device type only**. This rewrites `run_player.bat` and updates `device_type` in the config without touching credentials, display settings, or the exe. No download required.

```cmd
curl -fsSL https://raw.githubusercontent.com/Sacton86/Cloud-Desktop-Edition/main/full-install.bat -o %TEMP%\full-install.bat && %TEMP%\full-install.bat
```

Select `2) Samsung PrismView` when prompted for device type.

**Non-interactive / bulk deployment** — set environment variables before running to suppress all prompts:

```cmd
set VSN_TERMINAL_ID=your-terminal-id
set VSN_TERMINAL_SECRET=your-secret
set VSN_CMS_SERVER=https://access.impactledsigns.com/
set VSN_DEVICE_TYPE=samsung
set VSN_WIDTH=1920
set VSN_HEIGHT=1080
set VSN_FULLSCREEN=true
%TEMP%\full-install.bat
```

---

## Installation — Linux / OrangePi (one-liner)

```bash
curl -fsSL https://raw.githubusercontent.com/Sacton86/Cloud-Desktop-Edition/main/install.sh | sudo bash
```

Device type is automatically set to `linux` — no prompt required.

---

## Updating

**Windows** — updates are automatic. `updater.bat` is registered as a Task Scheduler job that runs 5 minutes after every boot. It compares the installed version against the latest GitHub release and updates silently if a new version is available.

- Player credentials and `player_config.json` are never overwritten during an update
- Samsung PrismView devices: the updater reads `device_type` from `player_config.json` after each update and rewrites `run_player.bat` with the System Matrix watchdog automatically — the watchdog survives all future updates

To force an immediate update check:
```cmd
C:\ImpactLED\CloudPlayer\updater.bat
```

**Linux / OrangePi** — run the updater manually:

```bash
sudo bash updater.sh
```

---

## Uninstall

Run the following in an **Administrator Command Prompt** to stop the player, remove both Task Scheduler jobs, and delete all installed files:

```cmd
schtasks /end /tn "ImpactLED Cloud+ Desktop Player" >nul 2>&1 && schtasks /end /tn "ImpactLED Cloud+ Updater" >nul 2>&1 && schtasks /delete /tn "ImpactLED Cloud+ Desktop Player" /f && schtasks /delete /tn "ImpactLED Cloud+ Updater" /f && taskkill /f /im "ImpactLED-Cloud-Player.exe" >nul 2>&1 && rmdir /s /q "C:\ImpactLED"
```

> **Note:** This permanently deletes `player_config.json` including stored credentials. Record the Terminal ID and Terminal Secret before uninstalling if the device will be reinstalled.

---

## Releasing a New Version (maintainers)

Commit your changes, then push a version tag:

```cmd
git tag v1.0.11
git push origin v1.0.11
```

GitHub Actions will automatically build the exe with PyInstaller, bundle it into `ImpactLED-Cloud-Player.zip`, and publish a GitHub Release. Running players will pick up the update on their next reboot.

---

## Running from Source *(development)*

```bash
pip install -r requirements.txt
python player.py
```

Make sure a display is available and `player_config.json` exists in the same directory.

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `O` | Open a local file |
| `F12` | Open settings panel |
| `F11` | Toggle fullscreen |
| `Space` | Pause / resume playback |
| `ESC` | Quit the player |
| `I` | Toggle HUD (on-screen info overlay) |
| `P` | Push a screenshot to Cloud+ |

---

## F12 Settings Panel

The settings panel (opened with `F12`) provides access to all player configuration. Changes take effect immediately on **Apply & Close**.

| Setting | Description |
|---------|-------------|
| Player Width / Height | Output resolution in pixels |
| Fullscreen | Toggle borderless fullscreen |
| Fit Mode | `native`, `letterbox`, `stretch`, or `crop` |
| Target FPS | 15, 25, 30, or 60 |
| Loop program | Restart from the first page after the last |
| Show info HUD | Toggle the on-screen program/page info overlay |
| Show FPS counter | Display live FPS in the bottom-right corner (below content layer) |
| Brightness (%) | Output brightness 0–100 |
| Timezone / Locale | Override system defaults |
| Cloud+ Auto-sync | Enable/disable Cloud+ connectivity |
| Server URL / Terminal ID / Password | Cloud+ credentials |
| Poll interval (s) | How often to check Cloud+ for program changes |

---

## Configuration Reference (`player_config.json`)

Written by the installer and lives in `C:\ImpactLED\CloudPlayer\`. It is **device-specific** and excluded from version control. Use `player_config.example.json` as a reference template.

| Field | Description |
|-------|-------------|
| `width` / `height` | Output resolution in pixels |
| `fullscreen` | `true` to run borderless fullscreen |
| `fit_mode` | How to fit content: `"native"`, `"letterbox"`, `"stretch"`, `"crop"` |
| `fps` | Target frame rate |
| `bar_color` | Letterbox/pillarbox colour (ARGB hex string) |
| `loop` | Loop content when playback ends |
| `show_hud` | Show the on-screen info overlay at startup |
| `show_fps` | Show live FPS counter in the bottom-right corner |
| `brightness` | Output brightness 0–100 |
| `timezone` | Override timezone (empty = system default) |
| `locale_code` | Override locale (empty = system default) |
| `cms_enabled` | Enable Cloud+ connectivity |
| `cms_server` | Cloud+ server base URL |
| `cms_username` | Terminal ID |
| `cms_password` | Terminal Secret |
| `cms_interval` | Polling interval in seconds |
| `cms_dl_dir` | Override download directory (empty = `downloads/` next to the player) |
| `device_sn` | Unique device serial number (auto-generated on first run) |
| `device_type` | Device type: `"windows"`, `"samsung"`, or `"linux"` |

> **Note:** `player_config.json` contains credentials and is listed in `.gitignore`. Never commit it. Commit `player_config.example.json` instead.

---

## File Layout

```
Cloud-Desktop-Edition/
├── player.py                  # Main application source
├── player.spec                # PyInstaller build spec
├── full-install.bat           # Windows full device installer (no Python required)
├── install.bat                # Windows installer (requires Python 3.12 pre-installed)
├── install.sh                 # Linux / OrangePi installer (Debian/Ubuntu)
├── updater.bat                # Windows auto-updater (runs at startup via Task Scheduler)
├── updater.sh                 # Linux/dev updater
├── CHANGELOG.md               # Version history
├── player_config.json         # Device config — generated by installer, git-ignored
├── player_config.example.json # Template for reference
├── requirements.txt           # Python dependencies
├── vsn_player.service         # systemd unit — Linux reference
├── .github/workflows/
│   └── build.yml              # GitHub Actions — builds exe and publishes release on tag push
├── downloads/                 # Cloud+-downloaded programs (git-ignored)
└── fonts/                     # Bundled fonts
```

---

## Roadmap

| Item | Status |
|------|--------|
| Core player (VSN playback, Cloud+ sync, WS commands) | Done |
| Brightness control via Cloud+ | Done |
| Screenshot push to Cloud+ | Done |
| Themed installer (`install.bat` — Windows) | Done |
| Themed installer (`install.sh` — Linux/OrangePi) | Done |
| curl-based updater (`updater.sh` — Linux/dev) | Done |
| Full device installer (`full-install.bat` — no Python required) | Done |
| PyInstaller standalone exe build | Done |
| GitHub Actions auto-build + release workflow | Done |
| Built-in startup auto-update check (Windows) | Done |
| Bulk deployment (env-var non-interactive mode) | Done |
| Device type selection (Windows / Samsung PrismView / Linux) | Done |
| Samsung PrismView — System Matrix watchdog | Done |
| FPS counter (F12 toggle, bottom-right corner) | Done |
| Console log output restored | Done |
| Screenshot visible in CMS panel | Tabled |
| Playlist history in CMS panel | Tabled |
