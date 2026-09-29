"""
اختبارات نظام تصريح الوكيل ومقاطعة SAS — test_reconciliation.py

تُغطّي:
1. وكيل يصرّح بعدده → يظهر في /reconciliation بالحكم الصحيح.
2. حكم matched / company_suspicious / agent_suspicious حسب الفرق.
3. وكيل لا يصرّح لغيره (403).
4. عزل: مستخدم شركة A لا يرى صفوف B.
5. وكيل يرى صفّه فقط في /reconciliation.
6. جهة رقابية ترى الكل.
7. اختبار النهاية /report الاختيارية (GET أحدث تصريح).
8. انحدار: كل الاختبارات القديمة لا تزال خضراء.
"""
from __future__ import annotations

import pytest
from sqlmodel import Session, select

from app.database import engine
from app.models import (
    Company, Agent, AgentReport, Subscriber, User,
    CompanySnapshot, MergeFinding,
)
from app.core import security as sec_module
from app.main import _seed_default_admin


# ─────────────────────────── مساعدات ───────────────────────────

_MGRID_SEQ = iter(range(70001, 79999))


def _mk_company(db: Session, name: str, code: str) -> Company:
    c = Company(name=name, code=code, governorate="بغداد")
    db.add(c)
    db.commit()
    db.refresh(c)
    return c


def _mk_agent(db: Session, company_id: int, username: str,
              users_count: int = 0) -> Agent:
    a = Agent(
        company_id=company_id,
        manager_id=next(_MGRID_SEQ),
        username=username,
        firstname=username,
        lastname="اختبار",
        users_count=users_count,
    )
    db.add(a)
    db.commit()
    db.refresh(a)
    return a


def _mk_user(db: Session, username: str, role: str,
             company_id: int | None = None,
             agent: str = "") -> User:
    u = User(
        username=username,
        password_hash=sec_module.hash_password("pw_recon"),
        role=role,
        scope_company_id=company_id,
        scope_agent=agent,
    )
    db.add(u)
    db.commit()
    db.refresh(u)
    return u


def _login(client, username: str, password: str = "pw_recon") -> dict:
    """يُسجّل الدخول ويُرجع رأس Authorization."""
    r = client.post("/api/auth/login", json={"username": username, "password": password})
    assert r.status_code == 200, f"فشل تسجيل الدخول {username}: {r.text}"
    return {"Authorization": f"Bearer {r.json()['token']}"}


# ─────────────────────────── Fixture التنظيف ───────────────────────────

@pytest.fixture(autouse=True)
def _clean():
    """تنظيف بيانات الاختبار قبل وبعد كل حالة."""
    def _do():
        with Session(engine) as db:
            for row in db.exec(select(AgentReport)).all():
                db.delete(row)
            for row in db.exec(select(Subscriber)).all():
                if row.sub_id >= 70000:
                    db.delete(row)
            for row in db.exec(select(MergeFinding)).all():
                db.delete(row)
            for row in db.exec(select(CompanySnapshot)).all():
                db.delete(row)
            # حذف الوكلاء التجريبيين (manager_id >= 70000)
            for row in db.exec(select(Agent).where(Agent.manager_id >= 70000)).all():
                db.delete(row)
            # حذف الشركات التجريبية
            for code in ("RA", "RB"):
                c = db.exec(select(Company).where(Company.code == code)).first()
                if c:
                    for ag in db.exec(select(Agent).where(Agent.company_id == c.id)).all():
                        db.delete(ag)
                    db.delete(c)
            # حذف المستخدمين التجريبيين
            for u in db.exec(select(User)).all():
                if u.username not in ("admin",) and u.scope_company_id is not None:
                    db.delete(u)
                elif u.username.startswith("recon_"):
                    db.delete(u)
            db.commit()
        _seed_default_admin()

    _do()
    yield
    _do()


# ─────────────────────────── بيانات مشتركة ───────────────────────────

