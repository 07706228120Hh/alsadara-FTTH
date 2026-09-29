"""
اختبارات تطبيق المشتركين (OTP واتساب) وسلسلة التذاكر (مشترك → وكيل → شركة → وزارة).

تُغطّي:
1. تطبيع أرقام الهاتف العراقية بكل الصيغ.
2. طلب OTP لرقم مسجّل → رمز (dev_code في وضع الاختبار)؛ رقم غير مسجّل → استجابة موحّدة بلا رمز.
3. تحقّق خاطئ → 401؛ استنفاد المحاولات يُبطل الرمز؛ حدّ الإرسال → 429.
4. توكن المشترك: /subscriber/me يُظهر حساباته (لدى شركتين)، ومرفوض في مسارات الموظّفين (403).
5. توكن الموظّف مرفوض في /subscriber/* (403).
6. المشترك يفتح تذكرة → الوكيل يراها ويردّ (تصبح in_progress) → الشركة تُصعّدها →
   الوزارة تراها ضمن الكل؛ وكيل آخر لا يراها (404)؛ شركة أخرى لا تراها.
7. الردود الداخلية مخفيّة عن المشترك؛ الوكيل لا يستطيع التصعيد (403).
"""
from __future__ import annotations

import pytest
from sqlmodel import Session, select

from app.database import engine
from app.models import Company, Agent, Subscriber, User, OtpCode, Ticket, TicketReply
from app.core import security as sec_module
from app.services import otp as otp_svc
from app.main import _seed_default_admin

PHONE_A = "07701234567"          # مشترك لديه حسابان (شركتان)
PHONE_A_NORM = "9647701234567"
PHONE_B = "07809876543"          # مشترك لدى الوكيل الآخر
PHONE_NONE = "07500000000"       # غير مسجّل


# ─────────────────────────── مساعدات ───────────────────────────

def _mk_company(db, name, code):
    c = Company(name=name, code=code, governorate="بغداد")
    db.add(c); db.commit(); db.refresh(c)
    return c


_SEQ = iter(range(80001, 89999))


def _mk_agent(db, cid, username):
    a = Agent(company_id=cid, manager_id=next(_SEQ), username=username,
              firstname=username, lastname="agent")
    db.add(a); db.commit(); db.refresh(a)
    return a


def _mk_sub(db, cid, agent, username, phone, sub_id):
    s = Subscriber(company_id=cid, sub_id=sub_id, username=username, firstname="مشترك",
                   lastname=username, agent_username=agent, phone=phone,
                   phone_norm=otp_svc.normalize_phone(phone), status="active")
    db.add(s); db.commit(); db.refresh(s)
    return s


def _mk_user(db, username, role, cid=None, agent=""):
    u = User(username=username, password_hash=sec_module.hash_password("pw_tk"),
             role=role, scope_company_id=cid, scope_agent=agent)
    db.add(u); db.commit(); db.refresh(u)
    return u


def _login(client, username, password="pw_tk"):
    r = client.post("/api/auth/login", json={"username": username, "password": password})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def _sub_login(client, phone):
    r = client.post("/api/subscriber/otp/request", json={"phone": phone})
    assert r.status_code == 200, r.text
    code = r.json()["dev_code"]
    r = client.post("/api/subscriber/otp/verify", json={"phone": phone, "code": code})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


@pytest.fixture(autouse=True)
def _clean():
    def clean():
        with Session(engine) as db:
            for r in db.exec(select(TicketReply)).all():
                db.delete(r)
            for t in db.exec(select(Ticket)).all():
                db.delete(t)
            for o in db.exec(select(OtpCode)).all():
                db.delete(o)
            for s in db.exec(select(Subscriber).where(Subscriber.sub_id >= 7000,
                                                      Subscriber.sub_id < 7100)).all():
                db.delete(s)
            for a in db.exec(select(Agent).where(Agent.manager_id >= 80000,
                                                 Agent.manager_id < 90000)).all():
                db.delete(a)
            for name in ("tk_ag1", "tk_ag2", "tk_co1", "tk_co2", "tk_reg"):
                u = db.exec(select(User).where(User.username == name)).first()
                if u:
                    db.delete(u)
            for code in ("TK1", "TK2"):
                c = db.exec(select(Company).where(Company.code == code)).first()
                if c:
                    db.delete(c)
            db.commit()
        _seed_default_admin()
    clean()
    yield
    clean()


