# ImpactLED Cloud+ Desktop Player — CLAUDE.md

This file is context for Claude Code sessions on this project. Read it at the start of every session.

---

## What This Project Is

A Python/pygame software LED sign player for the **Impact Cloud+** platform (`access.impactledsigns.com`). It runs on a standard Windows PC or mini-PC, renders VSN sign programs to a connected display, and replaces dedicated Colorlight hardware media boxes.

- Distributed as a standalone `.exe` (PyInstaller, built via GitHub Actions — no Python required on devices)
- Connects to the Colorlight-compatible Cloud+ CMS at `https://access.impactledsigns.com/`
- Repo: `https://github.com/Sacton86/Cloud-Desktop-Edition`

---

## Project History

Developed from scratch as `player.py` in `/home/sacton/Documents/Projects/APK TEST/vsn_player/`. Moved to this directory as the project matured into a distributable product. The GitHub repo (`Cloud-Desktop-Edition`) is the canonical source and build pipeline.

---

## Architecture Overview

| Component | Details |
|-----------|---------|
| Renderer | pygame — draws VSN program frames at target FPS |
| CMS sync | Polls `/wp-json/wp/v2/programs?clt_type=terminal&sn=...` every 30 s |
| WebSocket | Persistent connection to `wss://access.impactledsigns.com:8443/ColorWebSocket/websocket/chat` |
| Status reporting | HTTP PUT to `/wp-json/screen/v1/status` every 60 s |
| Local API | HTTP server on port 8989 (info, brightness, screenshot, vsns endpoints) |
| Auto-update | Player checks GitHub Releases on startup, self-updates exe and relaunches |

---

## Working Features (as of v1.0.32)

- **CMS sync** — downloads and plays assigned programs automatically; picks up schedule changes within 30 s
- **WebSocket online presence** — device shows as Online in CMS panel
- **WS commands** (routed by `author_url`, not content text — see rules below):
  - `api/brightness` → applied immediately (Colorlight 0–255 → internal 0–100)
  - `api/brightcurve` / `api/colortemp` → acknowledged/ignored
  - `transmission/ftp/config` → triggers debounced program sync
  - `api/screenshot` → triggers manual screenshot capture
