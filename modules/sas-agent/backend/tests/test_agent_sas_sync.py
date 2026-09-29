"""
اختبارات مزامنة الوكيل المستقل → القاعدة المحلية (sas_sync.sync_agent + النقاط).

يعالج العطل الذي رآه المستخدم: اختبار الاتصال يُظهر العدد (حيّ) لكن قائمة «مشتركيّ»
فارغة لأن مشتركي الوكيل لم يُحفظوا محلياً — sas_sync كان يزامن الشركات فقط، وبيانات
الوكيل على صفّ User. هنا نتحقّق أن:
  1. sync_agent يسحب مشتركي الوكيل ويحفظهم في Subscriber بنطاق (company_id, scope_agent).
  2. POST /agent/sas-sync يعمل للوكيل ثم GET /subscribers يُظهرهم (القائمة لم تعد فارغة).
  3. النقطة محجوبة عن غير الوكلاء (403) وتتطلّب إعداد SAS كاملاً (400).
  4. مزامنة وكيل لا تحذف صفوف وكيل آخر في نفس الشركة (عزل الحذف).

المحاكي يفكّ تشفير حمولة login فعلياً ⇒ يثبت صحّة الجلب على السلك لا مجرّد المنطق.
"""
from __future__ import annotations

import asyncio
import json
from uuid import uuid4

import httpx
import pytest
from sqlmodel import Session, delete, select

from app.core import security as sec
from app.database import engine
from app.integrations.sas_client import SASClient, sas_decrypt
from app.models import Company, SasAccount, Subscriber, User
from app.services import sas_sync

CREDS = ("agentmgr", "s3cret")
TOKEN = "agent-sync-token"

# مشتركو خادم الوكيل (SAS يُرجع مشتركي هذا المدير فقط — مُنطاق بالدخول)
AGENT_USERS = [
    {"id": 101, "username": "sub1", "profile_id": 1, "expiration": "2026-12-01",
     "status": {"status": True}, "city": "بغداد", "phone": "07701112233"},
    {"id": 102, "username": "sub2", "profile_id": 2, "expiration": "2026-11-01",
     "status": {"status": False}, "city": "البصرة"},
    {"id": 103, "username": "sub3", "profile_id": 1, "expiration": "2027-01-01",
     "status": {"status": True}},
]


def make_transport(username: str = CREDS[0], password: str = CREDS[1],
                   users=AGENT_USERS) -> httpx.MockTransport:
    def handler(request: httpx.Request) -> httpx.Response:
        path, method = request.url.path, request.method
        if path.endswith("/api/login") and method == "POST":
            body = json.loads(request.content.decode("utf-8"))
            payload = json.loads(sas_decrypt(body["payload"]))
            if payload.get("username") == username and payload.get("password") == password:
                return httpx.Response(200, json={"token": TOKEN})
            return httpx.Response(401, json={"error": "بيانات دخول خاطئة"})
        if request.headers.get("Authorization") != f"Bearer {TOKEN}":
            return httpx.Response(401, text="unauthorized")
        if path.endswith("/index/user") and method == "POST":
            return httpx.Response(200, json={"data": users, "total": len(users)})
        return httpx.Response(404, text=f"لا مسار: {path}")
    return httpx.MockTransport(handler)


def install_transport(monkeypatch, transport):
    def factory(*args, **kwargs):
        kwargs["transport"] = transport
        return SASClient(*args, **kwargs)
    monkeypatch.setattr(sas_sync, "SASClient", factory)


def _tok(client, username: str, password: str = "pw123") -> dict:
    r = client.post("/api/auth/login", json={"username": username, "password": password})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def _mk_agent(*, scope_agent: str, company_id: int, username: str,
              configured: bool = True) -> int:
    """ينشئ حساب وكيل في القاعدة (خادمه على المحاكي) ويُعيد user_id."""
    with Session(engine) as db:
        u = User(
            username=username, password_hash=sec.hash_password("pw123"),
            role="operator", scope_company_id=company_id, scope_agent=scope_agent,
            sas_host="sas.local" if configured else "",
            sas_username=CREDS[0] if configured else "",
            sas_password_enc=sec.encrypt(CREDS[1]) if configured else "",
        )
        db.add(u); db.commit(); db.refresh(u)
        return u.id


@pytest.fixture
def company_id():
    code = "AS_" + uuid4().hex[:6]
    with Session(engine) as db:
        c = Company(name=f"مزوّد-{code}", code=code, enabled=True)
        db.add(c); db.commit(); db.refresh(c)
        cid = c.id
    yield cid
    with Session(engine) as db:
        db.exec(delete(Subscriber).where(Subscriber.company_id == cid))
        db.exec(delete(SasAccount).where(SasAccount.company_id == cid))
        for u in db.exec(select(User).where(User.scope_company_id == cid)).all():
            db.delete(u)
        c = db.get(Company, cid)
        if c:
            db.delete(c)
        db.commit()


