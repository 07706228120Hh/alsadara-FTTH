"""
اختبارات عميل بوابة المشترك — test_sas_user_client.py

يحاكي واجهة `/user/api/` بالكامل عبر httpx.MockTransport (يفكّ حمولة auth/login
فعلياً بـ sas_decrypt ⇒ يثبت التشفير على السلك)، ثم يتحقّق من:
1. الدخول عبر auth/login وحمل التوكن على كل الطلبات.
2. القراءة: dashboard/invoices/sessions/traffic.
3. الكتابة: change_password يرسل {key:'password', value:<new>}، redeem يرسل pin،
   activate يرسل uuid — كلها مفكوكة ومطابقة على السلك.
4. الأخطاء: بيانات خاطئة → SASError، ومسار مفقود (بوابة معطّلة) → SASError.
"""
from __future__ import annotations

import asyncio
import json

import httpx
import pytest

from app.integrations.sas_client import sas_decrypt
from app.integrations.sas_user_client import SASUserClient, SASError

CREDS = ("sub1", "subpass")
TOKEN = "portal-token-abc"
BALANCE = {"balance": 12.5, "expiration": "2026-10-01", "profile": "10M"}
INVOICES = {"data": [{"id": 2, "invoice_number": "2020-1-2", "amount": "0.00"}], "total": 1}
SESSIONS = {"data": [{"radacctid": 9, "framedipaddress": "10.0.0.5"}], "total": 1}
TRAFFIC = {"status": 200, "data": {"rx": [0, 1, 2], "tx": [0, 3, 4]}}


def make_transport(username: str = CREDS[0], password: str = CREDS[1]) -> httpx.MockTransport:
    def handler(request: httpx.Request) -> httpx.Response:
        path = request.url.path
        method = request.method

        # دخول البوابة: auth/login مشفّر
        if path.endswith("/api/auth/login") and method == "POST":
            payload = json.loads(sas_decrypt(json.loads(request.content.decode())["payload"]))
            if payload.get("username") == username and payload.get("password") == password:
                return httpx.Response(200, json={"status": 200, "token": TOKEN})
            return httpx.Response(401, json={"error": "بيانات خاطئة"})

        if request.headers.get("Authorization") != f"Bearer {TOKEN}":
            return httpx.Response(401, text="unauthorized")

        if method == "GET":
            if path.endswith("/api/dashboard"):
                return httpx.Response(200, json={"status": 200, "data": BALANCE})
            if path.endswith("/api/user"):
                return httpx.Response(200, json={"status": 200, "data": {"username": username}})
            return httpx.Response(404, text=f"GET لا مسار: {path}")

        if method == "POST":
            # كل نقاط الكتابة/القوائم تفكّ الحمولة وتعيدها لإثبات الحقول
            sent = json.loads(sas_decrypt(json.loads(request.content.decode())["payload"]))
            if path.endswith("/api/index/invoice"):
                return httpx.Response(200, json=INVOICES)
            if path.endswith("/api/index/session"):
                return httpx.Response(200, json=SESSIONS)
            if path.endswith("/api/traffic"):
                return httpx.Response(200, json=TRAFFIC)
            if path.endswith("/api/redeem"):
                return httpx.Response(200, json={"status": 200, "sent": sent})
            if path.endswith("/api/service"):
                return httpx.Response(200, json={"status": 200, "sent": sent})
            if path.endswith("/api/user/activate"):
                return httpx.Response(200, json={"status": 200, "sent": sent})
            if path.endswith("/api/user/extend"):
                return httpx.Response(200, json={"status": 200, "sent": sent})
            if path.endswith("/api/user"):          # تغيير كلمة المرور
                return httpx.Response(200, json={"status": 200, "sent": sent})
            return httpx.Response(404, text=f"POST لا مسار: {path}")

        return httpx.Response(405, text="method")

    return httpx.MockTransport(handler)


def _run(coro):
    return asyncio.run(coro)


def test_login_and_dashboard():
    async def go():
        async with SASUserClient("sas.local", *CREDS, transport=make_transport()) as p:
            assert p._token == TOKEN
            bal = await p.dashboard()
            return bal
    res = _run(go())
    assert res["data"]["balance"] == 12.5


def test_base_url_is_user_portal():
    p = SASUserClient("https://sas.local/whatever", *CREDS)
    assert p.base_url == "https://sas.local/user/api/index.php/api/"


def test_invoices_sessions_traffic():
    async def go():
        async with SASUserClient("sas.local", *CREDS, transport=make_transport()) as p:
            return (await p.invoices(page=1), await p.sessions(), await p.traffic(month=9, year=2026))
    inv, ses, tr = _run(go())
    assert inv["total"] == 1 and inv["data"][0]["invoice_number"] == "2020-1-2"
    assert ses["data"][0]["framedipaddress"] == "10.0.0.5"
    assert tr["data"]["rx"] == [0, 1, 2]


def test_change_password_payload_shape():
    async def go():
        async with SASUserClient("sas.local", *CREDS, transport=make_transport()) as p:
            return await p.change_password("newpw")
    res = _run(go())
    assert res["sent"]["key"] == "password"
    assert res["sent"]["value"] == "newpw"
    assert res["sent"]["current_password"] is True


def test_redeem_and_activate_payloads():
    async def go():
        async with SASUserClient("sas.local", *CREDS, transport=make_transport()) as p:
            return await p.redeem("136154"), await p.activate("uuid-xyz")
    red, act = _run(go())
    assert red["sent"]["pin"] == "136154"
    assert act["sent"]["uuid"] == "uuid-xyz"


def test_wrong_creds_raise():
    async def go():
        async with SASUserClient("sas.local", "sub1", "WRONG", transport=make_transport()) as p:
            await p.dashboard()
    with pytest.raises(SASError):
        _run(go())


def test_missing_route_raises_portal_message():
    async def go():
        async with SASUserClient("sas.local", *CREDS, transport=make_transport()) as p:
            await p.packages()          # لا معالج له في المحاكي → 404
    with pytest.raises(SASError) as ei:
        _run(go())
    assert "404" in str(ei.value)
