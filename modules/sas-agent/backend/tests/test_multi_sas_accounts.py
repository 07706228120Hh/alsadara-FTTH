"""
اختبارات تعدّد حسابات SAS للوكيل — test_multi_sas_accounts.py

الوكيل يربط عدة حسابات SAS (قد تكون على خوادم مختلفة). نتحقّق أن:
  1. CRUD حسابات SAS للوكيل (إضافة/سرد/تعديل/حذف).
  2. المزامنة تسم كل مشترك بـ sas_account_id — ومفتاح (sas_account_id, sub_id) يسمح
     بتطابق أرقام المشتركين بين حسابين دون تصادم (مشترك id=201 في الحسابين معاً).
  3. GET /subscribers يدمج مشتركي كل الحسابات مع وسم مصدر الحساب (sas_account_label).
  4. لوحة SAS الحيّة تدمج القوائم عبر الحسابات (كل صفّ موسوم بـ _account_id)،
     وتُصفّى بحساب محدَّد عبر account_id.
  5. أي إجراء على مشترك يتطلّب تحديد الحساب (account_id) للوكيل متعدّد الحسابات،
     ويُوجَّه إلى الخادم الصحيح.
  6. لوحة القيادة تجمع أرقام كل الحسابات (عرض «كل الحسابات»).

المحاكي يفكّ تشفير حمولة login فعلياً ويميّز حسابين باعتمادين مختلفين (توكن لكل حساب).
"""
from __future__ import annotations

import json

import httpx
import pytest
from sqlmodel import Session, delete, select

from app.core import security as sec
from app.database import engine
from app.integrations.sas_client import SASClient, sas_decrypt
import app.api.sas_panel as sas_panel_api
from app.models import Company, SasAccount, Subscriber, User
from app.services import sas_sync

# حسابان على خادمين مختلفين (اعتمادان مختلفان)
CREDS_A = ("mgrA", "passA1234")
CREDS_B = ("mgrB", "passB1234")
TOKEN_A, TOKEN_B = "tok-A", "tok-B"

# ملاحظة: id=201 موجود في الحسابين → يثبت مفتاح (sas_account_id, sub_id) بلا تصادم
USERS_A = [
    {"id": 201, "username": "A_sub1", "profile_id": 1, "expiration": "2026-12-01",
     "status": {"status": True}, "city": "بغداد", "phone": "07701110001"},
    {"id": 202, "username": "A_sub2", "profile_id": 1, "expiration": "2026-10-01",
     "status": {"status": False}, "city": "البصرة"},
]
USERS_B = [
    {"id": 201, "username": "B_sub1", "profile_id": 2, "expiration": "2027-01-01",
     "status": {"status": True}, "city": "أربيل"},
]
DASH_A = {"total": 2, "active": 1, "expired": 1, "online": 0, "managers": 0}
DASH_B = {"total": 1, "active": 1, "expired": 0, "online": 0, "managers": 0}


def _combined_transport() -> httpx.MockTransport:
    def handler(request: httpx.Request) -> httpx.Response:
        path, method = request.url.path, request.method
        if path.endswith("/api/login") and method == "POST":
            p = json.loads(sas_decrypt(json.loads(request.content.decode())["payload"]))
            if (p.get("username"), p.get("password")) == CREDS_A:
                return httpx.Response(200, json={"token": TOKEN_A})
            if (p.get("username"), p.get("password")) == CREDS_B:
                return httpx.Response(200, json={"token": TOKEN_B})
            return httpx.Response(401, json={"error": "بيانات دخول خاطئة"})
        auth = request.headers.get("Authorization")
        if auth == f"Bearer {TOKEN_A}":
            users, dash = USERS_A, DASH_A
        elif auth == f"Bearer {TOKEN_B}":
            users, dash = USERS_B, DASH_B
        else:
            return httpx.Response(401, text="unauthorized")
        if method == "GET" and path.endswith("/advancedDashboard/subscribers"):
            return httpx.Response(200, json={"status": "success", "data": dash})
        if method == "GET" and path.endswith("/list/profile/0"):
            return httpx.Response(200, json=[{"id": 1, "name": "10M"}])
        if method == "POST" and path.endswith("/index/user"):
            return httpx.Response(200, json={"data": users, "total": len(users)})
        if method == "POST" and path.endswith("/index/online"):
            return httpx.Response(200, json={"data": [], "total": 0})
        if method == "GET":
            import re
            if (m := re.search(r"/user/(\d+)$", path)):
                u = next((x for x in users if x["id"] == int(m.group(1))), None)
                return httpx.Response(200, json={"data": u} if u else {"data": {}})
        if method == "POST" and (path.endswith("/user/activate") or path.endswith("/user/extend")):
            sent = json.loads(sas_decrypt(json.loads(request.content.decode())["payload"]))
            # نرمز أي حساب نُفّذ عليه عبر أول مشترك متاح على هذا التوكن
            return httpx.Response(200, json={"status": "success", "done": True,
                                             "server_user": users[0]["username"], "sent": sent})
        return httpx.Response(404, text=f"لا مسار: {path} ({method})")
    return httpx.MockTransport(handler)


