"""
التذاكر — مسارات الموظّفين /api/tickets/* (تطبيق الوكلاء · تطبيق الشركات · منصّة الوزارة).

العزل: الوكيل يرى تذاكر مشتركيه، الشركة تذاكرها كلّها، الوزارة الكل.
  GET   /stats                       إحصاءات للوحات
  GET   /                            قائمة (status/category/company_id/agent/escalated/search)
  POST  /                            فتح تذكرة نيابةً عن مشترك (operator+)
  GET   /{id}                        تفاصيل + الردود
  PATCH /{id}                        status / priority / assigned_to / escalated (operator+)
  POST  /{id}/reply                  ردّ (عام أو داخلي)
"""
from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlmodel import Session, select

from ..core.auth import current_identity, require_role, scope_of
from ..database import get_session
from ..models import Subscriber, Ticket, TicketReply, utcnow
from ..services import otp as otp_svc
from ..services import tickets as tk

router = APIRouter(prefix="/api/tickets", tags=["tickets"])
_operator = [Depends(require_role("operator"))]


class TicketStaffCreate(BaseModel):
    subscriber_id: int                     # صف Subscriber (من /api/companies/subscribers)
    category: str = "complaint"
    subject: str = Field(min_length=3, max_length=200)
    body: str = Field(default="", max_length=4000)
    priority: str = "normal"


class TicketPatch(BaseModel):
    status: Optional[str] = None
    priority: Optional[str] = None
    assigned_to: Optional[str] = None
    escalated: Optional[bool] = None


class ReplyIn(BaseModel):
    body: str = Field(min_length=1, max_length=4000)
    internal: bool = False


@router.get("/stats")
def ticket_stats(identity: dict = Depends(current_identity), db: Session = Depends(get_session)):
    return tk.stats(db, identity)


@router.get("")
def list_tickets(status: Optional[str] = None, category: Optional[str] = None,
                 company_id: Optional[int] = None, agent: Optional[str] = None,
                 escalated: Optional[bool] = None, search: Optional[str] = None,
                 page: int = 1, count: int = 50,
                 identity: dict = Depends(current_identity), db: Session = Depends(get_session)):
    q = tk.scoped_query(identity)
    scope_cid, scope_agent = scope_of(identity)
    # تضييق اختياري داخل النطاق فقط (لا توسيع)
    if company_id is not None and scope_cid is None:
        q = q.where(Ticket.company_id == company_id)
    if agent and not scope_agent.strip():
        q = q.where(Ticket.agent_username == agent)
    if status:
        q = q.where(Ticket.status == status)
    if category:
        q = q.where(Ticket.category == category)
    if escalated is not None:
        q = q.where(Ticket.escalated == escalated)
    rows = db.exec(q.order_by(Ticket.created_at.desc())).all()  # type: ignore[attr-defined]
    if search:
        s = search.strip()
        rows = [t for t in rows if s in t.subject or s in t.subscriber_username
                or s in t.subscriber_name or s in t.subscriber_phone]
    total = len(rows)
    page = max(1, page); count = max(1, min(count, 500))
    start = (page - 1) * count
    names = tk.company_names(db)
    return {"total": total, "page": page, "count": count,
            "tickets": [tk.to_dict(t, names.get(t.company_id, "")) for t in rows[start:start + count]]}


@router.post("", status_code=201, dependencies=_operator)
def create_for_subscriber(body: TicketStaffCreate, identity: dict = Depends(current_identity),
                          db: Session = Depends(get_session)):
    """فتح تذكرة نيابةً عن مشترك (اتصال هاتفي/زيارة مكتب الوكيل)."""
    if body.category not in tk.CATEGORIES:
        raise HTTPException(400, "تصنيف غير معروف")
    if body.priority not in tk.PRIORITIES:
        raise HTTPException(400, "أولوية غير معروفة")
    sub = db.get(Subscriber, body.subscriber_id)
    scope_cid, scope_agent = scope_of(identity)
    if (not sub or (scope_cid is not None and sub.company_id != scope_cid)
            or (scope_agent.strip() and sub.agent_username != scope_agent.strip())):
        raise HTTPException(404, "المشترك غير موجود ضمن نطاقك")
    t = Ticket(
        company_id=sub.company_id, agent_username=sub.agent_username,
        subscriber_username=sub.username,
        subscriber_phone=otp_svc.normalize_phone(sub.phone),
        subscriber_name=(f"{sub.firstname} {sub.lastname}").strip(),
        category=body.category, subject=body.subject.strip(), body=body.body.strip(),
        priority=body.priority,
        created_by=identity.get("user") or "system", created_by_kind=tk.kind_of(identity),
    )
    db.add(t); db.commit(); db.refresh(t)
    return tk.to_dict(t, tk.company_names(db).get(t.company_id, ""), replies=[])


@router.get("/{ticket_id}")
def get_ticket(ticket_id: int, identity: dict = Depends(current_identity),
               db: Session = Depends(get_session)):
    t = tk.get_visible(db, identity, ticket_id)
    replies = db.exec(select(TicketReply).where(TicketReply.ticket_id == t.id)
                      .order_by(TicketReply.ts)).all()  # type: ignore[attr-defined]
    return tk.to_dict(t, tk.company_names(db).get(t.company_id, ""), replies=replies)


@router.patch("/{ticket_id}", dependencies=_operator)
def patch_ticket(ticket_id: int, body: TicketPatch, identity: dict = Depends(current_identity),
                 db: Session = Depends(get_session)):
    t = tk.get_visible(db, identity, ticket_id)
    if body.status is not None:
        if body.status not in tk.STATUSES:
            raise HTTPException(400, "حالة غير معروفة")
        t.status = body.status
        t.resolved_at = utcnow() if body.status in ("resolved", "closed") else None
    if body.priority is not None:
        if body.priority not in tk.PRIORITIES:
            raise HTTPException(400, "أولوية غير معروفة")
        t.priority = body.priority
    if body.assigned_to is not None:
        t.assigned_to = body.assigned_to.strip()[:80]
    if body.escalated is not None:
        # التصعيد للوزارة: من الشركة أو الوزارة فقط (الوكيل لا يُصعّد)
        if tk.kind_of(identity) == "agent":
            raise HTTPException(403, "التصعيد من صلاحية الشركة أو الجهة الرقابية")
        t.escalated = body.escalated
    t.updated_at = utcnow()
    db.add(t); db.commit(); db.refresh(t)
    return tk.to_dict(t, tk.company_names(db).get(t.company_id, ""))


@router.post("/{ticket_id}/reply", status_code=201)
def reply_ticket(ticket_id: int, body: ReplyIn, identity: dict = Depends(current_identity),
                 db: Session = Depends(get_session)):
    t = tk.get_visible(db, identity, ticket_id)
    r = tk.add_reply(db, t, author=identity.get("user") or "system",
                     author_kind=tk.kind_of(identity), body=body.body, internal=body.internal)
    return {"id": r.id, "ticket_id": t.id, "status": t.status}
