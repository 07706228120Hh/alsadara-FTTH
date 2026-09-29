"""
اختبارات طبقة الشركات + تكامل SAS4 — بمحاكاة كاملة لخادم SAS عبر httpx.MockTransport.

تغطّي البقعة العمياء السابقة (لا اختبار كان يمسّ sas_client/sas_sync/api.companies):
  - التشفير المتوافق مع OpenSSL (ذهاباً وإياباً + بنية Salted__).
  - مسار الجلب الحقيقي: login → token → Bearer → advancedDashboard → تحليل.
  - معالجة الفشل: بيانات دخول خاطئة (401)، استجابة غير JSON.
  - المزامنة: sync_one يحفظ لقطة ويضبط حالة النجاح/الفشل، وsync_all_once يعدّ.
  - الـ API: CRUD (بلا تسريب كلمة المرور) + /sas/test + /sync + /overview/national.

المحاكي يفكّ تشفير الحمولة فعلياً بـ sas_decrypt، فينجح الاختبار فقط إذا كان
العميل يشفّر بالصيغة الصحيحة على السلك — أي أنه يثبت صحّة الجلب لا مجرّد المنطق.
"""
from __future__ import annotations

import asyncio
import json

import httpx
import pytest
from sqlmodel import Session, select

from app.database import engine
from app.models import Company, CompanySnapshot
from app.integrations.sas_client import (
    SASClient, SASError, sas_encrypt, sas_decrypt,
)
from app.services import sas_sync
import app.api.companies as companies_api

# ─────────────────────────── بيانات ثابتة للمحاكاة ───────────────────────────
CREDS = ("admin", "s3cret")
TOKEN = "faketoken-abc123"
DASHBOARD = {
    "total": 12000, "active": 9500, "expired": 2500, "online": 8700,
    "offline": 3300, "expiring_today": 40, "expiring_soon": 300,
    "fup": 12, "managers": 18,
}
MANAGERS = [{"id": 1, "username": "agentA"}, {"id": 2, "username": "agentB"}]
USERS = [
    {"id": 1, "username": "u1", "parent": "agentA", "expiration": "2026-12-01"},
    {"id": 2, "username": "u2", "parent": "agentB", "expiration": "2026-11-01"},
]
PROFILES = [{"id": 1, "name": "10M"}, {"id": 2, "name": "50M"}]


# ───────────────────────────── محاكي خادم SAS4 ─────────────────────────────
def make_transport(username=CREDS[0], password=CREDS[1], *,
                   dashboard=DASHBOARD, non_json_dashboard=False):
    """يبني httpx.MockTransport يحاكي واجهة SAS4: login مشفّر + مسارات محمية بـ Bearer."""
    def handler(request: httpx.Request) -> httpx.Response:
        path = request.url.path

        # تسجيل الدخول: يفكّ تشفير الحمولة ويتحقّق من الاعتماد
        if path.endswith("/api/login") and request.method == "POST":
            body = json.loads(request.content.decode("utf-8"))
            payload = json.loads(sas_decrypt(body["payload"]))
            if payload.get("username") == username and payload.get("password") == password:
                return httpx.Response(200, json={"token": TOKEN})
            return httpx.Response(401, json={"error": "بيانات دخول خاطئة"})

        # كل ما بعد الدخول يتطلّب Bearer الصحيح
        if request.headers.get("Authorization") != f"Bearer {TOKEN}":
            return httpx.Response(401, text="unauthorized")

        if path.endswith("/advancedDashboard/subscribers"):
            if non_json_dashboard:
                return httpx.Response(200, text="<html>not json</html>")
            return httpx.Response(200, json={"status": "success", "data": dashboard})
        if path.endswith("/index/manager"):
            return httpx.Response(200, json={"data": MANAGERS})
        if path.endswith("/list/profile/0"):
            return httpx.Response(200, json=PROFILES)
        if path.endswith("/index/user"):
            return httpx.Response(200, json={"data": USERS, "total": len(USERS)})
        return httpx.Response(404, text=f"لا مسار: {path}")

    return httpx.MockTransport(handler)


def install_transport(monkeypatch, transport):
    """يحقن transport الوهمي في كل موضع يُنشئ SASClient (sync + api)."""
    def factory(*args, **kwargs):
        kwargs["transport"] = transport
        return SASClient(*args, **kwargs)
    monkeypatch.setattr(sas_sync, "SASClient", factory)
    monkeypatch.setattr(companies_api, "SASClient", factory)


@pytest.fixture(autouse=True)
def _clean_companies():
    """قاعدة شركات نظيفة قبل كل اختبار (القاعدة معزولة لكن مشتركة عبر الجلسة)."""
    with Session(engine) as db:
        for s in db.exec(select(CompanySnapshot)).all():
            db.delete(s)
        for c in db.exec(select(Company)).all():
            db.delete(c)
        db.commit()
    yield


