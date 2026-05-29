#!/usr/bin/env python3
VERSION = "1.0.10"

def _runtime_version() -> str:
    """Return the installed release tag from version.txt if present, else VERSION."""
    import os, sys
    base = os.path.dirname(sys.executable if getattr(sys, 'frozen', False) else os.path.abspath(__file__))
    vfile = os.path.join(base, 'version.txt')
    try:
        with open(vfile) as _f:
            v = _f.read().strip()
        if v:
            return v
    except OSError:
        pass
    return VERSION

"""
Impact Cloud+ Desktop Player  –  Windows 10 / Linux desktop
Plays .vsn program files for LED sign displays.

Usage:
    python player.py                  # file picker dialog
    python player.py program.vsn      # direct launch
    python player.py program.vsn -w   # start windowed

Keys:
    ESC / Q      – quit
    F11          – toggle fullscreen
    F12          – settings overlay
    LEFT / RIGHT – prev / next page (manual)
    SPACE        – pause / resume page timer
    I            – toggle info HUD
"""

import sys, os, math, time, datetime, threading, io, re, json, queue as _queue, shutil, subprocess, socket, platform
import xml.etree.ElementTree as ET
from pathlib import Path
from dataclasses import dataclass, field, asdict
from typing import List, Optional, Tuple

# When running as a PyInstaller onefile exe, __file__ resolves to the temp
# extraction directory (_MEI*), not the install directory.  Every runtime
# path (config, fonts, logo, screenshots, downloads) must use _BASE_DIR so
# they land beside the exe in C:\ImpactLED\CloudPlayer\ instead of being
# lost in a throwaway temp folder.
_BASE_DIR = Path(sys.executable if getattr(sys, 'frozen', False)
                 else os.path.abspath(__file__)).parent

# Point requests and websocket-client at the bundled certifi CA store so SSL
# certificate verification works inside the PyInstaller exe on Windows.
try:
    import certifi as _certifi
    os.environ.setdefault('SSL_CERT_FILE',      _certifi.where())
    os.environ.setdefault('REQUESTS_CA_BUNDLE', _certifi.where())
except Exception:
    pass

import pygame

# ── optional deps ──────────────────────────────────────────────────────────────
try:
    from PIL import Image, ImageSequence
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False

try:
    import requests
    REQUESTS_AVAILABLE = True
except ImportError:
    REQUESTS_AVAILABLE = False

try:
    import feedparser
    FEEDPARSER_AVAILABLE = True
except ImportError:
    FEEDPARSER_AVAILABLE = False

try:
    import websocket as _websocket_lib
    WEBSOCKET_AVAILABLE = True
except ImportError:
    WEBSOCKET_AVAILABLE = False

try:
    import cv2
    CV2_AVAILABLE = True
except ImportError:
    CV2_AVAILABLE = False


# ══════════════════════════════════════════════════════════════════════════════
# Config  (persisted to player_config.json beside the script)
# ══════════════════════════════════════════════════════════════════════════════

CONFIG_PATH = _BASE_DIR / 'player_config.json'

@dataclass
class Config:
    width:       int   = 1920         # player window width  (px)
    height:      int   = 1080         # player window height (px)
    fullscreen:  bool  = True
    fit_mode:    str   = 'native'     # native | stretch | letterbox | crop
    fps:         int   = 30
    bar_color:   str   = '0xFF000000' # letterbox bar fill (ARGB hex)
    loop:        bool  = True         # restart from page 0 after last page
    show_hud:    bool  = False        # show program/page info overlay
    last_dir:    str   = ''           # remember last opened directory
    brightness:  int   = 100          # display brightness 0–100
    timezone:    str   = ''           # IANA timezone, e.g. 'America/New_York'
    locale_code: str   = ''           # locale string, e.g. 'en_US'
    # CMS cloud sync
    cms_enabled:  bool  = False
    cms_server:   str   = ''          # e.g. https://access.impactledsigns.com
    cms_username: str   = ''          # terminal ID
    cms_password: str   = ''          # secret
    cms_interval: int   = 30          # poll interval in seconds
    cms_dl_dir:   str   = ''          # download dir; blank = downloads/ beside player.py
    device_sn:    str   = ''          # Device SN – auto-generated on first run
    device_type:  str   = 'windows'   # windows | samsung | linux
    show_fps:     bool  = False       # show live FPS counter in bottom-right corner

    def save(self):
        try:
            CONFIG_PATH.write_text(json.dumps(asdict(self), indent=2))
        except Exception as e:
            print(f"[Config] save failed: {e}")

    @classmethod
    def load(cls) -> 'Config':
        cfg = cls()
        if CONFIG_PATH.exists():
            try:
                d = json.loads(CONFIG_PATH.read_text())
                cfg = cls(**{k: d[k] for k in d if k in cls.__dataclass_fields__})
            except Exception:
                pass
        if not cfg.device_sn:
            import random
            cfg.device_sn = 'CLCAPC' + ''.join(
                random.choices('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', k=6))
            cfg.save()
        return cfg


# Active timezone / locale (set at startup and on settings apply)
_player_timezone: str = ''
_player_locale:   str = ''


# ══════════════════════════════════════════════════════════════════════════════
# Layout math – returns (scale_x, scale_y, offset_x, offset_y)
# All content is rendered at: screen_pos = region_pos * scale + offset
# ══════════════════════════════════════════════════════════════════════════════

def compute_layout(prog_w: int, prog_h: int,
                   win_w: int,  win_h: int,
                   fit_mode: str) -> Tuple[float, float, int, int]:
    """
    native    – 1:1 pixels, top-left anchor; black fill around the content
    stretch   – fills the window exactly; origin always at (0,0)
    letterbox – uniform scale, black bars, content centred
    crop      – uniform scale to fill; content centred, edges clipped
    """
    if fit_mode == 'native':
        return 1.0, 1.0, 0, 0
    elif fit_mode == 'letterbox':
        s  = min(win_w / max(prog_w, 1), win_h / max(prog_h, 1))
        ox = int((win_w - prog_w * s) / 2)
        oy = int((win_h - prog_h * s) / 2)
        return s, s, ox, oy
    elif fit_mode == 'crop':
        s  = max(win_w / max(prog_w, 1), win_h / max(prog_h, 1))
        ox = int((win_w - prog_w * s) / 2)
        oy = int((win_h - prog_h * s) / 2)
        return s, s, ox, oy
    else:   # stretch
        sx = win_w / max(prog_w, 1)
        sy = win_h / max(prog_h, 1)
        return sx, sy, 0, 0


# ══════════════════════════════════════════════════════════════════════════════
# Colour / XML helpers
# ══════════════════════════════════════════════════════════════════════════════

def parse_color(s: str, default=(0, 0, 0, 255)) -> Tuple[int, int, int, int]:
    if not s:
        return default
    s = s.strip()
    try:
        if s.lower().startswith('0x'):
            val = int(s, 16)
        elif s.startswith('#'):
            h = s[1:]
            if len(h) == 6:
                return (int(h[0:2],16), int(h[2:4],16), int(h[4:6],16), 255)
            elif len(h) == 8:
                val = int(h, 16)
            else:
                return default
        else:
            val = int(s)
        a = (val >> 24) & 0xFF
        r = (val >> 16) & 0xFF
        g = (val >>  8) & 0xFF
        b =  val        & 0xFF
        return (r, g, b, a if a > 0 else 255)
    except (ValueError, TypeError):
        return default


def _find_child(elem, tag: str):
    if elem is None:
        return None
    child = elem.find(tag)
    if child is not None:
        return child
    tl = tag.lower()
    for ch in elem:
        if ch.tag.lower() == tl:
            return ch
    return None


def xt(elem, tag: str, default: str = '') -> str:
    ch = _find_child(elem, tag)
    return (ch.text or '').strip() if ch is not None else default

def xi(elem, tag: str, default: int = 0) -> int:
    try:    return int(xt(elem, tag, str(default)))
    except: return default

def xf(elem, tag: str, default: float = 0.0) -> float:
    try:    return float(xt(elem, tag, str(default)))
    except: return default


# ══════════════════════════════════════════════════════════════════════════════
# Data model
# ══════════════════════════════════════════════════════════════════════════════

@dataclass
class LogFont:
    height: int  = 32
    face:   str  = ''
    bold:   bool = False
    italic: bool = False
    uline:  bool = False

@dataclass
class FileSource:
    relative: bool = True
    path:     str  = ''

@dataclass
class FxEntry:
    type:  int  = 0
    ms:    int  = 500
    is_tr: bool = False

@dataclass
class Rect:
    x: int = 0;  y: int = 0
    w: int = 100; h: int = 100
    border_w:   int   = 0
    border_clr: Tuple = (255, 255, 0, 255)

@dataclass
class Item:
    type:        str   = '0'
    name:        str   = ''
    back_clr:    Tuple = (0,0,0,255)
    text_clr:    Tuple = (255,255,255,255)
    alpha:       float = 1.0
    duration:    int   = 5000
    text:        str   = ''
    font:        LogFont    = field(default_factory=LogFont)
    filesrc:     FileSource = field(default_factory=FileSource)
    in_fx:       FxEntry    = field(default_factory=FxEntry)
    out_fx:      FxEntry    = field(default_factory=FxEntry)
    scroll:         bool  = False
    scroll_by_time: bool  = False    # use time-based Speed instead of SpeedByFrame
    spd:            float = 2.0      # SpeedByFrame (px per frame unit)
    speed_px:       float = 0.0      # Speed in px/sec (time-based scroll)
    spd_by_frm:     bool  = True
    opacity_bg:     float = 1.0      # background opacity 0..1 (0 = transparent)
    head_tail:      bool  = True
    play_len:    int   = 30000
    center:      bool  = False
    multiline:   bool  = False
    move_type:   int   = 0
    analog:      bool  = False
    tz_off:      float = 0.0
    count_down:  bool  = True
    end_dt:      Optional[datetime.datetime] = None
    prefix:      str   = ''
    show_d: bool = True;  day_clr: Tuple = (255,255,255,255)
    show_h: bool = True;  hr_clr:  Tuple = (255,255,255,255)
    show_m: bool = True;  min_clr: Tuple = (255,255,255,255)
    show_s: bool = True;  sec_clr: Tuple = (255,255,255,255)
    region_name:  str  = ''
    region_code:  str  = ''
    fahrenheit:   bool = False
    show_weather: bool = True
    show_temp:    bool = True
    show_wind:    bool = True
    show_humid:   bool = True
    weather_pfx:  str  = ''
    temp_pfx:     str  = ''
    wind_pfx:     str  = ''
    humid_pfx:    str  = ''
    prevfix: str = ''
    suffix:  str = ''
    url:     str = ''
    base64_pages: List[str] = field(default_factory=list)

@dataclass
class Region:
    name:  str    = ''
    show:  bool   = True
    layer: int    = 1
    rect:  Rect   = field(default_factory=Rect)
    items: List[Item] = field(default_factory=list)

@dataclass
class Page:
    name:     str    = ''
    visible:  bool   = True
    bg_clr:   Tuple  = (0,0,0,255)
    duration: int    = 3600000
    loop:     int    = 1
    regions:  List[Region] = field(default_factory=list)

@dataclass
class Program:
    name:   str   = ''
    width:  int   = 1920
    height: int   = 1080
    pages:  List[Page] = field(default_factory=list)


# ══════════════════════════════════════════════════════════════════════════════
# VSN Parser
# ══════════════════════════════════════════════════════════════════════════════

def _parse_datetime(s: str) -> Optional[datetime.datetime]:
    if not s:
        return None
    m = re.match(r'(\d+)-(\d+)-(\d+)\s+(\d+):(\d+):(\d+)', s.strip())
    if m:
        try:
            return datetime.datetime(*[int(x) for x in m.groups()])
        except ValueError:
            pass
    return None

def _logfont(e) -> LogFont:
    lf = _find_child(e, 'LogFont')
    if lf is None:
        return LogFont()
    return LogFont(
        height = xi(lf, 'lfHeight', 32),
        face   = xt(lf, 'lfFaceName', ''),
        bold   = xi(lf, 'lfWeight', 400) >= 700,
        italic = xi(lf, 'lfItalic', 0) == 1,
        uline  = xi(lf, 'lfUnderline', 0) == 1,
    )

def _filesrc(e) -> FileSource:
    fs = _find_child(e, 'FileSource')
    if fs is None:
        return FileSource()
    return FileSource(
        relative = xi(fs, 'IsRelative', 0) == 1,
        path     = xt(fs, 'FilePath', ''),
    )

def _fx(e, tag: str) -> FxEntry:
    el = _find_child(e, tag)
    if el is None:
        return FxEntry()
    return FxEntry(
        type  = xi(el, 'Type', 0),
        ms    = xi(el, 'Time', 500),
        is_tr = xi(el, 'IsTran', 0) == 1,
    )

def _item(e) -> Item:
    raw_text = xt(e, 'Text', '').replace('&#xA;', '\n').replace('&#xa;', '\n')
    _bp_el = _find_child(e, 'base64Pages')
    _b64_pages: List[str] = []
    if _bp_el is not None:
        for _bpe in _bp_el.findall('base64Page'):
            _v = (_bpe.text or '').strip()
            if _v:
                _b64_pages.append(_v)
    _font     = _logfont(e)
    _text_clr = parse_color(xt(e, 'TextColor', '') or xt(e, 'ForeColor', '') or '0xFFFFFFFF')
    _dtclock  = _find_child(e, 'DigtalClock')
    if _dtclock is not None:
        _ft_size = xi(_dtclock, 'ftSize', 0)
        _ft_name = xt(_dtclock, 'Name', '')
        _ft_clr  = xt(_dtclock, 'ftColor', '')
        if _ft_size > 0 or _ft_name:
            _font = LogFont(height=_ft_size or _font.height, face=_ft_name or _font.face,
                            bold=xi(_dtclock, 'bBold', 0) == 1,
                            italic=xi(_dtclock, 'bItalic', 0) == 1,
                            uline=xi(_dtclock, 'bUnderline', 0) == 1)
        if _ft_clr:
            _text_clr = parse_color(_ft_clr)
    return Item(
        type       = xt(e, 'Type', '0'),
        name       = xt(e, 'Name', ''),
        back_clr   = parse_color(xt(e, 'BackColor',  '0xFF000000')),
        text_clr   = _text_clr,
        alpha      = xf(e, 'Opacity', xf(e, 'Alhpa', 1.0)),
        opacity_bg = xf(e, 'OpacityBg', 1.0),
        duration   = xi(e, 'Duration', 5000),
        text       = raw_text.strip(),
        font       = _font,
        filesrc    = _filesrc(e),
        in_fx      = _fx(e, 'inEffect'),
        out_fx     = _fx(e, 'outEffect'),
        scroll         = xi(e, 'IsScroll', 0) == 1,
        scroll_by_time = xi(e, 'IsScrollByTime', 0) == 1,
        spd            = xf(e, 'SpeedByFrame', 2.0),
        speed_px       = xf(e, 'Speed', 0.0),
        spd_by_frm     = xi(e, 'IfSpeedByFrame', 0) == 1,
        head_tail  = xi(e, 'IsHeadConnectTail', 1) == 1,
        play_len   = xi(e, 'PlayLenth', 30000),
        center     = (xi(e, 'centeralAlign', 0) or xi(e, 'CenteralAlign', 0)) == 1,
        multiline  = xi(e, 'IsMultiLine', 0) == 1,
        move_type  = xi(e, 'MoveType', 0),
        analog     = xi(e, 'IsAnolog', 0) == 1,
        tz_off     = xf(e, 'TimeZone', 0.0),
        count_down = xi(e, 'BeToEndTime', 0) == 0,
        end_dt     = _parse_datetime(xt(e, 'EndDateTime', '')),
        prefix     = xt(e, 'Prefix', ''),
        show_d     = xi(e, 'IsShowDayCount', 1) == 1,
        day_clr    = parse_color(xt(e, 'DayCountColor',    '0xFFFFFFFF')),
        show_h     = xi(e, 'IsShowHourCount', 1) == 1,
        hr_clr     = parse_color(xt(e, 'HourCountColor',   '0xFFFFFFFF')),
        show_m     = xi(e, 'IsShowMinuteCount', 1) == 1,
        min_clr    = parse_color(xt(e, 'MinuteCountColor', '0xFFFFFFFF')),
        show_s     = xi(e, 'IsShowSecondCount', 1) == 1,
        sec_clr    = parse_color(xt(e, 'secondCountColor', '0xFFFFFFFF')),
        region_name  = xt(e, 'RegionName', ''),
        region_code  = xt(e, 'regionCode', ''),
        fahrenheit   = (xi(e,'IsFahrenheit',0) or xi(e,'bShowAsFahrenheit',0)) == 1,
        show_weather = xi(e, 'IsShowWeather',     1) == 1,
        show_temp    = xi(e, 'IsShowTemperature', 1) == 1,
        show_wind    = xi(e, 'IsShowWind',        1) == 1,
        show_humid   = xi(e, 'IsShowHumidity',    1) == 1,
        weather_pfx  = xt(e, 'WeatherPrefix',           ''),
        temp_pfx     = xt(e, 'TemperaturePrefix',        ''),
        wind_pfx     = xt(e, 'WindPrefix',               ''),
        humid_pfx    = xt(e, 'Humidity',                 ''),
        prevfix      = xt(e, 'prevfix', ''),
        suffix       = xt(e, 'suffix',  ''),
        url          = xt(e, 'Url',     ''),
        base64_pages = _b64_pages,
    )

