# -*- mode: python ; coding: utf-8 -*-
"""
PyInstaller build spec for ImpactLED Cloud+ Desktop Player.

Build locally (Windows, Python 3.12):
    pip install pyinstaller
    pyinstaller player.spec

Output:  dist\ImpactLED-Cloud-Player.exe   (~60-80 MB, fully self-contained)

The exe uses Path(__file__).parent for all runtime paths, so the install
directory must also contain:
    fonts\          (bundled font files)
    cloudpluslogoinvert.png
    player_config.json  (written by installer, not shipped in the exe)
"""

from PyInstaller.utils.hooks import collect_data_files, collect_submodules

a = Analysis(
    ['player.py'],
    pathex=[],
    binaries=[],
    datas=[
        # pygame ships its SDL2 DLLs as package data -- must be collected
        *collect_data_files('pygame'),
        # opencv ships its own DLLs
        *collect_data_files('cv2'),
        # certifi CA bundle — required for SSL verification in the frozen exe
        *collect_data_files('certifi'),
    ],
    hiddenimports=[
        # These are inside try/except blocks so PyInstaller won't detect them
        'certifi',
        'feedparser',
        'websocket',
        'websocket._abnf',
        'websocket._core',
        'websocket._exceptions',
        'websocket._handshake',
        'websocket._http',
        'websocket._logging',
        'websocket._socket',
        'websocket._ssl_compat',
        'websocket._utils',
        'PIL',
        'PIL.Image',
        'PIL.ImageSequence',
        'PIL.ImageFile',
        'PIL.ImageDraw',
        'PIL.ImageFont',
        'cv2',
        'requests',
        'requests.adapters',
        'requests.auth',
        'requests.cookies',
        'requests.exceptions',
        'requests.models',
        'requests.sessions',
        'urllib3',
        'urllib3.util.retry',
        # tkinter is used for the file-open dialog
        'tkinter',
        'tkinter.filedialog',
        '_tkinter',
        # xml parser
        'xml.etree.ElementTree',
        'xml.etree.cElementTree',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        'matplotlib',
        'scipy',
        'pandas',
        'IPython',
        'notebook',
    ],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='ImpactLED-Cloud-Player',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,         # console window shows live player log output
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=None,            # add a .ico file path here to set the exe icon
)
