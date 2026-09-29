"""
اختبارات عزل النطاق (Multi-tenant scoping) — test_scope.py

تُغطّي سيناريوهات الأمان الحرجة:
1. جهة رقابية (admin بلا نطاق) ترى الكل.
2. مستخدم شركةA يرى شركته فقط.
3. مستخدم وكيل يرى نطاقه ضمن شركته.
4. محاولة تجاوز النطاق عبر query param ترفض.
5. مسارات رقابية (national/audit/sync-all) ترفض المستخدم ذا النطاق.
6. منع التصعيد الأفقي H2 في إدارة المستخدمين.
7. انحدار: الجهة الرقابية وDev-mode ما زالا يريان الكل.
"""
from __future__ import annotations

import pytest
from sqlmodel import Session, select

from app.database import engine
from app.models import (
    Company, CompanySnapshot, Agent, MergeFinding, Subscriber, User
)
from app.core import security as sec_module
from app.main import _seed_default_admin


# ─────────────────────────── مساعدات إعداد البيانات ───────────────────────────

def _create_company(db: Session, name: str, code: str) -> Company:
    c = Company(name=name, code=code, governorate="بغداد")
    db.add(c)
    db.commit()
    db.refresh(c)
    return c


def _create_scoped_user(db: Session, username: str, role: str,
                        company_id: int | None = None,
                        agent: str = "") -> User:
    u = User(
        username=username,
        password_hash=sec_module.hash_password("pw123"),
        role=role,
        scope_company_id=company_id,
        scope_agent=agent,
    )
    db.add(u)
    db.commit()
    db.refresh(u)
    return u


def _create_subscriber(db: Session, company_id: int, agent_username: str,
                        sub_id_offset: int = 0) -> Subscriber:
    s = Subscriber(
        company_id=company_id,
        sub_id=1000 + sub_id_offset,
        username=f"sub_{company_id}_{sub_id_offset}",
        agent_username=agent_username,
    )
    db.add(s)
    db.commit()
    db.refresh(s)
    return s


def _create_agent(db: Session, company_id: int, username: str,
                  parent_username: str = "") -> Agent:
    # manager_id فريد يعتمد على company_id + hash بسيط
    mgr_id = company_id * 100 + hash(username) % 100
    a = Agent(
        company_id=company_id,
        manager_id=abs(mgr_id),
        username=username,
        parent_username=parent_username,
        firstname=username,
        lastname="اختبار",
    )
    db.add(a)
    db.commit()
    db.refresh(a)
    return a


def _create_merge_finding(db: Session, company_id: int, username: str) -> MergeFinding:
    f = MergeFinding(
        company_id=company_id,
        username=username,
        kind="LOAD_BALANCING_SUSPECTED",
        severity="warning",
    )
    db.add(f)
    db.commit()
    db.refresh(f)
    return f


def _tok(client, username: str, password: str = "pw123") -> dict:
    """يسجّل الدخول ويُرجع رأس Authorization."""
    r = client.post("/api/auth/login", json={"username": username, "password": password})
    assert r.status_code == 200, f"فشل تسجيل دخول {username}: {r.text}"
    return {"Authorization": f"Bearer {r.json()['token']}"}


# ─────────────────────────── Fixture التنظيف ───────────────────────────

@pytest.fixture(autouse=True)
def _clean_scope_data():
    """تنظيف الجداول المُستخدمة في هذا الملف قبل كل اختبار.
    يضمن وجود مستخدم admin (بلا نطاق) بعد كل تنظيف."""
    def _do_clean():
        with Session(engine) as db:
            for model in (MergeFinding, Subscriber, Agent, CompanySnapshot, Company):
                for row in db.exec(select(model)).all():
                    db.delete(row)
            # حذف المستخدمين المُنشَأَين بواسطة هذه الاختبارات (غير admin)
            for u in db.exec(select(User)).all():
                if u.username != "admin":
                    db.delete(u)
            db.commit()
        # إعادة بذر المدير الافتراضي إن لزم (admin بلا نطاق)
        _seed_default_admin()

    _do_clean()
    yield
    _do_clean()


# ─────────────────────────── البيانات المشتركة ───────────────────────────

