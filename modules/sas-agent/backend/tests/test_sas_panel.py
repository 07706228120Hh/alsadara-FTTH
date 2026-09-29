"""
اختبارات بروكسي SAS الحيّ — test_sas_panel.py

يغطّي `api/sas_panel.py` (كان بلا اختبار رغم ربطه في main.py واستهلاكه من
`platform_core`). يحاكي خادم SAS4 بالكامل عبر httpx.MockTransport (يفكّ تشفير
حمولة login فعلياً بـ sas_decrypt ⇒ يثبت أن الجلب صحيح على السلك)، ثم يتحقّق من:

1. القراءة للجهة الرقابية: dashboard/finance/users/detail/overview/history/
   extend-data/online/managers/profiles.
2. عزل النطاق:
   - مستخدم شركة: شركته فقط (403 لشركة أخرى).
   - وكيل: مشتركوه فقط (تصفية parent_username على users/online، 404 لمشترك
     ليس تابعاً له، و403 على قائمة الوكلاء).
3. الأدوار: القراءة تتطلّب viewer، والإجراءات تتطلّب operator (viewer → 403).
4. الإجراءات (كتابة): القائمة البيضاء تُنفَّذ، وإجراء مجهول يُرفض 400.
5. حرّاس _resolve: شركة بلا بيانات SAS → 400، وشركة غير موجودة → 404.
"""
from __future__ import annotations

import json
import re

import httpx
import pytest
from sqlmodel import Session, select

from app.core import security as sec_module
from app.database import engine
from app.integrations.sas_client import SASClient, sas_decrypt
from app.main import _seed_default_admin
from app.models import Agent, Company, CompanySnapshot, MergeFinding, SasAccount, Subscriber, User
import app.api.sas_panel as sas_panel_api

# ─────────────────────────── بيانات محاكاة SAS ───────────────────────────
CREDS = ("sasadmin", "s3cret")
TOKEN = "sas-panel-token-xyz"

DASHBOARD = {"total": 5000, "active": 4200, "expired": 800, "online": 3900, "managers": 7}
FINANCE = {"income_today": 1234, "income_month": 56789, "debts": 42}
PROFILES = [{"id": 1, "name": "10M"}, {"id": 2, "name": "50M"}]
MANAGERS = [
    {"id": 10, "username": "agentX", "users_count": 120, "balance": 500},
    {"id": 11, "username": "agentY", "users_count": 60, "balance": 100},
    {"id": 12, "username": "agentZ", "users_count": 30, "balance": 0},
]
USERS = [
    # u1 يحمل كلمة مرور ظاهرة (كما يعيدها overview الحقيقي #40) لاختبار الحجب
    {"id": 1, "username": "u1", "parent_username": "agentX", "profile": "10M", "password": "plain123"},
    {"id": 2, "username": "u2", "parent_username": "agentY", "profile": "50M"},
    {"id": 3, "username": "u3", "parent_username": "agentZ", "profile": "10M"},
]
# المتصلون يحملون nas_details بأسرار (secret/api_password/snmp_community) كاستجابة #49 الحقيقية
ONLINE = [
    {"radacctid": 1, "username": "u1", "parent_username": "agentX",
     "nas_details": {"nasname": "10.0.0.1", "secret": "s3cr3t", "api_password": "ap", "snmp_community": "cmt"}},
    {"radacctid": 2, "username": "u2", "parent_username": "agentY"},
]


def _user_by_id(uid: int):
    return next((u for u in USERS if u["id"] == uid), None)