- **Brightness control** — CMS slider works end-to-end
- **Status PUT** — all required Colorlight fields present, including `brightcurve` with `_report_time` on every sub-object
- **Static text** — `IsScrollByTime=1` with `IsScroll=0` correctly renders static (not scrolling)
- **Screenshot push** — `P` key pushes PNG to `/wp-json/led/flowfee/v2/screenshot` (multipart)
- **Auto-update** — startup update check, silent self-update and relaunch
- **Lazy renderer init** — `PageSlot` class defers `RegionState`/`VideoRenderer` creation until a page becomes active; only 1 page worth of `VideoCapture` objects open at a time (reduces peak RAM from ~1 GB to ~250–300 MB on multi-page MP4 playlists)
- **VideoRenderer cleanup** — `VideoRenderer.destroy()` and `RegionState.destroy()` release the decode thread and `VideoCapture` on page leave and `rebuild()`; old threads no longer leak on reload
- **MSMF hardware decode** — on Windows, `VideoCapture` opens with `CAP_MSMF` and `VIDEO_ACCELERATION_ANY` hint, routing H.264/H.265 decode to Intel Quick Sync (off CPU cores); fallback to default backend if MSMF fails; no-op on Linux
- **Zero-copy frame blit** — numpy frame array passed directly to `pygame.image.frombuffer` (no `.tobytes()` copy); eliminates a ~3–6 MB per-frame allocation at 25–30 fps
- **WS reconnect backoff** — exponential backoff (5→10→20→30→60 s) on connection failure; backoff now correctly engages on DNS failure (previously reset to 5 s every attempt because `run_forever()` returned without raising). Max cap 60 s for reasonable modem recovery time.
- **Connectivity gate (`_net_ok`)** — `_net_ok` event is set on WS `on_open` and cleared when WS enters backoff. CMS download loop skips `_sync()` while `_net_ok` is clear, eliminating the parallel HTTP error storm during cell modem outages. Resumes automatically on reconnect.
- **Region layer ordering** — regions sorted descending by `Layer` value so CMS Layer=1 (foreground: text/weather/clock) renders on top of Layer=2 (background: video), matching Colorlight hardware behaviour.
- **Text/font background rendering** — `BaseRenderer._font_render()` uses `set_colorkey` when the background is transparent (`opacity_bg=0` or black `back_clr`), passes the real colour to `font.render` otherwise for correct AA edge blending.
- **Base64 PNG alpha compositing** — all PIL `pygame.image.fromstring(..., 'RGBA')` calls chain `.convert_alpha()` so per-pixel alpha blits correctly. Affected paths: `_build_from_b64()`, `ImageRenderer._load()`, `WebRenderer`, `_get_logo()`.
- **WeatherRenderer multi-line** — detects `type='5'` or `multiline=True` on the region and stacks all weather parts vertically (joined with `\n`) instead of forcing a single scrolling line. Single-line regions keep the existing paging/scrolling behaviour.
- **updater.bat self-overwrite fix** — replaced `xcopy /EXCLUDE:file.txt` with `robocopy /XF updater.bat` (reliable filename exclusion, no intermediate file); background swap of `updater.bat.new` moved to after `pause` so CMD has exited before the file is replaced.
- **updater.bat process-exit poll** — replaced fixed `timeout /t 3` with a `tasklist` poll loop; also kills the launcher `cmd.exe` by window title so `run_player.bat` is not held open during the Samsung launcher rewrite. `/IS /IT` flags added to robocopy so files copy even when timestamps match. Samsung launcher echo blocks escape `(` and `)` as `^(` / `^)` to prevent CMD block-parser misrouting the `>` redirect.
- **Black background = transparent** — `_fill_bg` and `_font_render` both treat `back_clr=(0,0,0,...)` as transparent, matching the CMS convention where `BackColor=0xFF000000` means "no background / clear."
- **VSN item-level schedules** — `<Schedule>` blocks on items inside regions marked `<IsScheduleRegion>1</IsScheduleRegion>` are honoured. Fields: `IsLimitTime` + `StartTime`/`EndTime` (midnight-wrap), `IsLimitDate` + `StartDay`/`EndDay` + `StartDayTime`/`EndDayTime` boundary times, `IsLimitWeek` + `LimitWeek` Monday-first mask. Filter re-evaluates on cycle wrap and every 30 s. Regions without the flag play unchanged (backward compat).
- **Clock 12-hour + selective flags** — `ClockRenderer._digital()` decodes the full `DigtalClock.Flags` bit map (year/month/day/hour/min/sec/DoW/AM-PM/24h/2-digit-year). Legacy `flags=0` VSN files still show `%H:%M:%S` for backward compat. Fixes "always military time" and "seconds still on" reports.
- **Startup fallback playback** — when the CMS is offline (Cloud+ maintenance, cell outage, DNS failure) and no CLI VSN was passed, the player auto-queues the most-recently-modified `downloads/*.vsn` so the sign never goes black on restart during an outage. A later successful sync overrides the fallback.
- **Bandwidth-safe CMS sync** — WS-triggered sync runs on a background thread and shares a non-blocking `_sync_lock` with the periodic sync, so WS ping/pong is never held up by an HTTP poll and syncs cannot race. The blanket `<progname>.files/` wipe on every VSN dirty-flag change is removed; per-media disk-size + URL check refetches only what actually changed. `_dl()` writes to a `.part` file and `os.replace()`s the target atomically, closing the WinError-32 unlink race during video playback. Each program's HTTP handle retries 3× before falling back; the log clearly announces when a stale program is being served because the newest failed. `[Cloud+] needs_dl <name>: url_changed=… cms_size=… disk_size=…` fires on every re-download decision so field techs can distinguish real content changes from glitches.
- **Bucket-program warning** — `mime_type=bucket` programs in the CMS response are logged once per program ID (`[Cloud+] Bucket program "<name>" ignored — …`) and skipped, since the barrel/bucket schedule schema is not in Colorlight Cloud SDK V1.2. Prevents blank-sign debug sessions when a customer accidentally creates one.

---

## Known Issues / Tabled

| Issue | Detail |
|-------|--------|
| Screenshot in CMS panel | CMS tries `GET http://localip:8989/api/screenshot` from cloud — 504, LAN not reachable. WS never sends `api/screenshot`. P key push succeeds but image doesn't appear in panel. **Tabled.** |
| Playlist history in CMS panel | `vsns.contents` populated correctly but CMS Angular panel crashes (`ngOnChanges: Method not implemented`) — pre-existing CMS bug. **Tabled.** |
| Local API 504 | Cloud server can't reach `http://localip:8989` — LAN IP not routable from internet. Server-pull features need port forwarding or tunnel. **Tabled.** |

---