@pytest.fixture
def scope_data(client):
    """
    ينشئ بيانات اختبار كاملة ويُرجع dict فيه:
    - company_a, company_b: كائنات Company
    - h_gov: رأس جهة رقابية (admin بلا نطاق)
    - h_a: رأس مستخدم شركةA (admin + scope_company_id=A)
    - h_agent: رأس مستخدم وكيل (operator + scope_company_id=A + scope_agent="agentX")
    """
    with Session(engine) as db:
        # شركتان
        ca = _create_company(db, "شركة-أ", "CA")
        cb = _create_company(db, "شركة-ب", "CB")

        # وكلاء
        _create_agent(db, ca.id, "agentX")
        _create_agent(db, ca.id, "agentY", parent_username="agentX")
        _create_agent(db, cb.id, "agentZ")

        # مشتركون
        _create_subscriber(db, ca.id, "agentX", sub_id_offset=1)
        _create_subscriber(db, ca.id, "agentY", sub_id_offset=2)
        _create_subscriber(db, cb.id, "agentZ", sub_id_offset=3)

        # نتائج دمج
        _create_merge_finding(db, ca.id, "agentX")
        _create_merge_finding(db, cb.id, "agentZ")

        # مستخدمون
        _create_scoped_user(db, "user_a", "admin", company_id=ca.id)
        _create_scoped_user(db, "user_agent", "operator",
                            company_id=ca.id, agent="agentX")

    h_gov = _tok(client, "admin", "admin")
    h_a = _tok(client, "user_a")
    h_agent = _tok(client, "user_agent")

    with Session(engine) as db:
        ca = db.exec(select(Company).where(Company.code == "CA")).first()
        cb = db.exec(select(Company).where(Company.code == "CB")).first()

    return {
        "company_a": ca, "company_b": cb,
        "h_gov": h_gov, "h_a": h_a, "h_agent": h_agent,
    }


# ═══════════════════════════════════════════════════════════════════
# 1) قائمة الشركات — رؤية صحيحة لكل نطاق
# ═══════════════════════════════════════════════════════════════════

def test_gov_sees_all_companies(client, scope_data):
    """الجهة الرقابية ترى شركتي A و B."""
    r = client.get("/api/companies", headers=scope_data["h_gov"])
    assert r.status_code == 200
    codes = {c["code"] for c in r.json()}
    assert "CA" in codes and "CB" in codes


def test_company_user_sees_own_company_only(client, scope_data):
    """مستخدم شركة A يرى شركة A فقط."""
    r = client.get("/api/companies", headers=scope_data["h_a"])
    assert r.status_code == 200
    items = r.json()
    assert len(items) == 1
    assert items[0]["code"] == "CA"


def test_agent_user_sees_own_company_only(client, scope_data):
    """مستخدم وكيل يرى شركة A فقط (عبر نطاقه)."""
    r = client.get("/api/companies", headers=scope_data["h_agent"])
    assert r.status_code == 200
    items = r.json()
    assert len(items) == 1
    assert items[0]["code"] == "CA"


# ═══════════════════════════════════════════════════════════════════
# 2) شركة بعينها — 404 عند الوصول لشركة خارج النطاق
# ═══════════════════════════════════════════════════════════════════

def test_company_user_gets_404_for_other_company(client, scope_data):
    """مستخدم شركة A على GET /companies/{B} يحصل على 404."""
    cid_b = scope_data["company_b"].id
    r = client.get(f"/api/companies/{cid_b}", headers=scope_data["h_a"])
    assert r.status_code == 404


def test_company_user_can_get_own_company(client, scope_data):
    """مستخدم شركة A يصل لشركته بنجاح."""
    cid_a = scope_data["company_a"].id
    r = client.get(f"/api/companies/{cid_a}", headers=scope_data["h_a"])
    assert r.status_code == 200
    assert r.json()["code"] == "CA"


# ═══════════════════════════════════════════════════════════════════
# 3) مسارات رقابية شاملة → 403 لمستخدم ذي نطاق
# ═══════════════════════════════════════════════════════════════════

def test_national_overview_denied_for_company_user(client, scope_data):
    r = client.get("/api/companies/overview/national", headers=scope_data["h_a"])
    assert r.status_code == 403


def test_national_overview_denied_for_agent_user(client, scope_data):
    r = client.get("/api/companies/overview/national", headers=scope_data["h_agent"])
    assert r.status_code == 403


def test_audit_denied_for_company_user(client, scope_data):
    r = client.get("/api/companies/audit", headers=scope_data["h_a"])
    assert r.status_code == 403


def test_sync_all_denied_for_company_user(client, scope_data):
    r = client.post("/api/companies/sync-all", headers=scope_data["h_a"])
    assert r.status_code == 403


def test_national_overview_allowed_for_gov(client, scope_data):
    """الجهة الرقابية تصل لـ national/overview بنجاح."""
    r = client.get("/api/companies/overview/national", headers=scope_data["h_gov"])
    assert r.status_code == 200


