"""
وحدة العقارات — نقل كامل من backend/app/premises/ إلى الساس Sidecar.

الفروق عن النسخة الأصلية:
  1. التخزين: SQLite النحيلة (service/data/sas.db) بدل SQLModel/SQLite backend.
     الجداول: premises · premises_subscribers · npn_counter.
  2. المصادقة: fail-closed بـ verify_internal_secret (X-Internal-Secret header) —
     نفس آلية بقية الخدمة. لا اعتماد JWT/OAuth أصلاً.
  3. العزل: كل استعلام يحمل WHERE company_id=? AND owner_user_id=? (نصّ لا عدد صحيح
     لتوافق نمط _LocalBase الحالي).
  4. تخصيص NPN ذرّي: threading.Lock + commit قبل تحرير القفل — نفس منطق
     addressing_service.allocate_npns لكن على sqlite3 مباشرةً بلا SQLModel.
  5. محرّك العنونة: مستورَد مباشرةً من backend/app/core/addressing.py (دوال نقية).
  6. حمولة QR: SADARA|NPN:…|PIN:…|GEO:… (بادئة المنصة بدل ALUKLAA).
  7. الوسائط: data/media/premises/<id>/house.<ext> تحت مجلد الخدمة.

يُستورَد هذا الملف في app.py بسطر:
    from premises import router as premises_router
    app.include_router(premises_router)
"""
from __future__ import annotations

import base64
import os
import re
import sqlite3
import sys
import threading
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterator, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, ConfigDict, Field
from pydantic.functional_validators import BeforeValidator
from typing import Annotated as _Annotated


def _coerce_int(v: Any) -> int:
    """يقبل int أو str رقمي — ينتج ValidationError لأي قيمة أخرى."""
    try:
        return int(v)
    except (TypeError, ValueError):
        raise ValueError(f"يجب أن يكون رقماً صحيحاً، وردت القيمة: {v!r}")


_IntFromAny = _Annotated[int, BeforeValidator(_coerce_int)]

# ─── مسار محرّك العنونة (يُضاف sys.path في app.py قبل الاستيراد) ────────────
# تستوردها بعد أن يُضيف app.py المسار؛ إن لم يكن في sys.path بعد نضيفه هنا
_BACKEND_APP = os.path.join(os.path.dirname(__file__), "..", "backend", "app")
if _BACKEND_APP not in sys.path:
    sys.path.insert(0, os.path.abspath(_BACKEND_APP))

from core import addressing  # noqa: E402 — يُستورَد بعد sys.path

# ─── قاعدة البيانات المشتركة مع app.py ─────────────────────────────────────
_DEFAULT_DB = os.path.join(os.path.dirname(__file__), "data", "sas.db")
_DB_PATH: str = os.environ.get("SADARA_SAS_DB_PATH", _DEFAULT_DB)

# ─── قفل تخصيص NPN (عملية واحدة) ───────────────────────────────────────────
_npn_lock = threading.Lock()

# ─── السرّ الداخلي (نفس متغيّر app.py) ──────────────────────────────────────
_INTERNAL_SECRET: str = os.environ.get("SADARA_SAS_INTERNAL_SECRET", "")

# ─── حدود الصور ──────────────────────────────────────────────────────────────
_MAX_PHOTO_BYTES = 6 * 1024 * 1024   # 6 MB
_ALLOWED_EXT = {".jpg", ".jpeg", ".png", ".webp"}

# ─── قيم مقبولة ──────────────────────────────────────────────────────────────
_OWNERSHIP = {"owned", "rent"}
_PROPERTY  = {"residential", "commercial"}


# ═════════════════════════════════════════════════════════════════════════════
# DDL — يُستدعى من _init_db في app.py
# ═════════════════════════════════════════════════════════════════════════════

