# -*- mode: python ; coding: utf-8 -*-
import sys
from pathlib import Path

# Find pyzbar DLLs if on Windows
binaries = []
if sys.platform.startswith('win'):
    # Try to find pyzbar DLLs
    try:
        import pyzbar
        import os
        pyzbar_path = Path(pyzbar.__file__).parent
        
        # Look for DLLs
        dll_files = list(pyzbar_path.glob('*.dll'))
        for dll in dll_files:
            binaries.append((str(dll), 'pyzbar'))
            
        # Also look for libiconv and libzbar in common locations
        # You might need to download these separately
        if (pyzbar_path / 'libiconv.dll').exists():
            binaries.append((str(pyzbar_path / 'libiconv.dll'), 'pyzbar'))
        if (pyzbar_path / 'libzbar-64.dll').exists():
            binaries.append((str(pyzbar_path / 'libzbar-64.dll'), 'pyzbar'))
            
    except ImportError:
        print("pyzbar not found - QR reading will be disabled")

a = Analysis(
    ['kash_stash.py'],
    pathex=[],
    binaries=binaries,
    datas=[('kash_stash_logo.png', '.')],
    hiddenimports=[
        'queue_boss',
        'bash_executor',
        'python_executor', 
        'powershell_executor',
        'pod_digest_fetcher',
        'kash_files',
        'qr_config',
        'PIL.ImageGrab',
        'pystray',
        'pystray._win32',
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
    console=False,  # Set to False for production
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon='kash_stash_logo.ico' if sys.platform.startswith('win') else None,
)