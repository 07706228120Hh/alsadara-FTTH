"""
التذاكر — منطق مشترك بين مسارات المشترك (/api/subscriber/tickets) ومسارات الموظّفين (/api/tickets).

سلسلة المتابعة: المشترك يفتح → الوكيل يعالج → الشركة تراقب/تُصعِّد → الوزارة ترى الكل.
كل طرف يرى نطاقه فقط (عزل عبر company_id / agent_username / subscriber_phone).
"""
from __future__ import annotations

from typing import Optional

from fastapi import HTTPException
from sqlmodel import Session, select

from ..models import Company, Ticket, TicketReply, utcnow

CATEGORIES = ("complaint", "outage", "billing", "speed", "other")
STATUSES = ("open", "in_progress", "resolved", "closed")
PRIORITIES = ("low", "normal", "high", "urgent")

CATEGORY_AR = {"complaint": "شكوى", "outage": "انقطاع", "billing": "فوترة/رصيد",
               "speed": "بطء السرعة", "other": "أخرى"}
STATUS_AR = {"open": "مفتوحة", "in_progress": "قيد المعالجة",
             "resolved": "محلولة", "closed": "مغلقة"}


def kind_of(identity: dict) -> str:
    """نوع الطرف: subscriber | agent | company | regulator."""
    if identity.get("kind") == "subscriber":
        return "subscriber"
    if (identity.get("agent") or "").strip():
        return "agent"
    if identity.get("company_id") is not None:
        return "company"
    return "regulator"


def scoped_query(identity: dict):
    """استعلام التذاكر مقيّداً بنطاق الطالب."""
    q = select(Ticket)
    k = kind_of(identity)
    if k == "subscriber":
        return q.where(Ticket.subscriber_phone == identity["phone"])
    if k == "agent":
        return q.where(Ticket.company_id == identity["company_id"],
                       Ticket.agent_username == identity["agent"].strip())
    if k == "company":
        return q.where(Ticket.company_id == identity["company_id"])
    return q


def get_visible(db: Session, identity: dict, ticket_id: int) -> Ticket:
    """التذكرة إن كانت ضمن النطاق وإلا 404 (لا 403 — لا نكشف الوجود)."""
    t = db.exec(scoped_query(identity).where(Ticket.id == ticket_id)).first()
    if not t:
        raise HTTPException(404, "التذكرة غير موجودة")
    return t


def to_dict(t: Ticket, company_name: str = "", replies: Optional[list[TicketReply]] = None,
            hide_internal: bool = False) -> dict:
    d = {
        "id": t.id, "company_id": t.company_id, "company": company_name,
        "agent": t.agent_username, "subscriber": t.subscriber_username,
        "subscriber_name": t.subscriber_name, "subscriber_phone": t.subscriber_phone,
        "category": t.category, "category_ar": CATEGORY_AR.get(t.category, t.category),
        "subject": t.subject, "body": t.body,
        "status": t.status, "status_ar": STATUS_AR.get(t.status, t.status),
        "priority": t.priority, "escalated": t.escalated,
        "created_by": t.created_by, "created_by_kind": t.created_by_kind,
        "assigned_to": t.assigned_to,
        "created_at": t.created_at.isoformat() if t.created_at else None,
        "updated_at": t.updated_at.isoformat() if t.updated_at else None,
        "resolved_at": t.resolved_at.isoformat() if t.resolved_at else None,
    }
    if replies is not None:
        d["replies"] = [{
            "id": r.id, "author": r.author, "author_kind": r.author_kind,
            "body": r.body, "internal": r.internal,
            "ts": r.ts.isoformat() if r.ts else None,
        } for r in replies if not (hide_internal and r.internal)]
    return d


def company_names(db: Session) -> dict[int, str]:
    return {c.id: c.name for c in db.exec(select(Company)).all()}


def add_reply(db: Session, t: Ticket, author: str, author_kind: str, body: str,
              internal: bool = False) -> TicketReply:
    body = (body or "").strip()
    if not body:
        raise HTTPException(400, "نصّ الردّ فارغ")
    if len(body) > 4000:
        raise HTTPException(400, "الردّ طويل جداً (الحدّ 4000 حرف)")
    r = TicketReply(ticket_id=t.id, author=author, author_kind=author_kind,
                    body=body, internal=internal)
    t.updated_at = utcnow()
    # ردّ الموظّف على تذكرة مفتوحة يجعلها «قيد المعالجة» تلقائياً
    if author_kind != "subscriber" and t.status == "open" and not internal:
        t.status = "in_progress"
    db.add(r); db.add(t); db.commit(); db.refresh(r)
    return r


def stats(db: Session, identity: dict) -> dict:
    """إحصاءات موجزة للوحات: حسب الحالة والتصنيف + المُصعَّدة."""
    rows = db.exec(scoped_query(identity)).all()
    by_status = {s: 0 for s in STATUSES}
    by_cat = {c: 0 for c in CATEGORIES}
    escalated = 0
    for t in rows:
        by_status[t.status] = by_status.get(t.status, 0) + 1
        by_cat[t.category] = by_cat.get(t.category, 0) + 1
        if t.escalated:
            escalated += 1
    return {"total": len(rows), "by_status": by_status, "by_category": by_cat,
            "escalated": escalated,
            "open_total": by_status["open"] + by_status["in_progress"]}
