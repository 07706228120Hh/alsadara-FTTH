"""اختبارات المصادقة وإدارة المستخدمين والصلاحيات."""
import pytest
from sqlmodel import Session, select

from app.core import security
from app.database import engine
from app.main import _seed_default_admin
from app.models import Company, Agent, User


def test_password_hashing_roundtrip():
    h = security.hash_password("s3cret")
    assert h.startswith("pbkdf2_sha256$")
    assert security.verify_password("s3cret", h)
    assert not security.verify_password("wrong", h)


def test_user_token_roundtrip():
    t = security.make_user_token("bob", "operator")
    d = security.read_user_token(t, 3600)
    assert d == {"u": "bob", "r": "operator"}
    assert security.read_user_token("garbage", 3600) is None


def test_login_and_me(client):
    _seed_default_admin()
    r = client.post("/api/auth/login", json={"username": "admin", "password": "admin"})
    assert r.status_code == 200
    body = r.json()
    assert body["role"] == "admin"
    tok = body["token"]
    me = client.get("/api/auth/me", headers={"Authorization": f"Bearer {tok}"})
    assert me.status_code == 200 and me.json()["role"] == "admin"


def test_bad_login_rejected(client):
    _seed_default_admin()
    assert client.post("/api/auth/login",
                       json={"username": "admin", "password": "nope"}).status_code == 401


def test_role_enforcement(client):
    # في وضع المحاكاة بلا توكن = admin تطويري → يمكنه إنشاء مستخدم
    r = client.post("/api/users",
                    json={"username": "viewer1", "password": "pw", "role": "viewer"})
    assert r.status_code == 200

    tok = client.post("/api/auth/login",
                      json={"username": "viewer1", "password": "pw"}).json()["token"]
    h = {"Authorization": f"Bearer {tok}"}

    # viewer يقرأ
    assert client.get("/api/devices", headers=h).status_code == 200
    # viewer لا يدير المستخدمين (admin) → 403
    assert client.post("/api/users", json={"username": "x", "password": "y"},
                       headers=h).status_code == 403
    # viewer لا ينفّذ تهيئة (operator) → 403
    assert client.post("/api/config/1/apply",
                       json={"procedure": "save_config", "params": {}},
                       headers=h).status_code == 403


def test_operator_can_apply_but_not_manage_users(client):
    client.post("/api/users",
                json={"username": "op1", "password": "pw", "role": "operator"})
    tok = client.post("/api/auth/login",
                      json={"username": "op1", "password": "pw"}).json()["token"]
    h = {"Authorization": f"Bearer {tok}"}
    # operator ينفّذ تهيئة
    assert client.post("/api/config/1/apply",
                       json={"procedure": "save_config", "params": {}},
                       headers=h).status_code == 200
    # لكن لا يدير المستخدمين
    assert client.get("/api/users", headers=h).status_code == 403


def test_cannot_delete_last_admin(client):
    _seed_default_admin()
    users = client.get("/api/users").json()
    admin = next(u for u in users if u["role"] == "admin")
    r = client.delete(f"/api/users/{admin['id']}")
    assert r.status_code == 400  # آخر مدير محمي


# ═══════════════════════════════════════════════════════════════════
# إنشاء حسابات ذات نطاق (شركة/وكيل) من شاشة الوزارة /api/users
# ═══════════════════════════════════════════════════════════════════

_SCOPE_USERNAMES = (
    "cm_via_users", "ag_via_users", "ag_no_company", "ag_bad_agent",
    "ag_admin_role", "ag_dup_a", "ag_dup_b", "cm_bad_company", "reg_plain",
    "cm_weak_pw",
)


