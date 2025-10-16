# -*- mode: python ; coding: utf-8 -*-


a = Analysis(
    ['kash_stash.py'],
    pathex=[],
    binaries=[],
    datas=[('kash_stash_logo.png', '.')],
    hiddenimports=[
        'queue_boss',
        'bash_executor',
        'python_executor', 
        'powershell_executor',
        'pod_digest_fetcher',
        'PIL.ImageGrab',  # For Windows clipboard screenshots
        'pystray',
        'pystray._win32',  # Windows system tray
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='kash_stash',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    #icon='kash_stash_logo.png',   #optional - include your icon if you want an icon, icns for osx, ico for windows, png for linux (can also be used for .desktop files)
)