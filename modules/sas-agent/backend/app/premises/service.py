"""خدمة العقارات — توليد العنوان الوطني (NPN + IQ-Pin) وحمولة الـ QR، وتخزين الصور.

يعيد استخدام محرّك العنونة الوطنية (app.core.addressing — رياضيات نقية) وتخصيص NPN
الفريد على مستوى المنصّة (app.services.addressing_service.allocate_npns) — منفذان
موثّقان في __init__. الـ QR لا يُولَّد كصورة هنا؛ نخزّن حمولته النصّية وتُرسَم في
الواجهة (qr_flutter). الباكند يخزّن فقط صورة الدار (ملفّ).
"""
from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Optional

from sqlmodel import Session

from ..core import addressing
from ..services import addressing_service


# ══════════════════════ العنونة و QR ══════════════════════
def resolve_gov_code(governorate: str, gov_code: Optional[int]) -> int:
    """كود المحافظة: صريح إن مُرِّر (1..99) وإلا يُشتقّ من الاسم (99 إن جُهِل)."""
    if gov_code and 1 <= gov_code <= 99:
        return gov_code
    return addressing.gov_code_for(governorate or "")


def build_qr_payload(npn: str, iqpin: str, lat: Optional[float], lon: Optional[float]) -> str:
    """حمولة الـ QR: نصّ مدمج يعمل دون إنترنت (رقم وطني + رمز موقع + إحداثيات)."""
    parts = []
    if npn:
        parts.append(f"NPN:{npn}")
    if iqpin:
        parts.append(f"PIN:{iqpin}")
    if lat is not None and lon is not None:
        parts.append(f"GEO:{lat:.5f},{lon:.5f}")
    return "ALUKLAA|" + "|".join(parts)


def generate_codes(db: Session, governorate: str, gov_code: Optional[int],
                   lat: Optional[float], lon: Optional[float]) -> dict:
    """يخصّص NPN للعقار، ويحسب IQ-Pin من الإحداثيات (إن صحّت)، ويبني حمولة الـ QR."""
    gc = resolve_gov_code(governorate, gov_code)
    npn = addressing_service.allocate_npns(db, gc, 1)[0]
    iqpin = ""
    iqpin_disp = ""
    if lat is not None and lon is not None and addressing.in_iraq_box(lat, lon):
        iqpin = addressing.iqpin_encode(lat, lon)
        iqpin_disp = addressing.iqpin_display(iqpin)
    return {
        "gov_code": gc,
        "npn": npn,
        "npn_display": addressing.npn_display(npn),
        "iqpin": iqpin,
        "iqpin_display": iqpin_disp,
        "qr_payload": build_qr_payload(npn, iqpin, lat, lon),
    }


def recompute_iqpin(lat: Optional[float], lon: Optional[float]) -> dict:
    """يُعيد حساب IQ-Pin عند تغيّر الموقع (لا يمسّ NPN المخصَّص)."""
    if lat is not None and lon is not None and addressing.in_iraq_box(lat, lon):
        pin = addressing.iqpin_encode(lat, lon)
        return {"iqpin": pin, "iqpin_display": addressing.iqpin_display(pin)}
    return {"iqpin": "", "iqpin_display": ""}


# ══════════════════════ تخزين صور الدار ══════════════════════
def media_root() -> Path:
    """جذر ملفّات الوسائط القابل للكتابة: %LOCALAPPDATA%\\Aluklaa\\media\\premises
    عند التثبيت، أو backend/media/premises في التطوير."""
    data_dir = os.environ.get("ALUKLAA_DATA_DIR", "").strip()
    base = Path(data_dir) if data_dir else Path(__file__).resolve().parents[2]
    root = base / "media" / "premises"
    root.mkdir(parents=True, exist_ok=True)
    return root


_ALLOWED_EXT = {".jpg", ".jpeg", ".png", ".webp"}


def save_photo(premises_id: int, content: bytes, filename: str) -> str:
    """يخزّن صورة الدار ويعيد المسار النسبي (<id>/house<ext>)."""
    ext = os.path.splitext(filename or "")[1].lower()
    if ext not in _ALLOWED_EXT:
        ext = ".jpg"
    folder = media_root() / str(premises_id)
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob("house.*"):        # صورة دار واحدة لكل عقار (تستبدل)
        try:
            old.unlink()
        except OSError:
            pass
    dest = folder / f"house{ext}"
    dest.write_bytes(content)
    return f"{premises_id}/house{ext}"


def photo_abspath(rel_path: str) -> Optional[Path]:
    """المسار المطلق لصورة مخزّنة (يمنع الخروج من جذر الوسائط)."""
    if not rel_path:
        return None
    safe = re.sub(r"\.\.", "", rel_path).lstrip("/\\")
    p = (media_root() / safe).resolve()
    try:
        p.relative_to(media_root().resolve())
    except ValueError:
        return None
    return p if p.exists() else None


def delete_media(premises_id: int) -> None:
    """يحذف مجلد وسائط العقار (عند حذف العقار)."""
    folder = media_root() / str(premises_id)
    if folder.exists():
        for f in folder.glob("*"):
            try:
                f.unlink()
            except OSError:
                pass
        try:
            folder.rmdir()
        except OSError:
            pass