def _new_company(client, **over):
    body = {
        "name": over.get("name", "شركة الاختبار"),
        "code": over.get("code", "TST"),
        "governorate": over.get("governorate", "بغداد"),
        "sas_host": over.get("sas_host", "sas.test.local"),
        "sas_username": over.get("sas_username", CREDS[0]),
        "sas_password": over.get("sas_password", CREDS[1]),
        "enabled": over.get("enabled", True),
    }
    r = client.post("/api/companies", json=body)
    assert r.status_code == 200, r.text
    return r.json()


# ═══════════════════════════ 1) طبقة التشفير ═══════════════════════════
def test_encryption_roundtrip_and_structure():
    sample = json.dumps({"username": "admin", "password": "x", "ع": "عربي"}, ensure_ascii=False)
    token = sas_encrypt(sample)
    assert sas_decrypt(token) == sample
    import base64
    assert base64.b64decode(token)[:8] == b"Salted__"


def test_decrypt_rejects_non_openssl():
    import base64
    with pytest.raises(ValueError):
        sas_decrypt(base64.b64encode(b"NoSalt__deadbeef").decode())


# ═══════════════════════ 2) مسار الجلب الحقيقي (SASClient) ═══════════════════════
def test_login_and_dashboard_ok():
    async def run():
        async with SASClient("h", CREDS[0], CREDS[1], transport=make_transport()) as sas:
            assert sas._token == TOKEN
            res = await sas.dashboard_subscribers()
            return res
    res = asyncio.run(run())
    assert res["data"]["total"] == 12000
    assert res["data"]["active"] == 9500


def test_login_bad_credentials_raises():
    async def run():
        async with SASClient("h", CREDS[0], "wrong", transport=make_transport()) as sas:
            pass
    with pytest.raises(SASError):
        asyncio.run(run())


def test_dashboard_non_json_raises():
    async def run():
        async with SASClient("h", CREDS[0], CREDS[1],
                             transport=make_transport(non_json_dashboard=True)) as sas:
            await sas.dashboard_subscribers()
    with pytest.raises(SASError):
        asyncio.run(run())


def test_managers_and_profiles_fetch():
    async def run():
        async with SASClient("h", CREDS[0], CREDS[1], transport=make_transport()) as sas:
            return await sas.managers(), await sas.profiles()
    managers, profiles = asyncio.run(run())
    assert {m["username"] for m in managers["data"]} == {"agentA", "agentB"}
    assert profiles[0]["name"] == "10M"


# ═══════════════════════════ 3) المزامنة (sas_sync) ═══════════════════════════
def test_sync_one_persists_snapshot(client, monkeypatch):
    install_transport(monkeypatch, make_transport())
    c = _new_company(client)
    snap = asyncio.run(sas_sync.sync_one(c["id"]))
    assert snap is not None
    assert snap.total == 12000 and snap.active == 9500 and snap.managers == 18
    with Session(engine) as db:
        comp = db.get(Company, c["id"])
        assert comp.last_sync_ok is True
        assert comp.last_sync_error == ""
        assert comp.last_sync_at is not None


def test_sync_one_failure_records_error(client, monkeypatch):
    # المحاكي يتوقّع كلمة مرور CREDS[1]، لكن الشركة أُنشئت بأخرى → فشل مصادقة
    install_transport(monkeypatch, make_transport())
    c = _new_company(client, sas_password="wrong-pass")
    snap = asyncio.run(sas_sync.sync_one(c["id"]))
    assert snap is None
    with Session(engine) as db:
        comp = db.get(Company, c["id"])
        assert comp.last_sync_ok is False
        assert comp.last_sync_error != ""


def test_sync_all_once_counts(client, monkeypatch):
    install_transport(monkeypatch, make_transport())
    _new_company(client, name="شركة أ")
    _new_company(client, name="شركة ب")
    _new_company(client, name="شركة معطّلة", enabled=False)  # تُتجاهَل
    summary = asyncio.run(sas_sync.sync_all_once())
    assert summary["companies"] == 2  # المُفعَّلتان فقط
    assert summary["ok"] == 2 and summary["failed"] == 0


# ═══════════════════════════ 4) واجهة API الشركات ═══════════════════════════
def test_company_crud_no_password_leak(client):
    created = _new_company(client, sas_password="topsecret")
    assert created["has_password"] is True
    assert "sas_password" not in created and "sas_password_enc" not in created

    cid = created["id"]
    assert client.get("/api/companies").json()  # القائمة غير فارغة
    got = client.get(f"/api/companies/{cid}").json()
    assert got["name"] == "شركة الاختبار"

    r = client.patch(f"/api/companies/{cid}", json={"name": "اسم جديد", "sas_password": ""})
    assert r.status_code == 200
    assert r.json()["name"] == "اسم جديد"
    assert r.json()["has_password"] is True  # لم تُمسح رغم تركها فارغة

    assert client.delete(f"/api/companies/{cid}").json()["ok"] is True
    assert client.get(f"/api/companies/{cid}").status_code == 404


