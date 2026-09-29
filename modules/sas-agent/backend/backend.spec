# -*- mode: python ; coding: utf-8 -*-
"""
حزمة PyInstaller لخادم تطبيق الوكلاء — ملف تشغيلي مستقل (بلا حاجة لبايثون على جهاز المستخدم).
البناء:  .venv\Scripts\pyinstaller backend.spec --noconfirm
الناتج:  dist\backend\backend.exe  (+ مجلد _internal بجواره)
التشغيل: يُشغَّل ومجلد العمل = مجلد backend كي يقرأ .env و iraq_digital_platform.db.
"""
import os
from PyInstaller.utils.hooks import collect_all, collect_submodules

datas, binaries, hiddenimports = [], [], []

# ملفات بيانات يقرأها التطبيق بمسارات نسبية لوحداته (knowledge/*, manual_*.json).
# نضعها في جذر الحزمة (_internal) كي يجدها الكود عبر __file__/../..
if os.path.isdir("knowledge"):
    datas += [("knowledge", "knowledge")]
for _f in ("manual_issues.json", "manual_agents.json"):
    if os.path.exists(_f):
        datas += [(_f, ".")]

# حزم تعتمد على استيراد ديناميكي/ملفات بيانات — نجمعها بالكامل كي لا ينقص شيء وقت التشغيل.
_PKGS = [
    "fastapi", "starlette", "uvicorn", "anyio", "sniffio", "h11", "httptools",
    "websockets", "httpx", "httpcore",
    "pydantic", "pydantic_core", "pydantic_settings", "annotated_types",
    "sqlmodel", "sqlalchemy",
    "pysnmp", "pyasn1", "pyasn1_modules", "pysmi",
    "netmiko", "paramiko", "cryptography", "bcrypt", "nacl",
    "anthropic", "defusedxml", "alembic", "dotenv", "multipart",
]
for pkg in _PKGS:
    try:
        d, b, h = collect_all(pkg)
        datas += d
        binaries += b
        hiddenimports += h
    except Exception:
        pass

# حزمة التطبيق نفسها — main.py يستورد وحدات كثيرة، فنضمّها جميعاً.
hiddenimports += collect_submodules("app")
# استيرادات uvicorn الديناميكية (حلقات/بروتوكولات/دورة حياة)
hiddenimports += collect_submodules("uvicorn")

a = Analysis(
    ["run_server.py"],
    pathex=["."],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["tkinter", "matplotlib", "PyQt5", "PyQt6", "PySide2", "PySide6", "IPython"],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="backend",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=True,
    disable_windowed_traceback=False,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    name="backend",
)
