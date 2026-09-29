"""
اختبارات بوابة المشترك عبر SAS — test_portal_sas.py

يحاكي خادم SAS بواجهتيه معاً (بوابة /user/api + إدارة /admin/api) عبر MockTransport
واحد يُحقن في كلا العميلين (SASUserClient و SASClient داخل portal_sas)، ثم يتحقّق من:
1. توكن المشترك مطلوب (توكن موظّف → 403).
2. عزل الملكية: حساب لا يخصّ رقم المشترك → 404.
3. العرض دون ربط: يعمل عبر واجهة الإدارة (src=admin) + حجب الأسرار (_redact).
4. الربط: يختبر الدخول ثم يحفظ؛ الحالة تعكسه؛ والعرض بعده من البوابة (src=portal).
5. الكتابة تتطلّب ربطاً (409 قبله)؛ تغيير كلمة المرور بعده ينجح.
6. idempotency: عملية مالية بنفس transaction_id تُرفض (409).
"""
from __future__ import annotations

import json

import httpx
import pytest
from sqlmodel import Session, select

from app.core import security as sec_module
from app.database import engine
from app.integrations.sas_client import SASClient, sas_decrypt
from app.integrations.sas_user_client import SASUserClient
from app.main import _seed_default_admin
from app.models import Company, OtpCode, SasPortalAudit, Subscriber
from app.services import otp as otp_svc
import app.api.portal_sas as portal

PHONE = "07799990000"
NORM = "9647799990000"
COMPANY_CREDS = ("compadmin", "comppw")     # اعتماد مدير الشركة (واجهة الإدارة)
PORTAL_CREDS = ("sub1portal", "portalpw")   # اعتماد بوابة المشترك
PORTAL_TOKEN = "portal-tok"
ADMIN_TOKEN = "admin-tok"
UNAME = "sub_ps"
SUB_ID = 7201


def make_transport() -> httpx.MockTransport:
    def handler(request: httpx.Request) -> httpx.Response:
        path, method = request.url.path, request.method
        is_portal = "/user/api/" in path

        # ── تسجيل الدخول ──
        if is_portal and path.endswith("/auth/login") and method == "POST":
            p = json.loads(sas_decrypt(json.loads(request.content.decode())["payload"]))
            if (p.get("username"), p.get("password")) == PORTAL_CREDS:
                return httpx.Response(200, json={"status": 200, "token": PORTAL_TOKEN})
            return httpx.Response(401, json={"error": "بيانات بوابة خاطئة"})
        if (not is_portal) and path.endswith("/api/login") and method == "POST":
            p = json.loads(sas_decrypt(json.loads(request.content.decode())["payload"]))
            if (p.get("username"), p.get("password")) == COMPANY_CREDS:
                return httpx.Response(200, json={"token": ADMIN_TOKEN})
            return httpx.Response(401, json={"error": "بيانات إدارة خاطئة"})

        expected = PORTAL_TOKEN if is_portal else ADMIN_TOKEN
        if request.headers.get("Authorization") != f"Bearer {expected}":
            return httpx.Response(401, text="unauthorized")

        # ── بوابة المشترك ──
        if is_portal:
            if method == "GET" and path.endswith("/dashboard"):
                return httpx.Response(200, json={"status": 200, "data": {"balance": 12.5, "src": "portal"}})
            if method == "GET" and path.endswith("/packages"):
                return httpx.Response(200, json={"status": 200, "data": [{"id": 1, "name": "P"}]})
            if method == "POST":
                sent = json.loads(sas_decrypt(json.loads(request.content.decode())["payload"]))
                if path.endswith("/index/invoice"):
                    return httpx.Response(200, json={"data": [{"id": 1}], "total": 1, "src": "portal"})
                if path.endswith("/index/session"):
                    return httpx.Response(200, json={"data": [{"radacctid": 1}], "total": 1})
                if path.endswith("/traffic"):
                    return httpx.Response(200, json={"status": 200, "data": {"rx": [1], "src": "portal"}})
                if path.endswith("/redeem"):
                    return httpx.Response(200, json={"status": 200, "sent": sent})
                if path.endswith("/service"):
                    return httpx.Response(200, json={"status": 200, "sent": sent})
                if path.endswith("/user/activate"):
                    return httpx.Response(200, json={"status": 200, "sent": sent})
                if path.endswith("/user/extend"):
                    return httpx.Response(200, json={"status": 200, "sent": sent})
                if path.endswith("/user"):        # تغيير كلمة المرور
                    return httpx.Response(200, json={"status": 200, "sent": sent})
            return httpx.Response(404, text=f"portal لا مسار: {path}")

        # ── واجهة الإدارة (fallback العرض) ──
        if method == "GET":
            if path.endswith(f"/user/overview/{SUB_ID}"):
                return httpx.Response(200, json={"data": {"balance": 9.9, "src": "admin",
                                                          "password": "SHOULD_BE_HIDDEN"}})
            if path.endswith("/list/profile/0"):
                return httpx.Response(200, json=[{"id": 1, "name": "P"}])
        if method == "POST":
            if path.endswith(f"/index/UserJournal/{SUB_ID}"):
                return httpx.Response(200, json={"data": [{"id": 1, "amount": 5}], "total": 1, "src": "admin"})
            if path.endswith("/index/online"):
                return httpx.Response(200, json={"data": [{"username": UNAME, "framedipaddress": "10.0.0.1"},
                                                          {"username": "other"}], "total": 2})
            if path.endswith("/user/traffic"):
                return httpx.Response(200, json={"data": {"rx": [2], "src": "admin"}})
        return httpx.Response(404, text=f"admin لا مسار: {path}")

    return httpx.MockTransport(handler)