@pytest.fixture
def data(client):
    with Session(engine) as db:
        c1 = _mk_company(db, "شركة تذاكر 1", "TK1")
        c2 = _mk_company(db, "شركة تذاكر 2", "TK2")
        _mk_agent(db, c1.id, "ag1")
        _mk_agent(db, c1.id, "ag2")
        _mk_agent(db, c2.id, "ag3")
        # صيغ هاتف مختلفة كما تكتبها الشركات في SAS
        s1 = _mk_sub(db, c1.id, "ag1", "subA_c1", "+964 770 123 4567", 7001)
        s2 = _mk_sub(db, c2.id, "ag3", "subA_c2", "07701234567", 7002)
        s3 = _mk_sub(db, c1.id, "ag2", "subB_c1", "9647809876543", 7003)
        _mk_user(db, "tk_ag1", "operator", c1.id, "ag1")
        _mk_user(db, "tk_ag2", "operator", c1.id, "ag2")
        _mk_user(db, "tk_co1", "admin", c1.id)
        _mk_user(db, "tk_co2", "admin", c2.id)
        _mk_user(db, "tk_reg", "admin")
        return {"c1": c1.id, "c2": c2.id, "s1": s1.id, "s2": s2.id, "s3": s3.id}


# ─────────────────────────── 1. التطبيع ───────────────────────────

@pytest.mark.parametrize("raw", [
    "07701234567", "7701234567", "+9647701234567", "009647701234567",
    "964 770 123 4567", "٠٧٧٠١٢٣٤٥٦٧", "+964 (770) 123-4567",
])
def test_normalize_phone_variants(raw):
    assert otp_svc.normalize_phone(raw) == PHONE_A_NORM


@pytest.mark.parametrize("raw", ["", "123", "0170123456", "+1 555 123 4567", "0770123456"])
def test_normalize_phone_rejects_invalid(raw):
    assert otp_svc.normalize_phone(raw) == ""


# ─────────────────────────── 2-3. OTP ───────────────────────────

def test_otp_request_registered_phone_issues_code(client, data):
    r = client.post("/api/subscriber/otp/request", json={"phone": PHONE_A})
    assert r.status_code == 200
    j = r.json()
    assert j["sent"] is True and j["masked"] == "****4567"
    assert len(j["dev_code"]) == 6 and j["dev_code"].isdigit()
    assert j["delivered"] is False   # لا بوابة واتساب في الاختبارات


def test_otp_request_unknown_phone_uniform_response(client, data):
    r = client.post("/api/subscriber/otp/request", json={"phone": PHONE_NONE})
    assert r.status_code == 200
    assert r.json()["sent"] is True and "dev_code" not in r.json()
    with Session(engine) as db:
        assert db.exec(select(OtpCode).where(OtpCode.phone == "9647500000000")).first() is None


def test_otp_request_invalid_phone_400(client, data):
    assert client.post("/api/subscriber/otp/request", json={"phone": "12345678"}).status_code == 400


def test_otp_verify_wrong_then_right(client, data):
    code = client.post("/api/subscriber/otp/request", json={"phone": PHONE_A}).json()["dev_code"]
    wrong = "000000" if code != "000000" else "111111"
    r = client.post("/api/subscriber/otp/verify", json={"phone": PHONE_A, "code": wrong})
    assert r.status_code == 401
    r = client.post("/api/subscriber/otp/verify", json={"phone": PHONE_A, "code": code})
    assert r.status_code == 200
    assert r.json()["role"] == "subscriber" and r.json()["accounts"] == 2
    # الرمز مستهلَك — لا يُعاد استخدامه
    r = client.post("/api/subscriber/otp/verify", json={"phone": PHONE_A, "code": code})
    assert r.status_code == 401


def test_otp_max_attempts_burns_code(client, data):
    code = client.post("/api/subscriber/otp/request", json={"phone": PHONE_A}).json()["dev_code"]
    wrong = "000000" if code != "000000" else "111111"
    for _ in range(5):
        client.post("/api/subscriber/otp/verify", json={"phone": PHONE_A, "code": wrong})
    r = client.post("/api/subscriber/otp/verify", json={"phone": PHONE_A, "code": code})
    assert r.status_code == 401


def test_otp_rate_limit(client, data):
    for _ in range(3):
        assert client.post("/api/subscriber/otp/request", json={"phone": PHONE_A}).status_code == 200
    assert client.post("/api/subscriber/otp/request", json={"phone": PHONE_A}).status_code == 429


# ─────────────────────────── 4-5. الفصل بين التطبيقين ───────────────────────────

def test_subscriber_me_lists_accounts_across_companies(client, data):
    h = _sub_login(client, PHONE_A)
    r = client.get("/api/subscriber/me", headers=h)
    assert r.status_code == 200
    j = r.json()
    assert j["phone"] == PHONE_A_NORM
    assert sorted(a["username"] for a in j["accounts"]) == ["subA_c1", "subA_c2"]
    acc = next(a for a in j["accounts"] if a["username"] == "subA_c1")
    assert acc["company"] == "شركة تذاكر 1" and acc["agent"] == "ag1" and acc["agent_name"] == "ag1 agent"


