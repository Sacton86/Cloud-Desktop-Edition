# Changelog — ImpactLED Cloud+ Desktop Player

---

## v1.0.32 — 2026-07-09

### Bandwidth / CMS sync fixes

- **WS-triggered sync now runs on a background thread with a shared lock** — `_ws_sync()` used to call `self._sync()` synchronously on the WebSocketApp callback thread, blocking WS ping/pong for the duration of the HTTP poll + downloads. On flaky cellular links, a slow sync caused the sign to appear offline in the CMS panel for tens of seconds. Fixed by spawning a background worker and serializing periodic + WS-triggered syncs on `_sync_lock` with **non-blocking acquire** — the WS callback returns immediately, and a redundant WS trigger while a periodic sync is running is dropped instead of piling up.

- **Removed blanket `.files/` wipe on every VSN dirty-flag change** — `_handle_program()` used to `shutil.rmtree(<progname>.files/)` and purge all per-media `_seen` keys any time the VSN's URL or size changed, forcing every video/image to be re-downloaded on the next pass. On a five-video playlist that was ~300 MB of cell data per trivial CMS edit. Wipe removed; the per-media loop below already refetches only what changed on disk.

- **`_dl()` is now atomic** — downloads write to `<name>.part`, then `os.replace()` swaps the temp file into place. Previously `_dl()` called `dest.unlink()` then opened `dest` for writing, opening a race window where the target file was momentarily gone and video playback would raise `WinError 32` if it happened to read that frame.

- **Retry + fallback logging in `_sync()`** — each program's HTTP handle is now retried up to 3× with backoff before being skipped. When the newest program fails after retries, the log prints `!! NEWEST program … FAILED after retries — falling back to an older program if available` and `!! Serving STALE program …`. Field techs can tell at a glance whether a stale playlist is a CMS or a network issue.

- **`[Cloud+] needs_dl <name>: url_changed=… cms_size=… disk_size=… url=…` diagnostic log** — printed whenever the VSN is flagged for download. Distinguishes "real content change" from "session-first-detection re-queue" from "size/URL glitch."

### VSN Schedule support (Colorlight Cloud SDK V1.2, spec 1.56.7+)

- **`IsScheduleRegion` regions filter items at render time** — new `ItemSchedule` dataclass, `_schedule()` parser, and module-level `schedule_active(sched, now)` helper. `RegionState._advance()` skips items whose schedule is not currently active and re-evaluates on cycle wrap + every 30 s so items whose window opens mid-loop appear next round. Regions without `IsScheduleRegion=1` keep the old play-everything behaviour for backward compat.

- **Fields honoured**: `IsLimitTime` + `StartTime`/`EndTime` (midnight-wrap when start > end), `IsLimitDate` + `StartDay`/`EndDay` + `StartDayTime`/`EndDayTime` boundary times, `IsLimitWeek` + `LimitWeek` mask.

- **Weekday mask ordering** — Colorlight Cloud SDK V1.2 states "List From Monday to Sunday" verbatim across `commandSchedule.limit_weekday`, `contentsSchedule.limit_weekday`, Java SDK `weeks`, and raw `/api/lanschedule` JSON. Player uses Python `datetime.weekday()` directly (Mon=0 .. Sun=6) — no offset needed. A Sunday-first interpretation would silently skew schedules by one day.

- **Bucket / barrel programs**: schema not documented in Colorlight Cloud SDK V1.2. When the CMS response's `mime_type` is `bucket`, the player logs `[Cloud+] Bucket program "<name>" ignored — bucket programs not yet supported. Use regular programs with CMS-level scheduling for rotating playlists.` **once per program ID** and skips the program. Prevents blank-sign debug sessions when a customer accidentally creates a bucket program.

### Clock renderer fixes

- **`DigtalClock.Flags` bits now honoured** — `ClockRenderer._digital()` previously hardcoded `%H:%M:%S` and only checked bit 8192 (mislabelled as date/day). Now decodes the full bit map per LANplayer SDK 1.25 spec (1=Year, 2=Month, 4=Day, 8=Hour, 16=Minute, 32=Second, 512=DoW, 1024=AM/PM, 2048=24-hour, 4096=2-digit-year, 8192=multi-line). If `flags==0` (legacy VSN with no clock config), falls back to `%H:%M:%S` for backward compat. Fixes the **"always military time"** and **"seconds still showing after being disabled"** bugs seen at customer sites.

### Startup / offline resilience

- **Auto-play cached VSN on startup when the CMS is offline** — after `CMSClient` is constructed, the player scans `downloads/*.vsn` and queues the most-recently-modified file with `vsn_was_fetched=False`. If the first CMS sync completes and returns a newer program, that overrides the fallback. If the CMS is unreachable (Cloud+ maintenance, cell outage, DNS failure), the sign keeps playing the last-known content instead of showing a black screen.

### Verification status

| Fix | Verified how | Status |
|---|---|---|
| Schedule filter (#9) | End-to-end parse + `schedule_active()` on a live VSN with a `<Schedule>` block | ✅ passed |
| Clock flags (#8) | 6 unit tests: flags=0, 12h, 24h, seconds on/off, AM/PM | ✅ passed |
| Startup fallback (#7) | Ran headless with CMS disabled + one cached VSN; log printed `[Cloud+] Startup fallback: queued cached …` and `[Cloud+] Now playing: …` | ✅ passed |
| Atomic `_dl()` (#4) | Code review + module import | ✅ code path present |
| WS bg sync + lock (#1) | Code review + module import | ⏳ needs live CMS |
| No-wipe `.files/` (#2) | Code review + module import | ⏳ needs live CMS |
| Retry + fallback log (#5) | Code review + module import | ⏳ needs live CMS |
| Bucket warning | Code review + module import | ⏳ needs a bucket program in CMS |
| `needs_dl` diagnostic (#3) | Code review + module import | ⏳ needs live CMS |

Field verification (Task #6) is pending on real hardware — George's Pharmacy (CLCAPCI61Q2W) and Skyline Chili (CLCAPC5WJQXD) are the target devices.

---

## v1.0.16 — 2026-06-03

### Fixes

- **WS reconnect backoff now engages on DNS failure** — previously, `run_forever()` returning without raising (after `on_error` + `on_close` callbacks) caused the outer loop to treat each DNS failure as a clean exit, resetting `attempt` to 0 and retrying every 5 s indefinitely. Fixed by tracking whether `on_open` ever fired; if `run_forever()` exits without a successful connection, `_ws_connect()` raises so the backoff actually triggers. Max backoff cap reduced from 120 s to 60 s to keep recovery time reasonable when the modem comes back.

- **CMS sync skips polling during connectivity outages** — added `_net_ok` shared flag (set on WS `on_open`, cleared when WS enters backoff). The download loop now skips `_sync()` calls while `_net_ok` is clear, eliminating the separate stream of HTTP connection errors that appeared alongside the WS reconnect storm during cell modem outages. Normal sync resumes automatically as soon as WS reconnects.

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