def install(monkeypatch):
    t = make_transport()

    def portal_factory(*a, **kw):
        kw["transport"] = t
        return SASUserClient(*a, **kw)

    def admin_factory(*a, **kw):
        kw["transport"] = t
        return SASClient(*a, **kw)

    monkeypatch.setattr(portal, "SASUserClient", portal_factory)
    monkeypatch.setattr(portal, "SASClient", admin_factory)


@pytest.fixture(autouse=True)
def _clean():
    def do():
        with Session(engine) as db:
            for a in db.exec(select(SasPortalAudit)).all():
                db.delete(a)
            for o in db.exec(select(OtpCode).where(OtpCode.phone == NORM)).all():
                db.delete(o)
            for s in db.exec(select(Subscriber).where(Subscriber.phone_norm == NORM)).all():
                db.delete(s)
            for c in db.exec(select(Company).where(Company.code == "PS1")).all():
                db.delete(c)
            db.commit()
        _seed_default_admin()
    do(); yield; do()


@pytest.fixture
def setup(client, monkeypatch):
    install(monkeypatch)
    with Session(engine) as db:
        c = Company(name="شركة بوابة", code="PS1", governorate="بغداد",
                    sas_host="sas.local", sas_username=COMPANY_CREDS[0],
                    sas_password_enc=sec_module.encrypt(COMPANY_CREDS[1]))
        db.add(c); db.commit(); db.refresh(c)
        s = Subscriber(company_id=c.id, sub_id=SUB_ID, username=UNAME, firstname="مشترك",
                       lastname="بوابة", agent_username="ag", phone=PHONE,
                       phone_norm=NORM, status="active")
        db.add(s); db.commit(); db.refresh(s)
        return {"cid": c.id, "acc": s.id}


def _sub_login(client):
    r = client.post("/api/subscriber/otp/request", json={"phone": PHONE})
    assert r.status_code == 200, r.text
    code = r.json()["dev_code"]
    r = client.post("/api/subscriber/otp/verify", json={"phone": PHONE, "code": code})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def _staff_login(client):
    r = client.post("/api/auth/login", json={"username": "admin", "password": "admin"})
    return {"Authorization": f"Bearer {r.json()['token']}"}


# ─────────────────────────── 1. الأمان والعزل ───────────────────────────
def test_staff_token_rejected(client, setup):
    h = _staff_login(client)
    assert client.get(f"/api/subscriber/sas/{setup['acc']}/balance", headers=h).status_code == 403


def test_foreign_account_404(client, setup):
    h = _sub_login(client)
    assert client.get("/api/subscriber/sas/999999/balance", headers=h).status_code == 404