@pytest.fixture
def scoped_seed():
    """يبذر شركة + وكيل لاختبار إنشاء حسابات ذات نطاق، وينظّف بعده."""
    def _clean():
        with Session(engine) as db:
            for name in _SCOPE_USERNAMES:
                u = db.exec(select(User).where(User.username == name)).first()
                if u:
                    db.delete(u)
            for a in db.exec(select(Agent).where(Agent.manager_id >= 88000)).all():
                db.delete(a)
            c = db.exec(select(Company).where(Company.code == "SU")).first()
            if c:
                for a in db.exec(select(Agent).where(Agent.company_id == c.id)).all():
                    db.delete(a)
                db.delete(c)
            db.commit()

    _clean()
    with Session(engine) as db:
        c = Company(name="شركة-إنشاء-مستخدم", code="SU", governorate="بغداد")
        db.add(c)
        db.commit()
        db.refresh(c)
        a = Agent(company_id=c.id, manager_id=88001, username="agentSU",
                  firstname="agentSU", lastname="t")
        db.add(a)
        db.commit()
        cid = c.id
    yield {"cid": cid, "agent": "agentSU"}
    _clean()


def test_create_company_manager_via_users(client, scoped_seed):
    """جهة رقابية تُنشئ مدير شركة (scope_company_id فقط) من /api/users."""
    cid = scoped_seed["cid"]
    r = client.post("/api/users", json={
        "username": "cm_via_users", "password": "pw123456",
        "role": "admin", "scope_company_id": cid,
    })
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["scope_company_id"] == cid
    assert body["scope_agent"] == ""

    # يسجّل الدخول و/me يُظهر شركته بلا وكيل
    tok = client.post("/api/auth/login",
                      json={"username": "cm_via_users", "password": "pw123456"}).json()["token"]
    me = client.get("/api/auth/me", headers={"Authorization": f"Bearer {tok}"}).json()
    assert me["company_id"] == cid and me["agent"] is None


def test_create_agent_via_users(client, scoped_seed):
    """جهة رقابية تُنشئ وكيلاً (شركة + وكيل) من /api/users."""
    cid = scoped_seed["cid"]
    r = client.post("/api/users", json={
        "username": "ag_via_users", "password": "pw123456",
        "role": "operator", "scope_company_id": cid, "scope_agent": "agentSU",
    })
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["scope_company_id"] == cid and body["scope_agent"] == "agentSU"

    tok = client.post("/api/auth/login",
                      json={"username": "ag_via_users", "password": "pw123456"}).json()["token"]
    me = client.get("/api/auth/me", headers={"Authorization": f"Bearer {tok}"}).json()
    assert me["company_id"] == cid and me["agent"] == "agentSU"


def test_agent_scope_without_company_rejected(client, scoped_seed):
    """scope_agent بلا شركة → 400."""
    r = client.post("/api/users", json={
        "username": "ag_no_company", "password": "pw123456",
        "role": "operator", "scope_agent": "agentSU",
    })
    assert r.status_code == 400, r.text


def test_agent_scope_nonexistent_agent_404(client, scoped_seed):
    """وكيل غير موجود في الشركة → 404."""
    r = client.post("/api/users", json={
        "username": "ag_bad_agent", "password": "pw123456",
        "role": "operator", "scope_company_id": scoped_seed["cid"],
        "scope_agent": "ghost_agent",
    })
    assert r.status_code == 404, r.text


def test_agent_scope_admin_role_rejected(client, scoped_seed):
    """دور admin ممنوع لحساب وكيل → 400."""
    r = client.post("/api/users", json={
        "username": "ag_admin_role", "password": "pw123456",
        "role": "admin", "scope_company_id": scoped_seed["cid"],
        "scope_agent": "agentSU",
    })
    assert r.status_code == 400, r.text


def test_duplicate_agent_scope_returns_409(client, scoped_seed):
    """حسابان لنفس (شركة، وكيل) → الثاني 409 حتى باسم مختلف."""
    cid = scoped_seed["cid"]
    base = {"password": "pw123456", "role": "operator",
            "scope_company_id": cid, "scope_agent": "agentSU"}
    r1 = client.post("/api/users", json={**base, "username": "ag_dup_a"})
    assert r1.status_code == 200, r1.text
    r2 = client.post("/api/users", json={**base, "username": "ag_dup_b"})
    assert r2.status_code == 409, r2.text