# ───────────────────────────── محاكي خادم SAS4 ─────────────────────────────
def make_transport(username: str = CREDS[0], password: str = CREDS[1]) -> httpx.MockTransport:
    """يحاكي واجهة SAS4 المستخدَمة في sas_panel: login مشفّر + مسارات محمية بـ Bearer."""
    def handler(request: httpx.Request) -> httpx.Response:
        path = request.url.path
        method = request.method

        # تسجيل الدخول: يفكّ الحمولة ويتحقّق من الاعتماد فعلياً
        if path.endswith("/api/login") and method == "POST":
            body = json.loads(request.content.decode("utf-8"))
            payload = json.loads(sas_decrypt(body["payload"]))
            if payload.get("username") == username and payload.get("password") == password:
                return httpx.Response(200, json={"token": TOKEN})
            return httpx.Response(401, json={"error": "بيانات دخول خاطئة"})

        # كل ما بعد الدخول يتطلّب Bearer الصحيح
        if request.headers.get("Authorization") != f"Bearer {TOKEN}":
            return httpx.Response(401, text="unauthorized")

        if method == "GET":
            if path.endswith("/advancedDashboard/subscribers"):
                return httpx.Response(200, json={"status": "success", "data": DASHBOARD})
            if path.endswith("/advancedDashboard/finance"):
                return httpx.Response(200, json={"status": "success", "data": FINANCE})
            if path.endswith("/list/profile/0"):
                return httpx.Response(200, json=PROFILES)
            if (m := re.search(r"/user/overview/(\d+)$", path)):
                return httpx.Response(200, json={"data": _user_by_id(int(m.group(1))) or {}})
            if re.search(r"/user/extensionData/(\d+)$", path):
                return httpx.Response(200, json={"data": {"price": 10, "days": 30}})
            if re.search(r"/allowedExtensions/(\d+)$", path):
                return httpx.Response(200, json={"data": [{"id": 1, "name": "30 يوماً"}]})
            if path.endswith("/auth"):
                return httpx.Response(200, json={"status": "success",
                    "permissions": ["all"], "features": ["hotspot"], "license_status": "active"})
            if path.endswith("/advancedDashboard/systemHealth"):
                return httpx.Response(200, json={"status": "success", "data": {"cpu": 12, "memory": 40}})
            if path.endswith("/manager/tree"):
                return httpx.Response(200, json=[{"id": 10, "parent_id": 0, "username": "agentX"}])
            if re.search(r"/user/activationData/(\d+)$", path):
                return httpx.Response(200, json={"data": {"price": 20}})
            if re.search(r"/user/refundData/(\d+)$", path):
                return httpx.Response(200, json={"data": {"refund_amount": "$ 20",
                    "price": "$ 20.00", "remaining_days": "31 day"}})
            if re.search(r"/user/refund/(\d+)$", path):
                return httpx.Response(200, json={"status": 200})
            if path.endswith("/resources/languages"):
                return httpx.Response(200, json={"data": [{"code": "ar"}, {"code": "en"}]})
            if re.search(r"/resources/language/[\w-]+$", path):
                return httpx.Response(200, json={"data": {"rsp_ok": "تم"}})
            if re.search(r"/mac/(\d+)$", path):
                return httpx.Response(200, json={"data": [{"mac": "AA:BB:CC"}]})
            if re.search(r"/customRadiusAttribute/user/(\d+)$", path):
                return httpx.Response(200, json={"data": []})
            if (m := re.search(r"/user/(\d+)$", path)):
                u = _user_by_id(int(m.group(1)))
                if not u:
                    return httpx.Response(404, text="no user")
                return httpx.Response(200, json={"data": u})
            return httpx.Response(404, text=f"GET لا مسار: {path}")

        if method == "POST":
            if path.endswith("/index/user"):
                return httpx.Response(200, json={"data": USERS, "total": len(USERS)})
            if path.endswith("/index/online"):
                return httpx.Response(200, json={"data": ONLINE, "total": len(ONLINE)})
            if path.endswith("/index/manager"):
                return httpx.Response(200, json={"data": MANAGERS, "total": len(MANAGERS)})
            if re.search(r"/index/UserHistory/(\d+)$", path):
                return httpx.Response(200, json={"data": [{"id": 1, "action": "login"}], "total": 1})
            if (re.search(r"/user/(activate|extend|changeProfile|addTraffic|deposit|withdraw|ping)$", path)
                    or re.search(r"/user/rename/(\d+)$", path)):
                return httpx.Response(200, json={"status": "success", "done": True})
            if re.search(r"/manager/(deposit|withdraw|addRewardPoints|deductRewardPoints|payDebt)$", path):
                return httpx.Response(200, json={"status": "success", "done": True})
            if path.endswith("/manager") or re.search(r"/manager/(\d+)$", path):
                return httpx.Response(200, json={"status": "success", "done": True})
            if re.search(r"/index/UserJournal/(\d+)$", path):
                return httpx.Response(200, json={"data": [], "total": 0})
            if path.endswith("/user/traffic") or path.endswith("/userNetworksTraffic"):
                return httpx.Response(200, json={"data": []})
            if path.endswith("/index/userauthlog"):
                return httpx.Response(200, json={"data": [
                    {"id": 1, "username": "u1", "reply": "Access-Accept",
                     "created_at": "2026-09-28 10:00:00", "mac": "AA:BB", "nas_ip_address": "10.0.0.1"}],
                    "total": 1})
            if path.endswith("/index/syslog"):
                return httpx.Response(200, json={"data": [
                    {"id": 1, "event": "login", "description": "manager login",
                     "created_by": "agentX", "ip": "1.2.3.4", "created_at": "2026-09-28 10:00:00"}],
                    "total": 1})
            if path.endswith("/user"):     # إنشاء مشترك — يفكّ الحمولة ويعيدها لإثبات الحقول
                sent = json.loads(sas_decrypt(json.loads(request.content.decode("utf-8"))["payload"]))
                return httpx.Response(200, json={"status": "success", "created": True, "sent": sent})
            return httpx.Response(404, text=f"POST لا مسار: {path}")

        if method == "DELETE":
            if re.search(r"/user/(\d+)$", path) or re.search(r"/manager/(\d+)$", path):
                return httpx.Response(200, json={"status": "success", "deleted": True})
            return httpx.Response(404, text=f"DELETE لا مسار: {path}")

        return httpx.Response(405, text="method")

    return httpx.MockTransport(handler)


