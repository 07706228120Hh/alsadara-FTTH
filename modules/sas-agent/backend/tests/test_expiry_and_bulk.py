"""
اختبارات المرحلة ١ (الأتمتة والتنبيهات) + إصلاح ملكية الوكيل المستقل.

- خدمة expiry: days_left/النوافذ/العدّاد (حتمية).
- تنبيهات الانتهاء في /portal/summary + مرشّح «قائمة التجديد» على /subscribers.
- العملية الجماعية bulk-action (تفعيل عدة مشتركين) عبر محاكي SAS.
- إصلاح الملكية: الوكيل المستقل (اعتماد SAS خاص) يصل لمشترك parent_username مختلف
  (وكيل فرعي) — كان يُرفض 404 خطأً قبل الإصلاح.
"""
from __future__ import annotations

import json
import re
from datetime import date, timedelta
from uuid import uuid4

import httpx
import pytest
from sqlmodel import Session, delete, select

from app.core import security as sec
from app.database import engine
from app.integrations.sas_client import SASClient, sas_decrypt
from app.models import Company, Subscriber, User, utcnow
from app.services import expiry as ex

CREDS = ("mgr", "pw")
TOKEN = "eb-token"

# مشتركون بأسماء وكلاء آباء مختلفة عن نطاق الوكيل (لاختبار إصلاح الملكية)
USERS = [
    {"id": 101, "username": "a", "parent_username": "sub1"},
    {"id": 102, "username": "b", "parent_username": "sub2"},
    {"id": 103, "username": "c", "parent_username": "Dijla"},
]


def make_transport(users=USERS) -> httpx.MockTransport:
    def h(req: httpx.Request) -> httpx.Response:
        p, m = req.url.path, req.method
        if p.endswith("/api/login") and m == "POST":
            pl = json.loads(sas_decrypt(json.loads(req.content.decode())["payload"]))
            if pl.get("username") == CREDS[0] and pl.get("password") == CREDS[1]:
                return httpx.Response(200, json={"token": TOKEN})
            return httpx.Response(401, json={"error": "no"})
        if req.headers.get("Authorization") != f"Bearer {TOKEN}":
            return httpx.Response(401, text="no")
        if p.endswith("/index/user") and m == "POST":
            return httpx.Response(200, json={"data": users, "total": len(users)})
        mm = re.search(r"/user/(\d+)$", p)
        if mm and m == "GET":
            u = next((x for x in users if x["id"] == int(mm.group(1))), None)
            return httpx.Response(200, json={"data": u}) if u else httpx.Response(404, text="no")
        if (p.endswith("/user/activate") or p.endswith("/user/extend")) and m == "POST":
            return httpx.Response(200, json={"status": 200})
        return httpx.Response(404, text=p)
    return httpx.MockTransport(h)


def install(monkeypatch, users=USERS):
    t = make_transport(users)
    def f(*a, **k):
        k["transport"] = t
        return SASClient(*a, **k)
    monkeypatch.setattr("app.api.sas_panel.SASClient", f)


def _tok(client, username: str, password: str = "pw123") -> dict:
    r = client.post("/api/auth/login", json={"username": username, "password": password})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def _mk_agent(company_id: int, username: str, scope_agent: str) -> int:
    with Session(engine) as db:
        u = User(username=username, password_hash=sec.hash_password("pw123"), role="operator",
                 scope_company_id=company_id, scope_agent=scope_agent,
                 sas_host="sas.local", sas_username=CREDS[0],
                 sas_password_enc=sec.encrypt(CREDS[1]))
        db.add(u); db.commit(); db.refresh(u)
        return u.id


def _add_sub(cid: int, agent: str, uid: int, days: int, status="active"):
    with Session(engine) as db:
        exp = (utcnow() + timedelta(days=days)).strftime("%Y-%m-%d %H:%M:%S")
        db.add(Subscriber(company_id=cid, sub_id=uid, username=f"u{uid}",
                          agent_username=agent, status=status, expiration=exp))
        db.commit()


@pytest.fixture
def company_id():
    code = "EB_" + uuid4().hex[:6]
    with Session(engine) as db:
        c = Company(name=f"m-{code}", code=code, enabled=True)
        db.add(c); db.commit(); db.refresh(c)
        cid = c.id
    yield cid
    with Session(engine) as db:
        db.exec(delete(Subscriber).where(Subscriber.company_id == cid))
        for u in db.exec(select(User).where(User.scope_company_id == cid)).all():
            db.delete(u)
        c = db.get(Company, cid)
        if c:
            db.delete(c)
        db.commit()


# ═══════════════════════ 1) خدمة expiry (حتمية) ═══════════════════════
def test_days_left():
    t = date(2026, 9, 28)
    assert ex.days_left("2026-09-28 23:00:00", t) == 0
    assert ex.days_left("2026-10-01 00:00:00", t) == 3
    assert ex.days_left("2026-09-25 00:00:00", t) == -3
    assert ex.days_left("", t) is None
    assert ex.days_left("garbage", t) is None