def test_subscriber_token_rejected_on_staff_routes(client, data):
    h = _sub_login(client, PHONE_A)
    assert client.get("/api/companies/subscribers", headers=h).status_code == 403
    assert client.get("/api/companies", headers=h).status_code == 403
    assert client.get("/api/tickets", headers=h).status_code == 403
    assert client.get("/api/devices", headers=h).status_code == 403
    assert client.get("/api/auth/me", headers=h).status_code == 403


def test_staff_token_rejected_on_subscriber_routes(client, data):
    h = _login(client, "tk_reg")
    assert client.get("/api/subscriber/me", headers=h).status_code == 403
    assert client.get("/api/subscriber/tickets", headers=h).status_code == 403


def test_auth_me_reports_kind(client, data):
    assert client.get("/api/auth/me", headers=_login(client, "tk_reg")).json()["kind"] == "regulator"
    assert client.get("/api/auth/me", headers=_login(client, "tk_co1")).json()["kind"] == "company"
    assert client.get("/api/auth/me", headers=_login(client, "tk_ag1")).json()["kind"] == "agent"


# ─────────────────────────── 6-7. سلسلة التذاكر ───────────────────────────

def _open_ticket(client, h, account_username, subject="لا يوجد إنترنت"):
    me = client.get("/api/subscriber/me", headers=h).json()
    acc = next(a for a in me["accounts"] if a["username"] == account_username)
    r = client.post("/api/subscriber/tickets", headers=h,
                    json={"account_id": acc["id"], "category": "outage",
                          "subject": subject, "body": "الخدمة مقطوعة منذ الصباح"})
    assert r.status_code == 201, r.text
    return r.json()


def test_ticket_chain_subscriber_agent_company_regulator(client, data):
    hs = _sub_login(client, PHONE_A)
    t = _open_ticket(client, hs, "subA_c1")
    assert t["status"] == "open" and t["agent"] == "ag1" and t["company_id"] == data["c1"]

    # الوكيل ag1 يراها؛ ag2 لا يراها
    h_ag1 = _login(client, "tk_ag1")
    lst = client.get("/api/tickets", headers=h_ag1).json()
    assert [x["id"] for x in lst["tickets"]] == [t["id"]]
    h_ag2 = _login(client, "tk_ag2")
    assert client.get("/api/tickets", headers=h_ag2).json()["total"] == 0
    assert client.get(f"/api/tickets/{t['id']}", headers=h_ag2).status_code == 404

    # الوكيل يردّ → in_progress، ويضيف ملاحظة داخلية
    r = client.post(f"/api/tickets/{t['id']}/reply", headers=h_ag1, json={"body": "جارٍ الفحص"})
    assert r.status_code == 201 and r.json()["status"] == "in_progress"
    client.post(f"/api/tickets/{t['id']}/reply", headers=h_ag1,
                json={"body": "ملاحظة داخلية", "internal": True})

    # الوكيل لا يُصعّد
    assert client.patch(f"/api/tickets/{t['id']}", headers=h_ag1,
                        json={"escalated": True}).status_code == 403

    # الشركة c1 تراها وتُصعّدها؛ c2 لا تراها
    h_co1 = _login(client, "tk_co1")
    r = client.patch(f"/api/tickets/{t['id']}", headers=h_co1, json={"escalated": True, "priority": "high"})
    assert r.status_code == 200 and r.json()["escalated"] is True
    h_co2 = _login(client, "tk_co2")
    assert client.get(f"/api/tickets/{t['id']}", headers=h_co2).status_code == 404

    # الوزارة ترى الكل + الإحصاءات + تصفية المُصعَّدة
    h_reg = _login(client, "tk_reg")
    st = client.get("/api/tickets/stats", headers=h_reg).json()
    assert st["total"] == 1 and st["escalated"] == 1 and st["by_status"]["in_progress"] == 1
    esc = client.get("/api/tickets?escalated=true", headers=h_reg).json()
    assert esc["total"] == 1
    full = client.get(f"/api/tickets/{t['id']}", headers=h_reg).json()
    assert len(full["replies"]) == 2   # الوزارة ترى الداخلية أيضاً

    # المشترك يرى الردّ العام فقط (الداخلية مخفيّة)
    mine = client.get(f"/api/subscriber/tickets/{t['id']}", headers=hs).json()
    assert [r_["body"] for r_ in mine["replies"]] == ["جارٍ الفحص"]

    # الحلّ ثم ردّ المشترك يعيد الفتح
    client.patch(f"/api/tickets/{t['id']}", headers=h_reg, json={"status": "resolved"})
    r = client.post(f"/api/subscriber/tickets/{t['id']}/reply", headers=hs, json={"body": "لم تُحلّ"})
    assert r.status_code == 201 and r.json()["status"] == "open"