PREMISES_DDL = """
CREATE TABLE IF NOT EXISTS premises (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    company_id      TEXT    NOT NULL DEFAULT '',
    owner_user_id   TEXT    NOT NULL DEFAULT '',
    npn             TEXT    NOT NULL DEFAULT '',
    npn_display     TEXT    NOT NULL DEFAULT '',
    iqpin           TEXT    NOT NULL DEFAULT '',
    iqpin_display   TEXT    NOT NULL DEFAULT '',
    gov_code        INTEGER NOT NULL DEFAULT 0,
    qr_payload      TEXT    NOT NULL DEFAULT '',
    lat             REAL,
    lon             REAL,
    governorate     TEXT    NOT NULL DEFAULT '',
    area            TEXT    NOT NULL DEFAULT '',
    landmark        TEXT    NOT NULL DEFAULT '',
    phone           TEXT    NOT NULL DEFAULT '',
    phone_norm      TEXT    NOT NULL DEFAULT '',
    ownership       TEXT    NOT NULL DEFAULT '',
    ptype           TEXT    NOT NULL DEFAULT '',
    photo_path      TEXT    NOT NULL DEFAULT '',
    created_at      TEXT    NOT NULL,
    updated_at      TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_prem_owner
    ON premises (company_id, owner_user_id);
CREATE INDEX IF NOT EXISTS idx_prem_npn
    ON premises (npn);
CREATE INDEX IF NOT EXISTS idx_prem_gov
    ON premises (governorate);

CREATE TABLE IF NOT EXISTS premises_subscribers (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    premises_id     INTEGER NOT NULL REFERENCES premises(id),
    subscriber_ref  TEXT    NOT NULL,
    linked_at       TEXT    NOT NULL,
    UNIQUE (subscriber_ref)
);

CREATE INDEX IF NOT EXISTS idx_ps_premises
    ON premises_subscribers (premises_id);

CREATE TABLE IF NOT EXISTS npn_counter (
    gov_code        INTEGER PRIMARY KEY,
    last_seq        INTEGER NOT NULL DEFAULT 0
);
"""


# ═════════════════════════════════════════════════════════════════════════════
# اتصال SQLite (يُعيد استخدام نفس الملف الذي تفتحه app.py)
# ═════════════════════════════════════════════════════════════════════════════

@contextmanager
def _db() -> Iterator[sqlite3.Connection]:
    conn = sqlite3.connect(_DB_PATH, check_same_thread=False, timeout=15)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


# ═════════════════════════════════════════════════════════════════════════════
# Dependency: التحقّق من السرّ (fail-closed) — نسخة محلّية لهذا الملف
# ═════════════════════════════════════════════════════════════════════════════

import secrets as _secrets_mod

async def _verify_secret(request: Request) -> None:
    # يُقرأ السرّ عند كل طلب (lazy) لا مرّة واحدة عند الاستيراد — لتفادي عدم الاتساق
    # مع app.py إن تغيّر المتغيّر (PRODUCTION_BUG_1).
    secret = os.environ.get("SADARA_SAS_INTERNAL_SECRET", "") or _INTERNAL_SECRET
    if not secret:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="الخدمة غير مُهيّأة بأمان — تواصل مع المشرف",
        )
    incoming = request.headers.get("X-Internal-Secret", "")
    if not _secrets_mod.compare_digest(incoming, secret):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="غير مصرّح")


_DEP = [Depends(_verify_secret)]


# ═════════════════════════════════════════════════════════════════════════════
# مساعدات مشتركة
# ═════════════════════════════════════════════════════════════════════════════

def _utcnow() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")


def _norm_phone(raw: str) -> str:
    """يطبّع رقم الهاتف إلى صيغة 9647XXXXXXXXXX أو يعيد سلسلة فارغة."""
    d = re.sub(r"\D", "", raw or "")
    if d.startswith("00964"):
        d = d[5:]
    if d.startswith("964"):
        d = d[3:]
    if d.startswith("0"):
        d = d[1:]
    return f"964{d}" if len(d) == 10 and d.startswith("7") else ""


def _guard_owner(company_id: str, owner_user_id: str) -> None:
    """يتحقّق أن حقلَي العزل غير فارغَين — يرمي 400 إن أخفق."""
    if not (company_id or "").strip():
        raise HTTPException(status_code=400, detail="companyId مطلوب")
    if not (owner_user_id or "").strip():
        raise HTTPException(status_code=400, detail="ownerUserId مطلوب")


def _get_owned_premises(conn: sqlite3.Connection,
                        company_id: str, owner_user_id: str,
                        premises_id: int) -> sqlite3.Row:
    """
    يجلب العقار ويتحقّق الملكية (company_id + owner_user_id).
    يرمي 404 إن لم يوجد أو لم ينتمِ لهذا المالك — لا يكشف عقارات آخرين.
    """
    row = conn.execute(
        "SELECT * FROM premises WHERE id = ? AND company_id = ? AND owner_user_id = ?",
        (premises_id, company_id, owner_user_id),
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="العقار غير موجود")
    return row


# ═════════════════════════════════════════════════════════════════════════════
# العنونة الوطنية — محرّك NAS-IQ (مستورَد من core/addressing.py)
# ═════════════════════════════════════════════════════════════════════════════

