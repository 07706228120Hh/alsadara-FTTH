"""
اختبارات بوابة الوكلاء — تزويد حساب دخول لوكيل موجود.

تُغطّي:
1. جهة رقابية تُزوّد حساب وكيل → 200 + كلمة مرور عشوائية.
   الوكيل يسجّل دخوله → /me يُظهر النطاق الصحيح.
2. الوكيل بعد الدخول يرى مشتركيه فقط (GET /companies/subscribers).
3. منع التصعيد: role=admin لا يُقبل؛ scope_company_id في الجسم يُتجاهل.
4. مدير شركة A يحاول تزويد وكيل في شركة B → 404.
5. /me للجهة الرقابية يُرجع company_id=null.
6. انحدار: كل الاختبارات الموجودة لا تتأثر (الملف منعزل ببيانات خاصة).
"""
from __future__ import annotations

import pytest
from sqlmodel import Session, select

from app.database import engine
from app.models import Company, Agent, Subscriber, User, MergeFinding, CompanySnapshot
from app.core import security as sec_module
from app.main import _seed_default_admin


# ─────────────────────────── مساعدات ───────────────────────────

def _mk_company(db: Session, name: str, code: str) -> Company:
    c = Company(name=name, code=code, governorate="بغداد")
    db.add(c)
    db.commit()
    db.refresh(c)
    return c


_AGENT_ID_SEQ = iter(range(90001, 99999))


def _mk_agent(db: Session, company_id: int, username: str,
               parent_username: str = "") -> Agent:
    # نستخدم manager_id >= 90000 لتسهيل التنظيف؛ تسلسل مضمون الفريدة
    mgr_id = next(_AGENT_ID_SEQ)
    a = Agent(
        company_id=company_id,
        manager_id=mgr_id,
        username=username,
        firstname=username,
        lastname="test",
        parent_username=parent_username,
    )
    db.add(a)
    db.commit()
    db.refresh(a)
    return a


def _mk_subscriber(db: Session, company_id: int, agent_username: str,
                    offset: int = 0) -> Subscriber:
    s = Subscriber(
        company_id=company_id,
        sub_id=5000 + offset,
        username=f"portal_sub_{company_id}_{offset}",
        agent_username=agent_username,
    )
    db.add(s)
    db.commit()
    db.refresh(s)
    return s


def _mk_scoped_user(db: Session, username: str, role: str,
                     company_id: int, agent: str = "") -> User:
    u = User(
        username=username,
        password_hash=sec_module.hash_password("pw_portal"),
        role=role,
        scope_company_id=company_id,
        scope_agent=agent,
    )
    db.add(u)
    db.commit()
    db.refresh(u)
    return u


def _login(client, username: str, password: str = "pw_portal") -> dict:
    """يُسجّل الدخول ويُرجع رأس Authorization."""
    r = client.post("/api/auth/login", json={"username": username, "password": password})
    assert r.status_code == 200, f"فشل تسجيل الدخول {username}: {r.text}"
    return {"Authorization": f"Bearer {r.json()['token']}"}


# ─────────────────────────── Fixture ───────────────────────────

@pytest.fixture(autouse=True)
def _clean_portal_data():
    """تنظيف بيانات الاختبار قبل وبعد كل حالة — عزل تام."""
    def _clean():
        with Session(engine) as db:
            # حذف المشتركين والوكلاء والشركات المُنشأَة بواسطة هذا الملف
            for s in db.exec(select(Subscriber).where(
                    Subscriber.sub_id >= 5000)).all():
                db.delete(s)
            for model in (MergeFinding, CompanySnapshot):
                pass  # لا توجد في هذا الملف
            # حذف المستخدمين ذوي النطاق المُنشَئين هنا (scope_company_id != NULL)
            for u in db.exec(select(User).where(User.scope_company_id.isnot(None))).all():
                db.delete(u)
            # حذف المستخدمين الأشقاء بالاسم
            for name in ("portal_admin_a", "portal_admin_b",
                         "portal_viewer_manually"):
                u = db.exec(select(User).where(User.username == name)).first()
                if u:
                    db.delete(u)
            # حذف الوكلاء التجريبيين (manager_id >= 90000)
            for a in db.exec(select(Agent).where(Agent.manager_id >= 90000)).all():
                db.delete(a)
            # حذف الشركات التجريبية
            for code in ("PA", "PB"):
                c = db.exec(select(Company).where(Company.code == code)).first()
                if c:
                    # حذف الوكلاء المرتبطين أولاً
                    for ag in db.exec(select(Agent).where(
                            Agent.company_id == c.id)).all():
                        db.delete(ag)
                    for sub in db.exec(select(Subscriber).where(
                            Subscriber.company_id == c.id)).all():
                        db.delete(sub)
                    db.delete(c)
            db.commit()
        _seed_default_admin()

    _clean()
    yield
    _clean()


