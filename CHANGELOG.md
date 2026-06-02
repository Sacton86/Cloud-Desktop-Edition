# Changelog — ImpactLED Cloud+ Desktop Player

---

## v1.0.15 — 2026-06-02

### Fix

- **Decode thread crash on page change** — `_decode_loop` raised `AttributeError: 'NoneType' object has no attribute 'read'` when `destroy()` fired while the thread was between its `_stop` check and the `cap.read()` call. Fixed by snapshotting `cap = self._cap` at the top of each iteration and breaking immediately on `None`, so the thread exits cleanly regardless of when `destroy()` fires.

---

## v1.0.14 — 2026-06-02

### Performance Fixes

- **Lazy renderer initialization** — Renderers (VideoCapture decoders, GIF frame buffers) are now created only for the page currently playing. All other pages remain dormant until activated. Reduces peak RAM from ~1 GB+ (10 open decoders) to ~250–300 MB on a typical playlist. Previous behavior opened N decoders at startup regardless of which page was playing.

- **Explicit renderer cleanup on page change and rebuild** — `VideoRenderer.destroy()` now stops the decode thread and calls `cap.release()`. `RegionState.destroy()` tears down all renderers in a region. On page advance, the departing page's renderers are destroyed before the next page activates. On `rebuild()` (CMS update, settings change), all old page slots are destroyed before new ones are created. Previously, old decode threads continued running indefinitely after every rebuild, accumulating ~30–50 MB of VideoCapture DPB each time — the primary cause of the progressive daily performance deterioration seen on deployed hardware.

- **Intel Quick Sync hardware video decode** — `VideoRenderer` now requests the MSMF (Windows Media Foundation) backend with `VIDEO_ACCELERATION_ANY`. On Windows 10/11 with Intel graphics (including HD Graphics 505 on the deployed Atom E3950), H.264/H.265 decode is offloaded to the Quick Sync engine, removing the per-frame CPU decode cost entirely. Falls back to software decode if MSMF is unavailable.

- **Zero-copy frame blit** — Removed `.tobytes()` from the numpy→pygame frame path. Numpy arrays implement the buffer protocol; `pygame.image.frombuffer()` accepts them directly, eliminating a full frame memory copy (~3 MB at 720p, ~6 MB at 1080p) on every rendered frame.

### Reliability Fixes

- **WebSocket heartbeat interval reduced to 25 s** — Cell modem NAT tables typically time out idle TCP connections in 30–90 s. The previous 55 s ping interval allowed the connection to silently drop, causing a reconnect that triggered the CMS to push `transmission/ftp/config`, which triggered a `rebuild()` — and with the old leak, each reconnect accumulated more leaked decoders. The 25 s interval keeps the connection alive through aggressive carrier NATs.

### New Features

- **F12 settings panel — mouse support** — The settings overlay now responds to mouse input: click a row to select it (same as arrow keys), scroll wheel to navigate the list, click a choice field to open a dropdown and select an option. Keyboard editing still works unchanged.

- **Updater progress display** — `updater.bat` now shows a banner with current and target versions, four numbered steps (`[1/4]` Downloading → `[2/4]` Stopping → `[3/4]` Extracting → `[4/4]` Installing), a curl progress bar during download, and a completion message. Error conditions print a plain-text explanation before exiting.

---

## v1.0.13 — 2026-05-29

### Fixes

- **Mid-video flash on playlist loop-back fixed** — after the v1.0.11 preseed fix eliminated the loop-restart stutter, a new one-frame flash appeared at the start of each loop. The preseed was seeking to frame 0 and then running the video forward at full speed while the page was off-screen. When the page looped back, `render()` read a mid-video frame from the running-ahead buffer before the second seek completed, blitting one frame of wrong content. Fixed by buffering exactly one frame (frame 0) during preseed and parking the decode thread — `self._raw` stays at frame 0 while the page is off-screen, so the first blit on resume is always clean.

- **Installer crash on re-run fixed** (`full-install.bat`) — re-running the installer on a device with an existing installation produced a "Update was unexpected at this time" CMD error and exited. Root cause: the retry label (`:existing_prompt`) was placed inside a parenthesized `if` block, which is invalid in Windows CMD. Restructured the existing-install detection to use a top-level `goto`-based skip, which is valid in all CMD versions.

- **SSL certificate verification** (from v1.0.12) — bundled the certifi CA store in the PyInstaller exe and configured `requests` and `websocket-client` to use it. Eliminates `ssl.SSLCertVerificationError` in the player console and prevents periodic mid-playback stutters caused by SSL timeout retries on background threads starving the render thread.

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
