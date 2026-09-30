"""راوتر وحدة العقارات — CRUD + ربط الاشتراكات (جدول ربط) + صورة الدار.

عزل النطاق: كل وكيل يرى عقاراته فقط (company_id + agent_username). الربط بالاشتراكات
عبر جدول `PremisesSubscriber` (لا يُلمَس نموذج Subscriber). عقار واحد → عدّة اشتراكات.
"""
from __future__ import annotations

import re
from typing import Optional

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel
from sqlmodel import Session, select

from ..core.auth import current_identity, require_role, scope_of
from ..database import get_session
from ..models import Subscriber            # قراءة فقط (عرض/ربط) — لا يُعدَّل
from . import service
from .models import Premises, PremisesSubscriber, utcnow

router = APIRouter(prefix="/api/premises", tags=["premises"])

_OWNERSHIP = {"owned", "rent"}
_PROPERTY = {"residential", "commercial"}
_MAX_PHOTO_BYTES = 6 * 1024 * 1024  # 6MB


# ══════════════════════ مخطّطات الإدخال ══════════════════════
class PremisesIn(BaseModel):
    governorate: str = ""
    gov_code: Optional[int] = None
    district: str = ""
    landmark: str = ""
    address_details: str = ""
    lat: Optional[float] = None
    lon: Optional[float] = None
    phone: str = ""
    ownership: str = ""
    property_type: str = ""
    owner_name: str = ""
    notes: str = ""


class PremisesUpdate(BaseModel):
    governorate: Optional[str] = None
    district: Optional[str] = None
    landmark: Optional[str] = None
    address_details: Optional[str] = None
    lat: Optional[float] = None
    lon: Optional[float] = None
    phone: Optional[str] = None
    ownership: Optional[str] = None
    property_type: Optional[str] = None
    owner_name: Optional[str] = None
    notes: Optional[str] = None


class LinkIn(BaseModel):
    subscriber_ids: list[int] = []


# ══════════════════════ مساعدات ══════════════════════
def _norm_phone(raw: str) -> str:
    d = re.sub(r"\D", "", raw or "")
    if d.startswith("00964"):
        d = d[5:]
    if d.startswith("964"):
        d = d[3:]
    if d.startswith("0"):
        d = d[1:]
    return f"964{d}" if len(d) == 10 and d.startswith("7") else ""


def _scoped(identity: dict):
    scope_cid, scope_agent = scope_of(identity)
    q = select(Premises)
    if scope_cid is not None:
        q = q.where(Premises.company_id == scope_cid)
        if scope_agent.strip():
            q = q.where(Premises.agent_username == scope_agent.strip())
    return q


def _get_owned(db: Session, identity: dict, pid: int) -> Premises:
    p = db.get(Premises, pid)
    if not p:
        raise HTTPException(404, "العقار غير موجود")
    scope_cid, scope_agent = scope_of(identity)
    if scope_cid is not None:
        if p.company_id != scope_cid:
            raise HTTPException(404, "العقار غير ضمن نطاقك")
        if scope_agent.strip() and p.agent_username != scope_agent.strip():
            raise HTTPException(404, "العقار غير ضمن نطاقك")
    return p


def _linked_sub_ids(db: Session, pid: int) -> list[int]:
    links = db.exec(select(PremisesSubscriber).where(PremisesSubscriber.premises_id == pid)).all()
    return [ln.subscriber_id for ln in links]


def _subscribers_payload(db: Session, pid: int) -> list[dict]:
    out = []
    for sid in _linked_sub_ids(db, pid):
        s = db.get(Subscriber, sid)
        if not s:
            continue
        out.append({
            "id": s.id, "username": s.username,
            "name": (f"{s.firstname} {s.lastname}").strip(),
            "profile": s.profile_name, "status": s.status,
            "expiration": s.expiration, "phone": s.phone, "online": s.online,
        })
    return out


