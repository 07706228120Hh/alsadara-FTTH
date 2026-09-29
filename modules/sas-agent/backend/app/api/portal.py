"""
بوابة التطبيقات المنفصلة — ملخّص لوحة واحد لكل نوع حساب: /api/portal/summary.

- وكيل:  بطاقته من SAS (users_count/الرصيد) + مشتركوه حسب الحالة + تذاكره.
- شركة:  آخر لقطة SAS للشركة + عدد وكلائها + المشتركون حسب الحالة + التذاكر + البلنك.
- وزارة: الصورة الوطنية (مجموع الشركات) + التذاكر (كلّها) — تكملة لـ /companies/overview/national.

نقطة واحدة بدل 4-5 نداءات عند فتح التطبيق؛ العزل مفروض بنفس scope_of.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy import func
from sqlmodel import Session, select

from ..core.auth import current_identity, scope_of
from ..database import get_session
from ..models import Agent, AgentReport, Company, CompanySnapshot, Subscriber, User
from ..services import tickets as tk
from ..services import expiry as expiry_svc


async def _agent_live_balance(u: User):
    """الرصيد ونقاط المكافآت الحيّة للوكيل من SAS (auth.client) — لا صفّ Agent للوكيل المستقل.
    أفضل-جهد: يُعيد (balance, reward_points) أو None عند تعذّر الاتصال."""
    from ..integrations.sas_client import SASClient
    from ..core.security import decrypt
    try:
        async with SASClient(u.sas_host, u.sas_username, decrypt(u.sas_password_enc),
                             https=u.sas_https, verify_tls=u.sas_verify_tls) as sas:
            res = await sas.get("auth")
            cl = res.get("client", {}) if isinstance(res, dict) else {}
            if isinstance(cl, dict):
                return (float(cl.get("balance") or 0), float(cl.get("reward_points") or 0))
    except Exception:  # noqa: BLE001
        pass
    return None

router = APIRouter(prefix="/api/portal", tags=["portal"])


def _sub_counts(db: Session, company_id: int | None, agent: str = "") -> dict:
    q = select(Subscriber.status, func.count()).select_from(Subscriber)  # type: ignore[arg-type]
    if company_id is not None:
        q = q.where(Subscriber.company_id == company_id)
    if agent:
        q = q.where(Subscriber.agent_username == agent)
    by = {"active": 0, "expired": 0}
    total = 0
    for status, n in db.exec(q.group_by(Subscriber.status)).all():  # type: ignore[attr-defined]
        by[status or "unknown"] = by.get(status or "unknown", 0) + n
        total += n
    q2 = select(func.count()).select_from(Subscriber).where(Subscriber.online == True)  # noqa: E712
    if company_id is not None:
        q2 = q2.where(Subscriber.company_id == company_id)
    if agent:
        q2 = q2.where(Subscriber.agent_username == agent)
    online = db.exec(q2).one()
    return {"total": total, "active": by.get("active", 0), "expired": by.get("expired", 0),
            "online": int(online or 0)}


def _expiry_counts(db: Session, company_id: int | None, agent: str = "") -> dict:
    """عدّاد نوافذ الانتهاء (منتهٍ/اليوم/خلال 3/خلال 7) لمشتركي النطاق — لتنبيهات اللوحة."""
    q = select(Subscriber.expiration).select_from(Subscriber)  # type: ignore[arg-type]
    if company_id is not None:
        q = q.where(Subscriber.company_id == company_id)
    if agent:
        q = q.where(Subscriber.agent_username == agent)
    return expiry_svc.expiry_counts(db.exec(q).all())


def _company_block(db: Session, c: Company) -> dict:
    snap = db.exec(select(CompanySnapshot).where(CompanySnapshot.company_id == c.id)
                   .order_by(CompanySnapshot.ts.desc())).first()  # type: ignore[attr-defined]
    return {
        "id": c.id, "name": c.name, "code": c.code, "color": c.color,
        "governorate": c.governorate, "access_type": c.access_type, "kind": c.kind,
        "last_sync_ok": c.last_sync_ok,
        "last_sync_at": c.last_sync_at.isoformat() if c.last_sync_at else None,
        "snapshot": {
            "total": snap.total if snap else 0, "active": snap.active if snap else 0,
            "expired": snap.expired if snap else 0, "online": snap.online if snap else 0,
            "managers": snap.managers if snap else 0,
            "ts": snap.ts.isoformat() if snap else None,
        },
    }


@router.get("/summary")
async def summary(identity: dict = Depends(current_identity), db: Session = Depends(get_session)):
    cid, agent = scope_of(identity)
    kind = tk.kind_of(identity)
    out = {"kind": kind, "user": identity.get("user"), "role": identity.get("role"),
           "tickets": tk.stats(db, identity)}

    if kind == "agent":
        c = db.get(Company, cid)
        a = db.exec(select(Agent).where(Agent.company_id == cid,
                                        Agent.username == agent.strip())).first()
        last = db.exec(select(AgentReport).where(AgentReport.company_id == cid,
                                                 AgentReport.agent_username == agent.strip())
                       .order_by(AgentReport.ts.desc())).first()  # type: ignore[attr-defined]
        subs = _sub_counts(db, cid, agent.strip())
        # الرصيد الحيّ من SAS (لا صفّ Agent للوكيل المستقل → لا نعرض 0 خطأً)
        bal = a.balance if a else 0.0
        rew = a.reward_points if a else 0.0
        u = db.exec(select(User).where(User.username == (identity.get("user") or ""))).first()
        if u and u.sas_host and u.sas_username and u.sas_password_enc:
            live = await _agent_live_balance(u)
            if live is not None:
                bal, rew = live
        out["company"] = _company_block(db, c) if c else None
        out["agent"] = {
            "id": a.id if a else None, "username": agent.strip(),
            "name": (f"{a.firstname} {a.lastname}").strip() if a else agent.strip(),
            # الوكيل المستقل يتصل بحسابه الخاص فلا يُزامَن جدول Agent باسمه (يُزامَن مشتركوه فقط).
            # لذا نعتمد العدّ الفعلي من مشتركيه المحفوظين محلياً بدل users_count=0.
            "users_count": (a.users_count if (a and a.users_count) else subs["total"]),
            "balance": bal,
            "reward_points": rew,
            "parent_username": a.parent_username if a else "",
            "enabled": a.enabled if a else True,
        }
        out["subscribers"] = subs
        out["expiry"] = _expiry_counts(db, cid, agent.strip())
        out["last_report"] = ({"declared_total": last.declared_total,
                               "declared_active": last.declared_active,
                               "note": last.note, "ts": last.ts.isoformat()} if last else None)
        return out

    if kind == "company":
        c = db.get(Company, cid)
        agents_n = db.exec(select(func.count()).select_from(Agent)
                           .where(Agent.company_id == cid)).one()
        out["company"] = _company_block(db, c) if c else None
        out["agents_count"] = int(agents_n or 0)
        out["subscribers"] = _sub_counts(db, cid)
        return out

    # وزارة/جهة رقابية
    companies = db.exec(select(Company)).all()
    blocks = [_company_block(db, c) for c in companies]
    totals = {"total": 0, "active": 0, "expired": 0, "online": 0, "managers": 0}
    for b in blocks:
        for k in totals:
            totals[k] += b["snapshot"][k]
    out["companies"] = blocks
    out["companies_count"] = len(blocks)
    out["totals"] = totals
    out["subscribers"] = _sub_counts(db, None)
    return out