def _resolve_gov_code(governorate: str, gov_code: Optional[int]) -> int:
    if gov_code and 1 <= gov_code <= 99:
        return gov_code
    return addressing.gov_code_for(governorate or "")


def _build_qr_payload(npn: str, iqpin: str,
                      lat: Optional[float], lon: Optional[float]) -> str:
    """حمولة QR: SADARA|NPN:…|PIN:…|GEO:… (بادئة المنصة)."""
    parts: List[str] = []
    if npn:
        parts.append(f"NPN:{npn}")
    if iqpin:
        parts.append(f"PIN:{iqpin}")
    if lat is not None and lon is not None:
        parts.append(f"GEO:{lat:.5f},{lon:.5f}")
    return "SADARA|" + "|".join(parts)


def _allocate_npn(gov_code: int) -> str:
    """
    تخصيص NPN ذرّي (قفل + commit قبل تحرير القفل).
    يُهدَر الرقم عند فشل ما بعده — مقبول، أفضل من التكرار.
    """
    with _npn_lock:
        with _db() as conn:
            row = conn.execute(
                "SELECT last_seq FROM npn_counter WHERE gov_code = ?",
                (gov_code,)
            ).fetchone()
            seq = (row["last_seq"] + 1) if row else 1
            if row:
                conn.execute(
                    "UPDATE npn_counter SET last_seq = ? WHERE gov_code = ?",
                    (seq, gov_code)
                )
            else:
                conn.execute(
                    "INSERT INTO npn_counter (gov_code, last_seq) VALUES (?, ?)",
                    (gov_code, seq)
                )
    # بناء NPN خارج القفل (لا I/O)
    return addressing.build_npn(gov_code, seq)


def _generate_codes(governorate: str, gov_code: Optional[int],
                    lat: Optional[float], lon: Optional[float]) -> dict:
    gc   = _resolve_gov_code(governorate, gov_code)
    npn  = _allocate_npn(gc)
    iqpin = iqpin_disp = ""
    if lat is not None and lon is not None and addressing.in_iraq_box(lat, lon):
        iqpin      = addressing.iqpin_encode(lat, lon)
        iqpin_disp = addressing.iqpin_display(iqpin)
    return {
        "gov_code":     gc,
        "npn":          npn,
        "npn_display":  addressing.npn_display(npn),
        "iqpin":        iqpin,
        "iqpin_display": iqpin_disp,
        "qr_payload":   _build_qr_payload(npn, iqpin, lat, lon),
    }


def _recompute_iqpin(lat: Optional[float], lon: Optional[float]) -> dict:
    if lat is not None and lon is not None and addressing.in_iraq_box(lat, lon):
        pin = addressing.iqpin_encode(lat, lon)
        return {"iqpin": pin, "iqpin_display": addressing.iqpin_display(pin)}
    return {"iqpin": "", "iqpin_display": ""}


# ═════════════════════════════════════════════════════════════════════════════
# تخزين صور الدار
# ═════════════════════════════════════════════════════════════════════════════

def _media_root() -> Path:
    """data/media/premises/ بجانب الخدمة (أو SADARA_SAS_MEDIA_DIR إن ضُبط)."""
    base = os.environ.get("SADARA_SAS_MEDIA_DIR", "").strip()
    root = (Path(base) if base
            else Path(os.path.dirname(__file__)) / "data" / "media" / "premises")
    root.mkdir(parents=True, exist_ok=True)
    return root


def _save_photo(premises_id: int, content: bytes, filename: str) -> str:
    """يخزّن صورة الدار ويعيد المسار النسبي <id>/house<ext>."""
    ext = os.path.splitext(filename or "")[1].lower()
    if ext not in _ALLOWED_EXT:
        ext = ".jpg"
    folder = _media_root() / str(premises_id)
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob("house.*"):
        try:
            old.unlink()
        except OSError:
            pass
    dest = folder / f"house{ext}"
    dest.write_bytes(content)
    return f"{premises_id}/house{ext}"


def _photo_abspath(rel_path: str) -> Optional[Path]:
    """المسار المطلق مع منع path traversal."""
    if not rel_path:
        return None
    safe = re.sub(r"\.\.", "", rel_path).lstrip("/\\")
    p = (_media_root() / safe).resolve()
    try:
        p.relative_to(_media_root().resolve())
    except ValueError:
        return None
    return p if p.exists() else None


def _delete_media(premises_id: int) -> None:
    folder = _media_root() / str(premises_id)
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