## Critical Technical Facts

These are non-obvious invariants that have caused bugs before — check these first when something breaks.

- **Brightness scaling**: Internal 0–100 ↔ Colorlight 0–255. Formula: `int(pct * 255 / 100)` and `round(raw * 100 / 255)`. WS brightness values are always on the 0–255 scale.
- **Status PUT sub-objects**: Every sub-object needs `_report_time: now` or the CMS silently discards it.
- **`brightcurve.sensorErrorDefaultValue`**: Must be present in the status PUT or the CMS brightness dialog crashes.
- **`IsScrollByTime`**: Controls speed method (time-based vs frame-based) only — NOT whether text scrolls. `IsScroll=1` is what enables scrolling.
- **`PageSlot` lazy init**: `build_page_regions()` now returns `List[PageSlot]` (not `List[List[RegionState]]`). Renderers are created on `activate()` and destroyed on `deactivate()`. `rebuild()` calls `deactivate()` on all old slots before creating new ones, then activates `page_regions[page_idx]`. Page advance and LEFT/RIGHT keys call `deactivate()` on departure and `activate()` on arrival. The old `preseed()` flow (decode thread seek-to-zero on page leave) is replaced by fresh renderer creation on activate.
- **`frombuffer` buffer ownership**: `pygame.image.frombuffer(raw, ...)` where `raw` is a numpy array — pygame holds a reference to `raw` via the Surface, so the array stays alive until the Surface is replaced. Safe because the decode thread replaces `self._raw` with a new array (never modifies in-place) and Python's GIL ensures atomic reference counting.
- **`vsns` field**: Must always be a dict with `contents` / `playing` / `_report_time`. The `ressize` field inside contents items causes a 500 error — never include it.
- **`newrtc.timezone`**: Must be an integer (UTC offset hours), not a string.
- **`newrtc.timezoneId`**: Must be a valid IANA name (e.g. `America/Chicago`), not the string `"UTC"`.
- **WS routing**: Always use `author_url` to identify command type. Content-text scanning caused `isNewBrightness:1` to be misread as `brightness=1`, nearly blacking out the display.
- **Screenshot endpoint**: `/wp-json/led/flowfee/v2/screenshot` — multipart POST with fields `image` (PNG file), `sn`, `time`.
- **`_net_ok` flag**: `CMSClient._net_ok` is a `threading.Event` — set on WS `on_open`, cleared when `_ws_connect()` raises (DNS/connection failure). `_dl_loop` checks it before each `_sync()` call. Do not clear it on a normal WS drop (server-side close) — only on failure to connect at all. Starting state is set (assume connectivity).
- **All PIL `fromstring` paths must call `.convert_alpha()`**: Every `pygame.image.fromstring(..., 'RGBA')` call must chain `.convert_alpha()`. Without it the surface blits without per-pixel alpha and transparent areas render opaque black. Affected: `_build_from_b64()`, `ImageRenderer._load()`, `WebRenderer._fetch_thread()`, `_get_logo()`. The non-PIL `pygame.image.load().convert_alpha()` path is always correct — keep all paths consistent.
- **Black `BackColor` = transparent (CMS convention)**: The CMS renders `BackColor=0xFF000000` (pure black) as clear/no-background. `_fill_bg` skips the fill when `back_clr` is `(0,0,0,...)` regardless of `opacity_bg`; `_font_render` uses the colorkey path in the same case. Never add a black region fill — it will cover video or other regions behind it.
- **`WeatherRenderer` fake Item type**: Always check `self.item.type == '5' or self.item.multiline` before creating the internal `TextRenderer`. Multi-line regions need `fake = Item(type='5', ..., multiline=True, scroll=False)`; single-line regions use `type='4'` with scroll/paging. Hardcoding `type='4'` was a recurring bug.
- **`updater.bat` — CMD reads by byte offset**: Overwriting a running `.bat` file causes CMD to jump to the wrong offset in the new file and re-execute earlier sections at random. `robocopy /XF updater.bat` excludes the running script during install; `xcopy /EXCLUDE:file.txt` silently failed on Samsung PrismView (the string-in-file matching did not apply). The background swap of `updater.bat.new` must be launched **after** `pause` — launching it before means schtasks/other commands can consume the delay and the swap fires while CMD is still running.
- **`updater.bat` — taskkill returns before handles are released**: A fixed `timeout /t 3` was not always long enough. The stop section polls `tasklist` until the exe disappears then waits an extra 2 s. The launcher `cmd.exe` (window title `ImpactLED Cloud+ Desktop Player`) must also be killed or it holds `run_player.bat` open, blocking the Samsung launcher rewrite redirect.
- **`updater.bat` — robocopy timestamp skipping**: `Expand-Archive` preserves ZIP timestamps, so reinstalling the same build produces identical source/dest timestamps and robocopy skips all files. `/IS /IT` flags force copy regardless.
- **`updater.bat` — Samsung echo `(` / `)` must be escaped**: Bare `(` and `)` inside a `( ... ) > file` redirect block are counted by the CMD block parser, causing the redirect to be misapplied. Use `^(` and `^)` in all `echo` lines inside that block.
- **Layer convention**: VSN Layer=1 is FOREGROUND (text, weather, clock), Layer=2 is BACKGROUND (video). Regions must be sorted `reverse=True` (descending layer number) so background renders first. This is the opposite of the intuitive reading.
- **VSN Schedule Monday-first mask**: Colorlight Cloud SDK V1.2 explicitly documents `LimitWeek` as "List From Monday to Sunday" across every schedule variant (`commandSchedule.limit_weekday`, `contentsSchedule.limit_weekday`, Java SDK `weeks`, raw `/api/lanschedule` JSON). Player uses Python `datetime.weekday()` (Mon=0..Sun=6) directly — no offset. A Sunday-first interpretation would silently skew schedules by one day.
- **`DigtalClock.Flags` bit map**: 1=Year, 2=Month, 4=Day, 8=Hour, 16=Minute, 32=Second, 512=DoW, 1024=AM/PM, 2048=24-hour, 4096=2-digit-year, 8192=multi-line-hint. `flags=0` means "display fixed text" per spec — treat as legacy VSN, fall back to `%H:%M:%S`. Bit 2048 SET = 24-hour; UNSET = 12-hour (AM/PM label controlled independently by bit 1024).
- **`schedule_active(sched, now)` semantics**: a schedule is active when all three limit flags (date, time-of-day, weekday) individually permit playback. A missing (`None`) schedule is always active. A `<Schedule>` block with all `IsLimit*=0` is also always active. Time-of-day wraps midnight when `StartTime > EndTime`. Boundary-day times (`StartDayTime`/`EndDayTime`) apply only on the exact start/end date.
- **`_dl()` atomic swap**: always writes to `<dest>.part` then `os.replace(tmp, dest)`. Do NOT re-introduce `dest.unlink()` before the write — on Windows the running video decoder holds the file open and a mid-playback unlink raises WinError 32 into the render loop.
- **`_sync_lock` non-blocking acquire**: both the WS-sync worker and the periodic download loop use `acquire(blocking=False)`. If the lock is held, the requester logs and returns immediately. Do NOT switch either to a blocking acquire — a blocking WS-sync would freeze WS ping/pong for the duration of the HTTP sync, which was the exact bug this fixes.
- **No blanket `.files/` wipe**: `_handle_program()` no longer calls `shutil.rmtree(<progname>.files/)` on VSN change. Per-media disk-size + URL comparison is the sole decision point for refetching. Do NOT re-add the wipe — it burned ~300 MB of cell data per trivial CMS edit on a five-video playlist.
- **Bucket programs (`mime_type=bucket`)**: schema not in Colorlight Cloud SDK V1.2. Player logs a one-shot warning per program ID and skips. Customers who need scheduled-playlist rotation can achieve the same result with regular programs + CMS-level scheduling — no code change required.

