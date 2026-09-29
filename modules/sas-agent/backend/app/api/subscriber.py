"""
تطبيق المشتركين — مسارات /api/subscriber/*.

الدخول برقم الهاتف + رمز OTP عبر واتساب (لا كلمة مرور):
  POST /otp/request  {phone}         → يُرسل رمزاً (يُعاد في dev_code بوضع التطوير فقط)
  POST /otp/verify   {phone, code}   → توكن جلسة مشترك
  GET  /me                            → حسابات المشترك لدى الشركات (من لقطات SAS)
  GET  /tickets · POST /tickets · GET /tickets/{id} · POST /tickets/{id}/reply

توكن المشترك مرفوض في كل مسارات الموظّفين (require_auth)، ومسارات هذا الملف
ترفض توكنات الموظّفين (require_subscriber) — فصل كامل بين التطبيقين.
"""
from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlmodel import Session, select

from ..config import settings
from ..core import security
from ..core.auth import require_subscriber
from ..database import get_session
from ..models import Agent, Company, Subscriber, Ticket, TicketReply
from ..services import otp as otp_svc
from ..services import tickets as tk

router = APIRouter(prefix="/api/subscriber", tags=["subscriber-app"])


# ─────────────────────────────── OTP ───────────────────────────────

class OtpRequest(BaseModel):
    phone: str = Field(min_length=7, max_length=24)


class OtpVerify(BaseModel):
    phone: str = Field(min_length=7, max_length=24)
    code: str = Field(min_length=4, max_length=8)


@router.post("/otp/request")
def otp_request(body: OtpRequest, db: Session = Depends(get_session)):
    """طلب رمز تحقّق. لا يكشف إن كان الرقم مسجّلاً (استجابة موحّدة) — إلا في وضع التطوير."""
    phone = otp_svc.normalize_phone(body.phone)
    if not phone:
        raise HTTPException(400, "رقم الهاتف غير صالح — أدخل رقماً عراقياً مثل 07701234567")
    accounts = otp_svc.find_subscriber_accounts(db, phone)
    resp = {"sent": True, "expires_in": settings.otp_ttl_seconds,
            "masked": f"****{phone[-4:]}"}
    if not accounts:
        # لا نُصدر رمزاً لرقم غير مسجّل، لكن الاستجابة موحّدة كي لا تُعدَّد الأرقام
        if settings.otp_echo_enabled:
            resp["dev_note"] = "الرقم غير مسجّل لدى أي شركة — لم يُصدر رمز"
        return resp
    try:
        code = otp_svc.issue_code(db, phone)
    except otp_svc.OtpRateLimited:
        raise HTTPException(429, "تجاوزت حدّ الطلبات — حاول بعد قليل")
    delivered = otp_svc.send_whatsapp(phone, otp_svc.otp_message(code))
    resp["delivered"] = delivered
    if settings.otp_echo_enabled:
        resp["dev_code"] = code
    return resp


@router.post("/otp/verify")
def otp_verify(body: OtpVerify, db: Session = Depends(get_session)):
    """التحقّق من الرمز وإصدار توكن جلسة المشترك."""
    phone = otp_svc.normalize_phone(body.phone)
    if not phone:
        raise HTTPException(400, "رقم الهاتف غير صالح")
    if not otp_svc.verify_code(db, phone, body.code):
        raise HTTPException(401, "رمز التحقّق غير صحيح أو منتهي الصلاحية")
    accounts = otp_svc.find_subscriber_accounts(db, phone)
    if not accounts:
        raise HTTPException(404, "لا يوجد اشتراك مرتبط بهذا الرقم")
    return {
        "token": security.make_subscriber_token(phone),
        "phone": phone,
        "role": "subscriber",
        "accounts": len(accounts),
        "expires_in": settings.subscriber_token_ttl_hours * 3600,
    }


# ─────────────────────────────── الحساب ───────────────────────────────

def _account_dict(s: Subscriber, companies: dict[int, Company], agents: dict) -> dict:
    c = companies.get(s.company_id)
    a = agents.get((s.company_id, s.agent_username))
    return {
        "id": s.id, "company_id": s.company_id,
        "company": c.name if c else "?",
        "username": s.username,
        "name": (f"{s.firstname} {s.lastname}").strip(),
        "profile": s.profile_name, "status": s.status, "online": s.online,
        "enabled": s.enabled, "expiration": s.expiration,
        "city": s.city, "governorate": s.governorate,
        "agent": s.agent_username,
        "agent_name": (f"{a.firstname} {a.lastname}").strip() if a else "",
        "updated_at": s.updated_at.isoformat() if s.updated_at else None,
    }