# ═══════════════════════════════════════════════════════════════════
# 4) subscribers/agents/merge-findings — تجاهل company_id العميل خارج النطاق
# ═══════════════════════════════════════════════════════════════════

def test_subscribers_company_user_ignores_client_company_id(client, scope_data):
    """مستخدم شركة A مهما مرّر company_id=B لا يرى مشتركي B."""
    cid_b = scope_data["company_b"].id
    r = client.get(f"/api/companies/subscribers?company_id={cid_b}",
                   headers=scope_data["h_a"])
    assert r.status_code == 200
    subs = r.json()["subscribers"]
    # يجب أن تكون كلها تابعة لشركة A فقط
    company_ids = {s["company_id"] for s in subs}
    assert cid_b not in company_ids


def test_subscribers_gov_can_see_all(client, scope_data):
    """الجهة الرقابية ترى مشتركي كل الشركات."""
    r = client.get("/api/companies/subscribers", headers=scope_data["h_gov"])
    assert r.status_code == 200
    company_ids = {s["company_id"] for s in r.json()["subscribers"]}
    # يجب أن يرى الشركتين
    assert scope_data["company_a"].id in company_ids
    assert scope_data["company_b"].id in company_ids


def test_merge_findings_company_user_ignores_client_company_id(client, scope_data):
    """مستخدم شركة A لا يرى نتائج دمج شركة B مهما مرّر company_id=B."""
    cid_b = scope_data["company_b"].id
    r = client.get(f"/api/companies/merge-findings?company_id={cid_b}",
                   headers=scope_data["h_a"])
    assert r.status_code == 200
    findings = r.json()["findings"]
    company_ids = {f["company_id"] for f in findings}
    assert cid_b not in company_ids


def test_agents_company_user_ignores_client_company_id(client, scope_data):
    """مستخدم شركة A لا يرى وكلاء شركة B مهما مرّر company_id=B."""
    cid_b = scope_data["company_b"].id
    r = client.get(f"/api/companies/agents/all?company_id={cid_b}",
                   headers=scope_data["h_a"])
    assert r.status_code == 200
    agents = r.json()["agents"]
    company_ids = {a["company_id"] for a in agents}
    assert cid_b not in company_ids


# ═══════════════════════════════════════════════════════════════════
# 5) وكيل يرى مشتركيه فقط
# ═══════════════════════════════════════════════════════════════════

def test_agent_sees_only_own_subscribers(client, scope_data):
    """مستخدم وكيل agentX يرى مشتركيه فقط (sub تحت agentX)."""
    r = client.get("/api/companies/subscribers", headers=scope_data["h_agent"])
    assert r.status_code == 200
    subs = r.json()["subscribers"]
    # كل مشترك يجب أن يكون agent_username == "agentX"
    for s in subs:
        assert s["agent"] == "agentX", f"وكيل خاطئ: {s['agent']}"
    # يجب أن يرى مشتركاً واحداً على الأقل
    assert len(subs) >= 1


def test_agent_agents_view_limited(client, scope_data):
    """وكيل agentX يرى نفسه وأبناءه المباشرين (agentY لكن ليس agentZ)."""
    r = client.get("/api/companies/agents/all", headers=scope_data["h_agent"])
    assert r.status_code == 200
    agents = r.json()["agents"]
    usernames = {a["username"] for a in agents}
    # agentX (نفسه) و agentY (ابنه) يجب أن يظهرا
    assert "agentX" in usernames
    assert "agentY" in usernames
    # agentZ تابع لشركة B — يجب ألا يظهر
    assert "agentZ" not in usernames


# ═══════════════════════════════════════════════════════════════════
# 6) منع التصعيد الأفقي H2 — إدارة المستخدمين
# ═══════════════════════════════════════════════════════════════════

def test_scoped_user_cannot_create_user(client, scope_data):
    """مستخدم شركة A لا يستطيع إنشاء مستخدم جديد."""
    r = client.post("/api/users",
                    json={"username": "hacker", "password": "pw", "role": "admin"},
                    headers=scope_data["h_a"])
    assert r.status_code == 403


def test_agent_user_cannot_create_user(client, scope_data):
    """مستخدم وكيل لا يستطيع إنشاء مستخدم."""
    r = client.post("/api/users",
                    json={"username": "hacker2", "password": "pw", "role": "viewer"},
                    headers=scope_data["h_agent"])
    assert r.status_code == 403