# ═════════════════════════════════════════════════════════════════════════════
# صياغة الاستجابة
# ═════════════════════════════════════════════════════════════════════════════

def _row_to_dict(conn: sqlite3.Connection,
                 row: sqlite3.Row,
                 with_subscribers: bool = False) -> dict:
    d = dict(row)
    # عدد الروابط
    links_rows = conn.execute(
        "SELECT subscriber_ref FROM premises_subscribers WHERE premises_id = ?",
        (d["id"],)
    ).fetchall()
    refs = [r["subscriber_ref"] for r in links_rows]
    d["subscriber_count"] = len(refs)
    d["has_photo"] = bool(d.get("photo_path"))
    if with_subscribers:
        # يجلب بيانات المشترك من local_subscribers إن وُجدت (بدون account_id — بحث بـ username)
        subs = []
        for ref in refs:
            ls = conn.execute(
                "SELECT * FROM local_subscribers WHERE username = ? LIMIT 1",
                (ref,)
            ).fetchone()
            if ls:
                r = dict(ls)
                r.pop("raw_json", None)
                subs.append(r)
            else:
                subs.append({"subscriber_ref": ref})
        d["subscribers"] = subs
    return d


# ═════════════════════════════════════════════════════════════════════════════
# نماذج Pydantic
# ═════════════════════════════════════════════════════════════════════════════

class _PremBase(BaseModel):
    """الحقول الأساسية لعزل النطاق (مطلوبة في كل طلبات العقارات)."""
    model_config = ConfigDict(extra="forbid")

    companyId:    str = Field(...,  description="معرّف الشركة")
    ownerUserId:  str = Field(...,  description="معرّف الوكيل المالك")


class PremListRequest(_PremBase):
    """POST /premises/list"""
    search:    Optional[str] = None
    ownership: Optional[str] = None
    ptype:     Optional[str] = None
    page:      int = Field(default=1,  ge=1)
    count:     int = Field(default=50, ge=1, le=500)


class PremCreateRequest(_PremBase):
    """POST /premises/create"""
    governorate:     str            = Field(..., min_length=1)  # مطلوب (PRODUCTION_BUG_2)
    gov_code:        Optional[int]  = None
    area:            str            = Field(..., min_length=1)  # مطلوب (PRODUCTION_BUG_2)
    landmark:        str            = Field(default="")
    lat:             Optional[float]= None
    lon:             Optional[float]= None
    phone:           str            = Field(default="")
    ownership:       str            = Field(default="")
    ptype:           str            = Field(default="")
    # البوّابة ترسل created_by من هوية المستخدم — يُقبَل ولا يُستخدَم للتخزين حالياً
    # (جدول premises لا يحتوي عمود created_by — يُقبَل ويُتجاهَل بأمان)
    created_by:      Optional[str]  = Field(default="")


class PremGetRequest(_PremBase):
    """POST /premises/get"""
    # البوّابة ترسل premises_id كنص — نقبل int أو str رقمي
    premises_id: _IntFromAny


class PremUpdateRequest(_PremBase):
    """POST /premises/update"""
    premises_id:     _IntFromAny
    governorate:     Optional[str]  = None
    area:            Optional[str]  = None
    landmark:        Optional[str]  = None
    lat:             Optional[float]= None
    lon:             Optional[float]= None
    phone:           Optional[str]  = None
    ownership:       Optional[str]  = None
    ptype:           Optional[str]  = None


class PremDeleteRequest(_PremBase):
    """POST /premises/delete"""
    premises_id: _IntFromAny


class PremPhotoUploadRequest(_PremBase):
    """POST /premises/photo/upload — صورة مُشفَّرة Base64"""
    premises_id: _IntFromAny
    image_b64:   str  = Field(..., min_length=1, max_length=8_000_000,
                              description="بيانات الصورة Base64 (حدّ ~6MB قبل الفكّ — PRODUCTION_BUG_3)")
    ext:         str  = Field(default="jpg", description="امتداد الملف (jpg|png|webp)")


class PremPhotoGetRequest(_PremBase):
    """POST /premises/photo/get"""
    premises_id: _IntFromAny


class PremLinkRequest(_PremBase):
    """POST /premises/link"""
    premises_id:    _IntFromAny
    subscriber_ref: str = Field(..., min_length=1)


class PremUnlinkRequest(_PremBase):
    """POST /premises/unlink"""
    premises_id:    _IntFromAny
    subscriber_ref: str = Field(..., min_length=1)