@router.get("/me")
def me(identity: dict = Depends(require_subscriber), db: Session = Depends(get_session)):
    """حسابات المشترك لدى كل الشركات المرتبطة بالمنصّة (بيانات SAS آخر مزامنة)."""
    phone = identity["phone"]
    accounts = otp_svc.find_subscriber_accounts(db, phone)
    companies = {c.id: c for c in db.exec(select(Company)).all()}
    agents = {(a.company_id, a.username): a for a in db.exec(select(Agent)).all()}
    return {"phone": phone, "masked": f"****{phone[-4:]}",
            "accounts": [_account_dict(s, companies, agents) for s in accounts]}


# ─────────────────────────────── التذاكر ───────────────────────────────

class TicketCreate(BaseModel):
    account_id: int                      # حساب المشترك (من /me) الذي تخصّه الشكوى
    category: str = "complaint"
    subject: str = Field(min_length=3, max_length=200)
    body: str = Field(default="", max_length=4000)


class ReplyIn(BaseModel):
    body: str = Field(min_length=1, max_length=4000)


@router.get("/tickets")
def my_tickets(status: Optional[str] = None,
               identity: dict = Depends(require_subscriber),
               db: Session = Depends(get_session)):
    q = tk.scoped_query(identity)
    if status:
        q = q.where(Ticket.status == status)
    rows = db.exec(q.order_by(Ticket.created_at.desc())).all()  # type: ignore[attr-defined]
    names = tk.company_names(db)
    return {"tickets": [tk.to_dict(t, names.get(t.company_id, "")) for t in rows],
            "count": len(rows)}


@router.post("/tickets", status_code=201)
def create_ticket(body: TicketCreate, identity: dict = Depends(require_subscriber),
                  db: Session = Depends(get_session)):
    """فتح تذكرة على أحد حسابات المشترك — تُوجَّه تلقائياً لوكيله وشركته."""
    if body.category not in tk.CATEGORIES:
        raise HTTPException(400, f"تصنيف غير معروف — المسموح: {', '.join(tk.CATEGORIES)}")
    phone = identity["phone"]
    acc = db.get(Subscriber, body.account_id)
    if not acc or acc.phone_norm != phone:
        raise HTTPException(404, "الحساب غير موجود أو لا يخصّ هذا الرقم")
    # حدّ معقول للتذاكر المفتوحة لكل مشترك (حماية من الإغراق)
    open_count = len(db.exec(tk.scoped_query(identity)
                             .where(Ticket.status.in_(("open", "in_progress")))).all())  # type: ignore[attr-defined]
    if open_count >= 10:
        raise HTTPException(429, "لديك 10 تذاكر مفتوحة — انتظر معالجتها قبل فتح غيرها")
    t = Ticket(
        company_id=acc.company_id, agent_username=acc.agent_username,
        subscriber_username=acc.username, subscriber_phone=phone,
        subscriber_name=(f"{acc.firstname} {acc.lastname}").strip(),
        category=body.category, subject=body.subject.strip(), body=body.body.strip(),
        created_by=phone, created_by_kind="subscriber",
    )
    db.add(t); db.commit(); db.refresh(t)
    names = tk.company_names(db)
    return tk.to_dict(t, names.get(t.company_id, ""), replies=[])


@router.get("/tickets/{ticket_id}")
def my_ticket(ticket_id: int, identity: dict = Depends(require_subscriber),
              db: Session = Depends(get_session)):
    t = tk.get_visible(db, identity, ticket_id)
    replies = db.exec(select(TicketReply).where(TicketReply.ticket_id == t.id)
                      .order_by(TicketReply.ts)).all()  # type: ignore[attr-defined]
    names = tk.company_names(db)
    return tk.to_dict(t, names.get(t.company_id, ""), replies=replies, hide_internal=True)


@router.post("/tickets/{ticket_id}/reply", status_code=201)
def my_ticket_reply(ticket_id: int, body: ReplyIn,
                    identity: dict = Depends(require_subscriber),
                    db: Session = Depends(get_session)):
    t = tk.get_visible(db, identity, ticket_id)
    if t.status == "closed":
        raise HTTPException(409, "التذكرة مغلقة — افتح تذكرة جديدة")
    r = tk.add_reply(db, t, author=identity["phone"], author_kind="subscriber", body=body.body)
    # ردّ المشترك على تذكرة محلولة يعيد فتحها
    if t.status == "resolved":
        t.status = "open"; t.resolved_at = None
        db.add(t); db.commit()
    return {"id": r.id, "ticket_id": t.id, "status": t.status}