def test_scoped_user_cannot_delete_user(client, scope_data):
    """مستخدم شركة A لا يستطيع حذف مستخدم."""
    # استعن بالمستخدم admin (ID موجود)
    users = client.get("/api/users").json()
    # البحث عن أي مستخدم غير admin في القائمة
    target = next((u for u in users if u["username"] == "user_a"), None)
    if target:
        r = client.delete(f"/api/users/{target['id']}", headers=scope_data["h_a"])
        assert r.status_code == 403


def test_scoped_user_cannot_update_user(client, scope_data):
    """مستخدم شركة A لا يستطيع تعديل مستخدم."""
    users = client.get("/api/users").json()
    target = next((u for u in users if u["username"] == "user_a"), None)
    if target:
        r = client.patch(f"/api/users/{target['id']}",
                         json={"role": "admin"},
                         headers=scope_data["h_a"])
        assert r.status_code == 403


# ═══════════════════════════════════════════════════════════════════
# 7) انحدار — الجهة الرقابية وDev-mode يريان الكل
# ═══════════════════════════════════════════════════════════════════

def test_gov_regression_sees_all_subscribers(client, scope_data):
    """الجهة الرقابية تصل لكل المشتركين بلا قيد."""
    r = client.get("/api/companies/subscribers", headers=scope_data["h_gov"])
    assert r.status_code == 200
    company_ids = {s["company_id"] for s in r.json()["subscribers"]}
    assert scope_data["company_a"].id in company_ids
    assert scope_data["company_b"].id in company_ids


def test_dev_mode_no_token_sees_all_companies(client, scope_data):
    """في وضع المحاكاة بلا توكن (dev) — يصل لكل الشركات."""
    # في conftest: API_TOKEN="" و USE_MOCK_OLT=true → dev identity → full access
    r = client.get("/api/companies")
    assert r.status_code == 200
    codes = {c["code"] for c in r.json()}
    assert "CA" in codes and "CB" in codes


def test_gov_regression_national_overview(client, scope_data):
    """الجهة الرقابية تصل لـ /overview/national."""
    r = client.get("/api/companies/overview/national", headers=scope_data["h_gov"])
    assert r.status_code == 200
    assert "companies" in r.json()


def test_gov_regression_audit(client, scope_data):
    """الجهة الرقابية تصل لـ /audit."""
    r = client.get("/api/companies/audit", headers=scope_data["h_gov"])
    assert r.status_code == 200
    assert "audit" in r.json()


def test_gov_can_create_company(client, scope_data):
    """الجهة الرقابية تنشئ شركة جديدة."""
    r = client.post("/api/companies",
                    json={"name": "شركة-رقابية", "code": "GOV",
                          "sas_host": "", "sas_username": ""},
                    headers=scope_data["h_gov"])
    assert r.status_code == 200
    assert r.json()["code"] == "GOV"


def test_scoped_user_cannot_create_company(client, scope_data):
    """مستخدم شركة A لا يستطيع إنشاء شركة جديدة."""
    r = client.post("/api/companies",
                    json={"name": "شركة-مزيّفة", "code": "FAKE",
                          "sas_host": "", "sas_username": ""},
                    headers=scope_data["h_a"])
    assert r.status_code == 403


def test_scoped_user_cannot_delete_company(client, scope_data):
    """مستخدم شركة A لا يستطيع حذف أي شركة."""
    cid_a = scope_data["company_a"].id
    r = client.delete(f"/api/companies/{cid_a}", headers=scope_data["h_a"])
    assert r.status_code == 403


# ═══════════════ إعداد SAS ذاتيّاً: الشركة تضبط شركتها فقط ═══════════════

def test_company_user_can_config_own_company_sas(client, scope_data):
    """مستخدم شركة A يضبط بيانات SAS لشركته."""
    cid_a = scope_data["company_a"].id
    r = client.patch(f"/api/companies/{cid_a}/sas-config",
                     json={"sas_host": "own.host", "sas_username": "own"},
                     headers=scope_data["h_a"])
    assert r.status_code == 200
    assert r.json()["sas_host"] == "own.host"


def test_company_user_cannot_config_other_company_sas(client, scope_data):
    """مستخدم شركة A لا يستطيع ضبط SAS لشركة B (404 خارج النطاق)."""
    cid_b = scope_data["company_b"].id
    r = client.patch(f"/api/companies/{cid_b}/sas-config",
                     json={"sas_host": "x", "sas_username": "y"},
                     headers=scope_data["h_a"])
    assert r.status_code == 404