def _region(e) -> Region:
    re_el = _find_child(e, 'Rect')
    rect  = Rect(
        x         = xi(re_el, 'X', 0),
        y         = xi(re_el, 'Y', 0),
        w         = xi(re_el, 'Width',  100),
        h         = xi(re_el, 'Height', 100),
        border_w  = xi(re_el, 'BorderWidth', 0),
        border_clr= parse_color(xt(re_el, 'BorderColor', '0xFFFFFF00')),
    ) if re_el is not None else Rect()
    items_el = _find_child(e, 'Items')
    items    = [_item(i) for i in items_el.findall('Item')] if items_el is not None else []
    return Region(
        name  = xt(e, 'Name', ''),
        show  = xi(e, 'Show', 1) == 1,
        layer = xi(e, 'Layer', 1),
        rect  = rect,
        items = items,
    )

def _page(e) -> Page:
    regions_el = _find_child(e, 'Regions')
    regions    = [_region(r) for r in regions_el.findall('Region')] \
                 if regions_el is not None else []
    # PlayOneTime is absent in most VSN files; fall back to the longest item
    # duration on the page so video/timer slides self-time correctly.
    dur = xi(e, 'PlayOneTime', 0)
    if dur <= 0:
        for reg in regions:
            for it in reg.items:
                if it.duration > dur:
                    dur = it.duration
    if dur <= 0:
        dur = 5000
    return Page(
        name     = xt(e, 'Name', ''),
        visible  = xi(e, 'VisibleOrNot', 1) == 1,
        bg_clr   = parse_color(xt(e, 'BgColor', '0xFF000000')),
        duration = dur,
        loop     = xi(e, 'LoopType', 1),
        regions  = regions,
    )

def _prog(e) -> Program:
    info     = _find_child(e, 'Information')
    pages_el = _find_child(e, 'Pages')
    pages    = [_page(p) for p in pages_el.findall('Page')] \
               if pages_el is not None else []
    return Program(
        name   = xt(e, 'Name', 'Program'),
        width  = xi(info, 'Width',  1920) if info is not None else 1920,
        height = xi(info, 'Height', 1080) if info is not None else 1080,
        pages  = pages,
    )

def parse_vsn(path: str) -> List[Program]:
    tree = ET.parse(path)
    root = tree.getroot()
    return [_prog(e) for e in root.findall('Program')]


# ══════════════════════════════════════════════════════════════════════════════
# Font cache
# ══════════════════════════════════════════════════════════════════════════════

_font_cache: dict = {}
_preferred_font_file: Optional[str] = None

# Logo cache – keyed by rendered height (int → Surface or None)
_logo_cache: dict = {}
_LOGO_PATH = _BASE_DIR / 'cloudpluslogoinvert.png'


def _get_logo(height: int) -> Optional[pygame.Surface]:
    """Return logo Surface scaled to *height* px, cached."""
    if height in _logo_cache:
        return _logo_cache[height]
    if not _LOGO_PATH.exists():
        _logo_cache[height] = None
        return None
    raw = _logo_cache.get('_raw')
    if raw is None:
        if PIL_AVAILABLE:
            try:
                img = Image.open(str(_LOGO_PATH)).convert('RGBA')
                raw = pygame.image.fromstring(img.tobytes(), img.size, 'RGBA')
            except Exception:
                pass
        if raw is None:
            try:
                raw = pygame.image.load(str(_LOGO_PATH)).convert_alpha()
            except Exception:
                _logo_cache[height] = None
                return None
        _logo_cache['_raw'] = raw
    scale = height / raw.get_height()
    w = max(1, int(raw.get_width() * scale))
    scaled = pygame.transform.smoothscale(raw, (w, height))
    _logo_cache[height] = scaled
    return scaled

_CJK_FONT_NAMES = [
    'microsoftyahei','msyh','simsun','nsimsun','simhei',
    'notosanscjksc','notosanscjk','wqycjkcomposite','droidhanssans',
]
_LATIN_FONT_NAMES = ['arial','tahoma','verdana','calibri','segoeui','helvetica']

# Local fonts folder – drop .ttf / .otf files here to make them available.
_FONT_DIR = _BASE_DIR / 'fonts'


def _find_best_font_file() -> Optional[str]:
    global _preferred_font_file
    if _preferred_font_file:
        return _preferred_font_file
    import glob
    dirs = ([r'C:\Windows\Fonts'] if sys.platform == 'win32'
            else ['/usr/share/fonts', os.path.expanduser('~/.fonts'),
                  '/usr/local/share/fonts'])
    pats = ['msyh.ttc','msyh.ttf','SimSun.ttc','simsun.ttc',
            'NotoSansCJK*.ttc','WenQuanYi*.ttf','DroidSansFallback.ttf']
    # Also check local fonts/ dir for CJK fallback files
    if _FONT_DIR.exists():
        dirs = [str(_FONT_DIR)] + dirs
    for d in dirs:
        for pat in pats:
            hits = glob.glob(os.path.join(d, '**', pat), recursive=True) or \
                   glob.glob(os.path.join(d, pat))
            if hits:
                _preferred_font_file = hits[0]
                return _preferred_font_file
    return None

# Cache: maps (full_stem_key, base_key) → file_path for every font file found.
# Rebuilt whenever _local_font_map is None (on startup or after cache clear).
_local_font_map: Optional[list] = None   # list of (full_norm, base_norm, path)

def _norm_face(s: str) -> str:
    """Normalise for matching: lowercase, strip all spaces/hyphens/underscores."""
    return re.sub(r'[\s\-_]', '', s.lower())

def _build_font_map():
    """Scan the fonts/ folder, return list of (full_norm, base_norm, path)."""
    entries = []
    for d in [_FONT_DIR]:
        if not d.exists():
            continue
        for f in sorted(d.iterdir()):
            if f.suffix.lower() not in ('.ttf', '.otf', '.ttc'):
                continue
            stem = f.stem   # e.g. "Zar-Mazar.46ca99bd4695f6cea074"
            full_norm = _norm_face(stem)
            # Strip the hash/version suffix: everything before the first '.'
            # e.g. "Zar-Mazar.46ca99bd4695f6cea074" → base "Zar-Mazar"
            base_norm = _norm_face(stem.split('.')[0])
            entries.append((full_norm, base_norm, str(f)))
    return entries

def _local_font_file(face: str) -> Optional[str]:
    """Return the best matching font file path for *face*, or None."""
    global _local_font_map
    if _local_font_map is None:
        _local_font_map = _build_font_map()
    if not face:
        return None
    norm = _norm_face(face)

    # Pass 1 – exact full stem match (e.g. file is literally "arial.ttf")
    for full, base, path in _local_font_map:
        if full == norm:
            return path

    # Pass 2 – base name (before any hash) matches face exactly
    # Handles "Zar-Mazar.46ca99bd4695f6cea074.ttf" → face "Zar-Mazar"
    for full, base, path in _local_font_map:
        if base == norm:
            return path

    # Pass 3 – base starts with face (e.g. face "Arial", file "Arial-Bold.hash")
    # or face starts with base (e.g. face "Arial Bold", file "Arial.hash")
    for full, base, path in _local_font_map:
        if base.startswith(norm) or norm.startswith(base):
            return path

    return None

def get_font(lf: LogFont, scale_y: float) -> pygame.font.Font:
    size = max(10, int(abs(lf.height) * scale_y))
    key  = (lf.face.lower(), size, lf.bold, lf.italic)
    if key in _font_cache:
        return _font_cache[key]
    font = None
    # 1. Local fonts/ directory – highest priority so custom/branded fonts win.
    if lf.face:
        ff = _local_font_file(lf.face)
        if ff:
            try:
                font = pygame.font.Font(ff, size)
            except Exception:
                pass
    # 2. System font by exact face name.
    if font is None and lf.face:
        try:
            font = pygame.font.SysFont(lf.face, size, bold=lf.bold, italic=lf.italic)
        except Exception:
            pass
    # 3. Generic system fallbacks.
    if font is None:
        for name in _CJK_FONT_NAMES + _LATIN_FONT_NAMES:
            try:
                f = pygame.font.SysFont(name, size, bold=lf.bold, italic=lf.italic)
                if f:
                    font = f; break
            except Exception:
                pass
    # 4. Best font file found on the system.
    if font is None:
        ff = _find_best_font_file()
        if ff:
            try:
                font = pygame.font.Font(ff, size)
            except Exception:
                pass
    if font is None:
        font = pygame.font.Font(None, size)
    _font_cache[key] = font
    return font

def ui_font(size: int = 20) -> pygame.font.Font:
    """Small font for UI overlays."""
    key = ('_ui_', size, False, False)
    if key not in _font_cache:
        f = None
        for name in _LATIN_FONT_NAMES:
            try:
                f = pygame.font.SysFont(name, size)
                break
            except Exception:
                pass
        _font_cache[key] = f or pygame.font.Font(None, size)
    return _font_cache[key]


# ══════════════════════════════════════════════════════════════════════════════
# File-path resolver
# ══════════════════════════════════════════════════════════════════════════════

def resolve_path(filesrc: FileSource, vsn_dir: str, vsn_stem: str) -> Optional[str]:
    if not filesrc.path:
        return None
    if filesrc.relative:
        rel = filesrc.path.replace('\\', '/')
        while rel.startswith('./') or rel.startswith('/'):
            rel = rel[2:] if rel.startswith('./') else rel[1:]
        basename = os.path.basename(rel)
        cands = [
            os.path.join(vsn_dir, rel),
            os.path.join(vsn_dir, vsn_stem + '.files', basename),
        ]
    else:
        basename = os.path.basename(filesrc.path.replace('\\', '/'))
        cands = [filesrc.path.replace('\\', '/')]
        for root, _, files in os.walk(vsn_dir):
            if basename in files:
                cands.append(os.path.join(root, basename))

    for c in cands:
        if os.path.exists(c):
            return c

    # Fuzzy fallback: search the .files folder for any file whose
    # stripped name matches (handles CMS hash-suffix mismatches).
    files_dir = os.path.join(vsn_dir, vsn_stem + '.files')
    if os.path.isdir(files_dir):
        # Strip CMS suffix pattern _<hex>_<digits> from both sides for comparison
        _sfx = re.compile(r'_[0-9a-fA-F]{6,32}_\d+(?=\.\w+$)')
        want = _sfx.sub('', basename)
        for fn in os.listdir(files_dir):
            if _sfx.sub('', fn) == want:
                return os.path.join(files_dir, fn)

    if os.path.isdir(files_dir):
        for fn in os.listdir(files_dir):
            if fn == basename:
                return os.path.join(files_dir, fn)

    return None


# ══════════════════════════════════════════════════════════════════════════════
# Weather fetcher
# ══════════════════════════════════════════════════════════════════════════════

class WeatherFetcher:
    _instances: dict = {}

    @classmethod
    def for_location(cls, name: str, code: str):
        key = name or code
        if key not in cls._instances:
            cls._instances[key] = cls(name, code)
        return cls._instances[key]

    def __init__(self, name: str, code: str):
        self.name = name; self.code = code
        self.data = {}
        self._lock   = threading.Lock()
        threading.Thread(target=self._loop, daemon=True).start()

    def _loop(self):
        while True:
            self._fetch(); time.sleep(1200)

    def _fetch(self):
        if not REQUESTS_AVAILABLE:
            return
        query = self.name or self.code
        if not query:
            return
        try:
            url  = f'https://wttr.in/{requests.utils.quote(query)}?format=j1'
            resp = requests.get(url, timeout=10)
            if resp.status_code == 200:
                j  = resp.json()
                cc = j['current_condition'][0]
                w0 = j['weather'][0]
                with self._lock:
                    self.data = {
                        'desc':    cc['weatherDesc'][0]['value'],
                        'temp_c':  cc['temp_C'],
                        'temp_f':  cc['temp_F'],
                        'humidity': cc['humidity'],
                        'windspd': cc['windspeedKmph'],
                        'winddir': cc['winddir16Point'],
                        'hi_c':    w0['maxtempC'],
                        'lo_c':    w0['mintempC'],
                    }
        except Exception:
            pass

    def get(self) -> dict:
        with self._lock:
            return dict(self.data)


# ══════════════════════════════════════════════════════════════════════════════
# RSS fetcher
# ══════════════════════════════════════════════════════════════════════════════

class RSSFetcher:
    _instances: dict = {}

    @classmethod
    def for_url(cls, url: str):
        if url not in cls._instances:
            cls._instances[url] = cls(url)
        return cls._instances[url]

    def __init__(self, url: str):
        # Strip CMS rendering-hint suffix: "...?type=rss&bgcolor=...&speed=..."
        self.url  = re.sub(r'\?type=rss.*$', '', url)
        self.text = ''
        self._lock = threading.Lock()
        threading.Thread(target=self._loop, daemon=True).start()

    def _loop(self):
        while True:
            self._fetch(); time.sleep(300)

    def _fetch(self):
        if not FEEDPARSER_AVAILABLE:
            return
        try:
            feed   = feedparser.parse(self.url)
            entries = feed.entries[:20]
            parts  = []
            for e in entries:
                title = getattr(e, 'title', '')
                desc  = getattr(e, 'summary', '') or getattr(e, 'description', '')
                # strip HTML tags from description
                desc  = re.sub(r'<[^>]+>', '', desc).strip()
                line  = title
                if desc:
                    line += ': ' + desc[:120]
                if line:
                    parts.append(line)
            with self._lock:
                self.text = '   ◆   '.join(parts) if parts else ''
        except Exception:
            pass

    def get(self) -> str:
        with self._lock:
            return self.text