@pytest.fixture(autouse=True)
def _install(monkeypatch):
    """يحقن المحاكي في كل SASClient داخل اللوحة والمزامنة."""
    transport = _combined_transport()

    def factory(*args, **kwargs):
        kwargs["transport"] = transport
        return SASClient(*args, **kwargs)
    monkeypatch.setattr(sas_panel_api, "SASClient", factory)
    monkeypatch.setattr(sas_sync, "SASClient", factory)


@pytest.fixture
def agent_ctx(client):
    """شركة + وكيل بلا اعتماد قديم (سيضيف حساباته بنفسه)."""
    with Session(engine) as db:
        c = Company(name="مزوّد-متعدد", code="MULTI", enabled=True)
        db.add(c); db.commit(); db.refresh(c)
        cid = c.id
        u = User(username="multi_agent", password_hash=sec.hash_password("pw123"),
                 role="operator", scope_company_id=cid, scope_agent="multi_agent")
        db.add(u); db.commit(); db.refresh(u)
        uid = u.id
        # تحصين ضد تلوث الحالة (SQLite يُعيد استخدام معرّفات المحذوفين): امسح أي
        # حسابات/مشتركين سابقين مرتبطين بهذا المعرّف قبل بدء الاختبار.
        stale = db.exec(select(SasAccount).where(SasAccount.owner_user_id == uid)).all()
        for a in stale:
            db.exec(delete(Subscriber).where(Subscriber.sas_account_id == a.id))
            db.delete(a)
        db.commit()
    r = client.post("/api/auth/login", json={"username": "multi_agent", "password": "pw123"})
    h = {"Authorization": f"Bearer {r.json()['token']}"}
    yield {"cid": cid, "uid": uid, "h": h}
    with Session(engine) as db:
        db.exec(delete(Subscriber).where(Subscriber.company_id == cid))
        db.exec(delete(SasAccount).where(SasAccount.company_id == cid))
        for user in db.exec(select(User).where(User.scope_company_id == cid)).all():
            db.delete(user)
        cc = db.get(Company, cid)
        if cc:
            db.delete(cc)
        db.commit()


def _add_account(client, h, label, creds):
    r = client.post("/api/companies/agent/sas-accounts", headers=h, json={
        "label": label, "sas_host": "sas.local",
        "sas_username": creds[0], "sas_password": creds[1]})
    assert r.status_code == 200, r.text
    return r.json()["id"]


def _add_both(client, h):
    return _add_account(client, h, "حساب أ", CREDS_A), _add_account(client, h, "حساب ب", CREDS_B)


# ═══════════════════════ 1) CRUD حسابات SAS ═══════════════════════
def test_add_list_accounts(client, agent_ctx):
    h = agent_ctx["h"]
    ida, idb = _add_both(client, h)
    assert ida != idb
    lst = client.get("/api/companies/agent/sas-accounts", headers=h).json()
    assert lst["count"] == 2
    labels = {a["label"] for a in lst["accounts"]}
    assert labels == {"حساب أ", "حساب ب"}
    assert all(a["has_password"] and a["configured"] for a in lst["accounts"])


def test_add_duplicate_rejected(client, agent_ctx):
    h = agent_ctx["h"]
    _add_account(client, h, "حساب أ", CREDS_A)
    dup = client.post("/api/companies/agent/sas-accounts", headers=h, json={
        "label": "تكرار", "sas_host": "sas.local",
        "sas_username": CREDS_A[0], "sas_password": "x"})
    assert dup.status_code == 409


def test_update_and_delete_account(client, agent_ctx):
    h = agent_ctx["h"]
    ida, _ = _add_both(client, h)
    up = client.patch(f"/api/companies/agent/sas-accounts/{ida}", headers=h,
                      json={"label": "محدّث"})
    assert up.status_code == 200 and up.json()["label"] == "محدّث"
    dl = client.delete(f"/api/companies/agent/sas-accounts/{ida}", headers=h)
    assert dl.status_code == 200
    assert client.get("/api/companies/agent/sas-accounts", headers=h).json()["count"] == 1