def test_company_scope_nonexistent_company_404(client, scoped_seed):
    """شركة غير موجودة → 404."""
    r = client.post("/api/users", json={
        "username": "cm_bad_company", "password": "pw123456",
        "role": "admin", "scope_company_id": 999999,
    })
    assert r.status_code == 404, r.text


def test_regulator_creation_has_no_scope(client, scoped_seed):
    """بلا نطاق → جهة رقابية (scope_company_id=None)."""
    r = client.post("/api/users", json={
        "username": "reg_plain", "password": "pw123456", "role": "operator",
    })
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["scope_company_id"] is None and body["scope_agent"] == ""


def test_scoped_account_weak_password_rejected(client, scoped_seed):
    """حساب ذو نطاق بكلمة مرور < 8 محارف → 400 (اتساقاً مع تزويد الوكيل)."""
    r = client.post("/api/users", json={
        "username": "cm_weak_pw", "password": "short7x",  # 7 محارف
        "role": "admin", "scope_company_id": scoped_seed["cid"],
    })
    assert r.status_code == 400, r.text


# ═══════════════════════════════════════════════════════════════════
# تعديل نطاق حساب موجود عبر PATCH /api/users/{id}
# ═══════════════════════════════════════════════════════════════════

_EDIT_USERNAMES = ("edit_reg", "edit_cm", "edit_ag", "edit_ag2", "edit_lock_admin")


def _mk_plain_user(username: str, role: str = "operator") -> int:
    """ينشئ مستخدماً رقابياً عبر الـ API ويعيد id."""
    from app.main import app as _app  # noqa
    # نُنشئه مباشرةً في القاعدة لتفادي تبعيات ترتيب الاختبارات
    with Session(engine) as db:
        u = User(username=username, role=role,
                 password_hash=security.hash_password("pw123456"))
        db.add(u)
        db.commit()
        db.refresh(u)
        return u.id


@pytest.fixture
def edit_seed(scoped_seed):
    """يعيد بيانات شركة/وكيل + ينظّف مستخدمي اختبار التعديل."""
    def _clean():
        with Session(engine) as db:
            for name in _EDIT_USERNAMES:
                u = db.exec(select(User).where(User.username == name)).first()
                if u:
                    db.delete(u)
            db.commit()
    _clean()
    yield scoped_seed
    _clean()


def test_edit_regulator_to_company_manager(client, edit_seed):
    """تحويل حساب رقابي إلى مدير شركة عبر PATCH."""
    cid = edit_seed["cid"]
    uid = _mk_plain_user("edit_reg")
    r = client.patch(f"/api/users/{uid}", json={"scope_company_id": cid})
    assert r.status_code == 200, r.text
    assert r.json()["scope_company_id"] == cid
    assert r.json()["scope_agent"] == ""


def test_edit_to_agent_scope(client, edit_seed):
    """تعيين نطاق وكيل لحساب موجود."""
    cid = edit_seed["cid"]
    uid = _mk_plain_user("edit_ag")
    r = client.patch(f"/api/users/{uid}",
                     json={"scope_company_id": cid, "scope_agent": "agentSU"})
    assert r.status_code == 200, r.text
    assert r.json()["scope_company_id"] == cid and r.json()["scope_agent"] == "agentSU"


def test_edit_scope_back_to_regulator(client, edit_seed):
    """إزالة النطاق (null) تُعيد الحساب جهةً رقابية."""
    cid = edit_seed["cid"]
    uid = _mk_plain_user("edit_cm")
    client.patch(f"/api/users/{uid}", json={"scope_company_id": cid})
    r = client.patch(f"/api/users/{uid}",
                     json={"scope_company_id": None, "scope_agent": ""})
    assert r.status_code == 200, r.text
    assert r.json()["scope_company_id"] is None and r.json()["scope_agent"] == ""