@pytest.fixture
def recon_data(client):
    """
    شركتان RA و RB، وكلاء، مستخدمون متنوّعون.
    يُرجع dict يحوي:
    - company_a, company_b: كائنات Company
    - agent_a1 (users_count=100), agent_a2 (users_count=50): وكلاء شركة A
    - agent_b1 (users_count=200): وكيل شركة B
    - h_gov: رأس جهة رقابية
    - h_ca: رأس مدير شركة A
    - h_agent_a1: رأس وكيل a1
    """
    with Session(engine) as db:
        ca = _mk_company(db, "شركة-مقاطعة-أ", "RA")
        cb = _mk_company(db, "شركة-مقاطعة-ب", "RB")

        ag_a1 = _mk_agent(db, ca.id, "recon_agentA1", users_count=100)
        ag_a2 = _mk_agent(db, ca.id, "recon_agentA2", users_count=50)
        ag_b1 = _mk_agent(db, cb.id, "recon_agentB1", users_count=200)

        _mk_user(db, "recon_ca_admin", "admin", company_id=ca.id)
        _mk_user(db, "recon_agent_a1_user", "operator",
                 company_id=ca.id, agent="recon_agentA1")

    h_gov = _login(client, "admin", "admin")
    h_ca = _login(client, "recon_ca_admin")
    h_agent_a1 = _login(client, "recon_agent_a1_user")

    with Session(engine) as db:
        ca = db.exec(select(Company).where(Company.code == "RA")).first()
        cb = db.exec(select(Company).where(Company.code == "RB")).first()
        ag_a1 = db.exec(select(Agent).where(Agent.username == "recon_agentA1")).first()
        ag_a2 = db.exec(select(Agent).where(Agent.username == "recon_agentA2")).first()
        ag_b1 = db.exec(select(Agent).where(Agent.username == "recon_agentB1")).first()

    return {
        "company_a": ca, "company_b": cb,
        "agent_a1": ag_a1, "agent_a2": ag_a2, "agent_b1": ag_b1,
        "h_gov": h_gov, "h_ca": h_ca, "h_agent_a1": h_agent_a1,
    }


# ═══════════════════════════════════════════════════════════════════
# 1) تصريح الوكيل بنفسه
# ═══════════════════════════════════════════════════════════════════