def _out(db: Session, p: Premises, with_subscribers: bool = False) -> dict:
    ids = _linked_sub_ids(db, p.id)
    d = {
        "id": p.id, "company_id": p.company_id, "agent_username": p.agent_username,
        "npn": p.npn, "npn_display": p.npn_display,
        "iqpin": p.iqpin, "iqpin_display": p.iqpin_display,
        "gov_code": p.gov_code, "qr_payload": p.qr_payload,
        "lat": p.lat, "lon": p.lon,
        "governorate": p.governorate, "district": p.district,
        "landmark": p.landmark, "address_details": p.address_details,
        "phone": p.phone, "ownership": p.ownership, "property_type": p.property_type,
        "owner_name": p.owner_name, "notes": p.notes,
        "has_photo": bool(p.photo_path),
        "subscriber_count": len(ids),
        "created_at": p.created_at.isoformat() if p.created_at else None,
        "updated_at": p.updated_at.isoformat() if p.updated_at else None,
    }
    if with_subscribers:
        d["subscribers"] = _subscribers_payload(db, p.id)
    return d


def _subs_in_scope(db: Session, identity: dict, ids: list[int]) -> list[Subscriber]:
    scope_cid, scope_agent = scope_of(identity)
    out = []
    for sid in ids:
        s = db.get(Subscriber, sid)
        if not s:
            continue
        if scope_cid is not None:
            if s.company_id != scope_cid:
                continue
            if scope_agent.strip() and s.agent_username != scope_agent.strip():
                continue
        out.append(s)
    return out


# ══════════════════════ نقاط النهاية ══════════════════════
@router.get("")
def list_premises(q: Optional[str] = None, property_type: Optional[str] = None,
                  ownership: Optional[str] = None, governorate: Optional[str] = None,
                  page: int = 1, count: int = 50,
                  db: Session = Depends(get_session),
                  identity: dict = Depends(current_identity)):
    """قائمة العقارات ضمن النطاق مع تصفية بحثية."""
    query = _scoped(identity)
    if property_type:
        query = query.where(Premises.property_type == property_type)
    if ownership:
        query = query.where(Premises.ownership == ownership)
    if governorate:
        query = query.where(Premises.governorate == governorate)
    rows = db.exec(query.order_by(Premises.updated_at.desc())).all()
    if q:
        term = q.strip().lower()
        rows = [p for p in rows if term in (
            f"{p.npn} {p.npn_display} {p.iqpin} {p.phone} {p.owner_name} "
            f"{p.governorate} {p.district} {p.landmark} {p.address_details}").lower()]
    total = len(rows)
    start = max(0, (page - 1) * count)
    page_rows = rows[start:start + count]
    return {"premises": [_out(db, p) for p in page_rows], "total": total,
            "page": page, "count": count}


@router.post("")
def create_premises(body: PremisesIn, db: Session = Depends(get_session),
                    identity: dict = Depends(require_role("operator"))):
    """ينشئ عقاراً: يخصّص NPN، ويحسب IQ-Pin من الإحداثيات (إن وُجدت)، ويبني حمولة QR."""
    if body.ownership and body.ownership not in _OWNERSHIP:
        raise HTTPException(400, "نوع الملكية غير صالح (owned|rent)")
    if body.property_type and body.property_type not in _PROPERTY:
        raise HTTPException(400, "نوع العقار غير صالح (residential|commercial)")

    scope_cid, scope_agent = scope_of(identity)
    codes = service.generate_codes(db, body.governorate, body.gov_code, body.lat, body.lon)
    p = Premises(
        company_id=scope_cid,
        agent_username=(scope_agent or "").strip(),
        npn=codes["npn"], npn_display=codes["npn_display"],
        iqpin=codes["iqpin"], iqpin_display=codes["iqpin_display"],
        gov_code=codes["gov_code"], qr_payload=codes["qr_payload"],
        lat=body.lat, lon=body.lon,
        governorate=body.governorate, district=body.district,
        landmark=body.landmark, address_details=body.address_details,
        phone=body.phone, phone_norm=_norm_phone(body.phone),
        ownership=body.ownership, property_type=body.property_type,
        owner_name=body.owner_name, notes=body.notes,
        created_by=(identity.get("user") or ""),
    )
    db.add(p)
    db.commit()
    db.refresh(p)
    return _out(db, p, with_subscribers=True)