# ═══════════════════════ 1) الخدمة: sync_agent يحفظ محلياً ═══════════════════════
def test_sync_agent_populates_local_subscribers(monkeypatch, company_id):
    install_transport(monkeypatch, make_transport())
    uid = _mk_agent(scope_agent="agentX", company_id=company_id, username="ag_x")

    res = asyncio.run(sas_sync.sync_agent(uid))
    assert res["ok"] is True and res["count"] == 3

    with Session(engine) as db:
        rows = db.exec(select(Subscriber).where(
            Subscriber.company_id == company_id,
            Subscriber.agent_username == "agentX")).all()
        assert {s.username for s in rows} == {"sub1", "sub2", "sub3"}
        # النطاق مثبّت على scope_agent (لا على parent_username الغائب/المحجوب)
        assert all(s.agent_username == "agentX" for s in rows)
        # حالة SAS ككائن {status} تُترجَم لعلم رئيسي
        by_name = {s.username: s for s in rows}
        assert by_name["sub1"].status == "active"
        assert by_name["sub2"].status == "expired"


def test_sync_agent_missing_config_returns_error(monkeypatch, company_id):
    install_transport(monkeypatch, make_transport())
    uid = _mk_agent(scope_agent="agentX", company_id=company_id,
                    username="ag_noconf", configured=False)
    res = asyncio.run(sas_sync.sync_agent(uid))
    assert res["ok"] is False and "SAS" in res["error"]


def test_sync_agent_isolated_from_other_agent(monkeypatch, company_id):
    """مزامنة وكيل لا تلمس صفوف وكيل آخر في نفس الشركة."""
    install_transport(monkeypatch, make_transport())
    # صفّ سابق لوكيل آخر في نفس الشركة
    with Session(engine) as db:
        db.add(Subscriber(company_id=company_id, sub_id=999,
                          username="other_sub", agent_username="agentOther"))
        db.commit()
    uid = _mk_agent(scope_agent="agentX", company_id=company_id, username="ag_x2")
    asyncio.run(sas_sync.sync_agent(uid))
    with Session(engine) as db:
        other = db.exec(select(Subscriber).where(
            Subscriber.company_id == company_id,
            Subscriber.agent_username == "agentOther")).all()
        assert len(other) == 1 and other[0].username == "other_sub"   # لم يُحذف


# ═══════════════════ 2) النقطة: مزامنة الوكيل ثم ظهور القائمة ═══════════════════
def test_agent_sync_endpoint_then_list_shows_subscribers(client, monkeypatch, company_id):
    install_transport(monkeypatch, make_transport())
    _mk_agent(scope_agent="agentX", company_id=company_id, username="ag_ep")
    h = _tok(client, "ag_ep")

    # القائمة فارغة قبل المزامنة (جوهر العطل)
    assert client.get("/api/companies/subscribers", headers=h).json()["total"] == 0

    r = client.post("/api/companies/agent/sas-sync", headers=h)
    assert r.status_code == 200, r.text
    assert r.json()["ok"] is True and r.json()["count"] == 3

    # بعد المزامنة تظهر القائمة (لم تعد فارغة)
    body = client.get("/api/companies/subscribers", headers=h).json()
    assert body["total"] == 3
    assert {s["username"] for s in body["subscribers"]} == {"sub1", "sub2", "sub3"}


def test_agent_summary_total_reflects_synced_count(client, monkeypatch, company_id):
    """بطاقة «إجمالي مشتركيّ (SAS)» تعكس العدّ المحفوظ محلياً (لا 0 لغياب صفّ Agent)."""
    install_transport(monkeypatch, make_transport())
    _mk_agent(scope_agent="agentX", company_id=company_id, username="ag_sum")
    h = _tok(client, "ag_sum")
    client.post("/api/companies/agent/sas-sync", headers=h)
    s = client.get("/api/portal/summary", headers=h).json()
    assert s["kind"] == "agent"
    assert s["subscribers"]["total"] == 3
    assert s["subscribers"]["active"] == 2 and s["subscribers"]["expired"] == 1
    assert s["agent"]["users_count"] == 3          # لا صفر — العدّ الفعلي


def test_agent_sync_endpoint_requires_agent(client, monkeypatch, company_id):
    install_transport(monkeypatch, make_transport())
    # مستخدم شركة (بلا scope_agent) → 403
    with Session(engine) as db:
        db.add(User(username="co_user", password_hash=sec.hash_password("pw123"),
                    role="operator", scope_company_id=company_id))
        db.commit()
    h = _tok(client, "co_user")
    r = client.post("/api/companies/agent/sas-sync", headers=h)
    assert r.status_code == 403


def test_agent_sync_endpoint_requires_config(client, monkeypatch, company_id):
    install_transport(monkeypatch, make_transport())
    _mk_agent(scope_agent="agentX", company_id=company_id,
              username="ag_noconf2", configured=False)
    h = _tok(client, "ag_noconf2")
    r = client.post("/api/companies/agent/sas-sync", headers=h)
    assert r.status_code == 400
