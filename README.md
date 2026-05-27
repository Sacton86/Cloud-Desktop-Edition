# ImpactLED Cloud+ Desktop Player

A software LED sign player for the **Impact Cloud+** platform. Runs on a standard Windows PC or mini-PC and renders sign programs received from the cloud directly to a connected display, replacing a dedicated hardware media player.

---

## Target Platform

| Item | Details |
|------|---------|
| OS | Windows 10 / 11 (64-bit) |
| Python | Not required — installer deploys a self-contained exe |
| Autostart | Windows Task Scheduler (player launches at logon, updater runs at startup) |
| Updates | Automatic — `updater.bat` checks for a new GitHub release 5 minutes after every boot |

> **Linux / macOS** — `player.py` runs directly with Python for development and testing. `install.sh` targets Debian/Ubuntu systems.

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
- **Terminal ID** — your Cloud+ terminal identifier
- **Terminal Secret** — your Cloud+ terminal secret
- **Cloud+ server URL** — defaults to `https://access.impactledsigns.com/`
- **Display resolution** and fullscreen preference

**Non-interactive / bulk deployment** — set environment variables before running to suppress all prompts:

```cmd
set VSN_TERMINAL_ID=your-terminal-id
set VSN_TERMINAL_SECRET=your-secret
set VSN_CMS_SERVER=https://access.impactledsigns.com/
set VSN_WIDTH=1920
set VSN_HEIGHT=1080
set VSN_FULLSCREEN=true
%TEMP%\full-install.bat
```

---

## Installation — Linux (one-liner)

```bash
curl -fsSL https://raw.githubusercontent.com/Sacton86/Cloud-Desktop-Edition/main/install.sh | sudo bash
```

---

## Updating

**Windows** — updates are automatic. `updater.bat` is registered as a Task Scheduler job that runs 5 minutes after every boot. It compares the installed version against the latest GitHub release and updates silently if a new version is available. Player credentials are never overwritten.

To force an immediate update check:
```cmd
C:\ImpactLED\CloudPlayer\updater.bat
```

**Linux / dev** — run the updater manually:

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
git tag v1.0.5
git push origin v1.0.5
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
| `brightness` | Output brightness 0–100 |
| `timezone` | Override timezone (empty = system default) |
| `locale_code` | Override locale (empty = system default) |
| `cms_enabled` | Enable Cloud+ connectivity |
| `cms_server` | Cloud+ server base URL |
| `cms_username` | Terminal ID |
| `cms_password` | Terminal Secret |
| `cms_interval` | Polling interval in seconds |
| `cms_dl_dir` | Override download directory (empty = `downloads/` next to the player) |

> **Note:** `player_config.json` contains credentials and is listed in `.gitignore`. Never commit it. Commit `player_config.example.json` instead.

---

## File Layout

```
Cloud-Desktop-Edition/
├── player.py                  # Main application source
├── player.spec                # PyInstaller build spec
├── full-install.bat           # Windows full device installer (no Python required)
├── install.bat                # Windows installer (requires Python 3.12 pre-installed)
├── install.sh                 # Linux installer (Debian/Ubuntu)
├── updater.bat                # Windows auto-updater (runs at startup via Task Scheduler)
├── updater.sh                 # Linux/dev updater
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
| Themed installer (`install.sh` — Linux/dev) | Done |
| curl-based updater (`updater.sh` — Linux/dev) | Done |
| Full device installer (`full-install.bat` — no Python required) | Done |
| PyInstaller standalone exe build | Done |
| GitHub Actions auto-build + release workflow | Done |
| Built-in startup auto-update check (Windows) | Done |
| Bulk deployment (env-var non-interactive mode) | Done |