def test_agent_can_submit_own_report(client, recon_data):
    """الوكيل يصرّح بعدده → 200 + البيانات صحيحة."""
    ca = recon_data["company_a"]
    ag = recon_data["agent_a1"]
    h = recon_data["h_agent_a1"]

    r = client.post(
        f"/api/companies/{ca.id}/agents/{ag.id}/report",
        json={"declared_total": 95, "declared_active": 80, "note": "شهر أيلول"},
        headers=h,
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["declared_total"] == 95
    assert body["declared_active"] == 80
    assert body["note"] == "شهر أيلول"
    assert body["agent_username"] == "recon_agentA1"
    assert body["company_id"] == ca.id


def test_admin_can_submit_report_for_agent(client, recon_data):
    """مدير الشركة يصرّح نيابةً عن وكيل → 200."""
    ca = recon_data["company_a"]
    ag = recon_data["agent_a1"]
    h = recon_data["h_ca"]

    r = client.post(
        f"/api/companies/{ca.id}/agents/{ag.id}/report",
        json={"declared_total": 102},
        headers=h,
    )
    assert r.status_code == 200, r.text


def test_gov_can_submit_report(client, recon_data):
    """الجهة الرقابية تصرّح لأي وكيل."""
    ca = recon_data["company_a"]
    ag = recon_data["agent_a2"]
    h = recon_data["h_gov"]

    r = client.post(
        f"/api/companies/{ca.id}/agents/{ag.id}/report",
        json={"declared_total": 48},
        headers=h,
    )
    assert r.status_code == 200, r.text
    assert r.json()["agent_username"] == "recon_agentA2"


# ═══════════════════════════════════════════════════════════════════
# 2) منع الوكيل من التصريح لغيره (403)
# ═══════════════════════════════════════════════════════════════════

def test_agent_cannot_report_for_another_agent(client, recon_data):
    """وكيل A1 يحاول التصريح لوكيل A2 → 403."""
    ca = recon_data["company_a"]
    ag_a2 = recon_data["agent_a2"]
    h = recon_data["h_agent_a1"]

    r = client.post(
        f"/api/companies/{ca.id}/agents/{ag_a2.id}/report",
        json={"declared_total": 45},
        headers=h,
    )
    assert r.status_code == 403, r.text


def test_agent_cannot_report_for_agent_in_other_company(client, recon_data):
    """وكيل A1 يحاول التصريح لوكيل في شركة B → 403 أو 404."""
    cb = recon_data["company_b"]
    ag_b1 = recon_data["agent_b1"]
    h = recon_data["h_agent_a1"]

    r = client.post(
        f"/api/companies/{cb.id}/agents/{ag_b1.id}/report",
        json={"declared_total": 100},
        headers=h,
    )
    # إمّا 404 (نطاق الشركة يرفضه) أو 403 (نطاق الوكيل يرفضه)
    assert r.status_code in (403, 404), r.text


# ═══════════════════════════════════════════════════════════════════
# 3) التحقّق من declared_total >= 0
# ═══════════════════════════════════════════════════════════════════

def test_negative_declared_total_rejected(client, recon_data):
    """declared_total سالب → 400."""
    ca = recon_data["company_a"]
    ag = recon_data["agent_a1"]
    h = recon_data["h_gov"]

    r = client.post(
        f"/api/companies/{ca.id}/agents/{ag.id}/report",
        json={"declared_total": -1},
        headers=h,
    )
    assert r.status_code == 400, r.text


def test_zero_declared_total_accepted(client, recon_data):
    """declared_total=0 مقبول."""
    ca = recon_data["company_a"]
    ag = recon_data["agent_a1"]
    h = recon_data["h_gov"]

    r = client.post(
        f"/api/companies/{ca.id}/agents/{ag.id}/report",
        json={"declared_total": 0},
        headers=h,
    )
    assert r.status_code == 200, r.text


# ═══════════════════════════════════════════════════════════════════
# 4) أحكام /reconciliation
# ═══════════════════════════════════════════════════════════════════

def _submit(client, ca_id, ag_id, total, headers):
    r = client.post(
        f"/api/companies/{ca_id}/agents/{ag_id}/report",
        json={"declared_total": total},
        headers=headers,
    )
    assert r.status_code == 200, r.text


def test_verdict_matched(client, recon_data):
    """وكيل يصرّح بفرق ضمن النطاق → matched.
    agent_a1.users_count=100 → threshold=max(5, 5)=5 → 100±5 يعطي matched."""
    ca = recon_data["company_a"]
    ag = recon_data["agent_a1"]
    h = recon_data["h_gov"]

    # 103 - 100 = 3 <= threshold(5) → matched
    _submit(client, ca.id, ag.id, 103, h)

    r = client.get("/api/companies/reconciliation", headers=h)
    assert r.status_code == 200, r.text
    rows = r.json()["rows"]
    row = next(x for x in rows if x["agent_username"] == "recon_agentA1")
    assert row["verdict"] == "matched"
    assert row["diff"] == 3


def test_verdict_company_suspicious(client, recon_data):
    """وكيل يصرّح بأكثر مما تُظهره الشركة (خارج النطاق) → company_suspicious.
    agent_a1.users_count=100, threshold=5 → 150-100=50 > 5."""
    ca = recon_data["company_a"]
    ag = recon_data["agent_a1"]
    h = recon_data["h_gov"]

    _submit(client, ca.id, ag.id, 150, h)

    r = client.get("/api/companies/reconciliation", headers=h)
    rows = r.json()["rows"]
    row = next(x for x in rows if x["agent_username"] == "recon_agentA1")
    assert row["verdict"] == "company_suspicious"
    assert row["diff"] == 50


def test_verdict_agent_suspicious(client, recon_data):
    """وكيل يصرّح بأقل مما تُظهره الشركة (خارج النطاق) → agent_suspicious.
    agent_a1.users_count=100, threshold=5 → 50-100=-50 < -5."""
    ca = recon_data["company_a"]
    ag = recon_data["agent_a1"]
    h = recon_data["h_gov"]

    _submit(client, ca.id, ag.id, 50, h)

    r = client.get("/api/companies/reconciliation", headers=h)
    rows = r.json()["rows"]
    row = next(x for x in rows if x["agent_username"] == "recon_agentA1")
    assert row["verdict"] == "agent_suspicious"
    assert row["diff"] == -50


def test_verdict_no_report(client, recon_data):
    """وكيل لم يصرّح بعد → no_report."""
    h = recon_data["h_gov"]

    r = client.get("/api/companies/reconciliation", headers=h)
    assert r.status_code == 200
    rows = r.json()["rows"]
    # agent_a2 لم يُصرّح بعد
    row = next(x for x in rows if x["agent_username"] == "recon_agentA2")
    assert row["verdict"] == "no_report"
    assert row["agent_declared"] is None
    assert row["diff"] is None


def test_reconciliation_totals(client, recon_data):
    """مجموع الأحكام في totals صحيح."""
    ca = recon_data["company_a"]
    ag_a1 = recon_data["agent_a1"]
    h = recon_data["h_gov"]

    # a1: matched، a2: no_report، b1: no_report
    _submit(client, ca.id, ag_a1.id, 100, h)  # 100==100 → matched

    r = client.get("/api/companies/reconciliation", headers=h)
    totals = r.json()["totals"]
    rows = r.json()["rows"]
    # مجموع الأحكام يجب أن يساوي عدد الصفوف
    assert (totals["matched"] + totals["company_suspicious"] +
            totals["agent_suspicious"] + totals["no_report"]) == len(rows)
    assert totals["matched"] >= 1


# ═══════════════════════════════════════════════════════════════════
# 5) عزل: مستخدم شركة A لا يرى صفوف B
# ═══════════════════════════════════════════════════════════════════

def test_company_user_sees_only_own_agents_in_reconciliation(client, recon_data):
    """مستخدم شركة A في /reconciliation يرى وكلاء A فقط."""
    h = recon_data["h_ca"]

    r = client.get("/api/companies/reconciliation", headers=h)
    assert r.status_code == 200, r.text
    rows = r.json()["rows"]
    ca_id = recon_data["company_a"].id
    cb_id = recon_data["company_b"].id

    company_ids = {row["company_id"] for row in rows}
    assert ca_id in company_ids, "يجب أن يرى شركته"
    assert cb_id not in company_ids, "يجب ألا يرى شركة B"


def test_company_user_cannot_submit_report_for_other_company(client, recon_data):
    """مستخدم شركة A يحاول التصريح لوكيل في شركة B → 404."""
    cb = recon_data["company_b"]
    ag_b1 = recon_data["agent_b1"]
    h = recon_data["h_ca"]

    r = client.post(
        f"/api/companies/{cb.id}/agents/{ag_b1.id}/report",
        json={"declared_total": 190},
        headers=h,
    )
    assert r.status_code == 404, r.text


# ═══════════════════════════════════════════════════════════════════
# 6) عزل: وكيل يرى صفّه فقط
# ═══════════════════════════════════════════════════════════════════

def test_agent_sees_only_own_row_in_reconciliation(client, recon_data):
    """مستخدم وكيل A1 في /reconciliation يرى صفّه هو فقط."""
    h = recon_data["h_agent_a1"]

    r = client.get("/api/companies/reconciliation", headers=h)
    assert r.status_code == 200, r.text
    rows = r.json()["rows"]
    assert len(rows) == 1
    assert rows[0]["agent_username"] == "recon_agentA1"


def test_agent_sees_own_verdict(client, recon_data):
    """وكيل A1 يصرّح ثم يتحقّق من حكمه عبر /reconciliation."""
    ca = recon_data["company_a"]
    ag = recon_data["agent_a1"]
    h = recon_data["h_agent_a1"]

    # يصرّح بنفسه
    _submit(client, ca.id, ag.id, 95, h)

    r = client.get("/api/companies/reconciliation", headers=h)
    rows = r.json()["rows"]
    assert len(rows) == 1
    # diff = 95 - 100 = -5 → abs(-5) = 5 <= threshold(5) → matched
    assert rows[0]["verdict"] == "matched"


# ═══════════════════════════════════════════════════════════════════
# 7) جهة رقابية ترى الكل
# ═══════════════════════════════════════════════════════════════════

def test_gov_sees_all_agents_in_reconciliation(client, recon_data):
    """الجهة الرقابية ترى وكلاء الشركتين."""
    h = recon_data["h_gov"]

    r = client.get("/api/companies/reconciliation", headers=h)
    assert r.status_code == 200, r.text
    rows = r.json()["rows"]
    usernames = {row["agent_username"] for row in rows}
    assert "recon_agentA1" in usernames
    assert "recon_agentA2" in usernames
    assert "recon_agentB1" in usernames


# ═══════════════════════════════════════════════════════════════════
# 8) نهاية GET /report (اختيارية)
# ═══════════════════════════════════════════════════════════════════

def test_get_latest_report_no_report(client, recon_data):
    """GET /report لوكيل لم يصرّح → 404."""
    ca = recon_data["company_a"]
    ag = recon_data["agent_a1"]
    h = recon_data["h_gov"]

    r = client.get(
        f"/api/companies/{ca.id}/agents/{ag.id}/report",
        headers=h,
    )
    assert r.status_code == 404, r.text


def test_get_latest_report_returns_most_recent(client, recon_data):
    """GET /report يُرجع آخر تصريح (الأحدث) لا الأقدم."""
    ca = recon_data["company_a"]
    ag = recon_data["agent_a1"]
    h = recon_data["h_gov"]

    # تصريحان — نتوقّع الثاني
    _submit(client, ca.id, ag.id, 80, h)
    _submit(client, ca.id, ag.id, 90, h)

    r = client.get(
        f"/api/companies/{ca.id}/agents/{ag.id}/report",
        headers=h,
    )
    assert r.status_code == 200, r.text
    assert r.json()["declared_total"] == 90


def test_get_report_agent_cannot_read_other_agent(client, recon_data):
    """وكيل A1 لا يستطيع قراءة تصريح A2."""
    ca = recon_data["company_a"]
    ag_a2 = recon_data["agent_a2"]
    h = recon_data["h_agent_a1"]

    r = client.get(
        f"/api/companies/{ca.id}/agents/{ag_a2.id}/report",
        headers=h,
    )
    assert r.status_code == 403, r.text


# ═══════════════════════════════════════════════════════════════════
# 9) انحدار: السلوك القديم لا يتأثر
# ═══════════════════════════════════════════════════════════════════

def test_regression_companies_list_still_works(client, recon_data):
    """قائمة الشركات لا تزال تعمل بعد الإضافات الجديدة."""
    r = client.get("/api/companies", headers=recon_data["h_gov"])
    assert r.status_code == 200
    codes = {c["code"] for c in r.json()}
    assert "RA" in codes and "RB" in codes


def test_regression_agents_all_still_works(client, recon_data):
    """GET /companies/agents/all لا تزال تعمل."""
    r = client.get("/api/companies/agents/all", headers=recon_data["h_gov"])
    assert r.status_code == 200
    assert "agents" in r.json()


def test_regression_national_overview_still_works(client, recon_data):
    """national overview لا تزال تعمل."""
    r = client.get("/api/companies/overview/national",
                   headers=recon_data["h_gov"])
    assert r.status_code == 200
    assert "companies" in r.json()


def test_regression_audit_still_works(client, recon_data):
    """/audit لا يزال يعمل."""
    r = client.get("/api/companies/audit", headers=recon_data["h_gov"])
    assert r.status_code == 200
    assert "audit" in r.json()


def test_regression_import():
    """التحقّق من إقلاع التطبيق بعد الإضافات."""
    import app.main  # noqa: F401