class PremSubscribersRequest(_PremBase):
    """POST /premises/subscribers"""
    premises_id: _IntFromAny


class PremBySubscriberRequest(_PremBase):
    """POST /premises/by-subscriber"""
    subscriber_ref: str = Field(..., min_length=1)


class PremLinkCandidatesRequest(_PremBase):
    """POST /premises/link-candidates"""
    search: str  = Field(default="")
    limit:  int  = Field(default=20, ge=1, le=100)


# ═════════════════════════════════════════════════════════════════════════════
# الراوتر
# ═════════════════════════════════════════════════════════════════════════════

router = APIRouter(prefix="/premises", tags=["premises"])


@router.post("/list", dependencies=_DEP)
async def premises_list(body: PremListRequest) -> Any:
    """
    قائمة عقارات الوكيل مع تصفية بحثية وترقيم.

    عقد: POST /premises/list
      { companyId, ownerUserId, search?, ownership?, ptype?, page?, count? }
    → { premises:[…], total, page, count }
    """
    _guard_owner(body.companyId, body.ownerUserId)
    with _db() as conn:
        sql  = ("SELECT * FROM premises "
                "WHERE company_id = ? AND owner_user_id = ?")
        args: list = [body.companyId, body.ownerUserId]
        if body.ownership:
            sql += " AND ownership = ?";  args.append(body.ownership)
        if body.ptype:
            sql += " AND ptype = ?";      args.append(body.ptype)
        sql += " ORDER BY updated_at DESC"
        rows = [dict(r) for r in conn.execute(sql, args).fetchall()]

        if body.search:
            term = body.search.strip().lower()
            rows = [r for r in rows if term in (
                f"{r.get('npn','')} {r.get('npn_display','')} "
                f"{r.get('iqpin','')} {r.get('phone','')} "
                f"{r.get('governorate','')} {r.get('area','')} "
                f"{r.get('landmark','')}").lower()]

        total = len(rows)
        start = max(0, (body.page - 1) * body.count)
        page_rows = rows[start:start + body.count]

        # إضافة subscriber_count و has_photo لكل صف
        out = []
        for r in page_rows:
            cnt = conn.execute(
                "SELECT COUNT(*) FROM premises_subscribers WHERE premises_id = ?",
                (r["id"],)
            ).fetchone()[0]
            r["subscriber_count"] = cnt
            r["has_photo"] = bool(r.get("photo_path"))
            out.append(r)

    return {"premises": out, "total": total, "page": body.page, "count": body.count}


@router.post("/create", dependencies=_DEP)
async def premises_create(body: PremCreateRequest) -> Any:
    """
    ينشئ عقاراً: يخصّص NPN ذرّياً، يحسب IQ-Pin، يبني QR.

    عقد: POST /premises/create
      { companyId, ownerUserId, governorate, area, landmark, lat?, lon?,
        phone?, ownership?, ptype? }
    → العقار المُنشأ
    """
    _guard_owner(body.companyId, body.ownerUserId)
    if body.ownership and body.ownership not in _OWNERSHIP:
        raise HTTPException(400, "نوع الملكية غير صالح (owned|rent)")
    if body.ptype and body.ptype not in _PROPERTY:
        raise HTTPException(400, "نوع العقار غير صالح (residential|commercial)")

    codes = _generate_codes(body.governorate, body.gov_code, body.lat, body.lon)
    now   = _utcnow()
    with _db() as conn:
        cur = conn.execute("""
            INSERT INTO premises
                (company_id, owner_user_id, npn, npn_display, iqpin, iqpin_display,
                 gov_code, qr_payload, lat, lon, governorate, area, landmark,
                 phone, phone_norm, ownership, ptype, photo_path, created_at, updated_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """, (
            body.companyId, body.ownerUserId,
            codes["npn"], codes["npn_display"],
            codes["iqpin"], codes["iqpin_display"],
            codes["gov_code"], codes["qr_payload"],
            body.lat, body.lon,
            body.governorate, body.area, body.landmark,
            body.phone, _norm_phone(body.phone),
            body.ownership, body.ptype,
            "", now, now,
        ))
        pid = cur.lastrowid
        row = conn.execute(
            "SELECT * FROM premises WHERE id = ?", (pid,)
        ).fetchone()
        return _row_to_dict(conn, row, with_subscribers=True)