@router.get("/by-subscriber/{sid}")
def premises_of_subscriber(sid: int, db: Session = Depends(get_session),
                           identity: dict = Depends(current_identity)):
    """عقار مشترك معيّن (لعرضه في تفاصيل المشترك)، أو null إن لم يُربَط."""
    link = db.exec(select(PremisesSubscriber)
                   .where(PremisesSubscriber.subscriber_id == sid)).first()
    if not link:
        return {"premises": None}
    p = _get_owned(db, identity, link.premises_id)
    return {"premises": _out(db, p, with_subscribers=True)}


@router.get("/link-candidates")
def link_candidates(q: str = "", limit: int = 20, db: Session = Depends(get_session),
                    identity: dict = Depends(current_identity)):
    """اشتراكات ضمن النطاق للبحث عند ربطها بعقار (مع بيان المربوط مسبقاً)."""
    scope_cid, scope_agent = scope_of(identity)
    query = select(Subscriber)
    if scope_cid is not None:
        query = query.where(Subscriber.company_id == scope_cid)
        if scope_agent.strip():
            query = query.where(Subscriber.agent_username == scope_agent.strip())
    rows = db.exec(query).all()
    term = q.strip().lower()
    if term:
        rows = [s for s in rows if term in (
            f"{s.username} {s.firstname} {s.lastname} {s.phone}").lower()]
    rows = rows[:max(1, min(limit, 100))]
    # حالة الربط الحالية لكل اشتراك
    linked = {ln.subscriber_id: ln.premises_id for ln in db.exec(
        select(PremisesSubscriber).where(
            PremisesSubscriber.subscriber_id.in_([s.id for s in rows] or [-1]))).all()}
    return {"candidates": [{
        "id": s.id, "username": s.username,
        "name": (f"{s.firstname} {s.lastname}").strip(),
        "phone": s.phone, "profile": s.profile_name, "status": s.status,
        "premises_id": linked.get(s.id),
    } for s in rows], "count": len(rows)}


@router.get("/{pid}")
def get_premises(pid: int, db: Session = Depends(get_session),
                 identity: dict = Depends(current_identity)):
    p = _get_owned(db, identity, pid)
    return _out(db, p, with_subscribers=True)


@router.patch("/{pid}")
def update_premises(pid: int, body: PremisesUpdate, db: Session = Depends(get_session),
                    identity: dict = Depends(require_role("operator"))):
    p = _get_owned(db, identity, pid)
    data = body.model_dump(exclude_unset=True)
    if data.get("ownership") and data["ownership"] not in _OWNERSHIP:
        raise HTTPException(400, "نوع الملكية غير صالح")
    if data.get("property_type") and data["property_type"] not in _PROPERTY:
        raise HTTPException(400, "نوع العقار غير صالح")

    for k, v in data.items():
        setattr(p, k, v)
    if "phone" in data:
        p.phone_norm = _norm_phone(data["phone"] or "")
    # عند تغيّر الموقع: أعِد حساب IQ-Pin وحمولة الـ QR (NPN يبقى ثابتاً).
    if "lat" in data or "lon" in data:
        pin = service.recompute_iqpin(p.lat, p.lon)
        p.iqpin = pin["iqpin"]
        p.iqpin_display = pin["iqpin_display"]
        p.qr_payload = service.build_qr_payload(p.npn, p.iqpin, p.lat, p.lon)
    p.updated_at = utcnow()
    db.add(p)
    db.commit()
    db.refresh(p)
    return _out(db, p, with_subscribers=True)


