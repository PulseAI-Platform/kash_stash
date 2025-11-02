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
        if (pyzbar_path / 'libiconv.dll').exists():
            binaries.append((str(pyzbar_path / 'libiconv.dll'), 'pyzbar'))
        if (pyzbar_path / 'libzbar-64.dll').exists():
            binaries.append((str(pyzbar_path / 'libzbar-64.dll'), 'pyzbar'))
            
    except ImportError:
        print("pyzbar not found - QR reading will be disabled")

# CAREFUL EXCLUDES - Only remove what we're SURE isn't needed
excludes = [
    # THE BIG ONES - DEFINITELY REMOVE (these alone save ~155MB)
    'cv2',
    'numpy',
    'numpy.core',
    'numpy.random',
    'numpy.linalg',
    'numpy.fft',
    'numpy.polynomial',
    'numpy.testing',
    'numpy.distutils',
    'numpy.f2py',
    'numpy.typing',
    'numpy.matrixlib',
    
    # Scientific/Data libraries (safe to remove)
    'pandas',
    'matplotlib', 
    'scipy',
    'sklearn',
    'IPython',
    'jupyter',
    'notebook',
    
    # GUI libraries we don't use
    'PyQt5',
    'PyQt6',
    'PySide2',
    'PySide6',
    'wx',
    'wxPython',
    'kivy',
    
    # Testing frameworks (safe to remove)
    'pytest',
    'unittest',
    'test',
    'tests',
    '_pytest',
    'doctest',
    
    # Development tools (safe to remove)
    'pip',
    'setuptools',
    'wheel',
    'distutils',
    'Cython',
    
    # Documentation (safe to remove)
    'pydoc',
    'pydoc_data',
    'sphinx',
    
    # Database drivers (safe to remove)
    'sqlite3',
    'psycopg2',
    'MySQLdb',
    'pymongo',
    'sqlalchemy',
    
    # Web frameworks (safe to remove)
    'flask',
    'django',
    'tornado',
    'twisted',
    'aiohttp',
    'fastapi',
    'uvicorn',
    'gunicorn',
    
    # Compression (might save a bit)
    'bz2',
    'lzma',
    '_lzma',
    
    # Network protocols we don't use
    # 'email',  # NEEDED by requests!
    'smtplib',
    'imaplib',
    'poplib',
    'ftplib',
    'telnetlib',
    
    # Parsers we don't use
    # 'html',  # Might be needed
    'html.parser',
    'xmlrpc',
    'lxml',
    
    # Terminal stuff (safe to remove)
    'curses',
    'readline',
    'rlcompleter',
    
    # Other unused
    'turtle',
    'idlelib',
    'lib2to3',
    'ensurepip',
    'venv',
    'tkinter.tix',
    'tkinter.scrolledtext',
    
    # Audio/Video
    'pyaudio',
    'pygame',
    'moviepy',
    'imageio',
    'ffmpeg',
    'pydub',
]

# Binary exclusions - specific .so files to exclude
excluded_binaries = [
    'Qt5',
    'Qt6',
    'libQt',
    'avcodec',
    'avformat',
    'avutil',
    'swresample',
    'swscale',
    'libopenblas',
    'libgfortran',
    'libvpx',
    'libopencv',
    'opencv',
    'libicudata',  # Try to remove the 29MB ICU data
    'libicuuc',
    'libicui18n',
]

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
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=excludes,
    noarchive=False,
    optimize=2,
)

# Filter out unwanted binaries
original_length = len(a.binaries)
a.binaries = [b for b in a.binaries if not any(
    excluded in b[0] for excluded in excluded_binaries
)]

print(f"Filtered binaries from {original_length} to {len(a.binaries)}")

# Print what large binaries are left
print("\nLarge binaries still included:")
for name, path, typecode in a.binaries:
    if any(lib in name for lib in ['libicu', 'libQt', 'opencv']):
        print(f"  {name}")

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
    strip=True,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon='kash_stash_logo.ico' if sys.platform.startswith('win') else None,
)