def install_transport(monkeypatch, transport: httpx.MockTransport | None = None) -> httpx.MockTransport:
    """يحقن transport الوهمي في كل SASClient يُنشأ داخل sas_panel."""
    transport = transport or make_transport()

    def factory(*args, **kwargs):
        kwargs["transport"] = transport
        return SASClient(*args, **kwargs)

    monkeypatch.setattr(sas_panel_api, "SASClient", factory)
    return transport


# ─────────────────────────────── تنظيف + بيانات ───────────────────────────────
@pytest.fixture(autouse=True)
def _clean():
    """قاعدة نظيفة قبل/بعد كل اختبار مع إبقاء admin (بلا نطاق)."""
    def _do():
        with Session(engine) as db:
            for model in (MergeFinding, Subscriber, SasAccount, Agent, CompanySnapshot, Company):
                for row in db.exec(select(model)).all():
                    db.delete(row)
            for u in db.exec(select(User)).all():
                if u.username != "admin":
                    db.delete(u)
            db.commit()
        _seed_default_admin()

    _do()
    yield
    _do()


def _tok(client, username: str, password: str = "pw123") -> dict:
    r = client.post("/api/auth/login", json={"username": username, "password": password})
    assert r.status_code == 200, f"فشل تسجيل دخول {username}: {r.text}"
    return {"Authorization": f"Bearer {r.json()['token']}"}