# ─────────────────────────── 2. العرض دون ربط (إدارة) ───────────────────────────
def test_display_without_link_uses_admin_and_redacts(client, setup):
    h = _sub_login(client)
    bal = client.get(f"/api/subscriber/sas/{setup['acc']}/balance", headers=h)
    assert bal.status_code == 200, bal.text
    assert bal.json()["src"] == "admin"
    assert bal.json()["password"] == "***"          # الأسرار محجوبة
    inv = client.get(f"/api/subscriber/sas/{setup['acc']}/invoices", headers=h).json()
    assert inv["src"] == "admin" and inv["total"] == 1
    ses = client.get(f"/api/subscriber/sas/{setup['acc']}/sessions", headers=h).json()
    assert ses["total"] == 1 and ses["data"][0]["username"] == UNAME   # مصفّى عليه فقط


def test_write_requires_link(client, setup):
    h = _sub_login(client)
    r = client.post(f"/api/subscriber/sas/{setup['acc']}/change-password",
                    json={"new_password": "x"}, headers=h)
    assert r.status_code == 409


# ─────────────────────────── 3. الربط ───────────────────────────
def test_link_status_and_link(client, setup):
    h = _sub_login(client)
    st = client.get(f"/api/subscriber/sas/link/{setup['acc']}", headers=h).json()
    assert st["linked"] is False
    ok = client.post("/api/subscriber/sas/link", headers=h,
                     json={"account_id": setup["acc"], "sas_username": PORTAL_CREDS[0],
                           "sas_password": PORTAL_CREDS[1]})
    assert ok.status_code == 200, ok.text
    assert ok.json()["linked"] is True
    st2 = client.get(f"/api/subscriber/sas/link/{setup['acc']}", headers=h).json()
    assert st2["linked"] is True and st2["sas_username"] == PORTAL_CREDS[0]


def test_link_wrong_creds_400(client, setup):
    h = _sub_login(client)
    r = client.post("/api/subscriber/sas/link", headers=h,
                    json={"account_id": setup["acc"], "sas_username": "x", "sas_password": "y"})
    assert r.status_code == 400


def test_display_after_link_uses_portal(client, setup):
    h = _sub_login(client)
    client.post("/api/subscriber/sas/link", headers=h,
                json={"account_id": setup["acc"], "sas_username": PORTAL_CREDS[0],
                      "sas_password": PORTAL_CREDS[1]})
    bal = client.get(f"/api/subscriber/sas/{setup['acc']}/balance", headers=h).json()
    assert bal["src"] == "portal" and bal["balance"] == 12.5


# ─────────────────────────── 4. الكتابة + idempotency ───────────────────────────
def _link(client, h, acc):
    client.post("/api/subscriber/sas/link", headers=h,
                json={"account_id": acc, "sas_username": PORTAL_CREDS[0],
                      "sas_password": PORTAL_CREDS[1]})


def test_change_password_after_link(client, setup):
    h = _sub_login(client)
    _link(client, h, setup["acc"])
    r = client.post(f"/api/subscriber/sas/{setup['acc']}/change-password",
                    json={"new_password": "newpw"}, headers=h)
    assert r.status_code == 200, r.text
    assert r.json()["result"]["sent"]["value"] == "newpw"
    # الاعتماد المخزَّن حُدِّث لكلمة المرور الجديدة
    with Session(engine) as db:
        s = db.get(Subscriber, setup["acc"])
        assert sec_module.decrypt(s.sas_password_enc) == "newpw"


def test_redeem_idempotency(client, setup):
    h = _sub_login(client)
    _link(client, h, setup["acc"])
    body = {"pin": "1234", "transaction_id": "tx-abc"}
    r1 = client.post(f"/api/subscriber/sas/{setup['acc']}/redeem", json=body, headers=h)
    assert r1.status_code == 200, r1.text
    assert r1.json()["result"]["sent"]["pin"] == "1234"
    r2 = client.post(f"/api/subscriber/sas/{setup['acc']}/redeem", json=body, headers=h)
    assert r2.status_code == 409                     # نفس المعاملة → مرفوضة


def test_redeem_requires_link(client, setup):
    h = _sub_login(client)
    r = client.post(f"/api/subscriber/sas/{setup['acc']}/redeem",
                    json={"pin": "1", "transaction_id": "t1"}, headers=h)
    assert r.status_code == 409