# ══════════════════════════════════════════════════════════════════════════════
# CMS Cloud Client  (polls Impact cloud for VSN programs)
# ══════════════════════════════════════════════════════════════════════════════

_RE_CMS_SFX = re.compile(r'^(.+?)(?:_[0-9a-fA-F]{8,32}_\d+)?(\.\w+)$')

def _strip_cms_suffix(name: str) -> str:
    """Remove CMS-appended _<md5>_<size>: 'vid_abc123_10240.mp4' → 'vid.mp4'"""
    m = _RE_CMS_SFX.match(name)
    return (m.group(1) + m.group(2)) if m else name


class CMSClient:
    """
    Manages the full connection to the Impact CMS cloud server:
      • WebSocket heartbeat  → keeps the device showing as Online
      • Status push          → reports dimensions / current program to CMS
      • Program poll/download → fetches new VSN files and hot-reloads player
    """

    def __init__(self, cfg: 'Config', dl_dir: Path, vsn_q: '_queue.Queue'):
        self.cfg          = cfg
        self.dl_dir       = dl_dir
        self.vsn_q        = vsn_q
        self._stop        = threading.Event()
        self._seen: dict  = {}
        self.status       = 'starting…'
        self.last_err     = ''
        self._current_vsn = ''        # name of currently playing program
        self._force_queue  = False    # True during a WS-triggered sync
        self._last_force_t = 0.0     # monotonic time of last WS-forced sync

        # Screenshot support
        self._screenshot_event = threading.Event()   # set by WS, cleared after capture
        self._screenshot_png: Optional[bytes] = None # latest PNG bytes
        self._screenshot_lock  = threading.Lock()

        threading.Thread(target=self._ws_loop,     daemon=True).start()
        threading.Thread(target=self._status_loop,  daemon=True).start()
        threading.Thread(target=self._dl_loop,      daemon=True).start()
        threading.Thread(target=self._local_api_loop, daemon=True).start()

    def stop(self):
        self._stop.set()

    def update_now_playing(self, name: str):
        """Call from the player when a new VSN starts playing."""
        self._current_vsn = name
        try:
            self._report_status()
        except Exception:
            pass

    # ── WebSocket (keeps device shown as Online in CMS) ───────────────────────

    def _ws_loop(self):
        if not WEBSOCKET_AVAILABLE:
            print('[Cloud+ WS] websocket-client not installed – device will not show Online.')
            print('         Run:  pip install websocket-client --break-system-packages')
            return
        delays = [5, 10, 20, 30, 60, 120]
        attempt = 0
        while not self._stop.is_set():
            try:
                self._ws_connect()
                attempt = 0
                self._stop.wait(timeout=5)
            except Exception as exc:
                d = delays[min(attempt, len(delays) - 1)]
                attempt += 1
                print(f'[Cloud+ WS] {exc} – retry in {d}s')
                self._stop.wait(timeout=d)

    def _ws_connect(self):
        from urllib.parse import urlencode, urlparse
        parsed = urlparse(self.cfg.cms_server)
        host   = parsed.hostname
        scheme = 'wss' if parsed.scheme == 'https' else 'ws'
        qs     = urlencode({
            'username': self.cfg.cms_username,
            'password': self.cfg.cms_password,
            'sn':       self.cfg.device_sn,
            'url':      self.cfg.cms_server.rstrip('/'),
        })
        url = f"{scheme}://{host}:8443/ColorWebSocket/websocket/chat?{qs}"
        print(f'[Cloud+ WS] Connecting to {host}:8443 …')

        _hb_running = threading.Event()

        def on_open(ws):
            print('[Cloud+ WS] Connected – device is Online')
            self.status = 'online'
            _hb_running.set()
            def _heartbeat():
                while _hb_running.is_set() and not self._stop.is_set():
                    self._stop.wait(timeout=55)
                    if self._stop.is_set():
                        break
                    try:
                        ws.send(json.dumps({
                            'name':    self.cfg.cms_username,
                            'url':     self.cfg.cms_server,
                            'content': 'heartbeat',
                        }))
                    except Exception:
                        break
            threading.Thread(target=_heartbeat, daemon=True).start()

        def on_message(ws, msg):
            if msg == 'heartbeat':
                return
            try:
                data = json.loads(msg)
                cmds = data.get('data', [])
                if cmds:
                    print(f'[Cloud+ WS] RAW message: {json.dumps(data)[:400]}')
                for cmd in cmds:
                    self._handle_ws_command(cmd)
            except Exception as exc:
                print(f'[Cloud+ WS] message error: {exc}  raw={msg[:200]}')

        def on_close(ws, code, reason):
            _hb_running.clear()
            self.status = 'reconnecting…'
            print(f'[Cloud+ WS] Closed ({code})')

        def on_error(ws, err):
            print(f'[Cloud+ WS] Error: {err}')

        _sslopt = {}
        try:
            import certifi as _c
            _sslopt = {'ca_certs': _c.where()}
        except Exception:
            pass
        _websocket_lib.WebSocketApp(
            url,
            on_open=on_open,
            on_message=on_message,
            on_close=on_close,
            on_error=on_error,
        ).run_forever(sslopt=_sslopt)

    def _handle_ws_command(self, cmd: dict):
        raw_field = cmd.get('content', {}).get('raw', '')
        content   = raw_field if isinstance(raw_field, str) else str(raw_field)
        api       = (cmd.get('author_url', '') or '').lower()

        # Parse JSON content once up front
        content_obj: dict = {}
        try:
            parsed = json.loads(content)
            if isinstance(parsed, dict):
                content_obj = parsed
        except Exception:
            pass

        # ── Route by author_url (the CMS's command type indicator) ────────────

        # Screenshot: api/screenshot
        if 'screenshot' in api:
            print('[Cloud+ WS] Screenshot requested')
            self._screenshot_event.set()
            return

        # Brightness: api/brightness (not brightcurve)
        if 'brightness' in api and 'brightcurve' not in api:
            raw_val = (content_obj.get('brightness')
                       if content_obj else None)
            if raw_val is None:
                m = re.search(r'\bbrightness\s*[:\s]\s*(\d+)', content, re.IGNORECASE)
                if m:
                    raw_val = int(m.group(1))
            if raw_val is not None:
                val = max(0, min(100, round(int(raw_val) * 100 / 255)))
                self.cfg.brightness = val
                self.cfg.save()
                print(f'[Cloud+ WS] Brightness → {val}%  (raw={raw_val})')
            return

        # Brightcurve / colortemp settings push — acknowledge, nothing to apply locally
        if 'brightcurve' in api or 'colortemp' in api:
            return

        # VSN / program play command: api/vsns, api/program, api/play
        if any(x in api for x in ('vsn', 'program', 'play')):
            play_name = (content_obj.get('play')
                         or content_obj.get('program')
                         or content_obj.get('name'))
            if play_name:
                stem = Path(play_name).stem
                for candidate in (self.dl_dir / play_name,
                                  self.dl_dir / (stem + '.vsn')):
                    if candidate.exists():
                        print(f'[Cloud+ WS] Playing local: {candidate.name}')
                        try:
                            self.vsn_q.put_nowait((candidate, False))
                        except _queue.Full:
                            pass
                        return
                print(f'[Cloud+ WS] Program "{play_name}" not cached – syncing…')
            self._ws_sync()
            return

        # Config / FTP sync: transmission/ftp/config — trigger a program sync
        if any(x in api for x in ('ftp', 'sync', 'reload', 'update', 'dirty')):
            self._ws_sync()
            return

        # Fallback: scan content text for legacy keyword-based commands
        cl = content.lower()
        if any(kw in cl for kw in ('dirty', 'update', 'reload', 'refresh')):
            self._ws_sync()

    def _ws_sync(self):
        """Trigger a debounced program sync from a WebSocket command."""
        now = time.monotonic()
        if now - self._last_force_t < 30.0:
            return
        self._last_force_t = now
        print('[Cloud+ WS] Syncing programs…')
        self._force_queue = True
        try:
            self._sync()
        except Exception as exc:
            print(f'[Cloud+ WS] sync error: {exc}')
        finally:
            self._force_queue = False

    def deliver_screenshot(self, png_bytes: bytes):
        """Called from main thread after capturing the pygame screen."""
        with self._screenshot_lock:
            self._screenshot_png = png_bytes
        self._screenshot_event.clear()
        print(f'[Screenshot] Captured {len(png_bytes)} bytes – uploading…')
        threading.Thread(target=self._upload_screenshot,
                         args=(png_bytes,), daemon=True).start()

    def _upload_screenshot(self, png_bytes: bytes):
        if not REQUESTS_AVAILABLE:
            return
        server = self.cfg.cms_server.rstrip('/')
        url    = f'{server}/wp-json/led/flowfee/v2/screenshot'
        try:
            r = requests.post(
                url,
                headers=self._auth(),
                files={'image': ('screenshot.png', png_bytes, 'image/png')},
                data={'sn': self.cfg.device_sn,
                      'time': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')},
                timeout=30,
            )
            print(f'[Screenshot] → {r.status_code}  {r.text[:80]}')
        except Exception as exc:
            print(f'[Screenshot] Upload failed: {exc}')

    # ── Status reporting (CMS shows device info + dimensions) ─────────────────

    def _status_loop(self):
        self._stop.wait(timeout=5)   # let WS connect first
        while not self._stop.is_set():
            try:
                self._report_status()
            except Exception:
                pass
            self._stop.wait(timeout=60)

    def _local_vsn_list(self) -> list:
        """Return vsns.contents in Colorlight grouped format: [{type, content:[{name,size,md5,publishedmd5}]}]."""
        items = []
        try:
            for f in sorted(self.dl_dir.iterdir()):
                if f.suffix.lower() == '.vsn':
                    try:
                        size = f.stat().st_size
                    except OSError:
                        size = 0
                    items.append({'name': f.name, 'size': size, 'md5': '', 'publishedmd5': ''})
        except Exception:
            pass
        return [{'type': 'internet', 'content': items}] if items else []

    @staticmethod
    def _local_ip() -> str:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(('8.8.8.8', 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except Exception:
            return '0.0.0.0'

    def _report_status(self):
        if not REQUESTS_AVAILABLE:
            return
        server = self.cfg.cms_server.rstrip('/')
        headers = {**self._auth(), 'Content-Type': 'application/json'}
        vsn_name = self._current_vsn
        now = int(time.time())

        # Brightness: internal 0-100 → Colorlight 0-255
        brightness_cl = int(self.cfg.brightness * 255 / 100)

        # Disk usage for storage field
        try:
            du = shutil.disk_usage(self.cfg.cms_dl_dir or str(Path.home()))
            storage_total = du.total // 1024
            storage_free  = du.free  // 1024
        except Exception:
            storage_total = storage_free = 0

        playing_name = (vsn_name + '.vsn') if vsn_name else ''

        # Resolve IANA timezone ID — the CMS rejects 'UTC', needs a real zone name
        tz_id = self.cfg.timezone or ''
        if not tz_id:
            try:
                tz_id = subprocess.check_output(
                    ['timedatectl', 'show', '--property=Timezone', '--value'],
                    text=True, stderr=subprocess.DEVNULL).strip()
            except Exception:
                pass
        if not tz_id:
            try:
                with open('/etc/timezone') as _f:
                    tz_id = _f.read().strip()
            except Exception:
                pass
        if not tz_id:
            tz_id = 'America/Chicago'

        local_ip = self._local_ip()
        body = {
            'terminal': {
                'name':           self.cfg.device_sn,
                'leddescription': f'{self.cfg.width}x{self.cfg.height}',
                'localip':        local_ip,
                'port':           8989,
                '_report_time':   now,
            },
            'powerstatus': {
                'powerstatus':  1,       # 1 = Awake
                '_report_time': now,
            },
            'info': {
                'info': {
                    'vername':  '1.0',
                    'serialno': self.cfg.device_sn,
                    'model':    'VSNPlayer',
                    'mem':      {'total': 0, 'free': 0},
                    'storage':  {'total': storage_total, 'free': storage_free},
                    'playing':  {'name': playing_name, 'path': '', 'source': 'local'},
                },
                '_report_time': now,
            },
            'vsns': {
                'contents':     self._local_vsn_list(),
                'playing':      {'name': playing_name, 'type': 'internet'},
                '_report_time': now,
            },
            'dimension': {
                'fps':          self.cfg.fps,
                'real_width':   self.cfg.width,
                'real_height':  self.cfg.height,
                'width':        self.cfg.width,
                'height':       self.cfg.height,
                '_report_time': now,
            },
            'brightnessandcolortemp': {
                'brightness':       brightness_cl,
                'colortemperature': 4100,
                '_report_time':     now,
            },
            'volume': {
                'musicvolume':  50,
                '_report_time': now,
            },
            'newrtc': {
                'time':         datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
                'timezoneId':   tz_id,
                'timezone':     -time.timezone // 3600,
                'isautotime':   1,
                '_report_time': now,
            },
            'brightcurve': {
                'auto':                          0,
                'isNewBrightness':               1,
                'maxPercent':                    100,
                'minPercent':                    0,
                'midPercent':                    50,
                'maxAdjustValue':                100,
                'minAdjustValue':                0,
                'midAdjustValue':                50,
                'maxOriginalValue':              0,
                'minOriginalValue':              0,
                'sensorErrorDefaultValue':       0,
                'sensorSource485':               0,
                'sensorSourceMultifunctionCard': 0,
                'sensitivity':                   0,
                'method':                        0,
                'save':                          0,
                'noneReverseGammaValues':        [55705],
                'reverseGammaValues':            [61410],
                '_report_time':                  now,
            },
            'allbrightnessinfo': {
                'isHasSensor':                   False,
                'sensorBright':                  -2,
                'savedBrightValue':              brightness_cl,
                'realTimeBrightValue':           brightness_cl,
                'isbShowOn':                     True,
                'sensorSource485':               0,
                'sensorSourceMultifunctionCard': 0,
                'briAndClrTAdjustType':          1,
                '_report_time':                  now,
            },
            'reportswitch': {
                'complete_screen_status_report':        'on',
                'rotate_program_screenshot_report':     'off',
                'log_report':                           'off',
                'not_rotate_program_screenshot_report': 'on',
                'auto_info_report':                     'on',
                'manual_info_report':                   'on',
                'manual_vsns_report':                   'on',
                'command_screenshot_report':            'on',
                'auto_vsns_report':                     'on',
                'rotate_program_vsns_report':           'off',
                '_report_time':                         now,
            },
            'brightnessversion': {'isNewBrightness': 1, '_report_time': now},
            'cmdinterval':       {'command_interval': 5000, '_report_time': now},
        }

        url = f"{server}/wp-json/screen/v1/status"
        try:
            resp = requests.put(url, headers=headers, json=body, timeout=15)
            print(f'[Cloud+] Status PUT → {resp.status_code}  {resp.text[:200]}')
            self._apply_brightness_from_response(resp)
        except Exception as e:
            print(f'[Cloud+] Status PUT failed: {e}')

        # Report playback to the content/flowfee endpoint if a program is playing
        if vsn_name:
            try:
                requests.post(
                    f"{server}/wp-json/led/flowfee/v2/program",
                    headers=headers,
                    json={'name': vsn_name, 'vsn': vsn_name + '.vsn',
                          'status': 'playing'},
                    timeout=10,
                )
            except Exception:
                pass

    def _apply_brightness_from_response(self, resp):
        try:
            data = resp.json()
            if not isinstance(data, dict):
                return
            val = None
            # Colorlight schema: brightnessandcolortemp.brightness (0-255)
            bct = data.get('brightnessandcolortemp') or {}
            if isinstance(bct, dict) and bct.get('brightness') is not None:
                raw = int(bct['brightness'])
                # Convert 0-255 → 0-100
                val = max(0, min(100, round(raw * 100 / 255)))
            # Fallbacks for other possible response shapes
            if val is None:
                for candidate in (
                    data.get('brightness'),
                    (data.get('powerstatus') or {}).get('brightness'),
                    (data.get('settings') or {}).get('brightness'),
                ):
                    if candidate is not None:
                        val = max(0, min(100, int(candidate)))
                        break
            if val is not None and val != self.cfg.brightness:
                self.cfg.brightness = val
                self.cfg.save()
                print(f'[Cloud+] Brightness ← {val}% (from Cloud+ response)')
        except Exception:
            pass

    # ── Local HTTP API (Player API, port 8989) ────────────────────────────────

    def _local_api_loop(self):
        """Exposes a local HTTP server so the CMS can read/set player state."""
        import http.server, zlib, struct

        def _make_placeholder_png():
            def _chunk(tag, data):
                raw = tag + data
                return struct.pack('>I', len(data)) + raw + struct.pack('>I', zlib.crc32(raw) & 0xFFFFFFFF)
            return (
                b'\x89PNG\r\n\x1a\n'
                + _chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0))
                + _chunk(b'IDAT', zlib.compress(b'\x00\x00\x00\x00'))
                + _chunk(b'IEND', b'')
            )

        _PLACEHOLDER_PNG = _make_placeholder_png()
        client = self

        class _Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass  # silence per-request log spam

            def _send_json(self, obj, status=200):
                body = json.dumps(obj).encode()
                self.send_response(status)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                self.send_header('Access-Control-Allow-Origin', '*')
                self.send_header('Access-Control-Allow-Headers', 'Content-Type,Authorization')
                self.end_headers()
                self.wfile.write(body)

            def _send_image(self, data, ctype='image/png'):
                self.send_response(200)
                self.send_header('Content-Type', ctype)
                self.send_header('Content-Length', str(len(data)))
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(data)

            def do_OPTIONS(self):
                self.send_response(204)
                self.send_header('Access-Control-Allow-Origin', '*')
                self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, OPTIONS')
                self.send_header('Access-Control-Allow-Headers', 'Content-Type,Authorization')
                self.end_headers()

            def do_GET(self):
                p = self.path.split('?')[0]
                if p in ('/api/brightness', '/api/brightness.json'):
                    b_cl = int(client.cfg.brightness * 255 / 100)
                    self._send_json({'code': 0, 'data': {
                        'brightness': b_cl,
                        'colortemperature': 4100,
                    }})
                elif p in ('/api/info.json', '/api/info'):
                    self._send_json({'code': 0, 'data': {
                        'vername':  '1.0',
                        'serialno': client.cfg.device_sn,
                        'model':    'VSNPlayer',
                    }})
                elif p in ('/api/powerstatus.json', '/api/powerstatus'):
                    self._send_json({'code': 0, 'data': {'powerstatus': 1}})
                elif p.startswith('/api/sensor'):
                    self._send_json({'code': 0, 'data': {
                        'sensors': [],
                        'sensorErrorDefaultValue': 0,
                        'sensorList': [],
                    }})
                elif p in ('/api/vsns', '/api/vsns.json'):
                    self._send_json({'code': 0, 'data': {
                        'contents': client._local_vsn_list(),
                        'playing':  {'name': client._current_vsn or '', 'type': 'internet'},
                    }})
                elif p in ('/api/screenshot', '/api/screenshot.png'):
                    with client._screenshot_lock:
                        png = client._screenshot_png
                    if png:
                        self._send_image(png, 'image/png')
                    else:
                        self._send_json({'code': 404, 'msg': 'no screenshot yet'}, 404)
                elif p.startswith('/images/'):
                    # CMS requests program thumbnails at /images/{name}.files/{name}.jpeg
                    # Serve a 1x1 placeholder so the canvas doesn't crash with height=0
                    self._send_image(_PLACEHOLDER_PNG, 'image/png')
                else:
                    self._send_json({'code': 404, 'msg': 'not found'}, 404)

            def do_POST(self):
                p = self.path.split('?')[0]
                length = int(self.headers.get('Content-Length', 0) or 0)
                raw = self.rfile.read(length) if length else b'{}'
                try:
                    body = json.loads(raw)
                except Exception:
                    body = {}
                if p in ('/api/brightness', '/api/brightness.json'):
                    val = body.get('brightness')
                    if val is not None:
                        pct = max(0, min(100, round(int(val) * 100 / 255)))
                        client.cfg.brightness = pct
                        client.cfg.save()
                        print(f'[Local API] Brightness → {pct}%')
                    self._send_json({'code': 0, 'data': None})
                else:
                    self._send_json({'code': 404, 'msg': 'not found'}, 404)

            do_PUT = do_POST

        for port in (8989, 8080, 9090):
            try:
                srv = http.server.HTTPServer(('0.0.0.0', port), _Handler)
                print(f'[Local API] Listening on port {port}')
                while not self._stop.is_set():
                    srv.handle_request()
                return
            except OSError:
                continue
        print('[Local API] Could not bind to any port (8989, 8080, 9090)')

    # ── Program download loop ─────────────────────────────────────────────────

    def _dl_loop(self):
        # Wait for WS to come online before the first poll so that a WS-pushed
        # sync always takes priority over the startup scan.  Cap at 8 s so the
        # player still starts if the WS server is unreachable.
        deadline = time.monotonic() + 8.0
        while time.monotonic() < deadline and not self._stop.is_set():
            if self.status == 'online':
                break
            self._stop.wait(timeout=0.5)

        while not self._stop.is_set():
            try:
                self._sync()
            except Exception as exc:
                self.last_err = str(exc)
                if self.status != 'online':
                    self.status = 'error'
                print(f'[Cloud+] {exc}')
            self._stop.wait(timeout=max(15, self.cfg.cms_interval))

    def _auth(self) -> dict:
        import base64
        raw = f"{self.cfg.cms_username}:{self.cfg.cms_password}"
        return {'Authorization': 'Basic ' + base64.b64encode(raw.encode()).decode()}

    def _get(self, url: str, **kw):
        return requests.get(url, headers=self._auth(), timeout=20, **kw)

    def _sync(self):
        if not REQUESTS_AVAILABLE:
            self.status = 'requests lib missing'; return
        if not (self.cfg.cms_server and self.cfg.cms_username):
            self.status = 'not configured'; return

        server = self.cfg.cms_server.rstrip('/')
        if self.status != 'online':
            self.status = 'syncing…'

        sn = self.cfg.device_sn or ''

        # Pull device-level settings (brightness) from the CMS if the endpoint exists.
        try:
            sr = self._get(f"{server}/wp-json/screen/v1/settings"
                           + (f"?sn={sn}" if sn else ""))
            if sr.status_code == 200:
                self._apply_brightness_from_response(sr)
        except Exception:
            pass

        r = self._get(f"{server}/wp-json/wp/v2/programs?clt_type=terminal"
                      + (f"&sn={sn}" if sn else ""))
        r.raise_for_status()
        programs = r.json()
        if not isinstance(programs, list):
            self.status = 'bad server response'; return

        # Sort oldest-modified first so the most recently updated program is
        # processed last.  The main-loop queue drain always loads the last-queued
        # path, so the newest program wins when multiple are assigned.
        programs.sort(key=lambda p: p.get('modified', p.get('date', '')))

        # Collect vsn paths from all programs; only queue the final winner
        # after all HTTP calls complete so the main loop never sees a partial
        # sync (which caused a flash of the older playlist on startup).
        final_vsn:     Optional[Path] = None
        final_fetched: bool           = False
        for prog in programs:
            try:
                result = self._handle_program(server, prog)
                if result is not None:
                    final_vsn, final_fetched = result   # sorted oldest-first, newest wins
            except Exception as exc:
                print(f'[Cloud+] program skip: {exc}')

        if final_vsn is not None:
            try:
                self.vsn_q.put_nowait((str(final_vsn), final_fetched))
            except _queue.Full:
                pass

        if self.status != 'online':
            self.status = 'ok'

    def _handle_program(self, server: str, prog: dict) -> Optional[Path]:
        # Locate the media-attachment href from the program's links
        links = prog.get('_links', {})
        href  = None
        for key in ('wp:attachment', 'https://api.w.org/attachment'):
            lst = links.get(key, [])
            if lst:
                href = lst[0].get('href'); break
        if not href:
            return

        r = self._get(href)
        if r.status_code != 200:
            return
        media = r.json()
        if not isinstance(media, list):
            return

        vsn_entries   = [m for m in media if m.get('source_url', '').lower().endswith('.vsn')]
        other_entries = [m for m in media if not m.get('source_url', '').lower().endswith('.vsn')]

        vsn_path      = None
        changed       = False
        vsn_fetched   = False   # True only when we actually HTTP-downloaded the VSN

        # Only use the first VSN entry — WordPress returns attachments newest-first,
        # so taking entry [0] ensures we always load the most-recently uploaded VSN.
        # Processing multiple entries caused the last (oldest) to overwrite vsn_path.
        for entry in vsn_entries[:1]:
            url  = entry.get('source_url', '')
            size = int(entry.get('attachment_filesize', 0))
            name = _strip_cms_suffix(os.path.basename(url))
            dest = self.dl_dir / name
            key  = name

            # Fast path: already known and file is present — skip unless forced.
            if self._seen.get(key) == (url, size) and dest.exists() and not self._force_queue:
                vsn_path = dest
                continue

            # Decide whether the file actually needs re-downloading.
            # _seen is in-memory and empty on every startup, so a _seen miss alone
            # does not mean the file changed — the file may already be on disk.
            old_entry   = self._seen.get(key)
            url_changed = old_entry is not None and old_entry[0] != url
            existing_sz = dest.stat().st_size if dest.exists() else 0
            needs_dl    = url_changed or \
                          not (existing_sz > 0 and (size == 0 or existing_sz == size))

            if needs_dl:
                # URL or size changed — wipe stale media and fetch fresh copy.
                old_files_dir = self.dl_dir / (dest.stem + '.files')
                if old_files_dir.is_dir():
                    shutil.rmtree(old_files_dir, ignore_errors=True)
                    print(f'[Cloud+] Cleared stale media: {old_files_dir.name}')
                stale_keys = [k for k in self._seen if k.startswith(dest.stem + '/')]
                for k in stale_keys:
                    del self._seen[k]
                print(f'[Cloud+] ↓ {name}')
                self._dl(url, dest, size)
                vsn_fetched = True

            # Mark changed if content changed, force-push (re-evaluate active program),
            # or first detection in this session.
            # During force-push, vsn_fetched is set True so the player restarts at page 0
            # for whichever program wins as final_vsn.
            if needs_dl or self._force_queue or old_entry is None:
                changed    = True
                if self._force_queue:
                    vsn_fetched = True

            self._seen[key] = (url, size)
            vsn_path = dest

        if vsn_path is None:
            return

        # Media files → <progname>.files/ folder
        files_dir = self.dl_dir / (vsn_path.stem + '.files')
        files_dir.mkdir(parents=True, exist_ok=True)

        for entry in other_entries:
            url  = entry.get('source_url', '')
            size = int(entry.get('attachment_filesize', 0))
            # Keep the exact CMS filename – the VSN's FileSource references it verbatim.
            # Stripping the hash suffix would cause resolve_path() to fail the lookup.
            cms_name   = os.path.basename(url)
            clean_name = _strip_cms_suffix(cms_name)   # human-readable alias
            dest       = files_dir / cms_name
            key        = f"{vsn_path.stem}/{cms_name}"

            # Also save under the stripped name as a fallback alias
            alias = files_dir / clean_name

            # Fast path: already in cache and file exists
            if self._seen.get(key) == (url, size) and dest.exists():
                if not alias.exists() and cms_name != clean_name:
                    try: alias.symlink_to(dest)
                    except Exception: pass
                continue

            # Check disk state — same as VSN logic: avoid re-queuing on startup
            # when _seen is empty but the file is already correctly on disk.
            existing_sz  = dest.stat().st_size if dest.exists() else 0
            media_needs_dl = not (existing_sz > 0 and (size == 0 or existing_sz == size))

            if not media_needs_dl:
                # File is correct on disk; just warm the cache and ensure alias
                self._seen[key] = (url, size)
                if not alias.exists() and cms_name != clean_name:
                    try: alias.symlink_to(dest)
                    except Exception: pass
                continue

            print(f'[Cloud+] ↓ media {cms_name}')
            try:
                self._dl(url, dest, size)
                self._seen[key] = (url, size)
                changed = True
                # Create a clean-name alias so path resolution works either way
                if cms_name != clean_name and not alias.exists():
                    try: alias.symlink_to(dest)
                    except Exception:
                        shutil.copy2(dest, alias)
            except Exception as exc:
                print(f'[Cloud+] media {cms_name}: {exc}')

        return (vsn_path, vsn_fetched) if changed else None

    def _dl(self, url: str, dest: Path, expected: int = 0, force: bool = False):
        existing = dest.stat().st_size if dest.exists() else 0
        # Exact size match → already complete, skip (bypass when forced)
        if not force and existing > 0 and expected > 0 and existing == expected:
            return
        # Wrong size, outdated, or forced refresh → start fresh.
        if dest.exists():
            dest.unlink()
        r = requests.get(url, headers=self._auth(), timeout=60, stream=True)
        r.raise_for_status()
        with open(dest, 'wb') as fh:
            for chunk in r.iter_content(65536):
                fh.write(chunk)


# ══════════════════════════════════════════════════════════════════════════════
# Item Renderers
# ══════════════════════════════════════════════════════════════════════════════

class BaseRenderer:
    def __init__(self, item: Item, srect: pygame.Rect,
                 sx: float, sy: float, vsn_dir: str, vsn_stem: str):
        self.item     = item
        self.srect    = srect
        self.sx       = sx; self.sy = sy
        self.vsn_dir  = vsn_dir
        self.vsn_stem = vsn_stem
        self.font     = get_font(item.font, sy)
        self._t0      = time.monotonic()

    def render(self, surf: pygame.Surface): pass

    def _fill_bg(self, surf):
        ob = self.item.opacity_bg
        if ob <= 0:
            return
        r, g, b, _ = self.item.back_clr
        if ob >= 1.0:
            pygame.draw.rect(surf, (r, g, b), self.srect)
        else:
            tmp = pygame.Surface((self.srect.w, self.srect.h), pygame.SRCALPHA)
            tmp.fill((r, g, b, int(ob * 255)))
            surf.blit(tmp, self.srect.topleft)

    def _text_color(self):
        r, g, b, _ = self.item.text_clr
        return (r, g, b)

    def _render_centered(self, surf, text, color=(255,255,255)):
        try:
            ts = self.font.render(text, True, color)
            x  = self.srect.x + (self.srect.w - ts.get_width())  // 2
            y  = self.srect.y + (self.srect.h - ts.get_height()) // 2
            surf.blit(ts, (x, y))
        except Exception:
            pass


# ── Image / GIF ───────────────────────────────────────────────────────────────

class ImageRenderer(BaseRenderer):
    def __init__(self, *a, **kw):
        super().__init__(*a, **kw)
        self._frames:    List[pygame.Surface] = []
        self._durations: List[float] = []
        self._idx   = 0
        self._frame_t = time.monotonic()
        self._load()

    def _load(self):
        path = resolve_path(self.item.filesrc, self.vsn_dir, self.vsn_stem)
        if not path:
            return
        w, h = self.srect.w, self.srect.h
        if w <= 0 or h <= 0:
            return
        if PIL_AVAILABLE:
            try:
                img = Image.open(path)
                n   = getattr(img, 'n_frames', 1)
                for frame in (ImageSequence.Iterator(img) if n > 1 else [img]):
                    dur = frame.info.get('duration', 100)/1000.0 if n > 1 \
                          else self.item.duration/1000.0
                    f2  = frame.convert('RGBA').resize((w, h), Image.LANCZOS)
                    s   = pygame.image.fromstring(f2.tobytes(), f2.size, 'RGBA')
                    self._frames.append(s)
                    self._durations.append(max(0.04, dur))
                return
            except Exception as e:
                print(f"[Image] PIL {path}: {e}")
        try:
            s = pygame.image.load(path).convert_alpha()
            self._frames    = [pygame.transform.scale(s, (w, h))]
            self._durations = [self.item.duration / 1000.0]
        except Exception as e:
            print(f"[Image] pygame {path}: {e}")

    def render(self, surf):
        self._fill_bg(surf)
        if not self._frames:
            pygame.draw.rect(surf, (40, 40, 40), self.srect)
            self._render_centered(surf, f"[{self.item.name or 'file'}]", (160,160,160))
            return
        now = time.monotonic()
        if len(self._frames) > 1 and now - self._frame_t >= self._durations[self._idx]:
            self._idx     = (self._idx + 1) % len(self._frames)
            self._frame_t = now
        surf.blit(self._frames[self._idx], self.srect.topleft)


# ── Video ─────────────────────────────────────────────────────────────────────

class VideoRenderer(BaseRenderer):
    def __init__(self, *a, **kw):
        super().__init__(*a, **kw)
        self._cap           = None
        self._fps           = 25.0
        self._duration_ms   = 0        # actual video length in ms (0 = unknown)
        self._raw           = None     # latest decoded numpy frame
        self._raw_ver       = 0
        self._surf_ver      = -1
        self._frame         = None     # pygame.Surface blitted by render()
        self._lock          = threading.Lock()
        self._stop          = threading.Event()
        self._restart       = threading.Event()  # main thread → restart from frame 0
        self._last_render   = 0.0      # monotonic time of last render() call

        if CV2_AVAILABLE:
            path = resolve_path(self.item.filesrc, self.vsn_dir, self.vsn_stem)
            if path:
                try:
                    self._cap = cv2.VideoCapture(path)
                    self._fps = self._cap.get(cv2.CAP_PROP_FPS) or 25.0
                    fc = self._cap.get(cv2.CAP_PROP_FRAME_COUNT)
                    if fc > 0 and self._fps > 0:
                        self._duration_ms = int(fc / self._fps * 1000)
                    threading.Thread(target=self._decode_loop, daemon=True).start()
                except Exception as e:
                    print(f"[Video] {e}")

    def _decode_loop(self):
        """Background thread: decode frames at video FPS; restart on signal."""
        w, h   = self.srect.w, self.srect.h
        period = 1.0 / max(self._fps, 1.0)
        next_t = time.monotonic()
        finished = False

        while not self._stop.is_set():
            # If a restart was requested (page became active), seek to frame 0.
            if self._restart.is_set():
                self._cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                self._restart.clear()
                next_t   = time.monotonic()
                finished = False

            # When finished, idle until a restart signal arrives.
            if finished:
                self._restart.wait(timeout=0.05)
                continue

            sleep_t = next_t - time.monotonic()
            if sleep_t > 0:
                time.sleep(sleep_t)

            ok, frame = self._cap.read()
            if not ok:
                # Video finished — hold last frame; wait for restart signal.
                finished = True
                continue

            frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            frame = cv2.resize(frame, (w, h))
            with self._lock:
                self._raw     = frame
                self._raw_ver += 1

            next_t += period
            if next_t < time.monotonic() - period:
                next_t = time.monotonic()

    def preseed(self):
        """Signal the decode thread to seek to frame 0 now, while this page is
        off-screen, so the first frame is buffered and ready when we come back."""
        if self._cap is not None:
            self._restart.set()

    def render(self, surf):
        self._fill_bg(surf)
        if self._cap is None:
            pygame.draw.rect(surf, (20, 20, 60), self.srect)
            self._render_centered(surf, f"▶ {self.item.name or 'video'}", (120,180,255))
            return

        now = time.monotonic()
        # First render or page switch (> 0.5 s gap) → restart from frame 0.
        if self._last_render == 0.0 or (now - self._last_render > 0.5):
            self._restart.set()
        self._last_render = now

        with self._lock:
            raw = self._raw
            ver = self._raw_ver
        if raw is not None and ver != self._surf_ver:
            try:
                self._frame = pygame.image.frombuffer(
                    raw.tobytes(), (raw.shape[1], raw.shape[0]), 'RGB')
                self._surf_ver = ver
            except Exception as e:
                print(f"[Video] frame error: {e}")
        if self._frame:
            surf.blit(self._frame, self.srect.topleft)


# ── Text (single-line Type 4 / multi-line Type 5) ────────────────────────────

class TextRenderer(BaseRenderer):
    def __init__(self, *a, **kw):
        super().__init__(*a, **kw)
        self._scroll_px = 0.0
        self._last_t: Optional[float] = None  # set on first render so scroll starts at edge
        self._surf:  Optional[pygame.Surface] = None
        self._tw     = 0
        self._th     = 0
        self._build()

    def _wrap_line(self, text: str, max_width: int) -> List[str]:
        """Word-wrap a single paragraph line to fit within max_width pixels."""
        if not text:
            return ['']
        words = text.split(' ')
        lines: List[str] = []
        current = ''
        for word in words:
            test = (current + ' ' + word).strip() if current else word
            try:
                w = self.font.size(test)[0]
            except Exception:
                w = max_width + 1
            if w <= max_width or not current:
                current = test
            else:
                lines.append(current)
                current = word
        if current:
            lines.append(current)
        return lines or ['']

    def _build_from_b64(self):
        import base64 as _b64, io as _io
        for raw in self.item.base64_pages:
            if raw.startswith('data:'):
                raw = raw.split(',', 1)[1] if ',' in raw else raw
            try:
                data = _b64.b64decode(raw)
                if PIL_AVAILABLE:
                    from PIL import Image as _PILImage
                    img = _PILImage.open(_io.BytesIO(data)).convert('RGBA')
                    s = pygame.image.fromstring(img.tobytes(), img.size, 'RGBA')
                else:
                    s = pygame.image.load(_io.BytesIO(data)).convert_alpha()
                self._surf = s
                self._tw   = s.get_width()
                self._th   = s.get_height()
                return
            except Exception as exc:
                print(f'[Base64Page] {exc}')

    def _build(self, text: str = ''):
        # If the CMS pre-rendered this item as an image, use that directly.
        if self.item.base64_pages and not text:
            self._build_from_b64()
            return
        txt   = text or self.item.text or ''
        color = self._text_color()
        fh    = self.font.get_height()
        sw    = self.srect.w

        if self.item.type in ('4', '102') and not self.item.multiline:
            try:
                s = self.font.render(txt, True, color)
                self._surf = s; self._tw = s.get_width(); self._th = s.get_height()
            except Exception:
                pass
        else:
            # Word-wrap each hard paragraph line to the region width
            raw_lines = txt.split('\n') if txt else ['']
            lines: List[str] = []
            for raw in raw_lines:
                if sw > 0:
                    lines.extend(self._wrap_line(raw, sw))
                else:
                    lines.append(raw)
            if not lines:
                lines = ['']
            th     = fh * len(lines)
            canvas = pygame.Surface((max(sw, 1), max(th, 1)), pygame.SRCALPHA)
            canvas.fill((0, 0, 0, 0))
            for i, line in enumerate(lines):
                try:
                    ls = self.font.render(line, True, color)
                    lx = (sw - ls.get_width()) // 2 if self.item.center else 0
                    canvas.blit(ls, (lx, i * fh))
                except Exception:
                    pass
            self._surf = canvas; self._tw = sw; self._th = th

    def update_text(self, text: str):
        self._build(text)
        self._scroll_px = 0.0
        self._last_t    = None

    def render(self, surf):
        self._fill_bg(surf)
        if self._surf is None:
            return
        sr = self.srect

        if self.item.scroll:
            now = time.monotonic()
            if self._last_t is None:
                # First render: start exactly at the leading edge, no jump.
                self._last_t = now
            else:
                dt = now - self._last_t
                self._last_t = now
                if dt > 0.5:
                    # Page was hidden (> 500 ms gap) — restart from the edge.
                    self._scroll_px = 0.0
                else:
                    if self.item.scroll_by_time and self.item.speed_px > 0:
                        self._scroll_px += self.item.speed_px * dt
                    else:
                        self._scroll_px += self.item.spd * 25.0 * dt

        old_clip = surf.get_clip()
        surf.set_clip(sr)

        if self.item.type in ('4', '102') and not self.item.multiline:
            self._single(surf, sr)
        else:
            self._multi(surf, sr)

        surf.set_clip(old_clip)

    def _single(self, surf, sr):
        tw, th = self._tw, self._th
        # top-align within region (editor places text at region top by default);
        # if region is nearly the same height as the text, center for visual polish
        cy = sr.y if sr.h > th * 2 else sr.y + (sr.h - th) // 2
        if self.item.scroll:
            span   = tw + sr.w
            offset = int(self._scroll_px) % max(span, 1)
            x0     = sr.x + sr.w - offset if self.item.move_type != 1 \
                     else sr.x + offset - tw
            surf.blit(self._surf, (x0, cy))
            if self.item.head_tail:
                surf.blit(self._surf, (x0 + span, cy))
                surf.blit(self._surf, (x0 - span, cy))
        else:
            x = sr.x + (sr.w - tw) // 2 if self.item.center else sr.x
            surf.blit(self._surf, (x, cy))

    def _multi(self, surf, sr):
        tw, th = self._tw, self._th
        if self.item.scroll:
            span   = th + sr.h
            offset = int(self._scroll_px) % max(span, 1)
            y0     = sr.y + sr.h - offset if self.item.move_type != 2 \
                     else sr.y + offset - th
            surf.blit(self._surf, (sr.x, y0))
            if self.item.head_tail:
                surf.blit(self._surf, (sr.x, y0 + span))
                surf.blit(self._surf, (sr.x, y0 - span))
        else:
            # Center vertically when the text block is shorter than the region.
            y0 = sr.y + (sr.h - th) // 2 if th < sr.h else sr.y
            surf.blit(self._surf, (sr.x, y0))


# ── Clock (Type 9) ────────────────────────────────────────────────────────────

class ClockRenderer(BaseRenderer):
    def _local_now(self) -> datetime.datetime:
        if self.item.tz_off != 0.0:
            return datetime.datetime.utcnow() + datetime.timedelta(hours=self.item.tz_off)
        if _player_timezone:
            try:
                try:
                    from zoneinfo import ZoneInfo
                except ImportError:
                    from backports.zoneinfo import ZoneInfo  # type: ignore
                return datetime.datetime.now(tz=ZoneInfo(_player_timezone)).replace(tzinfo=None)
            except Exception:
                pass
        return datetime.datetime.now()

    def render(self, surf):
        self._fill_bg(surf)
        now   = self._local_now()
        color = self._text_color()
        sr    = self.srect
        if self.item.analog:
            self._analog(surf, sr, now)
        else:
            self._digital(surf, sr, now, color)

    def _digital(self, surf, sr, now, color):
        fh    = self.font.get_height()
        lines = []
        fixed = self.item.text or self.item.prefix
        if fixed:
            lines.append(fixed)
        lines += [now.strftime('%H:%M:%S'), now.strftime('%Y-%m-%d'), now.strftime('%A')]
        total = fh * len(lines)
        y0    = sr.y + (sr.h - total) // 2
        for i, line in enumerate(lines):
            try:
                ts = self.font.render(line, True, color)
                x  = sr.x + (sr.w - ts.get_width()) // 2
                surf.blit(ts, (x, y0 + i * fh))
            except Exception:
                pass

    def _analog(self, surf, sr, now):
        cx = sr.x + sr.w // 2
        cy = sr.y + sr.h // 2
        r  = min(sr.w, sr.h) // 2 - 4
        pygame.draw.circle(surf, (255, 255, 255), (cx, cy), r, 2)
        for i in range(12):
            ang = math.radians(i * 30 - 90)
            x0, y0 = int(cx+(r-6)*math.cos(ang)), int(cy+(r-6)*math.sin(ang))
            x1, y1 = int(cx+ r   *math.cos(ang)), int(cy+ r   *math.sin(ang))
            pygame.draw.line(surf, (200,200,200), (x0,y0), (x1,y1), 2)
        sec  = now.second + now.microsecond/1e6
        minu = now.minute + sec/60
        hr   = now.hour % 12 + minu/60
        def hand(ratio, length, color, width):
            ang = math.radians(ratio*360 - 90)
            ex, ey = int(cx+length*math.cos(ang)), int(cy+length*math.sin(ang))
            pygame.draw.line(surf, color, (cx,cy), (ex,ey), width)
        hand(hr/12,   r*0.55, (255,80,80),  3)
        hand(minu/60, r*0.75, (80,255,80),  2)
        hand(sec/60,  r*0.88, (80,180,255), 1)
        pygame.draw.circle(surf, (255,255,255), (cx,cy), 4)


# ── Timer (Type 15) ──────────────────────────────────────────────────────────

class TimerRenderer(BaseRenderer):
    def render(self, surf):
        self._fill_bg(surf)
        it    = self.item
        color = self._text_color()
        sr    = self.srect
        end   = it.end_dt or (datetime.datetime.now() + datetime.timedelta(days=1))
        now   = datetime.datetime.now()
        diff  = (end - now) if it.count_down else (now - end)
        secs  = max(0, int(diff.total_seconds()))
        d = secs // 86400
        h = (secs % 86400) // 3600
        m = (secs % 3600) // 60
        s = secs % 60
        parts = []
        if it.show_d: parts.append(f"{d}d")
        if it.show_h: parts.append(f"{h:02d}h")
        if it.show_m: parts.append(f"{m:02d}m")
        if it.show_s: parts.append(f"{s:02d}s")
        line = (it.prefix + '  ' if it.prefix else '') + ' '.join(parts)
        self._render_centered(surf, line, color)


# ── Weather (Type 14) ─────────────────────────────────────────────────────────

class WeatherRenderer(BaseRenderer):
    _PAGE_DUR = 3.0   # seconds per auto-page chunk

    def __init__(self, *a, **kw):
        super().__init__(*a, **kw)
        self._fetcher   = WeatherFetcher.for_location(self.item.region_name,
                                                       self.item.region_code)
        self._txt_rend  = None
        self._last_data = {}
        self._pages:    List[str] = []
        self._page_idx: int  = 0
        self._page_t:   float = 0.0

    def _build_parts(self, data) -> List[str]:
        it   = self.item
        if not data:
            return [f"{it.region_name or 'Weather'}: Loading…"]
        unit = '°F' if it.fahrenheit else '°C'
        temp = data.get('temp_f' if it.fahrenheit else 'temp_c', '--')
        parts: List[str] = []
        if it.show_weather: parts.append(f"{it.weather_pfx}{data.get('desc','--')}")
        if it.show_temp:    parts.append(f"{it.temp_pfx}{temp}{unit}")
        if it.show_wind:    parts.append(f"{it.wind_pfx}{data.get('windspd','--')}km/h")
        if it.show_humid:   parts.append(f"{it.humid_pfx}{data.get('humidity','--')}%")
        return parts or [f"{it.region_name or 'Weather'}: --"]

    def _make_pages(self, parts: List[str]) -> List[str]:
        """Fit as many parts as possible per page; overflow goes to the next page."""
        sw = self.srect.w
        sep = '   '
        full = sep.join(parts)
        # If everything fits on one line, no paging needed.
        try:
            if sw <= 0 or self.font.size(full)[0] <= sw:
                return [full]
        except Exception:
            return [full]
        # Pack parts greedily into pages.
        pages: List[str] = []
        cur = ''
        for part in parts:
            candidate = (cur + sep + part) if cur else part
            try:
                fits = self.font.size(candidate)[0] <= sw
            except Exception:
                fits = False
            if fits:
                cur = candidate
            else:
                if cur:
                    pages.append(cur)
                cur = part
        if cur:
            pages.append(cur)
        return pages if pages else [full]

    def render(self, surf):
        self._fill_bg(surf)
        data = self._fetcher.get()
        if data != self._last_data:
            self._last_data = data
            self._pages   = self._make_pages(self._build_parts(data))
            self._page_idx = 0
            self._page_t   = time.monotonic()
            self._txt_rend = None

        if not self._pages:
            self._render_centered(surf, 'Fetching weather…', (160,160,160))
            return

        # Advance auto-page when the current chunk has been shown long enough.
        now = time.monotonic()
        if len(self._pages) > 1 and (now - self._page_t) >= self._PAGE_DUR:
            self._page_idx = (self._page_idx + 1) % len(self._pages)
            self._page_t   = now
            if self._txt_rend is not None:
                self._txt_rend.update_text(self._pages[self._page_idx])

        text = self._pages[self._page_idx]
        if self._txt_rend is None:
            # Use item.scroll (IsScroll flag) directly — never derive scroll from
            # Speed, which for weather items is a data-refresh interval, not px/s.
            fake = Item(type='4', text=text, text_clr=self.item.text_clr,
                        back_clr=self.item.back_clr, font=self.item.font,
                        scroll=self.item.scroll,
                        scroll_by_time=self.item.scroll_by_time,
                        spd=self.item.spd or 2.0,
                        speed_px=self.item.speed_px if self.item.scroll else 0.0,
                        head_tail=True, center=self.item.center)
            self._txt_rend = TextRenderer(fake, self.srect, self.sx, self.sy,
                                          self.vsn_dir, self.vsn_stem)
        self._txt_rend.render(surf)


# ── RSS (URL / Type 27) ───────────────────────────────────────────────────────

class RSSRenderer(BaseRenderer):
    def __init__(self, *a, **kw):
        super().__init__(*a, **kw)
        url = self.item.url or ''
        self._fetcher  = RSSFetcher.for_url(url) if url else None
        self._txt_rend = None
        self._last_txt = None
        # Parse rendering hints from URL: ?type=rss&bgcolor=...&color=...&speed=...&size=...
        self._url_clr  = self.item.text_clr
        self._url_bg   = self.item.back_clr
        self._url_spd  = self.item.speed_px
        self._url_font = self.item.font
        m = re.search(r'\?type=rss(.*)$', url)
        if m:
            params = dict(p.split('=', 1) for p in m.group(1).lstrip('&').split('&') if '=' in p)
            if 'color'   in params: self._url_clr  = parse_color(params['color'])
            if 'bgcolor' in params: self._url_bg   = parse_color(params['bgcolor'])
            if 'speed'   in params:
                try: self._url_spd = float(params['speed'])
                except ValueError: pass
            if 'size'    in params:
                try:
                    sz = int(params['size'])
                    self._url_font = LogFont(height=sz, face=self.item.font.face,
                                             bold=self.item.font.bold, italic=self.item.font.italic)
                except ValueError: pass

    def render(self, surf):
        self._fill_bg(surf)
        txt = self._fetcher.get() if self._fetcher else self.item.text
        if txt != self._last_txt:
            self._last_txt = txt
            _scroll_by_time = self._url_spd > 0
            fake = Item(type='4', text=txt or 'RSS: Loading…',
                        text_clr=self._url_clr, back_clr=self._url_bg,
                        font=self._url_font,
                        scroll=self.item.scroll,
                        scroll_by_time=_scroll_by_time,
                        spd=self.item.spd or 2.0, speed_px=self._url_spd,
                        head_tail=True)
            if self._txt_rend is None:
                self._txt_rend = TextRenderer(fake, self.srect, self.sx, self.sy,
                                              self.vsn_dir, self.vsn_stem)
            else:
                self._txt_rend.update_text(txt)
        if self._txt_rend:
            self._txt_rend.render(surf)

# ── Sensor placeholders (Types 21-29) ─────────────────────────────────────────

_SENSOR_LABELS = {'21':'Temperature','22':'Humidity','23':'Noise',
                  '24':'Air Quality','25':'CO₂','26':'PM2.5',
                  '28':'Smoke','29':'Sensor'}

class SensorRenderer(BaseRenderer):
    def render(self, surf):
        self._fill_bg(surf)
        label = self.item.prevfix or _SENSOR_LABELS.get(self.item.type, 'Sensor')
        self._render_centered(surf, f"{label}  – –  {self.item.suffix}", self._text_color())

class SyncRenderer(BaseRenderer):
    def render(self, surf):
        self._fill_bg(surf)
        pygame.draw.rect(surf, (20,60,20), self.srect, 2)
        self._render_centered(surf, '⟳ Sync Play', (100,200,100))

class WebRenderer(BaseRenderer):
    _REFRESH = 30.0

    def __init__(self, *a, **kw):
        super().__init__(*a, **kw)
        self._surf = None
        self._lock = threading.Lock()
        self._chrome = self._find_chrome()
        if self._chrome:
            threading.Thread(target=self._loop, daemon=True).start()

    def _find_chrome(self):
        for cmd in ('chromium-browser', 'chromium', 'google-chrome', 'google-chrome-stable'):
            try:
                subprocess.run([cmd, '--version'], capture_output=True, timeout=5)
                return cmd
            except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
                continue
        return None

    def _loop(self):
        while True:
            self._take_screenshot()
            time.sleep(self._REFRESH)

    def _take_screenshot(self):
        import tempfile
        tmp = None
        try:
            with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as f:
                tmp = f.name
            args = [
                self._chrome,
                '--headless', '--disable-gpu', '--no-sandbox',
                f'--screenshot={tmp}',
                f'--window-size={self.srect.w},{self.srect.h}',
                '--hide-scrollbars',
                self.item.url,
            ]
            subprocess.run(args, capture_output=True, timeout=30)
            if os.path.exists(tmp) and os.path.getsize(tmp) > 0:
                if PIL_AVAILABLE:
                    from PIL import Image as _PIL
                    img = _PIL.open(tmp).convert('RGBA')
                    s = pygame.image.fromstring(img.tobytes(), img.size, 'RGBA')
                else:
                    s = pygame.image.load(tmp).convert_alpha()
                if s.get_size() != (self.srect.w, self.srect.h):
                    s = pygame.transform.scale(s, (self.srect.w, self.srect.h))
                with self._lock:
                    self._surf = s
        except Exception as exc:
            print(f'[WebRenderer] {exc}')
        finally:
            if tmp:
                try:
                    os.unlink(tmp)
                except Exception:
                    pass

    def render(self, surf):
        self._fill_bg(surf)
        with self._lock:
            s = self._surf
        if s:
            surf.blit(s, self.srect.topleft)
        else:
            self._render_centered(surf, self.item.url, (120, 140, 220))


class PlaceholderRenderer(BaseRenderer):
    def render(self, surf):
        self._fill_bg(surf)
        pygame.draw.rect(surf, (60,30,30), self.srect, 1)
        self._render_centered(surf, f"[Type {self.item.type}]", (160,120,120))


# ══════════════════════════════════════════════════════════════════════════════
# Renderer factory
# ══════════════════════════════════════════════════════════════════════════════

def make_renderer(item: Item, srect: pygame.Rect,
                  sx: float, sy: float, vsn_dir: str, vsn_stem: str) -> BaseRenderer:
    args = (item, srect, sx, sy, vsn_dir, vsn_stem)
    t    = item.type
    if   t in ('1','2'):            return ImageRenderer(*args)
    elif t == '3':                  return VideoRenderer(*args)
    elif t in ('4','102'):          return TextRenderer(*args)
    elif t == '5':                  return TextRenderer(*args)
    elif t == '9':                  return ClockRenderer(*args)
    elif t == '14':                 return WeatherRenderer(*args)
    elif t == '15':                 return TimerRenderer(*args)
    elif t == '16':                 return SyncRenderer(*args)
    elif t in ('21','22','23','24','25','26','28','29'):
                                    return SensorRenderer(*args)
    elif t == '27':
        u = item.url
        if 'type=rss' in u or '/rss' in u or '/feed' in u or u.endswith('.xml') or u.endswith('.rss'):
            return RSSRenderer(*args)
        return WebRenderer(*args)
    elif item.url.startswith('http'):  return RSSRenderer(*args)
    else:                           return PlaceholderRenderer(*args)


# ══════════════════════════════════════════════════════════════════════════════
# Region state  (holds active item + renderer, now with layout offset)
# ══════════════════════════════════════════════════════════════════════════════

class RegionState:
    def __init__(self, region: Region,
                 sx: float, sy: float, ox: int, oy: int,
                 vsn_dir: str, vsn_stem: str):
        self.region   = region
        r             = region.rect
        # All coordinates start from (ox, oy) so the program's (0,0)
        # always maps to the configured origin on screen.
        self.srect    = pygame.Rect(
            int(r.x * sx) + ox,
            int(r.y * sy) + oy,
            max(1, int(r.w * sx)),
            max(1, int(r.h * sy)),
        )
        self._idx     = 0
        self._item_t  = time.monotonic()
        self._rends: List[BaseRenderer] = [
            make_renderer(it, self.srect, sx, sy, vsn_dir, vsn_stem)
            for it in region.items
        ]
        self._sx      = sx; self._sy = sy
        self._ox      = ox; self._oy = oy
        self._bw      = max(0, int(r.border_w * min(sx, sy)))

    def _advance(self):
        if not self.region.items:
            return
        now = time.monotonic()
        if now - self._item_t >= self.region.items[self._idx].duration / 1000.0:
            self._idx    = (self._idx + 1) % len(self.region.items)
            self._item_t = now

    def render(self, surf: pygame.Surface):
        if not self.region.show or not self._rends:
            return
        self._advance()
        self._rends[self._idx].render(surf)
        if self._bw > 0:
            r, g, b, _ = self.region.rect.border_clr
            pygame.draw.rect(surf, (r, g, b), self.srect, self._bw)


def build_page_regions(pages, sx, sy, ox, oy, vsn_dir, vsn_stem):
    result = []
    for page in pages:
        rs = [RegionState(r, sx, sy, ox, oy, vsn_dir, vsn_stem)
              for r in sorted(page.regions, key=lambda rr: rr.layer)]
        result.append(rs)
        # Override page duration with actual video file length when available,
        # so the slide lasts exactly as long as the video plays.
        for region_state in rs:
            for rend in region_state._rends:
                if isinstance(rend, VideoRenderer) and rend._duration_ms > 0:
                    page.duration = max(page.duration, rend._duration_ms)
    return result


# ══════════════════════════════════════════════════════════════════════════════
# F12 Settings Overlay  (rendered in-pygame, no external toolkit needed)
# ══════════════════════════════════════════════════════════════════════════════

class SettingsOverlay:
    """
    Full settings panel rendered over the player.
    Returns (closed, applied) from process_event().
    """

    DEFS = [
        # (label,                attr,           kind,     extra)
        ('Player Width (px)',    'width',         'int',    (320, 7680)),
        ('Player Height (px)',   'height',        'int',    (240, 4320)),
        ('Fullscreen',           'fullscreen',    'bool',   None),
        ('Fit Mode',             'fit_mode',      'choice', ['native','stretch','letterbox','crop']),
        ('Target FPS',           'fps',           'choice', [15, 25, 30, 60]),
        ('Loop program',         'loop',          'bool',   None),
        ('Show info HUD',        'show_hud',      'bool',   None),
        ('Show FPS counter',     'show_fps',      'bool',   None),
        ('Brightness (%)',       'brightness',    'int',    (0, 100)),
        ('Timezone',             'timezone',      'str',    64),
        ('Locale',               'locale_code',   'str',    32),
        ('━━━ CLOUD+ ━━━━━━━━',   None,            'sep',    None),
        ('Cloud+ Auto-sync',     'cms_enabled',   'bool',   None),
        ('Server URL',           'cms_server',    'str',    256),
        ('Terminal ID',          'cms_username',  'str',    64),
        ('Password / Secret',    'cms_password',  'str',    64),
        ('Poll interval (s)',     'cms_interval',  'int',    (15, 3600)),
        ('━━━ DISPLAY ━━━━━━━━',  None,            'sep',    None),
        ('  TITLE SCREEN',       None,            'action', 'title_screen'),
        ('━━━━━━━━━━━━━━━━━━━',  None,            'sep',    None),
        ('  APPLY & CLOSE',      None,            'action', 'apply'),
        ('  DISCARD',            None,            'action', 'discard'),
    ]

    PAD    = 16
    ROW_H  = 34
    W      = 600
    TITLE  = 40

    def __init__(self, cfg: Config):
        # working copy
        self.cfg         = Config(**asdict(cfg))
        self.sel         = 0          # selected row index (skips seps)
        self._editing    = False      # in text-edit mode for int fields
        self._edit       = ''         # current digit string
        self._selectable = [i for i, d in enumerate(self.DEFS) if d[2] != 'sep']
        self.extra_action: str = ''   # set when a non-apply/discard action fires

    # ── Input ────────────────────────────────────────────────────────────────

    def handle(self, ev) -> Tuple[bool, bool]:
        """Returns (closed, applied)."""
        if ev.type != pygame.KEYDOWN:
            return False, False

        k = ev.key

        if self._editing:
            return self._handle_edit(k, ev.unicode)

        if k in (pygame.K_F12, pygame.K_ESCAPE):
            return True, False                   # discard

        if k == pygame.K_UP:
            self._move(-1)
        elif k == pygame.K_DOWN:
            self._move(1)
        elif k == pygame.K_RETURN or k == pygame.K_KP_ENTER:
            return self._activate()
        elif k in (pygame.K_LEFT, pygame.K_RIGHT):
            self._nudge(-1 if k == pygame.K_LEFT else 1)

        return False, False

    def _move(self, d):
        idx  = self._selectable.index(self._selectable[self.sel] if self._selectable else 0)
        idx  = (idx + d) % len(self._selectable)
        self.sel = idx

    def _activate(self) -> Tuple[bool, bool]:
        row_i = self._selectable[self.sel]
        label, attr, kind, extra = self.DEFS[row_i]
        if kind == 'action':
            if extra == 'apply':
                return True, True
            elif extra in ('title_screen', 'return_playlist'):
                self.extra_action = extra
                return True, False
            else:
                return True, False
        elif kind == 'bool':
            setattr(self.cfg, attr, not getattr(self.cfg, attr))
        elif kind in ('int', 'str'):
            self._editing = True
            self._edit    = str(getattr(self.cfg, attr))
        elif kind == 'choice':
            opts  = extra
            cur   = getattr(self.cfg, attr)
            idx   = opts.index(cur) if cur in opts else 0
            setattr(self.cfg, attr, opts[(idx + 1) % len(opts)])
        return False, False

    def _nudge(self, d):
        row_i = self._selectable[self.sel]
        label, attr, kind, extra = self.DEFS[row_i]
        if kind == 'bool':
            setattr(self.cfg, attr, not getattr(self.cfg, attr))
        elif kind == 'int':
            lo, hi = extra
            setattr(self.cfg, attr, max(lo, min(hi, getattr(self.cfg, attr) + d * 10)))
        elif kind == 'choice':
            opts = extra
            cur  = getattr(self.cfg, attr)
            idx  = opts.index(cur) if cur in opts else 0
            setattr(self.cfg, attr, opts[(idx + d) % len(opts)])
        elif kind == 'str':
            # LEFT/RIGHT doesn't change text fields; press ENTER to edit
            pass

    def _handle_edit(self, k, uni) -> Tuple[bool, bool]:
        row_i = self._selectable[self.sel]
        _, attr, kind, extra = self.DEFS[row_i]

        if k in (pygame.K_RETURN, pygame.K_KP_ENTER):
            if kind == 'int':
                lo, hi = extra
                try:
                    v = int(self._edit)
                    setattr(self.cfg, attr, max(lo, min(hi, v)))
                except ValueError:
                    pass
            elif kind == 'str':
                setattr(self.cfg, attr, self._edit)
            self._editing = False
            self._edit    = ''

        elif k == pygame.K_ESCAPE:
            self._editing = False
            self._edit    = ''

        elif k == pygame.K_BACKSPACE:
            self._edit = self._edit[:-1]

        elif k == pygame.K_v and (pygame.key.get_mods() & pygame.KMOD_CTRL):
            # Ctrl+V paste from clipboard
            try:
                import tkinter as tk
                root = tk.Tk(); root.withdraw()
                clip = root.clipboard_get(); root.destroy()
                if isinstance(clip, str):
                    maxlen = extra if isinstance(extra, int) else 256
                    self._edit = (self._edit + clip)[:maxlen]
            except Exception:
                pass

        elif kind == 'int' and uni.isdigit():
            self._edit += uni

        elif kind == 'str' and uni and uni.isprintable():
            maxlen = extra if isinstance(extra, int) else 256
            if len(self._edit) < maxlen:
                self._edit += uni

        return False, False

    # ── Draw ─────────────────────────────────────────────────────────────────

    def draw(self, screen: pygame.Surface):
        sw, sh = screen.get_size()
        n_rows  = len(self.DEFS)

        # Fit panel width to screen
        panel_w = min(self.W, sw - self.PAD * 2)

        # Scale row/title heights so panel fits vertically on small screens
        full_h  = self.TITLE + n_rows * self.ROW_H + self.PAD * 2
        avail_h = sh - self.PAD * 2
        if full_h <= avail_h:
            scale   = 1.0
            row_h   = self.ROW_H
            title_h = self.TITLE
        else:
            scale   = avail_h / full_h
            row_h   = max(16, int(self.ROW_H * scale))
            title_h = max(20, int(self.TITLE * scale))

        panel_h = title_h + n_rows * row_h + self.PAD * 2
        px = (sw - panel_w) // 2
        py = max(0, (sh - panel_h) // 2)

        # Dim background
        dim = pygame.Surface((sw, sh), pygame.SRCALPHA)
        dim.fill((0, 0, 0, 180))
        screen.blit(dim, (0, 0))

        # Panel background
        pygame.draw.rect(screen, (30, 30, 40), (px, py, panel_w, panel_h))
        pygame.draw.rect(screen, (80, 130, 200), (px, py, panel_w, panel_h), 2)

        # Title
        tf = ui_font(max(13, int(22 * scale)))
        ts = tf.render('⚙  PLAYER SETTINGS  (F12 to close)', True, (180, 210, 255))
        screen.blit(ts, (px + self.PAD, py + (title_h - ts.get_height()) // 2))

        pygame.draw.line(screen, (80,130,200),
                         (px, py + title_h), (px + panel_w, py + title_h), 1)

        rf  = ui_font(max(11, int(18 * scale)))
        vf  = ui_font(max(11, int(18 * scale)))
        sel_row_i = self._selectable[self.sel] if self._selectable else -1

        for row_i, (label, attr, kind, extra) in enumerate(self.DEFS):
            ry     = py + title_h + self.PAD + row_i * row_h
            is_sel = (row_i == sel_row_i)

            if kind == 'sep':
                pygame.draw.line(screen, (60,70,90),
                                 (px+self.PAD, ry+row_h//2),
                                 (px+panel_w-self.PAD, ry+row_h//2), 1)
                continue

            # Highlight selected row
            if is_sel:
                pygame.draw.rect(screen, (50, 80, 130),
                                 (px+2, ry, panel_w-4, row_h-2))

            label_clr = (220,220,220) if kind != 'action' else (100,200,120)
            if kind == 'action':
                stripped = label.strip()
                if stripped == 'DISCARD':
                    label_clr = (200, 100, 100)
                elif stripped == 'TITLE SCREEN':
                    label_clr = (120, 180, 255)

            ls = rf.render(label, True, label_clr)
            screen.blit(ls, (px + self.PAD, ry + (row_h - ls.get_height()) // 2))

            if attr is not None:
                cur = getattr(self.cfg, attr)
                TRUNC = 28   # max chars shown in value column
                if kind == 'bool':
                    val_str = '  ON  ' if cur else '  OFF '
                    val_clr = (80,220,80) if cur else (200,80,80)
                elif kind == 'int':
                    val_str = f'  {self._edit}█' if (is_sel and self._editing) \
                              else f'  {cur}'
                    val_clr = (255, 220, 80) if is_sel else (200,200,200)
                elif kind == 'str':
                    is_pw = 'password' in attr.lower()
                    if is_sel and self._editing:
                        shown   = self._edit[-TRUNC:]
                        val_str = f'  {shown}█'
                        val_clr = (255, 220, 80)
                    else:
                        raw = str(cur)
                        if is_pw and raw:
                            shown = '●' * min(len(raw), 10)
                        else:
                            shown = (raw[:TRUNC] + '…') if len(raw) > TRUNC else raw
                        val_str = f'  {shown}'
                        val_clr = (120, 200, 255) if raw else (100, 100, 120)
                else:  # choice
                    val_str = f'  {cur}'
                    val_clr = (120,200,255)

                vs = vf.render(val_str, True, val_clr)
                screen.blit(vs, (px + panel_w - vs.get_width() - self.PAD,
                                 ry + (row_h - vs.get_height()) // 2))

        hint_txt = ('↑↓ select  ·  ←→ change  ·  Enter edit  ·  Esc discard'
                    if scale < 0.85 else
                    'UP/DOWN select  ·  LEFT/RIGHT change  ·  ENTER edit  ·  Ctrl+V paste  ·  ESC discard')
        hint = ui_font(max(9, int(14 * scale))).render(hint_txt, True, (100,100,130))
        screen.blit(hint, (px + self.PAD, py + panel_h - hint.get_height() - 6))


# ══════════════════════════════════════════════════════════════════════════════
# Info HUD
# ══════════════════════════════════════════════════════════════════════════════

def draw_fps(screen: pygame.Surface, clock: pygame.time.Clock):
    f    = ui_font(14)
    text = f"FPS: {clock.get_fps():.1f}"
    s    = f.render(text, True, (200, 200, 200))
    sh_  = f.render(text, True, (0, 0, 0))
    sw, sh = screen.get_size()
    x = sw - s.get_width() - 8
    y = sh - s.get_height() - 8
    screen.blit(sh_, (x + 1, y + 1))
    screen.blit(s,   (x,     y))


def draw_hud(screen, prog, page_idx, pages, cfg, sx, sy, ox, oy, cms=None):
    f    = ui_font(16)
    lines = [
        f"Program: {prog.name}  ({prog.width}×{prog.height})",
        f"Page {page_idx+1}/{len(pages)}: {pages[page_idx].name}",
        f"Scale: {sx:.2f}×{sy:.2f}  Offset: ({ox},{oy})  Mode: {cfg.fit_mode}",
        f"Window: {screen.get_width()}×{screen.get_height()}  FPS: {cfg.fps}",
    ]
    if cms is not None:
        err = f'  [{cms.last_err[:40]}]' if cms.last_err and cms.status == 'error' else ''
        lines.append(f"Cloud+: {cms.status}{err}")
    x, y = 8, 8
    for line in lines:
        s = f.render(line, True, (255, 220, 0))
        # shadow
        sh = f.render(line, True, (0,0,0))
        screen.blit(sh, (x+1, y+1))
        screen.blit(s,  (x,   y))
        y += s.get_height() + 2


# ══════════════════════════════════════════════════════════════════════════════
# Main player
# ══════════════════════════════════════════════════════════════════════════════

def _save_screenshot(screen: pygame.Surface):
    ts   = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    path = _BASE_DIR / f'screenshot_{ts}.png'
    try:
        pygame.image.save(screen, str(path))
        print(f'[Screenshot] Saved: {path.name}')
    except Exception as exc:
        print(f'[Screenshot] Error: {exc}')


def _capture_screenshot_for_cms(screen: pygame.Surface, cms: 'CMSClient'):
    """Capture the current frame as PNG bytes and hand them to CMSClient."""
    png_bytes: Optional[bytes] = None
    try:
        import io as _io
        size = screen.get_size()
        raw  = pygame.image.tostring(screen, 'RGB')
        if PIL_AVAILABLE:
            from PIL import Image as _PILImg
            img = _PILImg.frombytes('RGB', size, raw)
            buf = _io.BytesIO()
            img.save(buf, 'PNG')
            png_bytes = buf.getvalue()
        else:
            import tempfile as _tf
            tmp = _tf.mktemp(suffix='.png')
            pygame.image.save(screen, tmp)
            with open(tmp, 'rb') as _f:
                png_bytes = _f.read()
            try:
                os.unlink(tmp)
            except OSError:
                pass
        print(f'[Screenshot] Captured {len(png_bytes)} bytes (PIL={PIL_AVAILABLE})')
        cms.deliver_screenshot(png_bytes)
    except Exception as exc:
        print(f'[Screenshot] Capture failed: {exc}')
        cms._screenshot_event.clear()


def _apply_locale(code: str):
    if not code:
        return
    try:
        import locale as _loc
        _loc.setlocale(_loc.LC_ALL, code)
        print(f'[Locale] Set to {code}')
    except Exception as exc:
        print(f'[Locale] Could not set {code!r}: {exc}')


def _make_window(cfg: Config) -> pygame.Surface:
    info  = pygame.display.Info()
    if cfg.fullscreen:
        flags  = pygame.FULLSCREEN | pygame.HWSURFACE | pygame.DOUBLEBUF
        size   = (info.current_w, info.current_h)
    else:
        flags  = pygame.RESIZABLE
        size   = (cfg.width, cfg.height)
    return pygame.display.set_mode(size, flags)


# ══════════════════════════════════════════════════════════════════════════════
# Welcome / idle screen  (shown when no program is loaded)
# ══════════════════════════════════════════════════════════════════════════════

def draw_welcome(screen: pygame.Surface, cfg: Config,
                 cms: Optional['CMSClient'], has_playlist: bool = False):
    sw, sh = screen.get_size()
    screen.fill((12, 14, 22))

    # ── logo + "Desktop Player" title ─────────────────────────────────────────
    logo_h  = max(60, int(sh * 0.30))
    logo    = _get_logo(logo_h)
    logo_y  = max(10, int(sh * 0.06))

    if logo:
        lx = (sw - logo.get_width()) // 2
        screen.blit(logo, (lx, logo_y))
        dp_y = logo_y + logo_h + 10
    else:
        # Fallback if image can't be loaded
        fb_f = ui_font(48)
        fb_s = fb_f.render('Impact Cloud+', True, (200, 30, 30))
        screen.blit(fb_s, ((sw - fb_s.get_width()) // 2, logo_y))
        dp_y = logo_y + fb_s.get_height() + 10

    dp_f = ui_font(max(18, int(sh * 0.034)))
    dp_s = dp_f.render('Desktop Player', True, (210, 215, 230))
    screen.blit(dp_s, ((sw - dp_s.get_width()) // 2, dp_y))

    below_header = dp_y + dp_s.get_height() + 6

    # ── two cards ────────────────────────────────────────────────────────────
    card_w = min(360, (sw - 60) // 2)
    card_h = 200
    gap    = 24
    total  = card_w * 2 + gap
    cx     = (sw - total) // 2
    # Position cards below the logo/title; fall back to centred if there's room
    remaining = sh - below_header - 36 - 10   # 36 = hint bar, 10 = padding
    cy = below_header + max(8, (remaining - card_h) // 2)

    def card(x, y, title_txt, title_clr, lines, highlight=False):
        bg = (22, 28, 48) if not highlight else (18, 40, 28)
        border = (60, 100, 180) if not highlight else (40, 160, 80)
        pygame.draw.rect(screen, bg,     (x, y, card_w, card_h), border_radius=10)
        pygame.draw.rect(screen, border, (x, y, card_w, card_h), 2, border_radius=10)
        tf = ui_font(22)
        ts = tf.render(title_txt, True, title_clr)
        screen.blit(ts, (x + (card_w - ts.get_width()) // 2, y + 16))
        lf = ui_font(17)
        ly = y + 16 + ts.get_height() + 14
        for line, clr in lines:
            ls = lf.render(line, True, clr)
            screen.blit(ls, (x + (card_w - ls.get_width()) // 2, ly))
            ly += ls.get_height() + 6

    # Card 1 – local file
    card(cx, cy, 'Open Local File', (180, 210, 255), [
        ('Press  O  to browse',        (210, 210, 210)),
        ('or drag a .vsn file here',   (150, 155, 175)),
        ('',                           (0,0,0)),
        ('F11 – fullscreen toggle',    (110, 115, 140)),
    ])

    # Card 2 – CMS cloud
    if cms is None:
        # not configured
        card(cx + card_w + gap, cy, 'Cloud+ Sync', (100, 200, 130), [
            ('Not configured',              (190, 120, 60)),
            ('',                            (0,0,0)),
            ('Press F12 → Cloud+ section',   (180, 180, 200)),
            ('Enter Server URL,',           (150, 155, 175)),
            ('Terminal ID & Password',      (150, 155, 175)),
        ])
    else:
        ok = cms.status == 'ok'
        sc = (80, 220, 80) if ok else (255, 200, 60) if 'error' not in cms.status else (230, 80, 80)
        err_line = cms.last_err[:34] if cms.last_err and not ok else ''
        lines = [
            (f'Status: {cms.status}', sc),
            (cfg.cms_server[:34], (130, 140, 165)),
            ('',                    (0,0,0)),
            ('Waiting for program…' if ok else (err_line or 'Connecting…'),
             (160, 160, 180) if ok else (220, 120, 60)),
        ]
        card(cx + card_w + gap, cy, 'Cloud+ Sync', (100, 200, 130),
             lines, highlight=ok)

    # ── Return to Playlist button (only when a playlist is loaded) ───────────
    if has_playlist:
        btn_w = min(320, sw - 40)
        btn_h = 48
        btn_x = (sw - btn_w) // 2
        btn_y = cy + card_h + 18
        pygame.draw.rect(screen, (18, 60, 22),  (btn_x, btn_y, btn_w, btn_h), border_radius=10)
        pygame.draw.rect(screen, (50, 180, 70),  (btn_x, btn_y, btn_w, btn_h), 2, border_radius=10)
        bf  = ui_font(20)
        bs  = bf.render('▶  RETURN TO PLAYLIST', True, (80, 220, 100))
        screen.blit(bs, (btn_x + (btn_w - bs.get_width()) // 2,
                         btn_y + (btn_h - bs.get_height()) // 2))
        sub_bf = ui_font(13)
        sub_bs = sub_bf.render('SPACE  or  ENTER', True, (60, 110, 70))
        screen.blit(sub_bs, (btn_x + (btn_w - sub_bs.get_width()) // 2,
                              btn_y + btn_h + 4))

    # ── bottom hint bar ───────────────────────────────────────────────────────
    hints = [
        ('O',   'Open file'),
        ('F12', 'Settings / CMS'),
        ('F10', 'Screenshot'),
        ('F11', 'Fullscreen'),
        ('ESC', 'Quit'),
    ]
    hf  = ui_font(15)
    hx  = 20
    hy  = sh - 36
    pygame.draw.rect(screen, (18, 20, 32), (0, hy - 8, sw, 44))
    for key, desc in hints:
        ks = hf.render(f' {key} ', True, (30, 30, 40),)
        pygame.draw.rect(screen, (80, 130, 200),
                         (hx, hy, ks.get_width(), ks.get_height()), border_radius=3)
        ks2 = hf.render(f' {key} ', True, (240, 240, 240))
        screen.blit(ks2, (hx, hy))
        hx += ks.get_width() + 4
        ds = hf.render(f' {desc}', True, (140, 145, 165))
        screen.blit(ds, (hx, hy))
        hx += ds.get_width() + 20

    vs = hf.render(_runtime_version(), True, (210, 215, 230))
    screen.blit(vs, (sw - vs.get_width() - 12, hy))


def run(vsn_path: Optional[str], cfg: Config):
    global _player_timezone, _player_locale

    pygame.init()
    pygame.display.set_caption('Impact Cloud+ Desktop Player')
    pygame.event.set_allowed([pygame.QUIT, pygame.KEYDOWN, pygame.VIDEORESIZE,
                              pygame.DROPFILE, pygame.USEREVENT])

    # Apply timezone and locale from config
    _player_timezone = cfg.timezone
    _apply_locale(cfg.locale_code)

    screen = _make_window(cfg)

    # Brightness dim surface (lazily sized to match screen)
    _dim_surf: Optional[pygame.Surface] = None

    # Title screen is hidden from clients by default; accessible via F12
    _show_title: bool = False

    # ── Mutable program state ─────────────────────────────────────────────────
    prog:         Optional[Program]       = None
    pages:        List[Page]              = []
    vsn_dir:      str                     = ''
    vsn_stem:     str                     = ''
    page_regions: List                    = []
    sx = sy       = 1.0
    ox = oy       = 0
    page_idx      = 0
    page_t        = time.monotonic()
    paused        = False
    pause_extra   = 0.0
    _pause_st     = time.monotonic()

    def load_vsn(path: str) -> bool:
        nonlocal prog, pages, vsn_dir, vsn_stem
        try:
            progs = parse_vsn(path)
        except Exception as exc:
            print(f'[VSN] {exc}'); return False
        if not progs:
            return False
        p  = progs[0]
        pg = [pp for pp in p.pages if pp.visible] or p.pages
        if not pg:
            return False
        prog     = p
        vsn_dir  = str(Path(path).parent)
        vsn_stem = Path(path).stem
        pages    = pg
        cfg.last_dir = vsn_dir
        return True

    def rebuild():
        nonlocal sx, sy, ox, oy, page_regions
        if prog is None:
            return
        sw, sh = screen.get_size()
        sx, sy, ox, oy = compute_layout(prog.width, prog.height, sw, sh, cfg.fit_mode)
        page_regions = build_page_regions(pages, sx, sy, ox, oy, vsn_dir, vsn_stem)

    def _open_file():
        """Open file picker and load chosen VSN (called from main thread only)."""
        nonlocal page_idx, page_t, pause_extra, _show_title
        path = pick_vsn_file(cfg.last_dir)
        if path and load_vsn(path):
            page_idx    = 0
            page_t      = time.monotonic()
            pause_extra = 0.0
            _show_title = False
            rebuild()
            _font_cache.clear(); _local_font_map = None
            print(f'[VSN] Loaded: {prog.name}')
            if cms:
                cms.update_now_playing(prog.name)

    # ── Load initial VSN if given on command line ──────────────────────────────
    # Skip auto-loading when CMS is active — CMS is the source of truth and
    # the argument file would flash briefly before being replaced by the server playlist.
    _cms_active = cfg.cms_enabled and cfg.cms_server and cfg.cms_username
    if vsn_path and not _cms_active:
        if load_vsn(vsn_path):
            rebuild()
        else:
            print(f'[VSN] Could not load: {vsn_path}')

    # ── CMS cloud sync ────────────────────────────────────────────────────────
    dl_dir = Path(cfg.cms_dl_dir) if cfg.cms_dl_dir \
             else _BASE_DIR / 'downloads'
    dl_dir.mkdir(parents=True, exist_ok=True)
    vsn_q: _queue.Queue = _queue.Queue(maxsize=4)
    cms: Optional[CMSClient] = None
    if cfg.cms_enabled and cfg.cms_server and cfg.cms_username:
        cms = CMSClient(cfg, dl_dir, vsn_q)
        print(f'[Cloud+] Connecting to {cfg.cms_server} as {cfg.cms_username}')

    clock    = pygame.time.Clock()
    settings: Optional[SettingsOverlay] = None
    bar_clr  = parse_color(cfg.bar_color)[:3]

    if not CV2_AVAILABLE:
        print('[Video] opencv-python not installed – video items show placeholder.')
    print('O=open file  F12=settings  F11=fullscreen  SPACE=pause  ESC=quit  I=hud  P=push screenshot')

    while True:
        # ── Events ────────────────────────────────────────────────────────────
        for ev in pygame.event.get():

            if ev.type == pygame.QUIT:
                if cms: cms.stop()
                cfg.save(); pygame.quit(); return

            # Drag-and-drop a .vsn file onto the window
            if ev.type == pygame.DROPFILE:
                if ev.file.lower().endswith('.vsn') and os.path.isfile(ev.file):
                    if load_vsn(ev.file):
                        page_idx = 0; page_t = time.monotonic(); pause_extra = 0.0
                        _show_title = False
                        rebuild(); _font_cache.clear(); _local_font_map = None
                        print(f'[VSN] Drop-loaded: {prog.name}')
                continue

            # Route to settings overlay first when open
            if settings is not None:
                closed, applied = settings.handle(ev)
                if closed:
                    if applied:
                        cfg.__dict__.update(asdict(settings.cfg))
                        cfg.save()
                        _player_timezone = cfg.timezone
                        _apply_locale(cfg.locale_code)
                        screen  = _make_window(cfg)
                        bar_clr = parse_color(cfg.bar_color)[:3]
                        _dim_surf = None   # force resize on next frame
                        _font_cache.clear(); _local_font_map = None
                        rebuild()
                        # Restart CMS if credentials/server changed
                        if cms is not None:
                            cms.stop()
                        cms = None
                        if cfg.cms_enabled and cfg.cms_server and cfg.cms_username:
                            cms = CMSClient(cfg, dl_dir, vsn_q)
                            print(f'[Cloud+] Reconnecting to {cfg.cms_server}')
                    elif settings.extra_action == 'title_screen':
                        _show_title = True
                    elif settings.extra_action == 'return_playlist':
                        _show_title = False
                    settings = None
                continue

            if ev.type == pygame.KEYDOWN:
                k = ev.key
                if k in (pygame.K_ESCAPE, pygame.K_q):
                    if cms: cms.stop()
                    cfg.save(); pygame.quit(); return

                elif k == pygame.K_F12:
                    settings = SettingsOverlay(cfg)

                elif k == pygame.K_F11:
                    cfg.fullscreen = not cfg.fullscreen
                    screen = _make_window(cfg)
                    _font_cache.clear(); _local_font_map = None
                    rebuild()

                elif k == pygame.K_o:
                    _open_file()

                elif k == pygame.K_F10:
                    _save_screenshot(screen)

                elif k in (pygame.K_EQUALS, pygame.K_PLUS, pygame.K_KP_PLUS):
                    cfg.brightness = min(100, cfg.brightness + 5)

                elif k in (pygame.K_MINUS, pygame.K_KP_MINUS):
                    cfg.brightness = max(0, cfg.brightness - 5)

                elif _show_title and prog is not None and \
                        k in (pygame.K_SPACE, pygame.K_RETURN, pygame.K_KP_ENTER):
                    _show_title = False

                elif prog is not None:
                    # Keys that only make sense when a program is loaded
                    if k == pygame.K_SPACE:
                        if not paused:
                            paused = True;  _pause_st = time.monotonic()
                        else:
                            pause_extra += time.monotonic() - _pause_st; paused = False

                    elif k == pygame.K_RIGHT:
                        page_idx = (page_idx + 1) % len(pages)
                        page_t = time.monotonic(); pause_extra = 0.0

                    elif k == pygame.K_LEFT:
                        page_idx = (page_idx - 1) % len(pages)
                        page_t = time.monotonic(); pause_extra = 0.0

                    elif k == pygame.K_i:
                        cfg.show_hud = not cfg.show_hud

                    elif k == pygame.K_p and cms:
                        # Push a screenshot to the CMS on demand
                        print('[Screenshot] Manual push triggered (P key)')
                        cms._screenshot_event.set()

            elif ev.type == pygame.VIDEORESIZE:
                cfg.width, cfg.height = ev.w, ev.h
                rebuild()

        # ── CMS hot-reload – drain queue, use only the most-recently queued entry
        new_entry = None
        try:
            while True:
                new_entry = vsn_q.get_nowait()
        except _queue.Empty:
            pass
        if new_entry is not None:
            new_path, vsn_was_fetched = new_entry
            if load_vsn(new_path):
                # Reset to page 0 only when content was freshly downloaded OR no
                # playlist was loaded yet.  Startup re-detection of an already-on-disk
                # file (vsn_was_fetched=False) continues from wherever the player is.
                if vsn_was_fetched or prog is None:
                    page_idx    = 0
                    page_t      = time.monotonic()
                    pause_extra = 0.0
                    paused      = False
                _show_title = False   # playlist loaded — dismiss title screen
                rebuild()
                _font_cache.clear(); _local_font_map = None
                print(f'[Cloud+] Now playing: {prog.name}')
                if cms:
                    cms.update_now_playing(prog.name)

        # ── Draw ──────────────────────────────────────────────────────────────
        if _show_title:
            draw_welcome(screen, cfg, cms, has_playlist=prog is not None)

        elif prog is None:
            # Black screen until playlist loads — clients see nothing
            screen.fill((0, 0, 0))

        else:
            # ── Page advance ──────────────────────────────────────────────────
            if not paused and settings is None:
                elapsed = time.monotonic() - page_t - pause_extra
                limit   = pages[page_idx].duration / 1000.0
                if limit > 0 and elapsed >= limit:
                    if cfg.loop or page_idx < len(pages) - 1:
                        # Preseed departing page's videos so they seek to frame 0
                        # while other pages play — eliminates seek delay on loop-back.
                        for _rs in page_regions[page_idx]:
                            for _rend in _rs._rends:
                                if isinstance(_rend, VideoRenderer):
                                    _rend.preseed()
                        page_idx    = (page_idx + 1) % len(pages)
                        page_t      = time.monotonic()
                        pause_extra = 0.0

            page       = pages[page_idx]
            br,bg,bb,_ = page.bg_clr
            screen.fill(bar_clr)
            if cfg.show_fps:
                draw_fps(screen, clock)
            sw, sh = screen.get_size()
            prog_rect = pygame.Rect(ox, oy,
                                    int(prog.width  * sx),
                                    int(prog.height * sy))
            prog_rect.clamp_ip(screen.get_rect())
            pygame.draw.rect(screen, (br, bg, bb), prog_rect)

            for rs in page_regions[page_idx]:
                rs.render(screen)

            if cfg.show_hud:
                draw_hud(screen, prog, page_idx, pages, cfg, sx, sy, ox, oy, cms)

            if paused:
                pf = ui_font(20)
                ps = pf.render('⏸  PAUSED  (SPACE to resume)', True, (255,220,0))
                screen.blit(ps, (10, screen.get_height() - ps.get_height() - 10))

        # ── Brightness overlay ────────────────────────────────────────────────
        if cfg.brightness < 100:
            sw2, sh2 = screen.get_size()
            if _dim_surf is None or _dim_surf.get_size() != (sw2, sh2):
                _dim_surf = pygame.Surface((sw2, sh2), pygame.SRCALPHA)
            alpha = int(255 * (100 - cfg.brightness) / 100)
            _dim_surf.fill((0, 0, 0, alpha))
            screen.blit(_dim_surf, (0, 0))

        if settings is not None:
            settings.draw(screen)

        pygame.display.flip()

        # CMS screenshot: capture only when the WS has requested one
        if cms and cms._screenshot_event.is_set():
            _capture_screenshot_for_cms(screen, cms)

        clock.tick(cfg.fps)


# ══════════════════════════════════════════════════════════════════════════════
# Entry point
# ══════════════════════════════════════════════════════════════════════════════

def pick_vsn_file(start_dir: str = '') -> Optional[str]:
    try:
        import tkinter as tk
        from tkinter import filedialog
        root = tk.Tk(); root.withdraw()
        path = filedialog.askopenfilename(
            title='Select VSN program file',
            initialdir=start_dir or os.path.expanduser('~'),
            filetypes=[('VSN files','*.vsn'),('All files','*.*')],
        )
        root.destroy()
        return path or None
    except Exception:
        return None


def main():
    cfg      = Config.load()
    args     = sys.argv[1:]
    vsn_path = None

    for a in args:
        if a in ('-w', '--windowed'):
            cfg.fullscreen = False
        elif os.path.isfile(a):
            vsn_path = a

    # vsn_path may be None — run() will show the welcome screen in that case
    run(vsn_path, cfg)


if __name__ == '__main__':
    main()