# ═══════════════════════ 2) المزامنة والوسم ═══════════════════════
def test_sync_tags_subscribers_per_account(client, agent_ctx):
    h, cid = agent_ctx["h"], agent_ctx["cid"]
    ida, idb = _add_both(client, h)
    assert client.post(f"/api/companies/agent/sas-accounts/{ida}/sync", headers=h).json()["count"] == 2
    assert client.post(f"/api/companies/agent/sas-accounts/{idb}/sync", headers=h).json()["count"] == 1
    with Session(engine) as db:
        rows = db.exec(select(Subscriber).where(Subscriber.company_id == cid)).all()
        # مشترك id=201 في الحسابين → صفّان محليان مختلفان (بلا تصادم)
        assert len(rows) == 3
        by_acc = {}
        for s in rows:
            by_acc.setdefault(s.sas_account_id, set()).add(s.username)
        assert by_acc[ida] == {"A_sub1", "A_sub2"}
        assert by_acc[idb] == {"B_sub1"}


def test_subscribers_list_merged_with_labels(client, agent_ctx):
    h = agent_ctx["h"]
    _add_both(client, h)   # المزامنة الخلفية تملأ محلياً بعد الإضافة
    body = client.get("/api/companies/subscribers", headers=h).json()
    assert body["total"] == 3
    labels = {s["sas_account_label"] for s in body["subscribers"]}
    assert labels == {"حساب أ", "حساب ب"}
    assert {s["username"] for s in body["subscribers"]} == {"A_sub1", "A_sub2", "B_sub1"}


# ═══════════════════════ 3) لوحة SAS الحيّة ═══════════════════════
def test_live_users_merged_and_tagged(client, agent_ctx):
    h, cid = agent_ctx["h"], agent_ctx["cid"]
    ida, idb = _add_both(client, h)
    r = client.get(f"/api/companies/{cid}/sas/users", headers=h).json()
    assert r["total"] == 3
    tags = {row["username"]: row["_account_id"] for row in r["data"]}
    assert tags == {"A_sub1": ida, "A_sub2": ida, "B_sub1": idb}


def test_live_users_filtered_by_account(client, agent_ctx):
    h, cid = agent_ctx["h"], agent_ctx["cid"]
    ida, _idb = _add_both(client, h)
    r = client.get(f"/api/companies/{cid}/sas/users?account_id={ida}", headers=h).json()
    assert r["total"] == 2
    assert {row["username"] for row in r["data"]} == {"A_sub1", "A_sub2"}
    assert all(row["_account_id"] == ida for row in r["data"])


def test_accounts_endpoint_lists_agent_accounts(client, agent_ctx):
    h, cid = agent_ctx["h"], agent_ctx["cid"]
    _add_both(client, h)
    r = client.get(f"/api/companies/{cid}/sas/accounts", headers=h).json()
    assert r["is_agent"] is True
    assert {a["label"] for a in r["accounts"]} == {"حساب أ", "حساب ب"}


def test_dashboard_aggregates_across_accounts(client, agent_ctx):
    h, cid = agent_ctx["h"], agent_ctx["cid"]
    _add_both(client, h)
    d = client.get(f"/api/companies/{cid}/sas/dashboard", headers=h).json()
    assert d["total"] == 3 and d["active"] == 2 and d["expired"] == 1


# ═══════════════════════ 4) توجيه العمليات ═══════════════════════
def test_action_requires_account_when_multiple(client, agent_ctx):
    h, cid = agent_ctx["h"], agent_ctx["cid"]
    _add_both(client, h)
    r = client.post(f"/api/companies/{cid}/sas/users/201/action", headers=h,
                    json={"action": "activate", "payload": {}})
    assert r.status_code == 400   # لديه حسابان — يجب تحديد account_id


def test_action_routes_to_selected_account(client, agent_ctx):
    h, cid = agent_ctx["h"], agent_ctx["cid"]
    ida, idb = _add_both(client, h)
    ra = client.post(f"/api/companies/{cid}/sas/users/201/action", headers=h,
                     json={"action": "activate", "payload": {}, "account_id": ida})
    assert ra.status_code == 200 and ra.json()["server_user"] == "A_sub1"   # ذهب لخادم أ
    rb = client.post(f"/api/companies/{cid}/sas/users/201/action", headers=h,
                     json={"action": "activate", "payload": {}, "account_id": idb})
    assert rb.status_code == 200 and rb.json()["server_user"] == "B_sub1"   # ذهب لخادم ب


def test_single_account_no_account_id_needed(client, agent_ctx):
    """حساب واحد فقط → لا حاجة لتحديد account_id (يُحلّ تلقائياً)."""
    h, cid = agent_ctx["h"], agent_ctx["cid"]
    _add_account(client, h, "الوحيد", CREDS_A)
    r = client.post(f"/api/companies/{cid}/sas/users/201/action", headers=h,
                    json={"action": "activate", "payload": {}})
    assert r.status_code == 200 and r.json()["server_user"] == "A_sub1"