---

## Coding Rules

**No automatic periodic data uploads.**
Do not add timers that automatically upload data (screenshots, extra status pings beyond the existing 60 s PUT). The player runs on devices with metered/limited data plans. Any new background network activity must be on-demand (keyboard shortcut, WS command) or already-established. Get explicit approval before adding any new recurring upload timer.

**Probe-then-fix for unknown API schemas.**
When a CMS endpoint returns 500/4xx and the exact schema is unknown, strip to a minimal payload first, then add fields back in groups to isolate the failure. Don't guess the full schema upfront.

**Route WS commands by `author_url`, not content text.**
Always check `author_url` first. Use content parsing only as a fallback for legacy/unknown commands.

---

## Configuration (`player_config.json`)

Lives next to the exe. Device-specific, never committed. Use `player_config.example.json` as a template.

| Field | Description |
|-------|-------------|
| `width` / `height` | Output resolution in pixels |
| `fullscreen` | `true` for borderless fullscreen |
| `fit_mode` | `"native"`, `"fit"`, or `"fill"` |
| `fps` | Target frame rate |
| `bar_color` | Letterbox/pillarbox colour (ARGB hex) |
| `loop` | Loop content when playback ends |
| `show_hud` | Show on-screen info overlay at startup |
| `brightness` | Output brightness 0–100 |
| `timezone` | Override timezone (empty = system default) |
| `locale_code` | Override locale (empty = system default) |
| `cms_enabled` | Enable Cloud+ connectivity |
| `cms_server` | Cloud+ server base URL |
| `cms_username` | Cloud+ account username |
| `cms_password` | Cloud+ account password |
| `cms_interval` | Polling interval in seconds |
| `cms_dl_dir` | Override download directory (empty = `downloads/`) |
| `device_sn` | Unique serial number for this device in Cloud+ |