@router.delete("/{pid}")
def delete_premises(pid: int, db: Session = Depends(get_session),
                    identity: dict = Depends(require_role("operator"))):
    p = _get_owned(db, identity, pid)
    links = db.exec(select(PremisesSubscriber).where(PremisesSubscriber.premises_id == pid)).all()
    for ln in links:
        db.delete(ln)
    service.delete_media(pid)
    db.delete(p)
    db.commit()
    return {"ok": True, "unlinked": len(links)}


# ── الصور ──
@router.post("/{pid}/photo")
async def upload_photo(pid: int, file: UploadFile = File(...),
                       db: Session = Depends(get_session),
                       identity: dict = Depends(require_role("operator"))):
    """يرفع صورة الدار (تستبدل القديمة)."""
    p = _get_owned(db, identity, pid)
    content = await file.read()
    if len(content) > _MAX_PHOTO_BYTES:
        raise HTTPException(413, "حجم الصورة كبير جداً (الحد 6MB)")
    p.photo_path = service.save_photo(pid, content, file.filename or "house.jpg")
    p.updated_at = utcnow()
    db.add(p)
    db.commit()
    return {"ok": True, "has_photo": True}


@router.get("/{pid}/photo")
def get_photo(pid: int, db: Session = Depends(get_session),
              identity: dict = Depends(current_identity)):
    """يخدم صورة الدار (ضمن النطاق)."""
    p = _get_owned(db, identity, pid)
    ap = service.photo_abspath(p.photo_path)
    if not ap:
        raise HTTPException(404, "لا صورة لهذا العقار")
    return FileResponse(str(ap))


# ── ربط الاشتراكات (جدول الربط) ──
@router.post("/{pid}/link")
def link_subscribers(pid: int, body: LinkIn, db: Session = Depends(get_session),
                     identity: dict = Depends(require_role("operator"))):
    """يربط اشتراكات بهذا العقار (عقار واحد → عدّة اشتراكات). ينقل الاشتراك إن كان
    مربوطاً بعقار آخر (اشتراك ينتمي لعقار واحد)."""
    p = _get_owned(db, identity, pid)
    subs = _subs_in_scope(db, identity, body.subscriber_ids)
    linked = 0
    for s in subs:
        existing = db.exec(select(PremisesSubscriber)
                           .where(PremisesSubscriber.subscriber_id == s.id)).first()
        if existing:
            existing.premises_id = p.id
            db.add(existing)
        else:
            db.add(PremisesSubscriber(premises_id=p.id, subscriber_id=s.id))
        linked += 1
    db.commit()
    return {"ok": True, "linked": linked, "subscriber_count": len(_linked_sub_ids(db, p.id))}


@router.post("/{pid}/unlink")
def unlink_subscribers(pid: int, body: LinkIn, db: Session = Depends(get_session),
                       identity: dict = Depends(require_role("operator"))):
    """يفكّ ربط اشتراكات محدّدة (أو الكل إن كانت القائمة فارغة) عن العقار."""
    p = _get_owned(db, identity, pid)
    q = select(PremisesSubscriber).where(PremisesSubscriber.premises_id == pid)
    if body.subscriber_ids:
        q = q.where(PremisesSubscriber.subscriber_id.in_(body.subscriber_ids))
    links = db.exec(q).all()
    for ln in links:
        db.delete(ln)
    db.commit()
    return {"ok": True, "unlinked": len(links), "subscriber_count": len(_linked_sub_ids(db, p.id))}


@router.get("/{pid}/subscribers")
def premises_subscribers(pid: int, db: Session = Depends(get_session),
                         identity: dict = Depends(current_identity)):
    """قائمة الاشتراكات في هذا العقار."""
    p = _get_owned(db, identity, pid)
    subs = _subscribers_payload(db, p.id)
    return {"subscribers": subs, "count": len(subs)}
