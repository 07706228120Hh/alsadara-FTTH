"""
تطبيق إدارة Huawei OLT — نقطة الدخول (FastAPI).
شغّل: uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
"""
import asyncio
from contextlib import asynccontextmanager
from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlmodel import Session, select
from .config import settings
from .database import init_db, engine
from .models import OLTDevice, User
from .core.security import encrypt, hash_password
from .core.auth import require_auth
from .services.monitoring import monitor_loop
from .api import (devices, onts, provisioning, troubleshoot, ai, ws,
                  config as config_api, auth as auth_api, users as users_api,
                  national as national_api, issues as issues_api,
                  agents as agents_api, audit as audit_api,
                  snmp as snmp_api,
                  gov as gov_api, transit as transit_api,
                  dfos as dfos_api,
                  companies as companies_api,
                  security as security_api,
                  subscriber as subscriber_api,
                  portal_sas as portal_sas_api,
                  tickets as tickets_api,
                  portal as portal_api,
                  sas_panel as sas_panel_api)
from .services.snmp_poller import snmp_poll_loop
from .services.sas_sync import sas_sync_loop
from .services.snmp_traps import start_trap_receiver


def _seed_demo_device():
    """إضافة جهاز محاكاة افتراضي عند أول تشغيل (وضع المحاكاة)"""
    with Session(engine) as db:
        exists = db.exec(select(OLTDevice)).first()
        if not exists and settings.use_mock_olt:
            db.add(OLTDevice(
                name="OLT-محاكاة-بغداد", host="127.0.0.1", protocol="ssh",
                username="root", password_enc=encrypt("admin"), model="MA5800",
                reachable=True,
            ))
            db.commit()


def _seed_default_admin():
    """إنشاء مدير افتراضي عند غياب أي مستخدم (يُبدَّل من واجهة إدارة المستخدمين)."""
    if not settings.seed_default_admin:
        return
    with Session(engine) as db:
        if db.exec(select(User)).first() is None:
            db.add(User(
                username=settings.default_admin_user,
                password_hash=hash_password(settings.default_admin_password),
                role="admin",
            ))
            db.commit()


def _seed_demo_agent():
    """بذرة تطبيق الوكلاء (شركة + وكيل + حساب دخول + مشتركون) عند SEED_DEMO_DATA=true.
    idempotent: تتخطّى نفسها إن كان حساب الوكيل موجوداً. لا تُفشل الإقلاع عند أي خطأ."""
    if not settings.seed_demo_data:
        return
    try:
        from seed_agent_demo import seed as _seed
        _seed()
    except Exception as exc:  # noqa: BLE001 — البذرة تجميلية؛ لا تكسر الخادم
        import logging
        logging.getLogger(__name__).warning("[seed] تعذّرت بذرة الوكيل التجريبية: %s", exc)


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings.validate_runtime()   # يرفض الإقلاع بإعداد إنتاج غير آمن
    init_db()
    _seed_demo_device()
    _seed_default_admin()
    _seed_demo_agent()
    monitor_task = asyncio.create_task(monitor_loop(settings.monitor_interval))
    # مستقبِل SNMP Traps — يعمل دائماً (محاكاة وإنتاج)
    trap_task = asyncio.create_task(start_trap_receiver())
    # سحّاب SNMP الدوري — يعمل فقط إن كان مُفعَّلاً في الإعدادات
    snmp_task = asyncio.create_task(snmp_poll_loop()) if settings.snmp_poll_enabled else None
    sas_task = asyncio.create_task(sas_sync_loop())
    yield
    monitor_task.cancel()
    trap_task.cancel()
    if snmp_task is not None:
        snmp_task.cancel()
    sas_task.cancel()


app = FastAPI(
    title="منصة العراق الرقمية",
    description="المنصّة الوطنية للإشراف على خدمات الإنترنت — الشركات · الوكلاء · المشتركون · التذاكر · إدارة أجهزة OLT (Huawei MA5680T/MA5800/EA5800)",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,   # مقيّد بالأصول المُعدّة بدل "*"
    allow_methods=["*"],
    allow_headers=["*"],
)

# كل مسارات REST محميّة بالمصادقة (root و/api/health يبقيان مفتوحين لفحص الصحّة).
_auth = [Depends(require_auth)]
app.include_router(devices.router, dependencies=_auth)
app.include_router(onts.router, dependencies=_auth)
app.include_router(provisioning.router, dependencies=_auth)
app.include_router(troubleshoot.router, dependencies=_auth)
app.include_router(ai.router, dependencies=_auth)
app.include_router(config_api.router, dependencies=_auth)
# الوحدات التجريبية (بيانات مولّدة) — تُركّب فقط في وضع العرض التوضيحي (SEED_DEMO_DATA=true).
# في الإنتاج تبقى واجهة API حقيقية بالكامل (SAS/OLT). ملفات الخدمات تبقى للسجل/العرض.
if settings.seed_demo_data:
    app.include_router(national_api.router, dependencies=_auth)
    app.include_router(transit_api.router, dependencies=_auth)
    app.include_router(dfos_api.router, dependencies=_auth)
    app.include_router(issues_api.router, dependencies=_auth)
    app.include_router(agents_api.router, dependencies=_auth)
    app.include_router(gov_api.router, dependencies=_auth)
    app.include_router(audit_api.router, dependencies=_auth)
app.include_router(snmp_api.router, dependencies=_auth)
app.include_router(companies_api.router, dependencies=_auth)
app.include_router(sas_panel_api.router, dependencies=_auth)   # واجهة SAS الكاملة (بروكسي حيّ معزول)
app.include_router(security_api.router, dependencies=_auth)
app.include_router(tickets_api.router, dependencies=_auth)
app.include_router(portal_api.router, dependencies=_auth)    # ملخّص لوحة التطبيقات (وكيل/شركة/وزارة)   # التذاكر — الوكلاء/الشركات/الوزارة (بعزل النطاق)
app.include_router(subscriber_api.router)                    # تطبيق المشتركين — OTP عامّ، والبقية بتوكن مشترك
app.include_router(portal_sas_api.router)                    # بوابة المشترك عبر SAS — بتوكن المشترك (require_subscriber)
app.include_router(auth_api.router)      # /login عامّ · /me يحمي نفسه داخلياً
app.include_router(users_api.router)     # إدارة المستخدمين — admin (محمي داخل الراوتر)
app.include_router(ws.router)   # مصادقة الـ WebSocket تُدار داخلياً (query param)


@app.get("/")
def root():
    return {
        "app": "منصة العراق الرقمية",
        "status": "running",
        "mock_mode": settings.use_mock_olt,
        "docs": "/docs",
    }


@app.get("/api/health")
def health():
    # تستهلكه شاشات الدخول والبوّابة (مؤشّر حالة الخادم) — يبقى عامّاً وخفيفاً
    return {"ok": True, "mock": settings.use_mock_olt, "app": "منصة العراق الرقمية", "version": app.version}

# reload-trigger dbdf3fa3-261f-4cb1-ba08-a6bb97e54547

# reload 5db04894