def test_subscriber_cannot_open_ticket_on_foreign_account(client, data):
    hs = _sub_login(client, PHONE_A)
    r = client.post("/api/subscriber/tickets", headers=hs,
                    json={"account_id": data["s3"], "subject": "تجربة"})
    assert r.status_code == 404


def test_subscriber_sees_only_own_tickets(client, data):
    ha = _sub_login(client, PHONE_A)
    hb = _sub_login(client, PHONE_B)
    _open_ticket(client, ha, "subA_c1")
    _open_ticket(client, hb, "subB_c1", subject="بطء")
    assert client.get("/api/subscriber/tickets", headers=ha).json()["count"] == 1
    assert client.get("/api/subscriber/tickets", headers=hb).json()["count"] == 1


def test_staff_creates_ticket_on_behalf_within_scope(client, data):
    h_ag1 = _login(client, "tk_ag1")
    r = client.post("/api/tickets", headers=h_ag1,
                    json={"subscriber_id": data["s1"], "subject": "اتصال هاتفي", "category": "billing"})
    assert r.status_code == 201 and r.json()["created_by_kind"] == "agent"
    assert r.json()["subscriber_phone"] == PHONE_A_NORM
    # مشترك خارج نطاق الوكيل → 404
    r = client.post("/api/tickets", headers=h_ag1,
                    json={"subscriber_id": data["s3"], "subject": "اتصال هاتفي"})
    assert r.status_code == 404
    # المشترك يرى التذكرة التي فُتحت باسمه
    hs = _sub_login(client, PHONE_A)
    assert client.get("/api/subscriber/tickets", headers=hs).json()["count"] == 1


# ─────────────────────────── /api/portal/summary ───────────────────────────

def test_portal_summary_per_kind(client, data):
    hs = _sub_login(client, PHONE_A)
    _open_ticket(client, hs, "subA_c1")

    ag = client.get("/api/portal/summary", headers=_login(client, "tk_ag1")).json()
    assert ag["kind"] == "agent" and ag["agent"]["username"] == "ag1"
    assert ag["subscribers"]["total"] == 1 and ag["tickets"]["open_total"] == 1
    assert ag["company"]["name"] == "شركة تذاكر 1" and ag["last_report"] is None

    co = client.get("/api/portal/summary", headers=_login(client, "tk_co1")).json()
    assert co["kind"] == "company" and co["agents_count"] == 2
    assert co["subscribers"]["total"] == 2 and co["tickets"]["total"] == 1

    reg = client.get("/api/portal/summary", headers=_login(client, "tk_reg")).json()
    assert reg["kind"] == "regulator" and reg["companies_count"] >= 2
    assert reg["subscribers"]["total"] >= 3 and reg["tickets"]["total"] == 1

    # توكن المشترك مرفوض
    assert client.get("/api/portal/summary", headers=hs).status_code == 403


# ═══════════════════════════════════════════════════════════════════
# إضافة مشترك (مواطن) يدوياً من لوحة الوزارة (هاتف + اسم)
# ═══════════════════════════════════════════════════════════════════

def test_create_manual_subscriber(client):
    """POST /api/companies/subscribers: مواطن بلا شركة يدخل عبر OTP."""
    phone = "07711112222"
    norm = "9647711112222"

    def _clean():
        with Session(engine) as db:
            for s in db.exec(select(Subscriber).where(
                    Subscriber.phone_norm == norm)).all():
                db.delete(s)
            db.commit()

    _clean()
    # إنشاء
    r = client.post("/api/companies/subscribers",
                    json={"phone": phone, "name": "مواطن تجريبي"})
    assert r.status_code == 200, r.text
    assert r.json()["phone_norm"] == norm

    # أُنشئ بلا شركة وبحالة يدوية
    with Session(engine) as db:
        s = db.exec(select(Subscriber).where(Subscriber.phone_norm == norm)).first()
        assert s is not None and s.company_id is None and s.status == "manual"

    # تكرار نفس الهاتف → 409
    assert client.post("/api/companies/subscribers",
                       json={"phone": phone}).status_code == 409
    # هاتف غير صالح → 400
    assert client.post("/api/companies/subscribers",
                       json={"phone": "123"}).status_code == 400

    # المشترك اليدوي مسجَّل ⇒ طلب OTP يعيد رمزاً (dev_code)
    otp_r = client.post("/api/subscriber/otp/request", json={"phone": phone})
    assert otp_r.status_code == 200 and "dev_code" in otp_r.json()

    _clean()