@pytest.fixture
def portal_data(client):
    """
    بيانات اختبار البوابة:
    - شركتان PA و PB
    - وكيل agentP1 في PA، وكيل agentP2 في PB
    - مشتركون تابعون لكل وكيل
    - مدير شركة PA (admin مقيّد)
    - رأس جهة رقابية (admin بلا نطاق)
    """
    with Session(engine) as db:
        ca = _mk_company(db, "شركة-بوابة-أ", "PA")
        cb = _mk_company(db, "شركة-بوابة-ب", "PB")

        ag1 = _mk_agent(db, ca.id, "agentP1")
        ag2 = _mk_agent(db, cb.id, "agentP2")

        # مشتركان لكل وكيل
        _mk_subscriber(db, ca.id, "agentP1", offset=1)
        _mk_subscriber(db, ca.id, "agentP1", offset=2)
        _mk_subscriber(db, cb.id, "agentP2", offset=3)

        # مدير شركة PA (admin مقيّد بالشركة)
        _mk_scoped_user(db, "portal_admin_a", "admin", company_id=ca.id)

    h_gov = _login(client, "admin", "admin")
    h_admin_a = _login(client, "portal_admin_a")

    with Session(engine) as db:
        ca = db.exec(select(Company).where(Company.code == "PA")).first()
        cb = db.exec(select(Company).where(Company.code == "PB")).first()
        ag1 = db.exec(select(Agent).where(Agent.company_id == ca.id,
                                           Agent.username == "agentP1")).first()
        ag2 = db.exec(select(Agent).where(Agent.company_id == cb.id,
                                           Agent.username == "agentP2")).first()

    return {
        "company_a": ca, "company_b": cb,
        "agent1": ag1, "agent2": ag2,
        "h_gov": h_gov, "h_admin_a": h_admin_a,
    }


# ═══════════════════════════════════════════════════════════════════
# 1) تزويد حساب وكيل + تسجيل الدخول + /me يُظهر النطاق
# ═══════════════════════════════════════════════════════════════════