@router.post("/get", dependencies=_DEP)
async def premises_get(body: PremGetRequest) -> Any:
    """
    تفاصيل عقار واحد مع قائمة مشتركيه.

    عقد: POST /premises/get  { companyId, ownerUserId, premises_id }
    → العقار + subscribers
    """
    _guard_owner(body.companyId, body.ownerUserId)
    with _db() as conn:
        row = _get_owned_premises(conn, body.companyId, body.ownerUserId, body.premises_id)
        return _row_to_dict(conn, row, with_subscribers=True)


@router.post("/update", dependencies=_DEP)
async def premises_update(body: PremUpdateRequest) -> Any:
    """
    تحديث بيانات عقار. عند تغيّر الموقع يُعاد حساب IQ-Pin وQR (NPN ثابت).

    عقد: POST /premises/update
      { companyId, ownerUserId, premises_id, governorate?, area?, landmark?,
        lat?, lon?, phone?, ownership?, ptype? }
    → العقار المحدَّث
    """
    _guard_owner(body.companyId, body.ownerUserId)
    changes = body.model_dump(
        exclude={"companyId", "ownerUserId", "premises_id"},
        exclude_none=True
    )
    if not changes:
        raise HTTPException(400, "لا تغييرات — أرسل حقلاً واحداً على الأقل")
    if changes.get("ownership") and changes["ownership"] not in _OWNERSHIP:
        raise HTTPException(400, "نوع الملكية غير صالح (owned|rent)")
    if changes.get("ptype") and changes["ptype"] not in _PROPERTY:
        raise HTTPException(400, "نوع العقار غير صالح (residential|commercial)")

    now = _utcnow()
    with _db() as conn:
        row = _get_owned_premises(conn, body.companyId, body.ownerUserId, body.premises_id)
        current = dict(row)

        # تطبيق التغييرات على النسخة الحالية
        for k, v in changes.items():
            current[k] = v

        # إعادة حساب IQ-Pin وQR إن تغيّر الموقع (NPN يبقى)
        if "lat" in changes or "lon" in changes:
            pin = _recompute_iqpin(current.get("lat"), current.get("lon"))
            current["iqpin"]        = pin["iqpin"]
            current["iqpin_display"] = pin["iqpin_display"]
            current["qr_payload"]   = _build_qr_payload(
                current["npn"], pin["iqpin"],
                current.get("lat"), current.get("lon")
            )

        if "phone" in changes:
            current["phone_norm"] = _norm_phone(current.get("phone") or "")

        conn.execute("""
            UPDATE premises SET
                governorate=?, area=?, landmark=?, lat=?, lon=?,
                phone=?, phone_norm=?, ownership=?, ptype=?,
                iqpin=?, iqpin_display=?, qr_payload=?, updated_at=?
            WHERE id=? AND company_id=? AND owner_user_id=?
        """, (
            current["governorate"], current["area"], current["landmark"],
            current.get("lat"), current.get("lon"),
            current["phone"], current["phone_norm"],
            current["ownership"], current["ptype"],
            current["iqpin"], current["iqpin_display"], current["qr_payload"],
            now,
            body.premises_id, body.companyId, body.ownerUserId,
        ))
        updated = conn.execute(
            "SELECT * FROM premises WHERE id = ?", (body.premises_id,)
        ).fetchone()
        return _row_to_dict(conn, updated, with_subscribers=True)


@router.post("/delete", dependencies=_DEP)
async def premises_delete(body: PremDeleteRequest) -> Any:
    """
    حذف عقار وجميع روابط مشتركيه ومجلد وسائطه.

    عقد: POST /premises/delete  { companyId, ownerUserId, premises_id }
    → { ok, unlinked }
    """
    _guard_owner(body.companyId, body.ownerUserId)
    with _db() as conn:
        _get_owned_premises(conn, body.companyId, body.ownerUserId, body.premises_id)
        unlinked = conn.execute(
            "SELECT COUNT(*) FROM premises_subscribers WHERE premises_id = ?",
            (body.premises_id,)
        ).fetchone()[0]
        conn.execute(
            "DELETE FROM premises_subscribers WHERE premises_id = ?",
            (body.premises_id,)
        )
        conn.execute(
            "DELETE FROM premises WHERE id = ? AND company_id = ? AND owner_user_id = ?",
            (body.premises_id, body.companyId, body.ownerUserId)
        )

    _delete_media(body.premises_id)
    return {"ok": True, "unlinked": unlinked}


# ─── الصور ───────────────────────────────────────────────────────────────────