def test_sas_test_endpoint_ok(client, monkeypatch):
    install_transport(monkeypatch, make_transport())
    c = _new_company(client)
    r = client.post(f"/api/companies/{c['id']}/sas/test", json={})
    assert r.status_code == 200
    body = r.json()
    assert body["ok"] is True
    assert body["summary"]["total"] == 12000 and body["summary"]["managers"] == 18


def test_sas_test_endpoint_failure(client, monkeypatch):
    install_transport(monkeypatch, make_transport())
    c = _new_company(client, sas_password="nope")
    r = client.post(f"/api/companies/{c['id']}/sas/test", json={})
    assert r.status_code == 200
    assert r.json()["ok"] is False
    assert r.json()["error"]


def test_sync_endpoint_then_national_overview(client, monkeypatch):
    install_transport(monkeypatch, make_transport())
    c1 = _new_company(client, name="شركة أ", code="A", governorate="بغداد")
    c2 = _new_company(client, name="شركة ب", code="B", governorate="البصرة")

    r1 = client.post(f"/api/companies/{c1['id']}/sync")
    assert r1.status_code == 200 and r1.json()["snapshot"]["total"] == 12000
    client.post(f"/api/companies/{c2['id']}/sync")

    ov = client.get("/api/companies/overview/national").json()
    assert ov["count"] == 2
    assert ov["totals"]["total"] == 24000        # 12000 × 2
    assert ov["totals"]["active"] == 19000       # 9500 × 2
    assert ov["totals"]["managers"] == 36
    names = {row["company"] for row in ov["companies"]}
    assert names == {"شركة أ", "شركة ب"}
    for row in ov["companies"]:
        assert row["last_sync_ok"] is True
        assert row["total"] == 12000


def test_overview_company_without_snapshot_shows_zeros(client):
    c = _new_company(client, name="بلا مزامنة")
    ov = client.get("/api/companies/overview/national").json()
    assert ov["count"] == 1
    row = ov["companies"][0]
    assert row["company"] == "بلا مزامنة"
    assert row["total"] == 0 and row["active"] == 0
    assert row["last_sync_ok"] is False


# ═══════════════════ 5) كشف كلمة مرور SAS (عند الطلب + تدقيق) ═══════════════════
def test_reveal_sas_password_returns_decrypted_and_audits(client):
    """المدير يكشف كلمة المرور المحفوظة (مفكوكة) عند الطلب، ويُسجَّل الكشف في AuditLog."""
    from app.models import AuditLog
    created = _new_company(client, sas_password="topsecret-xyz")
    r = client.get(f"/api/companies/{created['id']}/sas-password")
    assert r.status_code == 200, r.text
    assert r.json()["password"] == "topsecret-xyz"     # تُفكّ فعلاً (تطابق ما حُفظ)
    assert r.json()["has_password"] is True
    # يُسجَّل ككشف حسّاس (dangerous) يذكر الشركة
    with Session(engine) as db:
        logs = [a for a in db.exec(select(AuditLog)).all()
                if f"للشركة {created['id']}" in a.command]
        assert logs and logs[-1].kind == "dangerous"


def test_reveal_sas_password_empty_when_none(client):
    """شركة بلا كلمة مرور → يُعيد نصّاً فارغاً و has_password=False."""
    created = _new_company(client, sas_password="")
    r = client.get(f"/api/companies/{created['id']}/sas-password")
    assert r.status_code == 200, r.text
    assert r.json()["password"] == "" and r.json()["has_password"] is False


# ═══════════════ 6) إعداد اتصال SAS ذاتيّاً (الشركة تضبط خادمها) ═══════════════
def test_update_sas_config_sets_fields(client):
    created = _new_company(client, sas_host="old.host", sas_username="olduser",
                           sas_password="oldpass")
    r = client.patch(f"/api/companies/{created['id']}/sas-config", json={
        "sas_host": "new.sas.host", "sas_username": "newuser",
        "sas_password": "newpass", "sas_https": True, "sas_verify_tls": False,
    })
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["sas_host"] == "new.sas.host" and body["sas_username"] == "newuser"
    assert body["sas_https"] is True and body["has_password"] is True
    # كلمة المرور حُدّثت فعلاً
    rv = client.get(f"/api/companies/{created['id']}/sas-password")
    assert rv.json()["password"] == "newpass"


def test_update_sas_config_empty_password_keeps(client):
    created = _new_company(client, sas_password="keepme")
    r = client.patch(f"/api/companies/{created['id']}/sas-config",
                     json={"sas_host": "h", "sas_username": "u", "sas_password": ""})
    assert r.status_code == 200, r.text
    rv = client.get(f"/api/companies/{created['id']}/sas-password")
    assert rv.json()["password"] == "keepme"     # لم تُمسح
