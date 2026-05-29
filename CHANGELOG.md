# Changelog — ImpactLED Cloud+ Desktop Player

---

## v1.0.11 — 2026-05-29

### New Features

- **FPS counter** — Toggle a live FPS display in the bottom-right corner of the player window via F12 settings (`Show FPS counter`). Rendered on the bottom layer (before content), so sign content naturally renders over it when the playlist fills that area. Persisted in `player_config.json` as `show_fps`.

- **Device type selection** — Windows installer (`full-install.bat`) now prompts for device type during setup:
  - `1) Windows 10/11` — standard PC install
  - `2) Samsung PrismView` — Prismview hardware with System Matrix watchdog
  - Linux installer (`install.sh`) automatically sets device type to `linux` (OrangePi).
  - Device type stored in `player_config.json` as `device_type`.

- **System Matrix watchdog** (Samsung PrismView only) — The generated `run_player.bat` launcher checks whether `System Matrix.exe` is running on startup and after every player restart. If not found, it launches `C:\Program Files\Prismview\System Matrix\System Matrix.exe` automatically and waits 5 seconds before continuing.

- **Updater preserves Samsung launcher** — `updater.bat` now reads `device_type` from `player_config.json` after each update. If `samsung`, it rewrites `run_player.bat` with the System Matrix watchdog automatically — the watchdog survives future auto-updates without re-running the installer.

- **Existing install detection in installer** — `full-install.bat` detects an existing `player_config.json` and offers three options:
  - `1) Update launcher / device type only` — rewrites `run_player.bat` and patches `device_type` in the config without touching credentials or display settings. Use this to add Samsung PrismView support to an existing 1.0.10 device.
  - `2) Full reinstall` — re-downloads and re-configures everything.
  - `3) Cancel`

### Fixes / Improvements

- **Video playlist loop stutter fixed** — eliminated the noticeable delay when an MP4 playlist restarts from the beginning. Previously, each video would seek to frame 0 only after the page became visible, causing a 100–200 ms freeze on the first frame. Videos now preseed (seek and buffer frame 0) immediately when their page transitions away, so the first frame is ready by the time the playlist loops back. The decode thread idle sleep was also changed from a fixed 50 ms poll to an event wait, so it wakes up immediately when a preseed is requested.

- **Console output restored** — `player.spec` changed from `console=False` to `console=True`. All player log output (`[Cloud+]`, `[WS]`, `[Screenshot]`, `[VSN]`, etc.) now appears live in the console window below the player.

---

## v1.0.10 — Prior release

- Core player: VSN playback, Cloud+ sync, WebSocket commands
- Brightness control via Cloud+ slider
- Screenshot push to Cloud+ (`P` key)
- Linux installer / updater
- PyInstaller build + GitHub Actions auto-build
- Built-in startup auto-update (exe)
- Windows installer (`install.ps1` / `full-install.bat`)