def _new_company(client, headers, *, code: str, gov: str = "بغداد",
                 sas: bool = True) -> dict:
    body = {
        "name": f"شركة-{code}", "code": code, "governorate": gov,
        "sas_host": "sas.local" if sas else "",
        "sas_username": CREDS[0] if sas else "",
        "sas_password": CREDS[1] if sas else "",
    }
    r = client.post("/api/companies", json=body, headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


@pytest.fixture
def panel(client, monkeypatch):
    """يثبّت المحاكي + شركتين (ببيانات SAS) + مستخدمي نطاق (شركة/وكيل/viewer)."""
    install_transport(monkeypatch)
    h_gov = _tok(client, "admin", "admin")
    ca = _new_company(client, h_gov, code="CA")
    cb = _new_company(client, h_gov, code="CB", gov="البصرة")

    with Session(engine) as db:
        db.add(User(username="user_a", password_hash=sec_module.hash_password("pw123"),
                    role="operator", scope_company_id=ca["id"]))
        db.add(User(username="viewer_a", password_hash=sec_module.hash_password("pw123"),
                    role="viewer", scope_company_id=ca["id"]))
        # الوكيل يتصل بخادمه الخاص بحسابه — نضبط الخادم والاعتماد على المحاكي كي يُصادَق
        db.add(User(username="user_agent", password_hash=sec_module.hash_password("pw123"),
                    role="operator", scope_company_id=ca["id"], scope_agent="agentX",
                    sas_host="sas.local", sas_username=CREDS[0],
                    sas_password_enc=sec_module.encrypt(CREDS[1])))
        db.commit()

    return {
        "ca": ca, "cb": cb,
        "h_gov": h_gov,
        "h_company": _tok(client, "user_a"),
        "h_viewer": _tok(client, "viewer_a"),
        "h_agent": _tok(client, "user_agent"),
    }


def _cid(panel, key="ca"):
    return panel[key]["id"]


# ═══════════════════════════ 1) القراءة — الجهة الرقابية ═══════════════════════════
def test_gov_dashboard(client, panel):
    r = client.get(f"/api/companies/{_cid(panel)}/sas/dashboard", headers=panel["h_gov"])
    assert r.status_code == 200, r.text
    assert r.json()["total"] == 5000 and r.json()["active"] == 4200


def test_gov_finance(client, panel):
    r = client.get(f"/api/companies/{_cid(panel)}/sas/finance", headers=panel["h_gov"])
    assert r.status_code == 200, r.text
    assert r.json()["income_today"] == 1234


def test_gov_users_all(client, panel):
    r = client.get(f"/api/companies/{_cid(panel)}/sas/users", headers=panel["h_gov"])
    assert r.status_code == 200, r.text
    assert r.json()["total"] == 3
    assert {u["username"] for u in r.json()["data"]} == {"u1", "u2", "u3"}


def test_gov_user_detail(client, panel):
    r = client.get(f"/api/companies/{_cid(panel)}/sas/users/1", headers=panel["h_gov"])
    assert r.status_code == 200, r.text
    assert r.json()["username"] == "u1"


def test_gov_user_overview(client, panel):
    r = client.get(f"/api/companies/{_cid(panel)}/sas/users/2/overview", headers=panel["h_gov"])
    assert r.status_code == 200, r.text
    assert r.json()["username"] == "u2"


def test_gov_user_history(client, panel):
    r = client.get(f"/api/companies/{_cid(panel)}/sas/users/1/history", headers=panel["h_gov"])
    assert r.status_code == 200, r.text
    assert "data" in r.json()


def test_gov_extend_data(client, panel):
    r = client.get(f"/api/companies/{_cid(panel)}/sas/users/1/extend-data?profile_id=1",
                   headers=panel["h_gov"])
    assert r.status_code == 200, r.text
    assert "extension" in r.json() and r.json()["allowed_extensions"] is not None


def test_gov_extend_data_without_profile_has_no_allowed(client, panel):
    r = client.get(f"/api/companies/{_cid(panel)}/sas/users/1/extend-data", headers=panel["h_gov"])
    assert r.status_code == 200, r.text
    assert r.json()["allowed_extensions"] is None


def test_gov_online(client, panel):
    r = client.get(f"/api/companies/{_cid(panel)}/sas/online", headers=panel["h_gov"])
    assert r.status_code == 200, r.text
    assert r.json()["total"] == 2


def test_online_redacts_nas_secrets(client, panel):
    """أسرار الـ NAS (secret/api_password/snmp_community) لا تُسرَّب في المتصلين."""
    r = client.get(f"/api/companies/{_cid(panel)}/sas/online", headers=panel["h_gov"])
    assert r.status_code == 200, r.text
    row = r.json()["data"][0]
    assert row["username"] == "u1"                 # الحقول العادية تبقى
    assert row["nas_details"] == "***"             # الأسرار محجوبة كاملةً
    assert "s3cr3t" not in r.text and "snmp_community" not in r.text


def test_user_overview_redacts_password(client, panel):
    """كلمة مرور المشترك الظاهرة (overview) لا تُسرَّب للتطبيق."""
    r = client.get(f"/api/companies/{_cid(panel)}/sas/users/1/overview", headers=panel["h_gov"])
    assert r.status_code == 200, r.text
    assert r.json()["username"] == "u1"
    assert r.json()["password"] == "***" and "plain123" not in r.text


def test_gov_managers(client, panel):
    r = client.get(f"/api/companies/{_cid(panel)}/sas/managers", headers=panel["h_gov"])
    assert r.status_code == 200, r.text
    assert {m["username"] for m in r.json()["data"]} == {"agentX", "agentY", "agentZ"}


def test_gov_profiles(client, panel):
    r = client.get(f"/api/companies/{_cid(panel)}/sas/profiles", headers=panel["h_gov"])
    assert r.status_code == 200, r.text
    assert [p["name"] for p in r.json()] == ["10M", "50M"]


# ═══════════════════════════ 2) عزل النطاق — الشركة ═══════════════════════════
def test_company_user_own_company_ok(client, panel):
    r = client.get(f"/api/companies/{_cid(panel)}/sas/dashboard", headers=panel["h_company"])
    assert r.status_code == 200, r.text
    assert r.json()["total"] == 5000


def test_company_user_other_company_forbidden(client, panel):
    r = client.get(f"/api/companies/{_cid(panel, 'cb')}/sas/dashboard", headers=panel["h_company"])
    assert r.status_code == 403


# ═══════════════════════════ 3) عزل النطاق — الوكيل ═══════════════════════════
def test_agent_users_trusts_sas_scoping(client, panel):
    # الوكيل المستقل يتصل باعتماد SAS الخاص به، وSAS يُنطّق النتائج على مشتركيه
    # (بما فيهم مشتركو وكلائه الفرعيين). لا تصفية parent_username في التطبيق —
    # كانت تُسقط مشتركين حقيقيين (parent = وكيل فرعي) خطأً. نمرّر ما يُرجعه SAS.
    r = client.get(f"/api/companies/{_cid(panel)}/sas/users", headers=panel["h_agent"])
    assert r.status_code == 200, r.text
    assert r.json()["total"] == len(USERS)


def test_agent_user_detail_owned_ok(client, panel):
    r = client.get(f"/api/companies/{_cid(panel)}/sas/users/1", headers=panel["h_agent"])
    assert r.status_code == 200, r.text
    assert r.json()["username"] == "u1"


def test_agent_user_detail_trusts_sas_scoping(client, panel):
    # مشترك parent_username=agentY: ما دام SAS أعاده للوكيل (بدخوله الخاص) نثق ونعرضه.
    # كان 404 خطأً — يكسر مشتركي الوكلاء الفرعيين (parent مختلف عن اسم الوكيل).
    r = client.get(f"/api/companies/{_cid(panel)}/sas/users/2", headers=panel["h_agent"])
    assert r.status_code == 200, r.text
    assert r.json()["username"] == "u2"


def test_agent_online_trusts_sas_scoping(client, panel):
    r = client.get(f"/api/companies/{_cid(panel)}/sas/online", headers=panel["h_agent"])
    assert r.status_code == 200, r.text
    assert r.json()["total"] == len(ONLINE)


def test_agent_managers_forbidden(client, panel):
    r = client.get(f"/api/companies/{_cid(panel)}/sas/managers", headers=panel["h_agent"])
    assert r.status_code == 403


# ═══════════════════════════ 4) الإجراءات + الأدوار ═══════════════════════════
def test_gov_action_activate_ok(client, panel):
    r = client.post(f"/api/companies/{_cid(panel)}/sas/users/1/action",
                    json={"action": "activate", "payload": {}}, headers=panel["h_gov"])
    assert r.status_code == 200, r.text
    assert r.json()["done"] is True


def test_company_operator_action_ok(client, panel):
    r = client.post(f"/api/companies/{_cid(panel)}/sas/users/1/action",
                    json={"action": "extend", "payload": {"days": 30}}, headers=panel["h_company"])
    assert r.status_code == 200, r.text


def test_unknown_action_rejected(client, panel):
    r = client.post(f"/api/companies/{_cid(panel)}/sas/users/1/action",
                    json={"action": "nuke", "payload": {}}, headers=panel["h_gov"])
    assert r.status_code == 400


def test_viewer_cannot_action(client, panel):
    r = client.post(f"/api/companies/{_cid(panel)}/sas/users/1/action",
                    json={"action": "activate", "payload": {}}, headers=panel["h_viewer"])
    assert r.status_code == 403


def test_viewer_can_read(client, panel):
    r = client.get(f"/api/companies/{_cid(panel)}/sas/dashboard", headers=panel["h_viewer"])
    assert r.status_code == 200


def test_agent_action_owned_ok(client, panel):
    r = client.post(f"/api/companies/{_cid(panel)}/sas/users/1/action",
                    json={"action": "ping", "payload": {}}, headers=panel["h_agent"])
    assert r.status_code == 200, r.text


def test_agent_action_trusts_sas_scoping(client, panel):
    # SAS يُنطّق الإجراء على مشتركي الوكيل بدخوله الخاص؛ لا فحص parent_username في التطبيق.
    r = client.post(f"/api/companies/{_cid(panel)}/sas/users/2/action",
                    json={"action": "activate", "payload": {}}, headers=panel["h_agent"])
    assert r.status_code == 200, r.text


# ═══════════════════════════ 5) حرّاس _resolve ═══════════════════════════
def test_company_without_sas_creds_400(client, panel):
    no_sas = _new_company(client, panel["h_gov"], code="NOS", sas=False)
    r = client.get(f"/api/companies/{no_sas['id']}/sas/dashboard", headers=panel["h_gov"])
    assert r.status_code == 400


def test_nonexistent_company_404(client, panel):
    r = client.get("/api/companies/999999/sas/dashboard", headers=panel["h_gov"])
    assert r.status_code == 404


# ═══════════════ 6) إعداد SAS للوكيل (خادمه الخاص + اسم مستخدمه + كلمة مروره) ═══════════════
def _new_agent(client, panel, username, scope_agent):
    with Session(engine) as db:
        db.add(User(username=username, password_hash=sec_module.hash_password("pw123"),
                    role="operator", scope_company_id=panel["ca"]["id"], scope_agent=scope_agent))
        db.commit()
    return _tok(client, username)


def test_agent_sas_config_get_and_set(client, panel):
    h = _new_agent(client, panel, "agent_cfg", "agentY")
    r = client.get("/api/companies/agent/sas-config", headers=h)
    assert r.status_code == 200, r.text
    assert r.json()["has_password"] is False
    assert r.json()["configured"] is False                 # لم يُضبط بعد (لا خادم/كلمة مرور)
    # الوكيل يُدخل خادمه واسم مستخدمه وكلمة مروره
    r2 = client.patch("/api/companies/agent/sas-config", headers=h,
                      json={"sas_host": "sas.local", "sas_username": "agentY_sas",
                            "sas_password": "mypass"})
    assert r2.status_code == 200, r2.text
    assert r2.json()["sas_username"] == "agentY_sas" and r2.json()["has_password"] is True
    assert r2.json()["sas_host"] == "sas.local" and r2.json()["configured"] is True


def test_agent_without_creds_panel_400(client, panel):
    """وكيل لم يضبط خادمه/بياناته → لوحة SAS ترجع 400 (يُوجَّه للإعداد)."""
    h = _new_agent(client, panel, "agent_nocfg", "agentZ")
    r = client.get(f"/api/companies/{_cid(panel)}/sas/dashboard", headers=h)
    assert r.status_code == 400


def test_non_agent_cannot_access_agent_config(client, panel):
    """مستخدم شركة (ليس وكيلاً) على /agent/sas-config → 403."""
    r = client.get("/api/companies/agent/sas-config", headers=panel["h_company"])
    assert r.status_code == 403


# ═══════════════ 7) البروكسي الكامل: تفاصيل + إجراءات + حذف + وكلاء ═══════════════
def test_sas_get_proxy_whitelist(client, panel):
    r = client.get(f"/api/companies/{_cid(panel)}/sas/get?path=auth", headers=panel["h_gov"])
    assert r.status_code == 200, r.text
    assert r.json().get("license_status") == "active"
    r2 = client.get(f"/api/companies/{_cid(panel)}/sas/get?path=advancedDashboard/systemHealth",
                    headers=panel["h_gov"])
    assert r2.status_code == 200
    r3 = client.get(f"/api/companies/{_cid(panel)}/sas/get?path=secret/thing", headers=panel["h_gov"])
    assert r3.status_code == 400                         # خارج القائمة البيضاء


def test_sas_post_proxy_lists_only(client, panel):
    r = client.post(f"/api/companies/{_cid(panel)}/sas/post", headers=panel["h_gov"],
                    json={"path": "index/UserJournal/1", "payload": {"page": 1}})
    assert r.status_code == 200, r.text
    r2 = client.post(f"/api/companies/{_cid(panel)}/sas/post", headers=panel["h_gov"],
                     json={"path": "manager/deposit", "payload": {}})
    assert r2.status_code == 400                         # الكتابة ليست عبر بروكسي القوائم


def test_agent_blocked_from_manager_paths(client, panel):
    r = client.get(f"/api/companies/{_cid(panel)}/sas/get?path=manager/tree", headers=panel["h_agent"])
    assert r.status_code == 403


def test_delete_user_gov_and_agent_ownership(client, panel):
    r = client.delete(f"/api/companies/{_cid(panel)}/sas/users/1", headers=panel["h_gov"])
    assert r.status_code == 200 and r.json().get("deleted") is True
    assert client.delete(f"/api/companies/{_cid(panel)}/sas/users/1",
                         headers=panel["h_agent"]).status_code == 200      # يثق بتنطيق SAS
    assert client.delete(f"/api/companies/{_cid(panel)}/sas/users/2",
                         headers=panel["h_agent"]).status_code == 200      # يثق بتنطيق SAS


def test_manager_action_and_delete(client, panel):
    ok = client.post(f"/api/companies/{_cid(panel)}/sas/managers/10/action", headers=panel["h_gov"],
                     json={"action": "deposit", "payload": {"amount": 100}})
    assert ok.status_code == 200, ok.text
    assert client.post(f"/api/companies/{_cid(panel)}/sas/managers/10/action", headers=panel["h_agent"],
                       json={"action": "deposit", "payload": {}}).status_code == 403   # الوكيل ممنوع
    assert client.post(f"/api/companies/{_cid(panel)}/sas/managers/10/action", headers=panel["h_gov"],
                       json={"action": "nuke", "payload": {}}).status_code == 400        # مجهول
    assert client.delete(f"/api/companies/{_cid(panel)}/sas/managers/10",
                         headers=panel["h_gov"]).status_code == 200
    assert client.delete(f"/api/companies/{_cid(panel)}/sas/managers/10",
                         headers=panel["h_agent"]).status_code == 403


# ═══════════════ 8) إنشاء مشترك (نقطة صريحة، بلا حقن user_id) ═══════════════
def test_create_user_endpoint_gov(client, panel):
    r = client.post(f"/api/companies/{_cid(panel)}/sas/users", headers=panel["h_gov"],
                    json={"payload": {"username": "newuser", "password": "1111",
                                      "profile_id": 1, "parent_id": 10}})
    assert r.status_code == 200, r.text
    sent = r.json()["sent"]
    assert sent["username"] == "newuser"
    assert sent["confirm_password"] == "1111"        # يُملأ تلقائياً من password
    assert "user_id" not in sent                       # لا حقن user_id عند الإنشاء
    assert sent["parent_id"] == 10


def test_create_user_requires_username_and_password(client, panel):
    r = client.post(f"/api/companies/{_cid(panel)}/sas/users", headers=panel["h_gov"],
                    json={"payload": {"password": "x", "profile_id": 1, "parent_id": 10}})
    assert r.status_code == 400
    r2 = client.post(f"/api/companies/{_cid(panel)}/sas/users", headers=panel["h_gov"],
                     json={"payload": {"username": "u", "profile_id": 1, "parent_id": 10}})
    assert r2.status_code == 400


def test_create_user_requires_parent_for_non_agent(client, panel):
    r = client.post(f"/api/companies/{_cid(panel)}/sas/users", headers=panel["h_gov"],
                    json={"payload": {"username": "np", "password": "1111", "profile_id": 1}})
    assert r.status_code == 400                        # parent_id مطلوب لغير الوكيل


def test_create_user_viewer_forbidden(client, panel):
    r = client.post(f"/api/companies/{_cid(panel)}/sas/users", headers=panel["h_viewer"],
                    json={"payload": {"username": "v", "password": "1111",
                                      "profile_id": 1, "parent_id": 10}})
    assert r.status_code == 403


def test_create_user_agent_drops_parent(client, panel):
    """الوكيل يتصل بحساب SAS الخاص به (هو المدير المُصادَق) → SAS يُسند المشترك إليه
    تلقائياً، ولا يُقبل parent_id يرسله (منع إسناد المشترك لوكيل آخر)."""
    r = client.post(f"/api/companies/{_cid(panel)}/sas/users", headers=panel["h_agent"],
                    json={"payload": {"username": "ag_user", "password": "1111",
                                      "profile_id": 1, "parent_id": 999}})  # محاولة إسناد لوكيل آخر
    assert r.status_code == 200, r.text
    assert "parent_id" not in r.json()["sent"]          # أُسقط — SAS يُسنده لحساب الوكيل المُصادَق


# ═══════════════ 9) الإلغاء/الاسترداد ═══════════════
def test_refund_data_and_execute_gov(client, panel):
    rd = client.get(f"/api/companies/{_cid(panel)}/sas/users/1/refund-data", headers=panel["h_gov"])
    assert rd.status_code == 200, rd.text
    assert rd.json()["refund_amount"] == "$ 20"
    ex = client.post(f"/api/companies/{_cid(panel)}/sas/users/1/refund", headers=panel["h_gov"])
    assert ex.status_code == 200, ex.text


def test_refund_requires_operator(client, panel):
    assert client.post(f"/api/companies/{_cid(panel)}/sas/users/1/refund",
                       headers=panel["h_viewer"]).status_code == 403


def test_refund_agent_ownership(client, panel):
    ok = client.get(f"/api/companies/{_cid(panel)}/sas/users/1/refund-data", headers=panel["h_agent"])
    assert ok.status_code == 200                        # مشتركه
    no = client.post(f"/api/companies/{_cid(panel)}/sas/users/2/refund", headers=panel["h_agent"])
    assert no.status_code == 200                         # يثق بتنطيق SAS


# ═══════════════ سجلّ الدخول / سجلّ النظام (تبويبات جديدة) ═══════════════
def test_auth_log_and_syslog_whitelisted_for_agent(client, panel):
    # سجلّ تسجيل الدخول (index/userauthlog) متاح للوكيل عبر البروكسي
    r = client.post(f"/api/companies/{_cid(panel)}/sas/post", headers=panel["h_agent"],
                    json={"path": "index/userauthlog", "payload": {"page": 1, "count": 5}})
    assert r.status_code == 200, r.text
    assert r.json()["data"][0]["reply"] == "Access-Accept"
    # سجلّ النظام (index/syslog)
    r2 = client.post(f"/api/companies/{_cid(panel)}/sas/post", headers=panel["h_agent"],
                     json={"path": "index/syslog", "payload": {"page": 1, "count": 5}})
    assert r2.status_code == 200, r2.text
    assert r2.json()["data"][0]["event"] == "login"


def test_unlisted_post_path_still_rejected(client, panel):
    r = client.post(f"/api/companies/{_cid(panel)}/sas/post", headers=panel["h_gov"],
                    json={"path": "index/secretstuff", "payload": {}})
    assert r.status_code == 400


# ═══════════════ تعديل المشترك (تعطيل/كلمة مرور/بيانات/MAC) عبر load-merge-save ═══════════════
def test_agent_update_user_disable_keeps_base_fields(client, panel):
    # تعطيل الحساب: enabled=0 يُرسَل، والحقول الأساسية تبقى من الحالي (لا تُمسح)
    r = client.post(f"/api/companies/{_cid(panel)}/sas/users/1/update", headers=panel["h_agent"],
                    json={"changes": {"enabled": 0}})
    assert r.status_code == 200, r.text
    sent = r.json()["sent"]
    assert sent["id"] == 1 and sent["enabled"] == 0
    assert sent["username"] == "u1"          # حقل أساسي مُرسَل من الحالي


def test_update_user_password_adds_confirm(client, panel):
    r = client.post(f"/api/companies/{_cid(panel)}/sas/users/1/update", headers=panel["h_gov"],
                    json={"changes": {"password": "newpass"}})
    assert r.status_code == 200, r.text
    sent = r.json()["sent"]
    assert sent["password"] == "newpass" and sent["confirm_password"] == "newpass"


def test_update_user_mac_fields(client, panel):
    r = client.post(f"/api/companies/{_cid(panel)}/sas/users/1/update", headers=panel["h_gov"],
                    json={"changes": {"mac_auth": 1, "allowed_macs": "AA:BB,CC:DD"}})
    assert r.status_code == 200, r.text
    sent = r.json()["sent"]
    assert sent["mac_auth"] == 1 and sent["allowed_macs"] == "AA:BB,CC:DD"


def test_update_user_rejects_uneditable_field(client, panel):
    r = client.post(f"/api/companies/{_cid(panel)}/sas/users/1/update", headers=panel["h_gov"],
                    json={"changes": {"balance": 999}})
    assert r.status_code == 400


def test_update_user_viewer_forbidden(client, panel):
    r = client.post(f"/api/companies/{_cid(panel)}/sas/users/1/update", headers=panel["h_viewer"],
                    json={"changes": {"enabled": 0}})
    assert r.status_code == 403


# ═══════════════ 10) القائمة البيضاء الموسّعة (الترجمات) ═══════════════
def test_resources_languages_whitelisted(client, panel):
    r = client.get(f"/api/companies/{_cid(panel)}/sas/get?path=resources/languages",
                   headers=panel["h_gov"])
    assert r.status_code == 200, r.text
    r2 = client.get(f"/api/companies/{_cid(panel)}/sas/get?path=resources/language/ar",
                    headers=panel["h_gov"])
    assert r2.status_code == 200, r2.text


# ═══════════════ 11) نموذج الوكيل المستقل: الأدمن ينشئ الحساب، الوكيل يضبط خادمه ═══════════════
def test_admin_creates_agent_then_agent_configures_own_server(client, panel):
    # 1) الأدمن ينشئ حساب وكيل مباشرةً تحت مزوّد جديد (بلا مزامنة SAS مسبقة)
    r = client.post("/api/companies/agent-accounts", headers=panel["h_gov"],
                    json={"username": "newagent", "password": "secret12",
                          "display_name": "وكيل تجريبي", "phone": "07701112233",
                          "provider": "مزوّد اختبار"})
    assert r.status_code == 200, r.text
    assert r.json()["provider"] == "مزوّد اختبار"
    cid = r.json()["company_id"]

    # 2) يظهر في قائمة الحسابات، وSAS غير مضبوط بعد
    lst = client.get("/api/companies/agent-accounts", headers=panel["h_gov"]).json()
    acc = next(a for a in lst["accounts"] if a["username"] == "newagent")
    assert acc["sas_configured"] is False and acc["display_name"] == "وكيل تجريبي"

    # 3) الوكيل يدخل ويضبط خادمه + اسم مستخدمه + كلمة مروره (على المحاكي)
    tok = client.post("/api/auth/login",
                      json={"username": "newagent", "password": "secret12"}).json()["token"]
    h = {"Authorization": f"Bearer {tok}"}
    cfg = client.patch("/api/companies/agent/sas-config", headers=h,
                       json={"sas_host": "sas.local", "sas_username": CREDS[0],
                             "sas_password": CREDS[1]})
    assert cfg.status_code == 200 and cfg.json()["configured"] is True

    # 4) الآن لوحة SAS تعمل للوكيل بخادمه الخاص
    d = client.get(f"/api/companies/{cid}/sas/dashboard", headers=h)
    assert d.status_code == 200, d.text
    assert d.json()["total"] == 5000

    # 5) الأدمن يحذف الحساب
    assert client.delete(f"/api/companies/agent-accounts/{acc['id']}",
                         headers=panel["h_gov"]).status_code == 200


def test_create_agent_account_rejects_short_password_and_dup(client, panel):
    ok = client.post("/api/companies/agent-accounts", headers=panel["h_gov"],
                     json={"username": "a1", "password": "longenough1", "provider": "P"})
    assert ok.status_code == 200, ok.text
    # كلمة مرور قصيرة
    assert client.post("/api/companies/agent-accounts", headers=panel["h_gov"],
                       json={"username": "a2", "password": "short"}).status_code == 400
    # اسم مكرّر
    assert client.post("/api/companies/agent-accounts", headers=panel["h_gov"],
                       json={"username": "a1", "password": "longenough1"}).status_code == 409


def test_create_agent_account_requires_admin(client, panel):
    # مستخدم viewer لا يستطيع إنشاء حسابات وكلاء
    assert client.post("/api/companies/agent-accounts", headers=panel["h_viewer"],
                       json={"username": "x", "password": "longenough1"}).status_code == 403
