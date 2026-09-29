"""
بذرة بيانات تجريبية لتطبيق الوكلاء — تُشغَّل مرّة واحدة (idempotent).

تُنشئ (إن لم تكن موجودة):
  • شركة تجريبية.
  • وكيلاً (Agent) تابعاً لها.
  • حساب دخول للوكيل: المستخدم «wakil» وكلمة المرور «wakil123»
    (نطاقه: هذه الشركة + هذا الوكيل، فيرى بياناته فقط).
  • مجموعة مشتركين موزَّعين على الحالات (نشط/منتهٍ، بعضهم متصل).
  • تصريحاً شهرياً (AgentReport) واحداً.

التشغيل:  python seed_agent_demo.py
تُستدعى تلقائياً من app.main عند SEED_DEMO_DATA=true (أول تشغيل فقط).
"""
from __future__ import annotations

from sqlmodel import Session, select

from app.database import engine, init_db
from app.core.security import hash_password
from app.models import Agent, AgentReport, Company, Subscriber, User

AGENT_USERNAME = "wakil"
AGENT_PASSWORD = "wakil123"
COMPANY_NAME = "شركة النور للإنترنت"

# مشتركون تجريبيون: (اسم المستخدم، الاسم، الحالة، متصل؟، الملف، المحافظة)
_SUBS = [
    ("noor001", "علي حسن", "active", True, "20Mbps", "بغداد"),
    ("noor002", "زينب كريم", "active", True, "50Mbps", "بغداد"),
    ("noor003", "محمد جواد", "active", False, "20Mbps", "بغداد"),
    ("noor004", "فاطمة عبد", "active", True, "100Mbps", "البصرة"),
    ("noor005", "حسين علي", "active", False, "20Mbps", "البصرة"),
    ("noor006", "رقية سعد", "active", True, "50Mbps", "النجف"),
    ("noor007", "كرار ناصر", "active", True, "20Mbps", "النجف"),
    ("noor008", "مريم فاضل", "active", False, "50Mbps", "كربلاء"),
    ("noor009", "أحمد وليد", "active", True, "100Mbps", "بغداد"),
    ("noor010", "سجى منير", "active", True, "20Mbps", "بغداد"),
    ("noor011", "عمر خالد", "active", False, "50Mbps", "أربيل"),
    ("noor012", "هدى صباح", "active", True, "20Mbps", "أربيل"),
    ("noor013", "ياسر جبار", "expired", False, "20Mbps", "بغداد"),
    ("noor014", "نور الهدى", "expired", False, "50Mbps", "البصرة"),
    ("noor015", "سيف الدين", "expired", False, "20Mbps", "النجف"),
    ("noor016", "دعاء رعد", "expired", False, "100Mbps", "بغداد"),
    ("noor017", "مصطفى قاسم", "active", True, "20Mbps", "بغداد"),
    ("noor018", "بتول حيدر", "active", True, "50Mbps", "كربلاء"),
    ("noor019", "ليث عادل", "active", False, "20Mbps", "بغداد"),
    ("noor020", "شهد ماجد", "expired", False, "20Mbps", "الديوانية"),
]


def _norm_gov(city: str) -> str:
    return city.strip()


def seed() -> None:
    init_db()
    with Session(engine) as db:
        # موجودة مسبقاً؟ لا نكرّر.
        if db.exec(select(User).where(User.username == AGENT_USERNAME)).first():
            print(f"[seed] الحساب «{AGENT_USERNAME}» موجود — تخطّي البذرة.")
            return

        # 1) شركة
        company = db.exec(select(Company).where(Company.name == COMPANY_NAME)).first()
        if not company:
            company = Company(
                name=COMPANY_NAME, code="NOOR", governorate="بغداد",
                color="#22D3EE", enabled=True, kind="primary", access_type="ftth",
            )
            db.add(company)
            db.commit()
            db.refresh(company)

        # 2) وكيل (Agent)
        active_count = sum(1 for s in _SUBS if s[2] == "active")
        agent = Agent(
            company_id=company.id, manager_id=1001, username=AGENT_USERNAME,
            firstname="وكيل", lastname="النور", parent_username="",
            users_count=len(_SUBS), balance=1_250_000.0, reward_points=340.0,
            discount_rate=0.05, enabled=True,
        )
        db.add(agent)

        # 3) حساب دخول الوكيل (مقيّد بنطاق الشركة + الوكيل)
        db.add(User(
            username=AGENT_USERNAME,
            password_hash=hash_password(AGENT_PASSWORD),
            role="operator",
            scope_company_id=company.id,
            scope_agent=AGENT_USERNAME,
            enabled=True,
        ))

        # 4) مشتركون
        for i, (uname, name, status, online, profile, city) in enumerate(_SUBS, start=1):
            first, _, last = name.partition(" ")
            db.add(Subscriber(
                company_id=company.id, sub_id=2000 + i, username=uname,
                firstname=first, lastname=last, agent_username=AGENT_USERNAME,
                profile_name=profile, status=status, online=online, enabled=(status == "active"),
                city=city, governorate=_norm_gov(city),
                phone=f"078{i:08d}", phone_norm=f"96478{i:08d}",
            ))

        # 5) تصريح شهري
        db.add(AgentReport(
            company_id=company.id, agent_username=AGENT_USERNAME,
            declared_total=len(_SUBS), declared_active=active_count,
            note="تصريح تجريبي أوّلي", submitted_by=AGENT_USERNAME,
        ))

        db.commit()
        print(f"[seed] تمّت البذرة: شركة «{COMPANY_NAME}» + وكيل «{AGENT_USERNAME}» "
              f"+ {len(_SUBS)} مشترك.")
        print(f"[seed] الدخول للتطبيق:  المستخدم = {AGENT_USERNAME}   كلمة المرور = {AGENT_PASSWORD}")


if __name__ == "__main__":
    seed()