def test_gov_provision_agent_account(client, portal_data):
    """جهة رقابية تُزوّد حساب وكيل → 200 + بيانات صحيحة."""
    ca = portal_data["company_a"]
    ag1 = portal_data["agent1"]
    h = portal_data["h_gov"]

    r = client.post(
        f"/api/companies/{ca.id}/agents/{ag1.id}/account",
        json={},
        headers=h,
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["ok"] is True
    assert body["username"]
    assert body["password"]  # كلمة مرور صريحة مرّة واحدة
    assert body["scope_company_id"] == ca.id
    assert body["scope_agent"] == "agentP1"
    assert "password_hash" not in body


def test_agent_login_and_me_shows_correct_scope(client, portal_data):
    """بعد تزويد الحساب: الوكيل يسجّل الدخول ثم /me يُظهر النطاق الصحيح."""
    ca = portal_data["company_a"]
    ag1 = portal_data["agent1"]
    h = portal_data["h_gov"]

    # تزويد الحساب
    r = client.post(
        f"/api/companies/{ca.id}/agents/{ag1.id}/account",
        json={"username": "agentP1_portal", "role": "viewer"},
        headers=h,
    )
    assert r.status_code == 200, r.text
    creds = r.json()

    # تسجيل الدخول بالوكيل
    login_r = client.post("/api/auth/login", json={
        "username": creds["username"],
        "password": creds["password"],
    })
    assert login_r.status_code == 200, login_r.text
    tok = login_r.json()["token"]

    # /me يُرجع النطاق الصحيح
    me_r = client.get("/api/auth/me", headers={"Authorization": f"Bearer {tok}"})
    assert me_r.status_code == 200, me_r.text
    me = me_r.json()
    assert me["role"] == "viewer"
    assert me["company_id"] == ca.id
    assert me["agent"] == "agentP1"


# ═══════════════════════════════════════════════════════════════════
# 2) الوكيل بعد الدخول يرى مشتركيه فقط
# ═══════════════════════════════════════════════════════════════════

def test_agent_sees_only_own_subscribers_after_login(client, portal_data):
    """وكيل agentP1 يرى مشتركيه فقط — لا مشتركي agentP2."""
    ca = portal_data["company_a"]
    ag1 = portal_data["agent1"]
    h = portal_data["h_gov"]

    # تزويد الحساب
    r = client.post(
        f"/api/companies/{ca.id}/agents/{ag1.id}/account",
        json={"username": "agentP1_scoped"},
        headers=h,
    )
    assert r.status_code == 200
    creds = r.json()

    # تسجيل الدخول
    h_agent = _login(client, creds["username"], creds["password"])

    # قراءة المشتركين
    subs_r = client.get("/api/companies/subscribers", headers=h_agent)
    assert subs_r.status_code == 200, subs_r.text
    subs = subs_r.json()["subscribers"]

    # يجب ألا يرى أي مشترك خارج نطاقه
    for s in subs:
        assert s["company_id"] == ca.id, f"شركة خاطئة: {s['company_id']}"
        assert s["agent"] == "agentP1", f"وكيل خاطئ: {s['agent']}"

    # يجب أن يرى المشتركين الاثنين التابعين لـ agentP1
    assert len(subs) == 2


# ═══════════════════════════════════════════════════════════════════
# 3) منع التصعيد
# ═══════════════════════════════════════════════════════════════════

def test_role_admin_rejected_for_agent_account(client, portal_data):
    """محاولة منح role=admin لحساب وكيل → 400."""
    ca = portal_data["company_a"]
    ag1 = portal_data["agent1"]
    h = portal_data["h_gov"]

    r = client.post(
        f"/api/companies/{ca.id}/agents/{ag1.id}/account",
        json={"role": "admin"},
        headers=h,
    )
    assert r.status_code == 400, r.text


def test_scope_not_accepted_from_body(client, portal_data):
    """تمرير scope_company_id في الجسم لا يؤثّر — النطاق مفروض من المسار."""
    ca = portal_data["company_a"]
    cb = portal_data["company_b"]
    ag1 = portal_data["agent1"]
    h = portal_data["h_gov"]

    # تزويد الحساب مع محاولة تضمين scope_company_id للشركة الأخرى في الجسم
    r = client.post(
        f"/api/companies/{ca.id}/agents/{ag1.id}/account",
        json={
            "username": "agent_escalation_test",
            "scope_company_id": cb.id,    # يُتجاهل — ليس من الـ schema
        },
        headers=h,
    )
    assert r.status_code == 200, r.text
    body = r.json()
    # النطاق يجب أن يكون شركة A لا B
    assert body["scope_company_id"] == ca.id
    assert body["scope_company_id"] != cb.id


def test_agent_account_role_is_viewer_by_default(client, portal_data):
    """الدور الافتراضي لحساب الوكيل هو viewer."""
    ca = portal_data["company_a"]
    ag1 = portal_data["agent1"]
    h = portal_data["h_gov"]

    r = client.post(
        f"/api/companies/{ca.id}/agents/{ag1.id}/account",
        json={"username": "agent_default_role"},
        headers=h,
    )
    assert r.status_code == 200

    # تسجيل الدخول والتحقّق من الدور
    creds = r.json()
    me_r = client.get("/api/auth/me",
                      headers=_login(client, creds["username"], creds["password"]))
    assert me_r.json()["role"] == "viewer"


def test_operator_role_allowed_for_agent_account(client, portal_data):
    """يُسمح بـ role=operator لحساب وكيل."""
    ca = portal_data["company_a"]
    ag1 = portal_data["agent1"]
    h = portal_data["h_gov"]

    r = client.post(
        f"/api/companies/{ca.id}/agents/{ag1.id}/account",
        json={"username": "agent_operator_role", "role": "operator"},
        headers=h,
    )
    assert r.status_code == 200
    creds = r.json()
    me_r = client.get("/api/auth/me",
                      headers=_login(client, creds["username"], creds["password"]))
    assert me_r.json()["role"] == "operator"


# ═══════════════════════════════════════════════════════════════════
# 4) مدير شركة A يحاول تزويد وكيل في شركة B → 404
# ═══════════════════════════════════════════════════════════════════

def test_company_admin_cannot_provision_agent_in_other_company(client, portal_data):
    """مدير شركة A يحاول تزويد وكيل في شركة B → 404 (عزل النطاق)."""
    cb = portal_data["company_b"]
    ag2 = portal_data["agent2"]
    h_admin_a = portal_data["h_admin_a"]

    r = client.post(
        f"/api/companies/{cb.id}/agents/{ag2.id}/account",
        json={},
        headers=h_admin_a,
    )
    assert r.status_code == 404, r.text


def test_company_admin_can_provision_own_agent(client, portal_data):
    """مدير شركة A يستطيع تزويد وكيل في شركته."""
    ca = portal_data["company_a"]
    ag1 = portal_data["agent1"]
    h_admin_a = portal_data["h_admin_a"]

    r = client.post(
        f"/api/companies/{ca.id}/agents/{ag1.id}/account",
        json={"username": "agent_by_company_admin"},
        headers=h_admin_a,
    )
    assert r.status_code == 200, r.text
    assert r.json()["scope_company_id"] == ca.id


# ═══════════════════════════════════════════════════════════════════
# 5) /me للجهة الرقابية يُرجع company_id=null
# ═══════════════════════════════════════════════════════════════════

def test_gov_me_returns_null_company_id(client, portal_data):
    """/me للجهة الرقابية (admin بلا نطاق) يُرجع company_id=null وagent=null."""
    r = client.get("/api/auth/me", headers=portal_data["h_gov"])
    assert r.status_code == 200
    me = r.json()
    assert me["company_id"] is None
    assert me["agent"] is None


def test_deleting_company_removes_scoped_users(client, portal_data):
    """حذف الشركة يزيل حساباتها المرتبطة (مدير الشركة + وكلاؤها) — لا أيتام."""
    ca = portal_data["company_a"]
    ag1 = portal_data["agent1"]
    h = portal_data["h_gov"]

    # زوّد حساب وكيل في الشركة أ (يضاف إلى مدير الشركة المزروع portal_admin_a)
    r = client.post(f"/api/companies/{ca.id}/agents/{ag1.id}/account",
                    json={"username": "orphan_agent_test"}, headers=h)
    assert r.status_code == 200, r.text

    # قبل الحذف: حسابان على الأقل مرتبطان بالشركة
    with Session(engine) as db:
        before = db.exec(select(User).where(User.scope_company_id == ca.id)).all()
    assert len(before) >= 2

    # احذف الشركة
    d = client.delete(f"/api/companies/{ca.id}", headers=h)
    assert d.status_code == 200, d.text

    # بعد الحذف: لا حساب يتيم يشير للشركة المحذوفة
    with Session(engine) as db:
        after = db.exec(select(User).where(User.scope_company_id == ca.id)).all()
    assert after == []


# ═══════════════════════════════════════════════════════════════════
# 6) اختبارات إضافية للصحّة والحافات
# ═══════════════════════════════════════════════════════════════════

def test_duplicate_account_returns_409(client, portal_data):
    """محاولة إنشاء حساب بنفس اسم المستخدم مرّتين → 409."""
    ca = portal_data["company_a"]
    ag1 = portal_data["agent1"]
    h = portal_data["h_gov"]

    client.post(
        f"/api/companies/{ca.id}/agents/{ag1.id}/account",
        json={"username": "dup_agent"},
        headers=h,
    )
    r2 = client.post(
        f"/api/companies/{ca.id}/agents/{ag1.id}/account",
        json={"username": "dup_agent"},
        headers=h,
    )
    assert r2.status_code == 409, r2.text


def test_nonexistent_agent_returns_404(client, portal_data):
    """وكيل غير موجود → 404."""
    ca = portal_data["company_a"]
    h = portal_data["h_gov"]

    r = client.post(
        f"/api/companies/{ca.id}/agents/99999/account",
        json={},
        headers=h,
    )
    assert r.status_code == 404, r.text


def test_get_agent_account_no_account(client, portal_data):
    """GET /account للوكيل الذي لا حساب له → has_account=false."""
    ca = portal_data["company_a"]
    ag1 = portal_data["agent1"]
    h = portal_data["h_gov"]

    r = client.get(
        f"/api/companies/{ca.id}/agents/{ag1.id}/account",
        headers=h,
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["has_account"] is False
    assert body["username"] is None


def test_get_agent_account_after_provision(client, portal_data):
    """GET /account بعد التزويد → has_account=true + username."""
    ca = portal_data["company_a"]
    ag1 = portal_data["agent1"]
    h = portal_data["h_gov"]

    client.post(
        f"/api/companies/{ca.id}/agents/{ag1.id}/account",
        json={"username": "agentP1_check"},
        headers=h,
    )
    r = client.get(
        f"/api/companies/{ca.id}/agents/{ag1.id}/account",
        headers=h,
    )
    assert r.status_code == 200
    body = r.json()
    assert body["has_account"] is True
    assert body["username"] == "agentP1_check"


def test_password_not_in_me_or_login_response(client, portal_data):
    """كلمة المرور لا تظهر في /me ولا تُحفظ صريحاً."""
    ca = portal_data["company_a"]
    ag1 = portal_data["agent1"]
    h = portal_data["h_gov"]

    r = client.post(
        f"/api/companies/{ca.id}/agents/{ag1.id}/account",
        json={"username": "agent_pw_check"},
        headers=h,
    )
    creds = r.json()
    # password موجودة مرّة واحدة في استجابة التزويد
    assert "password" in creds
    assert "password_hash" not in creds

    # /me لا يُرجع كلمة مرور
    h_agent = _login(client, creds["username"], creds["password"])
    me = client.get("/api/auth/me", headers=h_agent).json()
    assert "password" not in me
    assert "password_hash" not in me


def test_viewer_cannot_use_admin_endpoints(client, portal_data):
    """حساب وكيل viewer لا يصل لمسارات admin."""
    ca = portal_data["company_a"]
    ag1 = portal_data["agent1"]
    h = portal_data["h_gov"]

    r = client.post(
        f"/api/companies/{ca.id}/agents/{ag1.id}/account",
        json={"username": "agent_viewer_perms"},
        headers=h,
    )
    creds = r.json()
    h_viewer = _login(client, creds["username"], creds["password"])

    # يجب أن يُرفض عند محاولة إنشاء مستخدم (admin فقط)
    r2 = client.post(
        f"/api/companies/{ca.id}/agents/{ag1.id}/account",
        json={"username": "escalation_attempt"},
        headers=h_viewer,
    )
    assert r2.status_code == 403, r2.text


def test_agent_account_agent_field_stripped(client, portal_data):
    """scope_agent يُخزَّن بلا مسافات زائدة."""
    ca = portal_data["company_a"]
    ag1 = portal_data["agent1"]
    h = portal_data["h_gov"]

    r = client.post(
        f"/api/companies/{ca.id}/agents/{ag1.id}/account",
        json={"username": "agent_strip_test"},
        headers=h,
    )
    assert r.status_code == 200
    body = r.json()
    assert body["scope_agent"] == body["scope_agent"].strip()


def test_agent_cross_company_wont_see_other_subscribers(client, portal_data):
    """وكيل agentP1 لا يستطيع رؤية مشتركي شركة B حتى لو مرّر company_id=B."""
    ca = portal_data["company_a"]
    cb = portal_data["company_b"]
    ag1 = portal_data["agent1"]
    h = portal_data["h_gov"]

    r = client.post(
        f"/api/companies/{ca.id}/agents/{ag1.id}/account",
        json={"username": "agent_cross_test"},
        headers=h,
    )
    creds = r.json()
    h_agent = _login(client, creds["username"], creds["password"])

    # محاولة رؤية مشتركي شركة B بتمرير company_id
    subs_r = client.get(
        f"/api/companies/subscribers?company_id={cb.id}",
        headers=h_agent,
    )
    assert subs_r.status_code == 200
    subs = subs_r.json()["subscribers"]
    # يجب ألا يرى أي مشترك من شركة B
    assert all(s["company_id"] == ca.id for s in subs)