def test_edit_agent_scope_nonexistent_agent_404(client, edit_seed):
    """تعديل النطاق إلى وكيل غير موجود → 404."""
    cid = edit_seed["cid"]
    uid = _mk_plain_user("edit_ag2")
    r = client.patch(f"/api/users/{uid}",
                     json={"scope_company_id": cid, "scope_agent": "ghost"})
    assert r.status_code == 404, r.text


def test_edit_duplicate_agent_scope_409(client, edit_seed):
    """تعيين نطاق وكيل مستخدَم مسبقاً لحساب آخر → 409."""
    cid = edit_seed["cid"]
    u1 = _mk_plain_user("edit_ag")
    u2 = _mk_plain_user("edit_ag2")
    assert client.patch(f"/api/users/{u1}",
                        json={"scope_company_id": cid, "scope_agent": "agentSU"}).status_code == 200
    r = client.patch(f"/api/users/{u2}",
                     json={"scope_company_id": cid, "scope_agent": "agentSU"})
    assert r.status_code == 409, r.text


def test_edit_cannot_scope_last_regulator_admin(client, edit_seed):
    """تقييد آخر مدير رقابي بنطاق → 400 (يمنع قفل الإدارة)."""
    cid = edit_seed["cid"]
    _seed_default_admin()
    # admin الافتراضي هو المدير الرقابي الوحيد المفعّل
    users = client.get("/api/users").json()
    admin = next(u for u in users if u["username"] == "admin")
    r = client.patch(f"/api/users/{admin['id']}", json={"scope_company_id": cid})
    assert r.status_code == 400, r.text


def test_cannot_downgrade_last_regulator_admin_with_scoped_admin(client, edit_seed):
    """تنزيل دور آخر مدير رقابي مرفوض حتى مع وجود admin مقيّد بشركة (الثغرة 🟠)."""
    cid = edit_seed["cid"]
    _seed_default_admin()
    # admin مقيّد بشركة (ليس رقابياً — لا يُحتسب حارساً)
    client.post("/api/users", json={
        "username": "edit_lock_admin", "password": "pw123456",
        "role": "admin", "scope_company_id": cid,
    })
    users = client.get("/api/users").json()
    admin = next(u for u in users if u["username"] == "admin")
    # تنزيل الدور → 400
    r = client.patch(f"/api/users/{admin['id']}", json={"role": "operator"})
    assert r.status_code == 400, r.text
    # التعطيل → 400 أيضاً
    r2 = client.patch(f"/api/users/{admin['id']}", json={"enabled": False})
    assert r2.status_code == 400, r2.text


def test_edit_username(client, edit_seed):
    """تغيير اسم المستخدم عبر PATCH + رفض الاسم المكرّر."""
    uid = _mk_plain_user("edit_cm")
    r = client.patch(f"/api/users/{uid}", json={"username": "edit_ag"})
    assert r.status_code == 200, r.text
    assert r.json()["username"] == "edit_ag"
    # الاسم فارغ → 400
    assert client.patch(f"/api/users/{uid}", json={"username": "  "}).status_code == 400
    # اسم مكرّر (admin موجود) → 400
    _seed_default_admin()
    assert client.patch(f"/api/users/{uid}", json={"username": "admin"}).status_code == 400


def test_edit_role_only_unchanged_scope(client, edit_seed):
    """تعديل الدور وحده لا يمسّ النطاق (fields_set لا يشمل scope)."""
    cid = edit_seed["cid"]
    uid = _mk_plain_user("edit_cm", role="operator")
    client.patch(f"/api/users/{uid}", json={"scope_company_id": cid})
    r = client.patch(f"/api/users/{uid}", json={"role": "viewer"})
    assert r.status_code == 200, r.text
    assert r.json()["role"] == "viewer"
    assert r.json()["scope_company_id"] == cid  # النطاق سليم لم يُمسّ