@router.post("/photo/upload", dependencies=_DEP)
async def photo_upload(body: PremPhotoUploadRequest) -> Any:
    """
    يرفع صورة الدار (Base64) ويستبدل القديمة.
    حماية: حدّ 6MB · امتدادات jpg/png/webp فقط · منع path traversal.

    عقد: POST /premises/photo/upload
      { companyId, ownerUserId, premises_id, image_b64, ext }
    → { ok, has_photo }
    """
    _guard_owner(body.companyId, body.ownerUserId)
    ext = ("." + (body.ext or "jpg").lower().lstrip("."))
    if ext not in _ALLOWED_EXT:
        raise HTTPException(400, f"امتداد غير مسموح — المتاح: jpg, png, webp")

    try:
        content = base64.b64decode(body.image_b64)
    except Exception:
        raise HTTPException(400, "بيانات Base64 غير صالحة")

    if len(content) > _MAX_PHOTO_BYTES:
        raise HTTPException(413, "حجم الصورة كبير جداً (الحدّ 6MB)")

    now = _utcnow()
    with _db() as conn:
        _get_owned_premises(conn, body.companyId, body.ownerUserId, body.premises_id)
        rel = _save_photo(body.premises_id, content, f"house{ext}")
        conn.execute(
            "UPDATE premises SET photo_path=?, updated_at=? "
            "WHERE id=? AND company_id=? AND owner_user_id=?",
            (rel, now, body.premises_id, body.companyId, body.ownerUserId)
        )

    return {"ok": True, "has_photo": True}


@router.post("/photo/get", dependencies=_DEP)
async def photo_get(body: PremPhotoGetRequest) -> Any:
    """
    يعيد مسار الصورة المخزَّنة (أو 404 إن لم توجد صورة).
    المسار المطلق آمن (path traversal محمي).

    عقد: POST /premises/photo/get  { companyId, ownerUserId, premises_id }
    → FileResponse (صورة مباشرة) أو 404
    """
    _guard_owner(body.companyId, body.ownerUserId)
    with _db() as conn:
        row = _get_owned_premises(conn, body.companyId, body.ownerUserId, body.premises_id)
        photo_path = row["photo_path"]

    ap = _photo_abspath(photo_path)
    if not ap:
        raise HTTPException(404, "لا صورة لهذا العقار")
    return FileResponse(str(ap))


# ─── ربط الاشتراكات (جدول الربط) ────────────────────────────────────────────

@router.post("/link", dependencies=_DEP)
async def premises_link(body: PremLinkRequest) -> Any:
    """
    يربط اشتراكاً بعقار. إن كان مربوطاً بعقار آخر يُنقَل (اشتراك → عقار واحد).

    عقد: POST /premises/link
      { companyId, ownerUserId, premises_id, subscriber_ref }
    → { ok, premises_id, subscriber_ref, subscriber_count }
    """
    _guard_owner(body.companyId, body.ownerUserId)
    now = _utcnow()
    with _db() as conn:
        _get_owned_premises(conn, body.companyId, body.ownerUserId, body.premises_id)
        existing = conn.execute(
            "SELECT id FROM premises_subscribers WHERE subscriber_ref = ?",
            (body.subscriber_ref,)
        ).fetchone()
        if existing:
            conn.execute(
                "UPDATE premises_subscribers SET premises_id=?, linked_at=? WHERE subscriber_ref=?",
                (body.premises_id, now, body.subscriber_ref)
            )
        else:
            conn.execute(
                "INSERT INTO premises_subscribers (premises_id, subscriber_ref, linked_at) "
                "VALUES (?,?,?)",
                (body.premises_id, body.subscriber_ref, now)
            )
        cnt = conn.execute(
            "SELECT COUNT(*) FROM premises_subscribers WHERE premises_id = ?",
            (body.premises_id,)
        ).fetchone()[0]

    return {
        "ok": True,
        "premises_id": body.premises_id,
        "subscriber_ref": body.subscriber_ref,
        "subscriber_count": cnt,
    }


@router.post("/unlink", dependencies=_DEP)
async def premises_unlink(body: PremUnlinkRequest) -> Any:
    """
    يفكّ ربط اشتراك عن عقار.

    عقد: POST /premises/unlink
      { companyId, ownerUserId, premises_id, subscriber_ref }
    → { ok, subscriber_count }
    """
    _guard_owner(body.companyId, body.ownerUserId)
    with _db() as conn:
        _get_owned_premises(conn, body.companyId, body.ownerUserId, body.premises_id)
        conn.execute(
            "DELETE FROM premises_subscribers "
            "WHERE premises_id=? AND subscriber_ref=?",
            (body.premises_id, body.subscriber_ref)
        )
        cnt = conn.execute(
            "SELECT COUNT(*) FROM premises_subscribers WHERE premises_id = ?",
            (body.premises_id,)
        ).fetchone()[0]

    return {"ok": True, "subscriber_count": cnt}