def test_in_window():
    assert ex.in_window(-1, "overdue") and not ex.in_window(0, "overdue")
    assert ex.in_window(0, "today") and not ex.in_window(1, "today")
    assert ex.in_window(0, "soon3") and ex.in_window(3, "soon3") and not ex.in_window(4, "soon3")
    assert ex.in_window(7, "soon7") and not ex.in_window(8, "soon7")
    assert not ex.in_window(None, "soon7")


def test_expiry_counts_cumulative():
    today = utcnow().date()
    def d(n): return (today + timedelta(days=n)).strftime("%Y-%m-%d %H:%M:%S")
    c = ex.expiry_counts([d(-1), d(0), d(2), d(6), d(30), ""])
    assert c == {"overdue": 1, "today": 1, "soon3": 2, "soon7": 3}


# ═══════════════════════ 2) التنبيهات + مرشّح التجديد ═══════════════════════
def test_expiry_summary_and_filter(client, company_id):
    _mk_agent(company_id, "ag_exp", "agE")
    for uid, days in [(1, -2), (2, 0), (3, 2), (4, 6), (5, 40)]:
        _add_sub(company_id, "agE", uid, days, status="expired" if days < 0 else "active")
    h = _tok(client, "ag_exp")

    s = client.get("/api/portal/summary", headers=h).json()
    assert s["expiry"] == {"overdue": 1, "today": 1, "soon3": 2, "soon7": 3}

    f = client.get("/api/companies/subscribers", params={"expiring": "soon7"}, headers=h).json()
    assert f["total"] == 3                              # اليوم + يومان + 6 أيام
    dl = [x["days_left"] for x in f["subscribers"]]
    assert dl == sorted(dl)                             # مرتّب بالأقرب انتهاءً
    assert all("days_left" in x for x in f["subscribers"])

    fo = client.get("/api/companies/subscribers", params={"expiring": "overdue"}, headers=h).json()
    assert fo["total"] == 1 and fo["subscribers"][0]["days_left"] == -2


# ═══════════════════════ 3) العملية الجماعية ═══════════════════════
def test_bulk_activate_multiple(client, monkeypatch, company_id):
    install(monkeypatch)
    _mk_agent(company_id, "ag_bulk", "Dijla")
    h = _tok(client, "ag_bulk")
    r = client.post(f"/api/companies/{company_id}/sas/users/bulk-action",
                    json={"action": "activate", "user_ids": [101, 102, 103]}, headers=h)
    assert r.status_code == 200, r.text
    b = r.json()
    assert b["total"] == 3 and b["ok"] == 3 and b["failed"] == 0
    assert all(x["ok"] for x in b["results"])


def test_bulk_dedupes_and_rejects_bad_action(client, monkeypatch, company_id):
    install(monkeypatch)
    _mk_agent(company_id, "ag_b2", "Dijla")
    h = _tok(client, "ag_b2")
    # إجراء غير مسموح
    assert client.post(f"/api/companies/{company_id}/sas/users/bulk-action",
                       json={"action": "nuke", "user_ids": [101]}, headers=h).status_code == 400
    # قائمة فارغة
    assert client.post(f"/api/companies/{company_id}/sas/users/bulk-action",
                       json={"action": "activate", "user_ids": []}, headers=h).status_code == 400
    # تكرار المعرّفات يُزال (101 مرتين → عنصر واحد)
    r = client.post(f"/api/companies/{company_id}/sas/users/bulk-action",
                    json={"action": "extend", "user_ids": [101, 101]}, headers=h)
    assert r.json()["total"] == 1


# ═══════════════════════ 4) إصلاح ملكية الوكيل المستقل ═══════════════════════
def test_agent_detail_ok_despite_parent_mismatch(client, monkeypatch, company_id):
    """الوكيل المستقل يصل لمشترك parent_username='sub1' (وكيل فرعي) — كان 404 قبل الإصلاح."""
    install(monkeypatch)
    _mk_agent(company_id, "ag_own", "Dijla")
    h = _tok(client, "ag_own")
    r = client.get(f"/api/companies/{company_id}/sas/users/101", headers=h)
    assert r.status_code == 200, r.text
    assert r.json()["username"] == "a"


def test_agent_single_action_ok_despite_parent_mismatch(client, monkeypatch, company_id):
    install(monkeypatch)
    _mk_agent(company_id, "ag_own2", "Dijla")
    h = _tok(client, "ag_own2")
    r = client.post(f"/api/companies/{company_id}/sas/users/101/action",
                    json={"action": "activate", "payload": {}}, headers=h)
    assert r.status_code == 200, r.text