Dev device SN: `CLCAPC3256KH`

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `O` | Open a local file |
| `F12` | Open settings panel |
| `F11` | Toggle fullscreen |
| `Space` | Pause / resume playback |
| `ESC` | Quit |
| `I` | Toggle HUD overlay |
| `P` | Push screenshot to Cloud+ |

---

## File Layout

```
Cloud+ Desktop Edition/
├── player.py                   # Main application source (3200+ lines)
├── player_config.json          # Device config — git-ignored
├── player_config.example.json  # Template
├── requirements.txt            # Python deps (dev/source installs)
├── fonts/                      # Bundled sign fonts
├── downloads/                  # Cloud+-downloaded programs — git-ignored
├── releases/                   # Local release artifacts
├── install.sh                  # Linux/dev themed installer
├── updater.sh                  # Linux/dev curl-based updater (no git)
├── armbian-install.sh          # Armbian-specific install helper
├── vsn_player.service          # systemd unit — Linux/dev reference
└── CLAUDE.md                   # This file
```

---

## Roadmap

| Item | Status |
|------|--------|
| Core player (VSN playback, Cloud+ sync, WS commands) | Done |
| Brightness control via Cloud+ | Done |
| Screenshot push to Cloud+ | Done |
| Linux installer / updater | Done |
| PyInstaller build + GitHub Actions auto-build | Done (v1.0.10) |
| Built-in startup auto-update (exe) | Done (v1.0.10) |
| Windows installer (`install.ps1`) | Done (v1.0.10) |
| Lazy renderer init — `PageSlot`, peak RAM fix | Done (v1.0.14) |
| `VideoRenderer.destroy()` — no decode thread leaks on reload | Done (v1.0.14) |
| MSMF hw-decode + Quick Sync hint on Windows | Done (v1.0.14) |
| Zero-copy numpy→pygame frame blit | Done (v1.0.14) |
| WS reconnect backoff + cell modem connectivity gate | Done (v1.0.16) |
| Region layer ordering (video behind text/weather/clock) | Done (v1.0.17) |
| Text background rendering / AA fringe fix (`_font_render`) | Done (v1.0.17) |
| Base64 PNG alpha fix (`.convert_alpha()` in PIL path) | Done (v1.0.20) |
| WeatherRenderer multi-line region support | Done (v1.0.20) |
| updater.bat self-overwrite fix (`robocopy /XF`, post-pause swap) | Done (v1.0.21) |
| updater.bat: process-exit poll, launcher kill, `/IS /IT`, `^(`/`^)` escaping | Done (v1.0.23) |
| PNG/GIF/image transparency — `.convert_alpha()` on all PIL `fromstring` paths | Done (v1.0.23) |
| Black `BackColor` = transparent — `_fill_bg` / `_font_render` CMS convention | Done (v1.0.24) |
| Bandwidth-safe CMS sync (WS bg sync + non-blocking lock, no blanket wipe, atomic `_dl`, retry + fallback log, `needs_dl` diagnostic) | Done (v1.0.32) — code, ⏳ field verification |
| VSN item-level schedule (`<Schedule>` in schedule regions; Monday-first mask) | Done (v1.0.32) — verified via unit tests + VSN parse |
| ClockRenderer 12-h / seconds / AM-PM / DoW / date flag decoding | Done (v1.0.32) — verified via unit tests |
| Offline startup fallback (auto-queue newest cached VSN) | Done (v1.0.32) — verified end-to-end headless |
| Bucket / barrel program schema | Deferred — no doc, one-shot warning log only |
| Screenshot visible in CMS panel | Tabled |
| Playlist history in CMS panel | Tabled |
| Bulk deployment (env-var mode) | Planned |