@router.post("/subscribers", dependencies=_DEP)
async def premises_subscribers(body: PremSubscribersRequest) -> Any:
    """
    قائمة الاشتراكات المرتبطة بعقار (مع بياناتها من local_subscribers إن وُجدت).

    عقد: POST /premises/subscribers  { companyId, ownerUserId, premises_id }
    → { subscribers:[…], count }
    """
    _guard_owner(body.companyId, body.ownerUserId)
    with _db() as conn:
        _get_owned_premises(conn, body.companyId, body.ownerUserId, body.premises_id)
        links = conn.execute(
            "SELECT subscriber_ref, linked_at FROM premises_subscribers "
            "WHERE premises_id = ?",
            (body.premises_id,)
        ).fetchall()
        subs = []
        for lnk in links:
            ref = lnk["subscriber_ref"]
            ls  = conn.execute(
                "SELECT * FROM local_subscribers WHERE username = ? LIMIT 1", (ref,)
            ).fetchone()
            if ls:
                r = dict(ls)
                r.pop("raw_json", None)
                r["linked_at"] = lnk["linked_at"]
                subs.append(r)
            else:
                subs.append({"subscriber_ref": ref, "linked_at": lnk["linked_at"]})

    return {"subscribers": subs, "count": len(subs)}


@router.post("/by-subscriber", dependencies=_DEP)
async def premises_by_subscriber(body: PremBySubscriberRequest) -> Any:
    """
    العقار المرتبط باشتراك معيّن (أو null إن لم يُربَط).

    عقد: POST /premises/by-subscriber
      { companyId, ownerUserId, subscriber_ref }
    → { premises: {…} | null }
    """
    _guard_owner(body.companyId, body.ownerUserId)
    with _db() as conn:
        lnk = conn.execute(
            "SELECT premises_id FROM premises_subscribers WHERE subscriber_ref = ?",
            (body.subscriber_ref,)
        ).fetchone()
        if not lnk:
            return {"premises": None}
        row = conn.execute(
            "SELECT * FROM premises "
            "WHERE id = ? AND company_id = ? AND owner_user_id = ?",
            (lnk["premises_id"], body.companyId, body.ownerUserId)
        ).fetchone()
        if not row:
            return {"premises": None}
        return {"premises": _row_to_dict(conn, row, with_subscribers=True)}


@router.post("/link-candidates", dependencies=_DEP)
async def link_candidates(body: PremLinkCandidatesRequest) -> Any:
    """
    يبحث في local_subscribers للعثور على مشتركين ضمن النطاق للربط بعقار.
    يُبيّن حالة الربط الحالية (هل مرتبط بعقار أم لا).

    عقد: POST /premises/link-candidates
      { companyId, ownerUserId, search?, limit? }
    → { candidates:[…], count }
    """
    _guard_owner(body.companyId, body.ownerUserId)
    with _db() as conn:
        # جلب المشتركين ضمن النطاق (company_id + owner_user_id)
        sql  = ("SELECT * FROM local_subscribers "
                "WHERE company_id = ? AND owner_user_id = ?")
        args: list = [body.companyId, body.ownerUserId]
        rows = [dict(r) for r in conn.execute(sql, args).fetchall()]

        if body.search:
            term = body.search.strip().lower()
            rows = [r for r in rows if
                    term in (r.get("username") or "").lower() or
                    term in (r.get("name") or "").lower() or
                    term in (r.get("phone") or "").lower()]

        rows = rows[:max(1, min(body.limit, 100))]

        # حالة الربط لكل اشتراك
        refs   = [r.get("username", "") for r in rows if r.get("username")]
        linked: Dict[str, int] = {}
        if refs:
            placeholders = ",".join("?" * len(refs))
            for lnk in conn.execute(
                f"SELECT subscriber_ref, premises_id FROM premises_subscribers "
                f"WHERE subscriber_ref IN ({placeholders})",
                refs
            ).fetchall():
                linked[lnk["subscriber_ref"]] = lnk["premises_id"]

        candidates = []
        for r in rows:
            r.pop("raw_json", None)
            r["premises_id"] = linked.get(r.get("username", ""))
            candidates.append(r)

    return {"candidates": candidates, "count": len(candidates)}
