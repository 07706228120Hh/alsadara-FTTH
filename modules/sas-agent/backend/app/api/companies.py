"""
نقاط نهاية الشركات — إدارة الشركات المربوطة عبر SAS + اختبار الاتصال + المزامنة الفورية
+ صورة اللوحة الوطنية من لقطات حقيقية.

يُوضع في backend/app/api/companies.py، ويُربط في main.py:
    from .api import ... , companies as companies_api
    app.include_router(companies_api.router, dependencies=_auth)

عزل النطاق (Multi-tenant scoping):
- جهة رقابية (company_id=None, agent=""): ترى الكل.
- مستخدم شركة (company_id=X): يرى شركته X فقط.
- مستخدم وكيل (company_id=X, agent="Y"): يرى نطاقه ضمن شركته.
"""
from __future__ import annotations

import json
import random
import re
import secrets
import xml.etree.ElementTree as ET
from typing import List, Optional

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel
from sqlmodel import Session, select, delete

# تحليل XML آمن للـ KML: يرفض DTD/الكيانات (يمنع billion-laughs/XXE)
from defusedxml.ElementTree import fromstring as _safe_fromstring
from defusedxml.common import DefusedXmlException

from ..database import get_session
from ..models import (Company, CompanySnapshot, Agent, AgentReport, MergeFinding,
                      Subscriber, SasAccount, User, GisLayer, AuditLog)
from ..core.security import encrypt, hash_password, decrypt
from ..core.auth import require_role, current_identity, scope_of
from ..integrations.sas_client import SASClient, SASError, is_cert_error
from ..services import sas_sync
from ..services import addressing_service
from ..services import expiry as expiry_svc
from ..core import addressing as addr

# حجم أقصى لملف GIS (10 MB)
_GIS_MAX_BYTES = 10 * 1024 * 1024

# بادئة KML namespace الشائعة
_KML_NS = "http://www.opengis.net/kml/2.2"

router = APIRouter(prefix="/api/companies", tags=["companies"])

_operator = [Depends(require_role("operator"))]
_admin = [Depends(require_role("admin"))]


# ─────────────────────── مساعدات عزل النطاق ───────────────────────

def _assert_company(identity: dict, company_id: int) -> None:
    """يتحقّق أن الطالب مسموح له برؤية هذه الشركة.
    نُرجع 404 (لا 403) كي لا نُكشف وجود الموارد للطرف الآخر."""
    cid, _agent = scope_of(identity)
    if cid is not None and company_id != cid:
        raise HTTPException(404, "الشركة غير موجودة")


def _deny_scoped(identity: dict) -> None:
    """يرفض أي طالب ذو نطاق (شركة أو وكيل) — للمسارات الرقابية الشاملة فقط."""
    cid, agent = scope_of(identity)
    if cid is not None or agent:
        raise HTTPException(403, "للجهة الرقابية فقط")


# ----------------------------- المخططات (I/O) -----------------------------
class CompanyIn(BaseModel):
    name: str
    code: str = ""
    governorate: str = ""
    color: str = "#22D3EE"
    enabled: bool = True
    kind: str = "primary"            # primary=رئيسية | secondary=ثانوية
    access_type: str = "ftth"        # ftth | wireless
    sas_host: str = ""
    sas_https: bool = False
    sas_verify_tls: bool = False     # الافتراض: بلا تحقّق شهادة (لوحات SAS ذاتية التوقيع غالباً)
    sas_username: str = ""
    sas_password: str = ""          # نص صريح عند الإدخال — يُشفَّر قبل الحفظ


class CompanyOut(BaseModel):
    id: int
    name: str
    code: str
    governorate: str
    color: str
    enabled: bool
    kind: str
    access_type: str
    sas_host: str
    sas_https: bool
    sas_verify_tls: bool
    sas_username: str
    has_password: bool
    last_sync_at: Optional[str] = None
    last_sync_ok: bool
    last_sync_error: str

    @classmethod
    def of(cls, c: Company) -> "CompanyOut":
        return cls(
            id=c.id, name=c.name, code=c.code, governorate=c.governorate,
            color=c.color, enabled=c.enabled, kind=c.kind, access_type=c.access_type,
            sas_host=c.sas_host,
            sas_https=c.sas_https, sas_verify_tls=c.sas_verify_tls,
            sas_username=c.sas_username,
            has_password=bool(c.sas_password_enc),
            last_sync_at=c.last_sync_at.isoformat() if c.last_sync_at else None,
            last_sync_ok=c.last_sync_ok, last_sync_error=c.last_sync_error,
        )


# ------------------------------- القراءة -------------------------------
@router.get("", response_model=List[CompanyOut])
def list_companies(db: Session = Depends(get_session),
                   identity: dict = Depends(current_identity)):
    cid, _agent = scope_of(identity)
    q = select(Company)
    if cid is not None:
        # مستخدم شركة → يرى شركته فقط
        q = q.where(Company.id == cid)
    return [CompanyOut.of(c) for c in db.exec(q).all()]


@router.get("/{company_id:int}", response_model=CompanyOut)
def get_company(company_id: int, db: Session = Depends(get_session),
                identity: dict = Depends(current_identity)):
    _assert_company(identity, company_id)
    c = db.get(Company, company_id)
    if not c:
        raise HTTPException(404, "الشركة غير موجودة")
    return CompanyOut.of(c)


# ------------------------------- الكتابة -------------------------------
@router.post("", response_model=CompanyOut, dependencies=_admin)
def create_company(body: CompanyIn, db: Session = Depends(get_session),
                   identity: dict = Depends(current_identity)):
    # إنشاء الشركات: للجهة الرقابية فقط (مستخدم ذو نطاق لا يُنشئ شركات)
    _deny_scoped(identity)
    c = Company(
        name=body.name, code=body.code, governorate=body.governorate,
        color=body.color, enabled=body.enabled,
        kind=body.kind, access_type=body.access_type,
        sas_host=body.sas_host,
        sas_https=body.sas_https, sas_verify_tls=body.sas_verify_tls,
        sas_username=body.sas_username,
        sas_password_enc=encrypt(body.sas_password) if body.sas_password else "",
    )
    db.add(c)
    db.commit()
    db.refresh(c)
    return CompanyOut.of(c)


@router.patch("/{company_id}", response_model=CompanyOut, dependencies=_admin)
def update_company(company_id: int, body: CompanyIn, db: Session = Depends(get_session),
                   identity: dict = Depends(current_identity)):
    # مدير شركة يعدّل شركته فقط؛ جهة رقابية تعدّل أي شركة
    _assert_company(identity, company_id)
    c = db.get(Company, company_id)
    if not c:
        raise HTTPException(404, "الشركة غير موجودة")
    for f in ("name", "code", "governorate", "color", "enabled",
              "kind", "access_type",
              "sas_host", "sas_https", "sas_verify_tls", "sas_username"):
        setattr(c, f, getattr(body, f))
    if body.sas_password:                       # لا تمسح كلمة المرور إن تُركت فارغة
        c.sas_password_enc = encrypt(body.sas_password)
    db.add(c)
    db.commit()
    db.refresh(c)
    return CompanyOut.of(c)


@router.get("/{company_id:int}/sas-password", dependencies=_admin)
def reveal_sas_password(company_id: int, db: Session = Depends(get_session),
                        identity: dict = Depends(current_identity)):
    """يكشف كلمة مرور SAS المحفوظة (مفكوكة) عند الطلب — مدير/جهة رقابية ضمن النطاق فقط.

    كل كشف يُسجَّل في AuditLog (من كشف كلمة مرور أي شركة ومتى). عدا ذلك تبقى كلمة
    المرور مشفّرة ولا تُعاد في أي مسار آخر (has_password فقط)."""
    _assert_company(identity, company_id)
    c = db.get(Company, company_id)
    if not c:
        raise HTTPException(404, "الشركة غير موجودة")
    from ..core.security import decrypt
    pwd = decrypt(c.sas_password_enc) if c.sas_password_enc else ""
    db.add(AuditLog(
        user=str(identity.get("user", "system")),
        command=f"كشف كلمة مرور SAS للشركة {company_id} ({c.name})",
        kind="dangerous", success=True))
    db.commit()
    return {"password": pwd, "has_password": bool(c.sas_password_enc)}


@router.delete("/{company_id}", dependencies=_admin)
def delete_company(company_id: int, db: Session = Depends(get_session),
                   identity: dict = Depends(current_identity)):
    # حذف الشركات: للجهة الرقابية فقط
    _deny_scoped(identity)
    c = db.get(Company, company_id)
    if not c:
        raise HTTPException(404, "الشركة غير موجودة")
    # حذف تعاقبي لكل ما يتبع الشركة (تفادي أيتام تُربك التدقيق وكشف الدمج)
    db.exec(delete(CompanySnapshot).where(CompanySnapshot.company_id == company_id))
    db.exec(delete(Agent).where(Agent.company_id == company_id))
    db.exec(delete(MergeFinding).where(MergeFinding.company_id == company_id))
    db.exec(delete(Subscriber).where(Subscriber.company_id == company_id))
    # حذف حسابات الدخول المرتبطة بالشركة (مديرو الشركة ووكلاؤها) — وإلا بقيت
    # حسابات يتيمة تشير لشركة محذوفة (تظهر كـ «شركة #N» ولا تعمل عند الدخول).
    db.exec(delete(User).where(User.scope_company_id == company_id))
    db.delete(c)
    db.commit()
    return {"ok": True}


# --------------------------- اختبار الاتصال بـ SAS ---------------------------
class SASTestBody(BaseModel):
    """اختبار بيانات جديدة قبل الحفظ، أو اترك الحقول فارغة لاختبار المحفوظة."""
    sas_host: Optional[str] = None
    sas_https: Optional[bool] = None
    sas_verify_tls: Optional[bool] = None
    sas_username: Optional[str] = None
    sas_password: Optional[str] = None


@router.post("/{company_id}/sas/test", dependencies=_operator)
async def test_sas(company_id: int, body: SASTestBody,
                   db: Session = Depends(get_session),
                   identity: dict = Depends(current_identity)):
    """يسجّل الدخول لـ SAS ويسحب ملخّص المشتركين — يُرجع ok + عيّنة أرقام."""
    _assert_company(identity, company_id)
    c = db.get(Company, company_id)
    if not c:
        raise HTTPException(404, "الشركة غير موجودة")
    from ..core.security import decrypt
    # الوكيل يختبر خادمه الخاص؛ الشركة/الجهة الرقابية تختبر بيانات الشركة.
    _cid, scope_agent = scope_of(identity)
    src = None
    if scope_agent:
        src = db.exec(select(User).where(User.username == (identity.get("user") or ""))).first()
    if src is not None:                         # مصدر الافتراضات = بيانات الوكيل المحفوظة
        host = body.sas_host or src.sas_host
        user = body.sas_username or src.sas_username
        pwd = body.sas_password if body.sas_password else (decrypt(src.sas_password_enc) if src.sas_password_enc else "")
        https = src.sas_https if body.sas_https is None else body.sas_https
        verify = src.sas_verify_tls if body.sas_verify_tls is None else body.sas_verify_tls
    else:                                       # مصدر الافتراضات = بيانات الشركة
        host = body.sas_host or c.sas_host
        user = body.sas_username or c.sas_username
        pwd = body.sas_password if body.sas_password else decrypt(c.sas_password_enc)
        https = c.sas_https if body.sas_https is None else body.sas_https
        verify = c.sas_verify_tls if body.sas_verify_tls is None else body.sas_verify_tls
    if not host or not user:
        raise HTTPException(400, "عنوان SAS واسم المستخدم مطلوبان")
    async def _probe(verify_tls: bool):
        async with SASClient(host, user, pwd, https=https, verify_tls=verify_tls) as sas:
            res = await sas.dashboard_subscribers()
            return res.get("data", res) if isinstance(res, dict) else {}
    fell_back = False
    try:
        try:
            data = await _probe(verify)
        except Exception as e:                     # noqa: BLE001
            if verify and is_cert_error(e):        # شهادة ذاتية → أعِد المحاولة بلا تحقّق
                data = await _probe(False)
                fell_back = True
            else:
                raise
        return {"ok": True, "cert_fallback": fell_back, "summary": {
            "total": data.get("total"), "active": data.get("active"),
            "expired": data.get("expired"), "online": data.get("online"),
            "managers": data.get("managers")}}
    except SASError as e:
        return {"ok": False, "error": str(e)}
    except Exception as e:   # noqa: BLE001
        return {"ok": False, "error": f"تعذّر الاتصال بـ SAS: {e}"}


# --------------------- إعداد اتصال SAS ذاتيّاً (الشركة نفسها) ---------------------
class SASConfigBody(BaseModel):
    """بيانات الاتصال بـ SAS التي تضبطها الشركة داخل تطبيقها."""
    sas_host: str = ""
    sas_username: str = ""
    sas_password: Optional[str] = None      # فارغ/None = إبقاء المحفوظة
    sas_https: bool = False
    sas_verify_tls: bool = False


@router.patch("/{company_id:int}/sas-config", response_model=CompanyOut, dependencies=_operator)
def update_sas_config(company_id: int, body: SASConfigBody,
                      db: Session = Depends(get_session),
                      identity: dict = Depends(current_identity)):
    """تضبط الشركة (أو الجهة الرقابية) بيانات الاتصال بـ SAS الخاصة بها — معزولة بالنطاق.

    تُحدّث حقول SAS فقط (لا الاسم/الرمز/الحالة). كلمة المرور الفارغة = إبقاء المحفوظة.
    مسموحة لمستخدم الشركة (operator+) على شركته فقط عبر [_assert_company]."""
    _assert_company(identity, company_id)
    c = db.get(Company, company_id)
    if not c:
        raise HTTPException(404, "الشركة غير موجودة")
    c.sas_host = (body.sas_host or "").strip()
    c.sas_username = (body.sas_username or "").strip()
    c.sas_https = body.sas_https
    c.sas_verify_tls = body.sas_verify_tls
    if body.sas_password:                       # فارغة = إبقاء المحفوظة
        c.sas_password_enc = encrypt(body.sas_password)
    db.add(c)
    db.commit()
    db.refresh(c)
    return CompanyOut.of(c)


# --------------- إعداد اتصال SAS للوكيل (خادمه واسم مستخدمه وكلمة مروره — يُدخلها بنفسه) ---------------
class AgentSASConfigBody(BaseModel):
    """بيانات اتصال الوكيل بنظام SAS: عنوان الخادم + اسم المستخدم + كلمة المرور."""
    sas_host: Optional[str] = None          # عنوان خادم SAS الخاص بالوكيل (host[:port] أو رابط)
    sas_https: Optional[bool] = None
    sas_verify_tls: Optional[bool] = None
    sas_username: str = ""
    sas_password: Optional[str] = None      # فارغ/None = إبقاء المحفوظة


def _current_agent_user(db: Session, identity: dict) -> User:
    """مستخدم الوكيل الحالي (يُرفض لغير الوكلاء)."""
    _cid, scope_agent = scope_of(identity)
    if not scope_agent:
        raise HTTPException(403, "هذه الصفحة خاصّة بالوكلاء")
    u = db.exec(select(User).where(User.username == (identity.get("user") or ""))).first()
    if not u:
        raise HTTPException(404, "الحساب غير موجود")
    return u


def _sas_account_out(a: SasAccount, subscribers: Optional[int] = None) -> dict:
    """تمثيل حساب SAS للواجهة — بلا كلمة مرور (has_password فقط)."""
    out = {
        "id": a.id, "label": a.label,
        "sas_host": a.sas_host, "sas_https": a.sas_https, "sas_verify_tls": a.sas_verify_tls,
        "sas_username": a.sas_username, "has_password": bool(a.sas_password_enc),
        "enabled": a.enabled,
        "configured": bool(a.sas_host and a.sas_username and a.sas_password_enc),
        "last_sync_at": a.last_sync_at.isoformat() if a.last_sync_at else None,
        "last_sync_ok": a.last_sync_ok, "last_sync_error": a.last_sync_error,
    }
    if subscribers is not None:
        out["subscribers"] = subscribers
    return out


def _agent_account_or_404(db: Session, u: User, account_id: int) -> SasAccount:
    """حساب SAS يملكه الوكيل الحالي — 404 إن لم يوجد/ليس له."""
    acc = db.get(SasAccount, account_id)
    if not acc or acc.owner_user_id != u.id:
        raise HTTPException(404, "حساب SAS غير موجود ضمن حساباتك")
    return acc


@router.get("/agent/sas-config")
def get_agent_sas_config(db: Session = Depends(get_session),
                         identity: dict = Depends(current_identity)):
    """إعداد SAS للوكيل الحالي — يُرجع الحساب **الأساسي** (توافق خلفي مع الحساب المفرد).
    لإدارة عدة حسابات استخدم /agent/sas-accounts. لا يُعاد كلمة المرور."""
    u = _current_agent_user(db, identity)
    accounts = sas_sync.ensure_agent_accounts(db, u)
    a = accounts[0] if accounts else None
    if not a:
        return {"sas_host": "", "sas_https": False, "sas_verify_tls": False,
                "sas_username": "", "has_password": False, "configured": False}
    return {
        "sas_host": a.sas_host, "sas_https": a.sas_https, "sas_verify_tls": a.sas_verify_tls,
        "sas_username": a.sas_username, "has_password": bool(a.sas_password_enc),
        "configured": bool(a.sas_host and a.sas_username and a.sas_password_enc),
    }


@router.patch("/agent/sas-config")
def update_agent_sas_config(body: AgentSASConfigBody,
                            background: BackgroundTasks,
                            db: Session = Depends(get_session),
                            identity: dict = Depends(current_identity)):
    """توافق خلفي: يضبط الوكيل حسابه **الأساسي** (يُنشأ إن لم يوجد). كلمة المرور الفارغة = إبقاء.
    يُثبّت scope_agent على اسم مستخدم SAS كي يعمل العرض المدموج، ويُطلق سحباً خلفياً للحساب."""
    u = _current_agent_user(db, identity)
    accounts = sas_sync.ensure_agent_accounts(db, u)
    a = accounts[0] if accounts else SasAccount(
        owner_user_id=u.id, company_id=u.scope_company_id, label="الحساب الأساسي")
    if body.sas_host is not None:
        a.sas_host = body.sas_host.strip()
    if body.sas_https is not None:
        a.sas_https = body.sas_https
    if body.sas_verify_tls is not None:
        a.sas_verify_tls = body.sas_verify_tls
    uname = (body.sas_username or "").strip()
    if uname:
        a.sas_username = uname
        if not a.label:
            a.label = uname
        u.scope_agent = uname               # النطاق يتبع اسم مستخدم SAS (يسري فوراً)
        db.add(u)
    if body.sas_password:
        a.sas_password_enc = encrypt(body.sas_password)
    db.add(a)
    db.commit()
    db.refresh(a)
    configured = bool(a.sas_host and a.sas_username and a.sas_password_enc)
    if configured:                          # حفظ محلي فور الحفظ: يسحب مشتركي الحساب في الخلفية
        background.add_task(sas_sync.sync_account, a.id)
    return {
        "sas_host": a.sas_host, "sas_https": a.sas_https, "sas_verify_tls": a.sas_verify_tls,
        "sas_username": a.sas_username, "has_password": bool(a.sas_password_enc),
        "configured": configured,
    }


@router.post("/agent/sas-sync")
async def sync_agent_now(db: Session = Depends(get_session),
                         identity: dict = Depends(current_identity)):
    """يسحب الوكيل مشتركيه من **كل حساباته** ويحفظها محلياً الآن (زر «مزامنة الكل»).
    يُعيد عدد المشتركين المحفوظين + حالة كل حساب. رسالة واضحة عند غياب أي حساب مضبوط."""
    u = _current_agent_user(db, identity)
    accounts = sas_sync.ensure_agent_accounts(db, u)
    if not any(a.enabled and a.sas_host and a.sas_username and a.sas_password_enc for a in accounts):
        raise HTTPException(400, "أضف حساب SAS واحداً على الأقل (الخادم + اسم المستخدم + كلمة المرور)")
    res = await sas_sync.sync_agent(u.id)
    if not res.get("ok"):
        raise HTTPException(502, res.get("error") or "تعذّرت المزامنة من خوادم SAS")
    return res


# ═══════════ حسابات SAS المتعددة للوكيل — إضافة/تعديل/حذف/اختبار/مزامنة ═══════════
# الوكيل يربط عدة حسابات SAS (قد تكون على خوادم مختلفة)؛ تُعرَض مشتركوها مدموجين
# وتُوجَّه أي عملية تلقائياً إلى الحساب الصحيح عبر Subscriber.sas_account_id.

class SasAccountIn(BaseModel):
    """إضافة حساب SAS جديد للوكيل."""
    label: str = ""
    sas_host: str = ""
    sas_username: str = ""
    sas_password: Optional[str] = None
    sas_https: bool = False
    sas_verify_tls: bool = False
    enabled: bool = True


class SasAccountPatch(BaseModel):
    """تعديل حساب SAS (كل الحقول اختيارية؛ كلمة المرور الفارغة = إبقاء)."""
    label: Optional[str] = None
    sas_host: Optional[str] = None
    sas_username: Optional[str] = None
    sas_password: Optional[str] = None
    sas_https: Optional[bool] = None
    sas_verify_tls: Optional[bool] = None
    enabled: Optional[bool] = None


@router.get("/agent/sas-accounts")
def list_agent_sas_accounts(db: Session = Depends(get_session),
                            identity: dict = Depends(current_identity)):
    """كل حسابات SAS التابعة للوكيل (مع عدد مشتركي كل حساب) — مع ترحيل الحساب المفرد القديم."""
    u = _current_agent_user(db, identity)
    accounts = sas_sync.ensure_agent_accounts(db, u)
    out = []
    for a in accounts:
        n = len(db.exec(select(Subscriber.id).where(Subscriber.sas_account_id == a.id)).all())
        out.append(_sas_account_out(a, subscribers=n))
    return {"accounts": out, "count": len(out)}


@router.post("/agent/sas-accounts")
def add_agent_sas_account(body: SasAccountIn,
                          background: BackgroundTasks,
                          db: Session = Depends(get_session),
                          identity: dict = Depends(current_identity)):
    """يضيف الوكيل حساب SAS جديداً. يُطلق سحباً خلفياً لمشتركيه فور الإضافة إن اكتمل."""
    u = _current_agent_user(db, identity)
    sas_sync.ensure_agent_accounts(db, u)   # رحّل القديم أولاً كي لا يتكرّر لاحقاً
    host = (body.sas_host or "").strip()
    uname = (body.sas_username or "").strip()
    if not host or not uname:
        raise HTTPException(400, "عنوان الخادم واسم المستخدم مطلوبان")
    dup = db.exec(select(SasAccount).where(
        SasAccount.owner_user_id == u.id,
        SasAccount.sas_host == host,
        SasAccount.sas_username == uname)).first()
    if dup:
        raise HTTPException(409, "لديك حساب بنفس الخادم واسم المستخدم مسبقاً")
    a = SasAccount(
        owner_user_id=u.id, company_id=u.scope_company_id,
        label=(body.label or "").strip() or uname,
        sas_host=host, sas_username=uname,
        sas_https=body.sas_https, sas_verify_tls=body.sas_verify_tls,
        sas_password_enc=encrypt(body.sas_password) if body.sas_password else "",
        enabled=body.enabled,
    )
    db.add(a)
    db.commit()
    db.refresh(a)
    if a.enabled and a.sas_host and a.sas_username and a.sas_password_enc:
        background.add_task(sas_sync.sync_account, a.id)
    return _sas_account_out(a, subscribers=0)


@router.patch("/agent/sas-accounts/{account_id}")
def update_agent_sas_account(account_id: int, body: SasAccountPatch,
                             background: BackgroundTasks,
                             db: Session = Depends(get_session),
                             identity: dict = Depends(current_identity)):
    """تعديل حساب SAS للوكيل. كلمة المرور الفارغة = إبقاء المحفوظة."""
    u = _current_agent_user(db, identity)
    a = _agent_account_or_404(db, u, account_id)
    if body.label is not None:
        a.label = body.label.strip()
    if body.sas_host is not None:
        a.sas_host = body.sas_host.strip()
    if body.sas_username is not None:
        a.sas_username = body.sas_username.strip()
    if body.sas_https is not None:
        a.sas_https = body.sas_https
    if body.sas_verify_tls is not None:
        a.sas_verify_tls = body.sas_verify_tls
    if body.enabled is not None:
        a.enabled = body.enabled
    if body.sas_password:
        a.sas_password_enc = encrypt(body.sas_password)
    if not a.label:
        a.label = a.sas_username
    db.add(a)
    db.commit()
    db.refresh(a)
    if a.enabled and a.sas_host and a.sas_username and a.sas_password_enc:
        background.add_task(sas_sync.sync_account, a.id)
    n = len(db.exec(select(Subscriber.id).where(Subscriber.sas_account_id == a.id)).all())
    return _sas_account_out(a, subscribers=n)


@router.delete("/agent/sas-accounts/{account_id}")
def delete_agent_sas_account(account_id: int,
                             db: Session = Depends(get_session),
                             identity: dict = Depends(current_identity)):
    """حذف حساب SAS للوكيل + مشتركيه المحليين المرتبطين به (معزول بالحساب)."""
    u = _current_agent_user(db, identity)
    a = _agent_account_or_404(db, u, account_id)
    db.exec(delete(Subscriber).where(Subscriber.sas_account_id == a.id))
    db.delete(a)
    db.commit()
    return {"ok": True}


@router.post("/agent/sas-accounts/{account_id}/test")
async def test_agent_sas_account(account_id: int, body: SASTestBody,
                                 db: Session = Depends(get_session),
                                 identity: dict = Depends(current_identity)):
    """اختبار اتصال حساب SAS للوكيل (ببيانات جديدة أو المحفوظة) — يُرجع ok + عيّنة أرقام."""
    u = _current_agent_user(db, identity)
    a = _agent_account_or_404(db, u, account_id)
    host = (body.sas_host or a.sas_host or "").strip()
    user = (body.sas_username or a.sas_username or "").strip()
    pwd = body.sas_password if body.sas_password else (decrypt(a.sas_password_enc) if a.sas_password_enc else "")
    https = a.sas_https if body.sas_https is None else body.sas_https
    verify = a.sas_verify_tls if body.sas_verify_tls is None else body.sas_verify_tls
    if not host or not user:
        raise HTTPException(400, "عنوان SAS واسم المستخدم مطلوبان")

    async def _probe(verify_tls: bool):
        async with SASClient(host, user, pwd, https=https, verify_tls=verify_tls) as sas:
            res = await sas.dashboard_subscribers()
            return res.get("data", res) if isinstance(res, dict) else {}
    fell_back = False
    try:
        try:
            data = await _probe(verify)
        except Exception as e:                     # noqa: BLE001
            if verify and is_cert_error(e):
                data = await _probe(False)
                fell_back = True
            else:
                raise
        return {"ok": True, "cert_fallback": fell_back, "summary": {
            "total": data.get("total"), "active": data.get("active"),
            "expired": data.get("expired"), "online": data.get("online"),
            "managers": data.get("managers")}}
    except SASError as e:
        return {"ok": False, "error": str(e)}
    except Exception as e:                          # noqa: BLE001
        return {"ok": False, "error": f"تعذّر الاتصال بـ SAS: {e}"}


@router.post("/agent/sas-accounts/{account_id}/sync")
async def sync_agent_sas_account(account_id: int,
                                 db: Session = Depends(get_session),
                                 identity: dict = Depends(current_identity)):
    """مزامنة مشتركي حساب SAS واحد الآن — يُعيد {ok, count}."""
    u = _current_agent_user(db, identity)
    a = _agent_account_or_404(db, u, account_id)
    if not (a.sas_host and a.sas_username and a.sas_password_enc):
        raise HTTPException(400, "اضبط الحساب أولاً (الخادم + اسم المستخدم + كلمة المرور)")
    res = await sas_sync.sync_account(a.id)
    if not res.get("ok"):
        raise HTTPException(502, res.get("error") or "تعذّرت المزامنة من خادم SAS")
    return res


# --------------- إنشاء حساب وكيل مباشرةً (الأدمن) — بلا حاجة لمزامنة SAS مسبقة ---------------
class NewAgentAccount(BaseModel):
    """حساب دخول لوكيل ينشئه الأدمن: اسم مستخدم + كلمة مرور + معلومات + مزوّد."""
    username: str
    password: str
    display_name: str = ""
    phone: str = ""
    provider: str = ""              # اسم المزوّد/الشركة — يُنشأ إن لم يوجد (يُتجاهَل لمدير شركة مقيّد)
    role: str = "operator"          # operator | viewer


@router.post("/agent-accounts", dependencies=_admin)
def create_agent_account(body: NewAgentAccount,
                         db: Session = Depends(get_session),
                         identity: dict = Depends(current_identity)):
    """ينشئ الأدمن حساب دخول لوكيل مباشرةً. الوكيل يضبط خادم SAS وبياناته بعد الدخول.
    النطاق يُفرض قسراً: مدير شركة → شركته؛ جهة رقابية → المزوّد المُدخَل (يُنشأ إن لزم)."""
    username = (body.username or "").strip()
    if not username:
        raise HTTPException(400, "اسم المستخدم مطلوب")
    if len(body.password or "") < 8:
        raise HTTPException(400, "كلمة المرور قصيرة — 8 محارف على الأقل")
    role = (body.role or "operator").strip()
    if role not in {"viewer", "operator"}:
        raise HTTPException(400, "دور غير مسموح لحساب وكيل — المسموح: viewer/operator")
    if db.exec(select(User).where(User.username == username)).first():
        raise HTTPException(409, f"اسم المستخدم '{username}' مستخدم مسبقاً")
    # المزوّد (الشركة): مدير شركة مقيّد → شركته؛ وإلا إيجاد/إنشاء بالاسم المُدخَل
    scope_cid, _ = scope_of(identity)
    if scope_cid:
        company = db.get(Company, scope_cid)
        if not company:
            raise HTTPException(404, "الشركة غير موجودة")
    else:
        provider = (body.provider or "").strip() or "المزوّد الافتراضي"
        company = db.exec(select(Company).where(Company.name == provider)).first()
        if not company:
            company = Company(name=provider, code="", governorate="")
            db.add(company); db.commit(); db.refresh(company)
    u = User(
        username=username,
        password_hash=hash_password(body.password),
        role=role,
        scope_company_id=company.id,
        scope_agent=username,           # مؤقّت — يُحدَّث تلقائياً إلى اسم مستخدم SAS عند ضبط الوكيل إعداده
        display_name=(body.display_name or "").strip(),
        phone=(body.phone or "").strip(),
        enabled=True,
    )
    db.add(u); db.commit(); db.refresh(u)
    return {"ok": True, "id": u.id, "username": u.username,
            "company_id": company.id, "provider": company.name,
            "display_name": u.display_name, "phone": u.phone}


@router.get("/agent-accounts", dependencies=_admin)
def list_agent_accounts(db: Session = Depends(get_session),
                        identity: dict = Depends(current_identity)):
    """قائمة حسابات الوكلاء التي أنشأها الأدمن (مع حالة ضبط SAS لكلٍّ)."""
    scope_cid, _ = scope_of(identity)
    q = select(User).where(User.scope_agent != "")            # noqa: E712 — الوكلاء فقط
    if scope_cid:
        q = q.where(User.scope_company_id == scope_cid)
    users = db.exec(q).all()
    companies = {c.id: c for c in db.exec(select(Company)).all()}
    return {"accounts": [{
        "id": u.id, "username": u.username, "role": u.role, "enabled": u.enabled,
        "display_name": u.display_name, "phone": u.phone,
        "company_id": u.scope_company_id,
        "provider": (companies.get(u.scope_company_id).name
                     if companies.get(u.scope_company_id) else ""),
        "sas_username": u.sas_username,
        "sas_configured": bool(u.sas_host and u.sas_username and u.sas_password_enc),
    } for u in users], "count": len(users)}


@router.delete("/agent-accounts/{user_id}", dependencies=_admin)
def delete_agent_account(user_id: int, db: Session = Depends(get_session),
                         identity: dict = Depends(current_identity)):
    """حذف حساب وكيل (ضمن نطاق الطالب)."""
    scope_cid, _ = scope_of(identity)
    u = db.get(User, user_id)
    if not u or not u.scope_agent:
        raise HTTPException(404, "حساب الوكيل غير موجود")
    if scope_cid and u.scope_company_id != scope_cid:
        raise HTTPException(404, "حساب الوكيل غير موجود ضمن نطاقك")
    db.delete(u); db.commit()
    return {"ok": True}


# ----------------------------- المزامنة الفورية -----------------------------
@router.post("/{company_id}/sync", dependencies=_operator)
async def sync_now(company_id: int, db: Session = Depends(get_session),
                   identity: dict = Depends(current_identity)):
    _assert_company(identity, company_id)
    if not db.get(Company, company_id):
        raise HTTPException(404, "الشركة غير موجودة")
    snap = await sas_sync.sync_one(company_id)
    if not snap:
        c = db.get(Company, company_id)
        raise HTTPException(502, c.last_sync_error or "فشلت المزامنة")
    return {"ok": True, "snapshot": {
        "ts": snap.ts.isoformat(), "total": snap.total, "active": snap.active,
        "expired": snap.expired, "online": snap.online, "offline": snap.offline,
        "managers": snap.managers}}


@router.post("/sync-all", dependencies=_operator)
async def sync_all(identity: dict = Depends(current_identity)):
    _deny_scoped(identity)
    return await sas_sync.sync_all_once()


# --------------------- الصورة الوطنية من لقطات حقيقية ---------------------
@router.get("/overview/national")
def national_overview(db: Session = Depends(get_session),
                      identity: dict = Depends(current_identity)):
    """يجمّع أحدث لقطة لكل شركة إلى صورة وطنية حقيقية (بديل مولّد national.py)."""
    _deny_scoped(identity)
    companies = db.exec(select(Company)).all()
    rows, totals = [], {"total": 0, "active": 0, "expired": 0, "online": 0, "managers": 0}
    for c in companies:
        snap = db.exec(
            select(CompanySnapshot)
            .where(CompanySnapshot.company_id == c.id)
            .order_by(CompanySnapshot.ts.desc())
        ).first()
        row = {"company": c.name, "code": c.code, "color": c.color,
               "governorate": c.governorate, "enabled": c.enabled,
               "last_sync_ok": c.last_sync_ok,
               "last_sync_at": c.last_sync_at.isoformat() if c.last_sync_at else None,
               "total": snap.total if snap else 0,
               "active": snap.active if snap else 0,
               "expired": snap.expired if snap else 0,
               "online": snap.online if snap else 0,
               "managers": snap.managers if snap else 0}
        for k in totals:
            totals[k] += row[k]
        rows.append(row)
    return {"companies": rows, "totals": totals, "count": len(companies)}


# ============================ الوكلاء (Agents) ============================
@router.get("/agents/all")
def list_agents(company_id: Optional[int] = None, db: Session = Depends(get_session),
                identity: dict = Depends(current_identity)):
    """قائمة الوكلاء (كل الشركات أو شركة محدّدة) مع عدد مشتركي كل وكيل.
    عزل النطاق: مستخدم شركة → شركته فقط؛ وكيل → نطاقه (username أو parent) فقط.
    قيمة company_id من العميل تُضيّق داخل النطاق ولا توسّعه."""
    scope_cid, scope_agent = scope_of(identity)

    q = select(Agent)
    if scope_cid is not None:
        # فرض نطاق الشركة — نتجاهل company_id العميل ونستخدم نطاق الهوية
        q = q.where(Agent.company_id == scope_cid)
        if scope_agent.strip():
            # وكيل: يرى نفسه + من تحته مباشرة
            q = q.where(
                (Agent.username == scope_agent.strip()) |
                (Agent.parent_username == scope_agent.strip())
            )
    elif company_id is not None:
        # جهة رقابية + تصفية اختيارية بالشركة
        q = q.where(Agent.company_id == company_id)

    names = {c.id: c.name for c in db.exec(select(Company)).all()}
    rows = []
    for a in db.exec(q).all():
        rows.append({
            "id": a.id, "company_id": a.company_id,
            "company": names.get(a.company_id, "?"),
            "manager_id": a.manager_id, "username": a.username,
            "name": (f"{a.firstname} {a.lastname}").strip(),
            "parent_username": a.parent_username, "users_count": a.users_count,
            "balance": a.balance, "reward_points": a.reward_points,
            "enabled": a.enabled,
            "updated_at": a.updated_at.isoformat() if a.updated_at else None,
        })
    rows.sort(key=lambda r: r["users_count"], reverse=True)
    return {"agents": rows, "count": len(rows)}


# ============================ التدقيق (Audit) ============================
@router.get("/audit")
def audit(db: Session = Depends(get_session),
          identity: dict = Depends(current_identity)):
    """
    تدقيق لكل شركة: مجموع مشتركي الوكلاء (Σ users_count) مقابل إجمالي مشتركي الشركة
    من آخر لقطة. الفرق يكشف مشتركين غير منسوبين لوكيل (مباشرون/مخفيون) أو تعارضاً.
    للجهة الرقابية فقط — مستخدم ذو نطاق لا يملك صلاحية التدقيق الكامل.
    """
    _deny_scoped(identity)
    out = []
    for c in db.exec(select(Company)).all():
        snap = db.exec(select(CompanySnapshot)
                       .where(CompanySnapshot.company_id == c.id)
                       .order_by(CompanySnapshot.ts.desc())).first()
        agents = db.exec(select(Agent).where(Agent.company_id == c.id)).all()
        agent_sum = sum(a.users_count for a in agents)
        company_total = snap.total if snap else 0
        diff = company_total - agent_sum      # >0: مشتركون غير منسوبين لوكيل
        status = "matched"
        if diff > 0:
            status = "unattributed_subscribers"   # الشركة تذكر أكثر مما ينسبه الوكلاء
        elif diff < 0:
            status = "over_attributed"            # الوكلاء ينسبون أكثر من إجمالي الشركة
        out.append({
            "company": c.name, "code": c.code, "color": c.color,
            "agents_count": len(agents), "agent_reported_sum": agent_sum,
            "company_total": company_total, "difference": diff, "status": status,
            "last_sync_ok": c.last_sync_ok,
        })
    return {"audit": out, "count": len(out)}


# ========================= كشف الدمج (Merge findings) =========================
@router.get("/merge-findings")
def merge_findings(company_id: Optional[int] = None,
                   db: Session = Depends(get_session),
                   identity: dict = Depends(current_identity)):
    """نتائج كشف الدمج المُحتسبة من جلسات SAS (LB/Bonding/إعادة بيع).
    عزل النطاق: نطاق شركة → company_id مقيَّد؛ نطاق وكيل → إضافةً username مقيَّد."""
    scope_cid, scope_agent = scope_of(identity)

    q = select(MergeFinding)
    if scope_cid is not None:
        # فرض نطاق الشركة — نتجاهل company_id العميل
        q = q.where(MergeFinding.company_id == scope_cid)
        if scope_agent.strip():
            q = q.where(MergeFinding.username == scope_agent.strip())
    elif company_id is not None:
        q = q.where(MergeFinding.company_id == company_id)

    names = {c.id: c.name for c in db.exec(select(Company)).all()}
    rows = []
    counts = {}
    for f in db.exec(q).all():
        counts[f.kind] = counts.get(f.kind, 0) + 1
        rows.append({
            "id": f.id, "company": names.get(f.company_id, "?"),
            "company_id": f.company_id, "username": f.username,
            "kind": f.kind, "severity": f.severity,
            "session_count": f.session_count, "nas_count": f.nas_count,
            "ip_count": f.ip_count, "detail": f.detail,
            "ts": f.ts.isoformat() if f.ts else None,
        })
    return {"findings": rows, "count": len(rows), "by_kind": counts}


# ============================ المشتركون (Subscribers) ============================
@router.get("/subscribers")
def list_subscribers(company_id: Optional[int] = None, agent: Optional[str] = None,
                     status: Optional[str] = None, governorate: Optional[str] = None,
                     expiring: Optional[str] = None,
                     search: Optional[str] = None, page: int = 1, count: int = 50,
                     db: Session = Depends(get_session),
                     identity: dict = Depends(current_identity)):
    """قائمة المشتركين الحقيقيين (من SAS) مع تصفية وترقيم.
    عزل النطاق: نطاق شركة → company_id مقيَّد (تجاهل قيمة العميل)؛
                 نطاق وكيل → إضافةً agent_username مقيَّد.
    `expiring` = overdue|today|soon3|soon7 لمرشّح «قائمة التجديد» (قرب الانتهاء)."""
    scope_cid, scope_agent = scope_of(identity)

    q = select(Subscriber)
    if scope_cid is not None:
        # فرض نطاق الهوية — نتجاهل company_id من العميل كي لا يوسَّع النطاق
        q = q.where(Subscriber.company_id == scope_cid)
        if scope_agent.strip():
            # وكيل: مشتركوه فقط
            q = q.where(Subscriber.agent_username == scope_agent.strip())
        elif agent:
            # مدير شركة يصفّي بوكيل بعينه (ضمن نطاقه)
            q = q.where(Subscriber.agent_username == agent)
    else:
        # جهة رقابية: تصفية اختيارية من العميل
        if company_id is not None:
            q = q.where(Subscriber.company_id == company_id)
        if agent:
            q = q.where(Subscriber.agent_username == agent)
    if status:
        q = q.where(Subscriber.status == status)
    if governorate:
        q = q.where(Subscriber.governorate == governorate)
    rows = db.exec(q).all()
    if search:
        s = search.strip()
        rows = [r for r in rows if s in r.username or s in (r.firstname + " " + r.lastname)
                or s in r.phone]
    if expiring:                        # مرشّح «قرب الانتهاء» (قائمة التجديد)
        win = expiring.strip()
        rows = [r for r in rows if expiry_svc.in_window(expiry_svc.days_left(r.expiration), win)]
        rows.sort(key=lambda r: (expiry_svc.days_left(r.expiration) if expiry_svc.days_left(r.expiration) is not None else 1 << 30))
    total = len(rows)
    page = max(1, page); count = max(1, min(count, 500))
    start = (page - 1) * count
    names = {c.id: c.name for c in db.exec(select(Company)).all()}
    page_rows = rows[start:start + count]
    # وسم مصدر الحساب (تعدّد حسابات SAS للوكيل) — للحسابات الظاهرة في هذه الصفحة فقط
    acc_ids = {r.sas_account_id for r in page_rows if r.sas_account_id}
    acc_labels = {a.id: (a.label or a.sas_username)
                  for a in db.exec(select(SasAccount).where(SasAccount.id.in_(acc_ids))).all()} \
        if acc_ids else {}
    return {
        "total": total, "page": page, "count": count,
        "subscribers": [{
            "id": r.id,
            "company": names.get(r.company_id) or ("مواطن" if r.company_id is None else "?"),
            "company_id": r.company_id, "username": r.username,
            "name": (f"{r.firstname} {r.lastname}").strip(),
            "agent": r.agent_username, "profile": r.profile_name,
            "status": r.status, "online": r.online, "enabled": r.enabled,
            "expiration": r.expiration, "days_left": expiry_svc.days_left(r.expiration),
            "city": r.city, "governorate": r.governorate, "phone": r.phone,
            "sas_account_id": r.sas_account_id,
            "sas_account_label": acc_labels.get(r.sas_account_id, ""),
        } for r in page_rows],
    }


class SubscriberCreateIn(BaseModel):
    """إضافة مشترك (مواطن) يدوياً — هاتف + اسم فقط."""
    phone: str
    name: str = ""


@router.post("/subscribers", dependencies=_admin)
def create_subscriber(body: SubscriberCreateIn, db: Session = Depends(get_session),
                      identity: dict = Depends(current_identity)):
    """إضافة مشترك (مواطن) يدوياً بالهاتف + الاسم — للجهة الرقابية فقط.

    المشترك اليدوي بلا شركة (company_id=None) ويدخل تطبيق المشتركين عبر
    رقم الهاتف + رمز OTP واتساب (phone_norm مفتاح الدخول)."""
    _deny_scoped(identity)
    from ..services.otp import normalize_phone
    phone_norm = normalize_phone(body.phone)
    if not phone_norm:
        raise HTTPException(400, "رقم هاتف عراقي غير صالح")
    name = (body.name or "").strip()
    # منع تكرار مشترك يدوي بنفس الهاتف (بلا شركة)
    if db.exec(select(Subscriber).where(
            Subscriber.phone_norm == phone_norm,
            Subscriber.company_id.is_(None))).first():
        raise HTTPException(409, "مشترك بهذا الهاتف موجود مسبقاً")
    s = Subscriber(
        company_id=None, sub_id=0,
        firstname=name, username=phone_norm,
        phone=body.phone.strip(), phone_norm=phone_norm,
        status="manual", enabled=True,
    )
    db.add(s)
    db.commit()
    db.refresh(s)
    return {"ok": True, "id": s.id, "phone_norm": phone_norm, "name": name}


# ============================ بوابة الوكلاء — تزويد حساب دخول ============================

class AgentAccountIn(BaseModel):
    """جسم طلب إنشاء حساب وكيل — كل الحقول اختيارية."""
    username: Optional[str] = None
    role: Optional[str] = None          # viewer | operator فقط (لا admin لحساب وكيل)
    password: Optional[str] = None


@router.post("/{company_id}/agents/{agent_id}/account", dependencies=_admin)
def provision_agent_account(
    company_id: int,
    agent_id: int,
    body: AgentAccountIn,
    db: Session = Depends(get_session),
    identity: dict = Depends(current_identity),
):
    """تزويد حساب دخول لوكيل موجود.

    الصلاحية: admin + (جهة رقابية بلا نطاق) أو (مدير الشركة نفسها).
    النطاق مفروض قسراً من المعاملات — لا يُقبل من الجسم.
    """
    # تحقّق نطاق الطالب: إن كان مدير شركة أخرى → 404
    _assert_company(identity, company_id)

    # تحقّق وجود الشركة
    if not db.get(Company, company_id):
        raise HTTPException(404, "الشركة غير موجودة")

    # تحقّق وجود الوكيل وانتمائه للشركة
    agent = db.get(Agent, agent_id)
    if not agent or agent.company_id != company_id:
        raise HTTPException(404, "الوكيل غير موجود في هذه الشركة")

    # التحقّق من الدور — نسمح بـ viewer أو operator فقط (لا admin لحساب وكيل)
    _ALLOWED_ROLES = {"viewer", "operator"}
    role = (body.role or "viewer").strip()
    if role not in _ALLOWED_ROLES:
        raise HTTPException(400, f"دور غير مسموح لحساب وكيل: {role} — المسموح: viewer/operator")

    # منع تعدّد الحسابات لنفس الوكيل (فريدة على النطاق لا الاسم فقط) — تفادي حسابات شبح
    scope_agent = agent.username.strip()
    if db.exec(select(User).where(
            User.scope_company_id == company_id,
            User.scope_agent == scope_agent)).first():
        raise HTTPException(409, "للوكيل حساب دخول مسبقاً")

    # اشتقاق اسم المستخدم
    username = (body.username or "").strip() or scope_agent
    if not username:
        raise HTTPException(400, "تعذّر اشتقاق اسم مستخدم — عيّن username صراحةً")

    # التحقّق من فريدة اسم المستخدم
    if db.exec(select(User).where(User.username == username)).first():
        raise HTTPException(409, f"اسم المستخدم '{username}' مستخدم مسبقاً")

    # كلمة المرور: حدّ أدنى للتعقيد إن وُفّرت، وإلا توليد قوي (~96 بت)
    if body.password is not None and len(body.password) < 8:
        raise HTTPException(400, "كلمة المرور قصيرة — 8 محارف على الأقل")
    plain_password = body.password or secrets.token_urlsafe(12)

    # إنشاء المستخدم — النطاق مفروض قسراً (لا يُقبل من الجسم)
    new_user = User(
        username=username,
        password_hash=hash_password(plain_password),
        role=role,
        scope_company_id=company_id,           # مقيّد بالشركة — قسراً
        scope_agent=agent.username.strip(),    # مقيّد بالوكيل — قسراً
        enabled=True,
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)

    return {
        "ok": True,
        "username": new_user.username,
        "password": plain_password,            # مرّة واحدة فقط — لا يُحفظ صريحاً
        "scope_company_id": company_id,
        "scope_agent": agent.username.strip(),
    }


@router.get("/{company_id}/agents/{agent_id}/account", dependencies=_admin)
def get_agent_account(
    company_id: int,
    agent_id: int,
    db: Session = Depends(get_session),
    identity: dict = Depends(current_identity),
):
    """هل للوكيل حساب دخول؟ يُرجع {has_account, username} بلا كلمة مرور."""
    _assert_company(identity, company_id)

    if not db.get(Company, company_id):
        raise HTTPException(404, "الشركة غير موجودة")

    agent = db.get(Agent, agent_id)
    if not agent or agent.company_id != company_id:
        raise HTTPException(404, "الوكيل غير موجود في هذه الشركة")

    existing = db.exec(
        select(User).where(
            User.scope_company_id == company_id,
            User.scope_agent == agent.username.strip(),
        )
    ).first()

    return {
        "has_account": existing is not None,
        "username": existing.username if existing else None,
    }


# ============================ تصريحات الوكلاء (Agent Reports) ============================

class AgentReportIn(BaseModel):
    """جسم طلب تصريح الوكيل بعدده."""
    declared_total: int
    declared_active: int = 0
    note: str = ""


class AgentReportOut(BaseModel):
    id: int
    company_id: int
    agent_username: str
    declared_total: int
    declared_active: int
    note: str
    submitted_by: str
    ts: str

    @classmethod
    def of(cls, r: AgentReport) -> "AgentReportOut":
        return cls(
            id=r.id, company_id=r.company_id,
            agent_username=r.agent_username,
            declared_total=r.declared_total,
            declared_active=r.declared_active,
            note=r.note, submitted_by=r.submitted_by,
            ts=r.ts.isoformat(),
        )


@router.post("/{company_id}/agents/{agent_id}/report",
             response_model=AgentReportOut)
def submit_agent_report(
    company_id: int,
    agent_id: int,
    body: AgentReportIn,
    db: Session = Depends(get_session),
    identity: dict = Depends(current_identity),
):
    """تصريح الوكيل بعدد مشتركيه.

    يُسمح إمّا للوكيل نفسه (scope == (company_id, agent.username))
    أو لمدير/admin ضمن الشركة.
    يمنع وكيلاً من التصريح باسم وكيل آخر (403).
    """
    if body.declared_total < 0 or body.declared_total > 10_000_000:
        raise HTTPException(400, "declared_total خارج المدى المسموح (0 … 10,000,000)")
    if body.declared_active < 0 or body.declared_active > body.declared_total:
        raise HTTPException(400, "declared_active يجب أن يكون بين 0 و declared_total")

    # التحقّق من وجود الشركة أولاً (عزل النطاق)
    _assert_company(identity, company_id)
    if not db.get(Company, company_id):
        raise HTTPException(404, "الشركة غير موجودة")

    # التحقّق من وجود الوكيل وانتمائه للشركة
    agent = db.get(Agent, agent_id)
    if not agent or agent.company_id != company_id:
        raise HTTPException(404, "الوكيل غير موجود في هذه الشركة")

    # فرض عزل الوكيل: إن كان الطالب ذا نطاق وكيل → يجب أن يطابق الوكيل المستهدف
    scope_cid, scope_agent = scope_of(identity)
    if scope_agent.strip():
        # الطالب هو وكيل — يجب أن يصرّح عن نفسه فقط
        if scope_agent.strip() != agent.username.strip():
            raise HTTPException(403, "لا يمكن التصريح باسم وكيل آخر")

    submitted_by = identity.get("user") or "system"

    report = AgentReport(
        company_id=company_id,
        agent_username=agent.username.strip(),
        declared_total=body.declared_total,
        declared_active=body.declared_active,
        note=body.note,
        submitted_by=submitted_by,
    )
    db.add(report)
    db.commit()
    db.refresh(report)
    return AgentReportOut.of(report)


@router.get("/{company_id}/agents/{agent_id}/report",
            response_model=AgentReportOut)
def get_latest_agent_report(
    company_id: int,
    agent_id: int,
    db: Session = Depends(get_session),
    identity: dict = Depends(current_identity),
):
    """أحدث تصريح للوكيل (أو 404 إن لم يُصرّح بعد)."""
    _assert_company(identity, company_id)
    if not db.get(Company, company_id):
        raise HTTPException(404, "الشركة غير موجودة")

    agent = db.get(Agent, agent_id)
    if not agent or agent.company_id != company_id:
        raise HTTPException(404, "الوكيل غير موجود في هذه الشركة")

    # عزل الوكيل
    scope_cid, scope_agent = scope_of(identity)
    if scope_agent.strip() and scope_agent.strip() != agent.username.strip():
        raise HTTPException(403, "لا يمكن الاطلاع على تصريح وكيل آخر")

    latest = db.exec(
        select(AgentReport)
        .where(AgentReport.company_id == company_id,
               AgentReport.agent_username == agent.username.strip())
        .order_by(AgentReport.ts.desc())
    ).first()
    if not latest:
        raise HTTPException(404, "لا يوجد تصريح لهذا الوكيل بعد")
    return AgentReportOut.of(latest)


@router.get("/reconciliation")
def reconciliation(
    db: Session = Depends(get_session),
    identity: dict = Depends(current_identity),
):
    """ورقة مقاطعة: تصريح الوكيل مقابل ما تُظهره الشركة (SAS).

    العزل:
    - جهة رقابية (scope_cid=None, scope_agent=""): ترى كل الشركات.
    - مستخدم شركة (scope_cid=X, scope_agent=""): يرى وكلاء شركته فقط.
    - مستخدم وكيل (scope_cid=X, scope_agent="Y"): يرى صفّه فقط.

    الحكم (verdict):
    - no_report: لا تصريح.
    - matched: |diff| <= max(5, 5% من sas_attributed).
    - company_suspicious: الوكيل يصرّح أكثر مما تُظهره الشركة (diff > 0).
    - agent_suspicious: الوكيل يصرّح أقل (diff < 0).

    يُرجع {rows:[...], totals:{matched, company_suspicious, agent_suspicious, no_report}}.
    """
    scope_cid, scope_agent = scope_of(identity)

    # بناء استعلام الوكلاء حسب النطاق
    q = select(Agent)
    if scope_cid is not None:
        q = q.where(Agent.company_id == scope_cid)
        if scope_agent.strip():
            # وكيل: صفّه فقط
            q = q.where(Agent.username == scope_agent.strip())
    # جهة رقابية: لا قيد إضافي

    agents_list = db.exec(q).all()

    # تحميل أحدث تصريح لكل (company_id, agent_username) في دفعة واحدة
    # لتفادي N+1 queries: نسحب كل AgentReport المطابقة ثم نختار الأحدث بالذاكرة
    latest_reports: dict[tuple, AgentReport] = {}
    for ag in agents_list:
        key = (ag.company_id, ag.username.strip())
        if key not in latest_reports:
            rep = db.exec(
                select(AgentReport)
                .where(AgentReport.company_id == ag.company_id,
                       AgentReport.agent_username == ag.username.strip())
                .order_by(AgentReport.ts.desc())
            ).first()
            latest_reports[key] = rep  # قد يكون None

    # أسماء الشركات للعرض
    company_names = {c.id: c.name for c in db.exec(select(Company)).all()}

    rows = []
    totals = {"matched": 0, "company_suspicious": 0,
              "agent_suspicious": 0, "no_report": 0}

    for ag in agents_list:
        key = (ag.company_id, ag.username.strip())
        rep = latest_reports.get(key)
        sas_attributed = ag.users_count

        if rep is None:
            verdict = "no_report"
            diff = None
            declared_total = None
            declared_active = None
            last_report_ts = None
        else:
            declared_total = rep.declared_total
            declared_active = rep.declared_active
            last_report_ts = rep.ts.isoformat()
            diff = declared_total - sas_attributed
            threshold = max(5, int(sas_attributed * 0.05))
            if abs(diff) <= threshold:
                verdict = "matched"
            elif diff > 0:
                verdict = "company_suspicious"
            else:
                verdict = "agent_suspicious"

        totals[verdict] += 1
        rows.append({
            "company_id": ag.company_id,
            "company": company_names.get(ag.company_id, "?"),
            "agent_id": ag.id,
            "agent_username": ag.username,
            "agent_name": (f"{ag.firstname} {ag.lastname}").strip(),
            "sas_attributed": sas_attributed,
            "agent_declared": declared_total,
            "declared_active": declared_active,
            "diff": diff,
            "verdict": verdict,
            "last_report_ts": last_report_ts,
        })

    return {"rows": rows, "totals": totals}


@router.get("/subscribers/map")
def subscribers_map(company_id: Optional[int] = None,
                    db: Session = Depends(get_session),
                    identity: dict = Depends(current_identity)):
    """توزيع المشتركين على المحافظات (تجميعي) لطبقة الخريطة — مواقع تقريبية بمركز المحافظة.
    عزل النطاق: نطاق شركة → company_id مقيَّد؛ نطاق وكيل → إضافةً agent_username."""
    # مراكز المحافظات (متوافقة مع national._GOVERNORATES)
    from ..services import national
    centers = {name: (lat, lng) for name, _w, lat, lng in national._GOVERNORATES}
    scope_cid, scope_agent = scope_of(identity)

    q = select(Subscriber)
    if scope_cid is not None:
        # فرض نطاق الهوية — نتجاهل company_id العميل
        q = q.where(Subscriber.company_id == scope_cid)
        if scope_agent.strip():
            q = q.where(Subscriber.agent_username == scope_agent.strip())
    elif company_id is not None:
        q = q.where(Subscriber.company_id == company_id)
    agg = {}
    for r in db.exec(q).all():
        g = r.governorate or "غير محدّد"
        d = agg.setdefault(g, {"governorate": g, "total": 0, "online": 0, "active": 0})
        d["total"] += 1
        if r.online:
            d["online"] += 1
        if r.status == "active":
            d["active"] += 1
    points = []
    for g, d in agg.items():
        c = centers.get(g)
        points.append({**d, "lat": c[0] if c else None, "lng": c[1] if c else None})
    points.sort(key=lambda x: x["total"], reverse=True)
    return {"points": points, "total": sum(p["total"] for p in points)}


# ══════════════════════════════════════════════════════════════════════
# طبقات الخريطة المُصفّاة — GET /api/companies/map
# ══════════════════════════════════════════════════════════════════════

@router.get("/map")
def companies_map(
    company_id: Optional[int] = None,
    agent: Optional[str] = None,
    governorate: Optional[str] = None,
    status: Optional[str] = None,       # active | expired
    access_type: Optional[str] = None,  # ftth | wireless
    db: Session = Depends(get_session),
    identity: dict = Depends(current_identity),
):
    """طبقات الخريطة المُصفّاة (محافظات + شركات + وكلاء) بإحداثيات حقيقية من قواعد البيانات.

    عزل النطاق:
    - جهة رقابية: ترى الكل، تصفية اختيارية بالباراميترات.
    - نطاق شركة: تُقيَّد بها — باراميتر company_id يُتجاهَل إن حاول التوسّع.
    - نطاق وكيل: تُقيَّد بشركته ووكيله — agent يُتجاهَل إن حاول التوسّع.

    الاستجابة:
    {
      "governorates": [{governorate, lat, lng, total, active, online}],
      "companies":    [{company_id, company, color, governorate, lat, lng,
                        subscriber_total, access_type}],
      "agents":       [{agent, company, governorate, lat, lng, users_count}]
    }
    """
    from ..services import national as nat_svc

    # خريطة مراكز المحافظات
    centers: dict = {name: (lat, lng) for name, _w, lat, lng in nat_svc._GOVERNORATES}

    scope_cid, scope_agent = scope_of(identity)

    # ── بناء استعلام المشتركين (أساس كل الطبقات) ──
    sub_q = select(Subscriber)
    if scope_cid is not None:
        sub_q = sub_q.where(Subscriber.company_id == scope_cid)
        if scope_agent.strip():
            sub_q = sub_q.where(Subscriber.agent_username == scope_agent.strip())
    else:
        if company_id is not None:
            sub_q = sub_q.where(Subscriber.company_id == company_id)
        if agent:
            sub_q = sub_q.where(Subscriber.agent_username == agent)
    if status:
        sub_q = sub_q.where(Subscriber.status == status)
    if governorate:
        sub_q = sub_q.where(Subscriber.governorate == governorate)

    subscribers = db.exec(sub_q).all()

    # ── طبقة المحافظات ──
    gov_agg: dict = {}
    for s in subscribers:
        g = s.governorate or ""
        if not g or g not in centers:
            continue
        d = gov_agg.setdefault(g, {"governorate": g, "total": 0, "active": 0, "online": 0})
        d["total"] += 1
        if s.status == "active":
            d["active"] += 1
        if s.online:
            d["online"] += 1
    governorates_layer = []
    for g, d in gov_agg.items():
        lat, lng = centers[g]
        governorates_layer.append({**d, "lat": lat, "lng": lng})
    governorates_layer.sort(key=lambda x: x["total"], reverse=True)

    # ── طبقة الشركات (كل شركة عند مركز محافظتها) ──
    # نحتاج الشركات المرئيّة ضمن النطاق
    comp_q = select(Company)
    if scope_cid is not None:
        comp_q = comp_q.where(Company.id == scope_cid)
    elif company_id is not None:
        comp_q = comp_q.where(Company.id == company_id)
    if access_type:
        comp_q = comp_q.where(Company.access_type == access_type)
    if governorate:
        comp_q = comp_q.where(Company.governorate == governorate)

    # تجميع عدد المشتركين لكل شركة من سجلات المشتركين المفلترة
    subs_by_company: dict = {}
    for s in subscribers:
        subs_by_company[s.company_id] = subs_by_company.get(s.company_id, 0) + 1

    companies_layer = []
    for c in db.exec(comp_q).all():
        gov_name = c.governorate or ""
        lat, lng = centers.get(gov_name, (None, None))
        if lat is None:
            continue  # محافظة غير معروفة → تجاهل
        companies_layer.append({
            "company_id": c.id,
            "company": c.name,
            "color": c.color,
            "governorate": gov_name,
            "lat": lat,
            "lng": lng,
            "subscriber_total": subs_by_company.get(c.id, 0),
            "access_type": c.access_type,
        })

    # ── طبقة الوكلاء (كل وكيل عند مركز المحافظة الغالبة لمشتركيه) ──
    agent_q = select(Agent)
    if scope_cid is not None:
        agent_q = agent_q.where(Agent.company_id == scope_cid)
        if scope_agent.strip():
            agent_q = agent_q.where(Agent.username == scope_agent.strip())
    else:
        if company_id is not None:
            agent_q = agent_q.where(Agent.company_id == company_id)
        if agent:
            agent_q = agent_q.where(Agent.username == agent)

    # المحافظة الغالبة لمشتركي كل وكيل
    agent_gov_counts: dict = {}   # {agent_username: {gov: count}}
    for s in subscribers:
        au = s.agent_username.strip()
        if not au:
            continue
        g = s.governorate or ""
        if g not in centers:
            continue
        agent_gov_counts.setdefault(au, {})
        agent_gov_counts[au][g] = agent_gov_counts[au].get(g, 0) + 1

    company_names = {c.id: c.name for c in db.exec(select(Company)).all()}
    company_govs = {c.id: c.governorate for c in db.exec(select(Company)).all()}

    agents_layer = []
    for ag in db.exec(agent_q).all():
        ag_gov_map = agent_gov_counts.get(ag.username.strip(), {})
        if ag_gov_map:
            dominant_gov = max(ag_gov_map, key=lambda g: ag_gov_map[g])
        else:
            dominant_gov = company_govs.get(ag.company_id, "")
        if not dominant_gov or dominant_gov not in centers:
            continue
        lat, lng = centers[dominant_gov]
        agents_layer.append({
            "agent": ag.username,
            "company": company_names.get(ag.company_id, "?"),
            "governorate": dominant_gov,
            "lat": lat,
            "lng": lng,
            "users_count": ag.users_count,
        })

    return {
        "governorates": governorates_layer,
        "companies": companies_layer,
        "agents": agents_layer,
    }


# ══════════════════════════════════════════════════════════════════════
# طبقات GIS (ألياف/مسارات) — رفع + قراءة + حذف
# ══════════════════════════════════════════════════════════════════════

def _parse_kml_to_geojson(content: bytes) -> dict:
    """يحوّل KML بسيط (LineString/Point/Polygon) إلى GeoJSON FeatureCollection.
    يتعامل مع namespace KML القياسي."""
    try:
        # utf-8-sig: يزيل BOM إن وُجد (شائع في تصدير QGIS/أدوات ويندوز)
        root = _safe_fromstring(content.decode("utf-8-sig", errors="replace"))
    except DefusedXmlException:
        # DTD/كيانات داخلية (billion-laughs) أو مرجع خارجي — رفض قاطع
        raise HTTPException(400, "ملف KML يحتوي بنية غير مسموحة (DTD/كيانات)")
    except ET.ParseError as e:
        raise HTTPException(400, f"ملف KML تالف: {e}")

    ns = {"k": _KML_NS}

    def _coords_text(elem) -> Optional[str]:
        """يُعيد نص إحداثيات أول coordinates وجدها تحت elem."""
        c = elem.find(".//k:coordinates", ns)
        if c is None:
            # بعض الملفات بلا namespace
            c = elem.find(".//coordinates")
        return (c.text or "").strip() if c is not None else None

    def _parse_coords(text: str) -> list:
        """يحوّل نص KML «lng,lat,alt» إلى [[lng, lat], ...]."""
        pts = []
        for tok in text.split():
            parts = tok.strip().split(",")
            if len(parts) >= 2:
                try:
                    pts.append([float(parts[0]), float(parts[1])])
                except ValueError:
                    pass
        return pts

    features = []

    def _handle_placemark(pm):
        # نسحب أي شكل هندسي (LineString/Point/Polygon)
        for geom_tag, geom_type in [
            ("k:LineString", "LineString"),
            ("k:Point", "Point"),
            ("k:Polygon", "Polygon"),
        ]:
            geom_elem = pm.find(geom_tag, ns)
            if geom_elem is None:
                geom_elem = pm.find(geom_tag.split(":")[-1])  # بلا namespace
            if geom_elem is None:
                continue
            raw = _coords_text(geom_elem)
            if not raw:
                continue
            pts = _parse_coords(raw)
            if not pts:
                continue
            if geom_type == "Point":
                geometry = {"type": "Point", "coordinates": pts[0]}
            elif geom_type == "LineString":
                geometry = {"type": "LineString", "coordinates": pts}
            else:  # Polygon
                geometry = {"type": "Polygon", "coordinates": [pts]}
            name_elem = pm.find("k:name", ns)
            if name_elem is None:
                name_elem = pm.find("name")
            name_val = name_elem.text if name_elem is not None else ""
            features.append({
                "type": "Feature",
                "geometry": geometry,
                "properties": {"name": name_val},
            })
            break  # أول شكل هندسي لكل Placemark

    # بحث متكرّر في كل Placemark ضمن المستند
    for pm in root.iter("{%s}Placemark" % _KML_NS):
        _handle_placemark(pm)
    if not features:
        # محاولة بلا namespace
        for pm in root.iter("Placemark"):
            _handle_placemark(pm)

    return {"type": "FeatureCollection", "features": features}


def _validate_geojson(data: dict) -> dict:
    """يتحقّق أن البيانات FeatureCollection أو Feature ويُطبيع إلى FeatureCollection."""
    t = data.get("type")
    if t == "FeatureCollection":
        if not isinstance(data.get("features"), list):
            raise HTTPException(400, "GeoJSON FeatureCollection يحتاج مصفوفة features")
        return data
    if t == "Feature":
        return {"type": "FeatureCollection", "features": [data]}
    raise HTTPException(400, f"نوع GeoJSON غير مدعوم: {t!r} — يجب FeatureCollection أو Feature")


_HTML_TAG_RE = re.compile(r"<[^>]*>")


def _sanitize_properties(fc: dict) -> None:
    """تعقيم خصائص كل ميزة: allow-list للقيم السكالر + قصّ الأطوال + تجريد وسوم
    HTML. دفاع في العمق ضد Stored XSS لو عُرضت الطبقة في أي واجهة ويب، ويحدّ
    تضخيم التخزين (عدد مفاتيح/طول محدود)."""
    for feat in fc.get("features", []):
        if not isinstance(feat, dict):
            continue
        props = feat.get("properties")
        if not isinstance(props, dict):
            feat["properties"] = {}
            continue
        clean: dict = {}
        for k, val in list(props.items())[:20]:  # حدّ عدد المفاتيح
            if not isinstance(k, str) or len(k) > 60:
                continue
            if isinstance(val, str):
                clean[k] = _HTML_TAG_RE.sub("", val)[:200]
            elif isinstance(val, (int, float, bool)) or val is None:
                clean[k] = val
        feat["properties"] = clean


def _validate_coords(fc: dict) -> None:
    """تحقّق سريع أن الإحداثيات في النطاق المعقول (−180..180 lng, −90..90 lat)."""
    for feat in fc.get("features", []):
        geom = feat.get("geometry") or {}
        coords_raw = geom.get("coordinates")
        if coords_raw is None:
            continue
        # نسطّح إلى قائمة نقاط
        def _flat(c):
            if not c:
                return
            if isinstance(c[0], (int, float)):
                yield c
            else:
                for sub in c:
                    yield from _flat(sub)
        for pt in _flat(coords_raw):
            if len(pt) >= 2:
                lng_v, lat_v = pt[0], pt[1]
                if not (-180 <= lng_v <= 180) or not (-90 <= lat_v <= 90):
                    raise HTTPException(400,
                        f"إحداثيات خارج النطاق: lng={lng_v}, lat={lat_v}")


def _layer_meta(lyr: GisLayer) -> dict:
    """بيانات وصفية موحّدة لطبقة GIS (بلا GeoJSON)."""
    return {
        "id": lyr.id,
        "name": lyr.name,
        "group_name": lyr.group_name,
        "kind": lyr.kind,
        "company_id": lyr.company_id,
        "feature_count": lyr.feature_count,
        "created_at": lyr.created_at.isoformat(),
    }


@router.post("/gis-layers", dependencies=_admin)
async def upload_gis_layer(
    name: str = Form(...),
    kind: str = Form(default="fiber"),
    group: str = Form(default=""),
    company_id: Optional[int] = Form(default=None),
    file: UploadFile = File(...),
    db: Session = Depends(get_session),
    identity: dict = Depends(current_identity),
):
    """رفع طبقة GIS (GeoJSON أو KML) وتخزينها محوَّلةً إلى GeoJSON.

    - `group`: المستوى/المجموعة الحرّة (اسم يدوي — شركة، «الباك بون»، أي تصنيف).
      عدّة ملفات بنفس الاسم = طبقات ضمن نفس المستوى.
    - admin رقابي → يرفع طبقة عامّة (company_id=None) أو مرتبطة بشركة (للعزل).
    - admin شركة → يرفع لشركته فقط (company_id يُفرض قسراً من النطاق).
    - _deny_scoped: لا يُسمح لوكيل بالرفع.
    """
    scope_cid, scope_agent = scope_of(identity)
    if scope_agent.strip():
        raise HTTPException(403, "رفع الطبقات للمديرين فقط")

    # فرض نطاق الشركة: مدير شركة لا يرفع طبقة لشركة أخرى
    if scope_cid is not None:
        company_id = scope_cid  # override
    comp = None
    if company_id is not None:
        comp = db.get(Company, company_id)
        if not comp:
            raise HTTPException(404, "الشركة غير موجودة")

    # المستوى/المجموعة: نصّ حرّ (مُجرّد من وسوم HTML، محدود الطول)؛
    # افتراضياً اسم الشركة إن رُبطت، وإلا «عامّة».
    group_name = _HTML_TAG_RE.sub("", group.strip())[:120] or (
        comp.name if comp else "عامّة")

    # قراءة الملف مع حد الحجم
    raw = await file.read(_GIS_MAX_BYTES + 1)
    if len(raw) > _GIS_MAX_BYTES:
        raise HTTPException(400, "حجم الملف يتجاوز 10 ميغابايت")
    if not raw:
        raise HTTPException(400, "الملف فارغ")

    filename = (file.filename or "").lower()

    # ── تحديد النوع وتحويله ──
    if filename.endswith(".kml"):
        fc = _parse_kml_to_geojson(raw)
    elif filename.endswith((".geojson", ".json")):
        try:
            data = json.loads(raw.decode("utf-8-sig", errors="replace"))
        except json.JSONDecodeError as e:
            raise HTTPException(400, f"GeoJSON تالف: {e}")
        fc = _validate_geojson(data)
    elif filename.endswith((".shp", ".zip")):
        raise HTTPException(
            400,
            "Shapefile غير مدعوم مباشرةً — حوّل إلى GeoJSON من QGIS "
            "(Layer → Export → Save Features As → GeoJSON)."
        )
    else:
        raise HTTPException(
            400,
            "امتداد غير معروف — استخدم .geojson أو .json أو .kml"
        )

    _validate_coords(fc)
    _sanitize_properties(fc)
    feature_count = len(fc.get("features", []))

    layer = GisLayer(
        name=name.strip() or filename,
        group_name=group_name,
        kind=kind.strip() or "fiber",
        company_id=company_id,
        geojson=json.dumps(fc, ensure_ascii=False),
        feature_count=feature_count,
    )
    db.add(layer)
    db.commit()
    db.refresh(layer)

    return _layer_meta(layer)


@router.get("/gis-layers")
def list_gis_layers(
    db: Session = Depends(get_session),
    identity: dict = Depends(current_identity),
):
    """قائمة طبقات GIS (بيانات وصفية بلا GeoJSON) — بعزل النطاق.

    - جهة رقابية: كل الطبقات (عامّة + مرتبطة).
    - نطاق شركة: الطبقات العامّة + طبقات شركتها.
    - نطاق وكيل: الطبقات العامّة + طبقات شركته.
    """
    scope_cid, _scope_agent = scope_of(identity)
    layers = db.exec(select(GisLayer)).all()

    result = []
    for lyr in layers:
        # طبقة عامّة → للجميع
        if lyr.company_id is None:
            visible = True
        elif scope_cid is None:
            # جهة رقابية → ترى كل الطبقات
            visible = True
        else:
            visible = (lyr.company_id == scope_cid)
        if not visible:
            continue
        result.append(_layer_meta(lyr))
    return {"layers": result, "count": len(result)}


@router.get("/gis-layers/{layer_id}")
def get_gis_layer(
    layer_id: int,
    db: Session = Depends(get_session),
    identity: dict = Depends(current_identity),
):
    """يُرجع GeoJSON كاملاً للطبقة — بعزل النطاق."""
    scope_cid, _scope_agent = scope_of(identity)
    lyr = db.get(GisLayer, layer_id)
    if not lyr:
        raise HTTPException(404, "الطبقة غير موجودة")
    # فحص الصلاحية
    if lyr.company_id is not None and scope_cid is not None and lyr.company_id != scope_cid:
        raise HTTPException(404, "الطبقة غير موجودة")
    try:
        fc = json.loads(lyr.geojson)
    except json.JSONDecodeError:
        fc = {"type": "FeatureCollection", "features": []}
    return {**_layer_meta(lyr), "geojson": fc}


@router.delete("/gis-layers/{layer_id}", dependencies=_admin)
def delete_gis_layer(
    layer_id: int,
    db: Session = Depends(get_session),
    identity: dict = Depends(current_identity),
):
    """حذف طبقة GIS — admin (رقابي: أي طبقة؛ مدير شركة: طبقات شركته فقط)."""
    scope_cid, scope_agent = scope_of(identity)
    if scope_agent.strip():
        raise HTTPException(403, "حذف الطبقات للمديرين فقط")
    lyr = db.get(GisLayer, layer_id)
    if not lyr:
        raise HTTPException(404, "الطبقة غير موجودة")
    if scope_cid is not None and lyr.company_id != scope_cid:
        raise HTTPException(404, "الطبقة غير موجودة")
    db.delete(lyr)
    db.commit()
    return {"ok": True}


# ══════════════════════════════════════════════════════════════════════
# العنونة الوطنية NAS-IQ: ترقيم تلقائي للطبقة + encode/reverse
# ══════════════════════════════════════════════════════════════════════

# حدود الترقيم (حماية من DoS — مستقلّة عن حدّ حجم الرفع)
_MAX_NUMBER_FEATURES = 50_000            # أقصى عدد ميزات في طبقة واحدة للترقيم
_MAX_STREET_PRODUCT = 5_000_000          # سقف (مبانٍ × شوارع) لترقيم الشوارع


class NumberLayerRequest(BaseModel):
    gov_code: Optional[int] = None   # كود المحافظة (10, 31, …)
    gov: Optional[str] = None        # أو اسمها (يُحوَّل لكود)
    street_layer_id: Optional[int] = None  # طبقة محاور شوارع (لترقيم الدور)
    auto_streets: bool = False       # استيراد محاور الشوارع من OSM تلقائياً


@router.post("/gis-layers/{layer_id}/number", dependencies=_admin)
def number_gis_layer(
    layer_id: int,
    body: NumberLayerRequest,
    db: Session = Depends(get_session),
    identity: dict = Depends(current_identity),
):
    """ترقيم تلقائي لمباني الطبقة: NPN + IQ-Pin (+ رقم دار عند تمرير طبقة شوارع).

    admin فقط؛ مدير الشركة مقيّد بطبقات شركته/العامّة. النتائج تُكتب في خصائص
    كل ميزة داخل geojson الطبقة (النظام الوطني للعنونة الرقمية NAS-IQ).
    """
    scope_cid, scope_agent = scope_of(identity)
    if scope_agent.strip():
        raise HTTPException(403, "الترقيم للمديرين فقط")
    lyr = db.get(GisLayer, layer_id)
    if not lyr:
        raise HTTPException(404, "الطبقة غير موجودة")
    # عزل: مدير الشركة يُرقّم طبقات شركته فقط (لا العامّة المشتركة ولا غيرها)
    if scope_cid is not None and lyr.company_id != scope_cid:
        raise HTTPException(404, "الطبقة غير موجودة")
    if (lyr.feature_count or 0) > _MAX_NUMBER_FEATURES:
        raise HTTPException(
            413, f"الطبقة تتجاوز حدّ الترقيم ({_MAX_NUMBER_FEATURES} ميزة)")

    gov_code = body.gov_code
    if gov_code is None and body.gov:
        gov_code = addr.gov_code_for(body.gov)
    if not gov_code or not (1 <= gov_code <= 99):
        raise HTTPException(400, "حدّد محافظة صالحة (gov_code أو gov)")

    street_layer = None
    if body.street_layer_id is not None:
        street_layer = db.get(GisLayer, body.street_layer_id)
        if not street_layer:
            raise HTTPException(404, "طبقة الشوارع غير موجودة")
        if scope_cid is not None and street_layer.company_id != scope_cid:
            raise HTTPException(404, "طبقة الشوارع غير موجودة")
        # سقف تربيعي: مبانٍ × مقاطع شوارع
        if (lyr.feature_count or 0) * (street_layer.feature_count or 0) > _MAX_STREET_PRODUCT:
            raise HTTPException(
                400, "حجم (المباني × الشوارع) كبير جداً لترقيم الشوارع")

    # استيراد شوارع OSM تلقائياً (أفضل-جهد) إن طُلب ولم تُمرَّر طبقة شوارع
    if street_layer is None and body.auto_streets:
        try:
            imported = addressing_service.import_streets_layer(db, lyr)
            if imported and (lyr.feature_count or 0) * (imported.feature_count or 0) <= _MAX_STREET_PRODUCT:
                street_layer = imported
        except ValueError:
            street_layer = None  # نُكمل بـ NPN+IQ-Pin فقط

    return addressing_service.number_layer(db, lyr, gov_code, street_layer)


@router.post("/gis-layers/{layer_id}/import-streets", dependencies=_admin)
def import_streets(
    layer_id: int,
    db: Session = Depends(get_session),
    identity: dict = Depends(current_identity),
):
    """ينشئ طبقة محاور شوارع من OSM تغطّي امتداد طبقة المباني (لترقيم الدور)."""
    scope_cid, scope_agent = scope_of(identity)
    if scope_agent.strip():
        raise HTTPException(403, "الاستيراد للمديرين فقط")
    lyr = db.get(GisLayer, layer_id)
    if not lyr:
        raise HTTPException(404, "الطبقة غير موجودة")
    if scope_cid is not None and lyr.company_id != scope_cid:
        raise HTTPException(404, "الطبقة غير موجودة")
    try:
        street = addressing_service.import_streets_layer(db, lyr)
    except ValueError as e:
        raise HTTPException(400, str(e))
    return _layer_meta(street)


_DEMO_NAMES = [
    "أحمد علي", "محمد حسن", "علي حسين", "فاطمة كاظم", "زينب عبد الله",
    "عمر خالد", "يوسف إبراهيم", "كريم جبار", "سارة نوري", "نور الدين صالح",
    "ليلى حميد", "مصطفى وليد", "حيدر عباس", "مريم سعد", "عبد الله فاضل",
    "رقية ماجد", "حسن طارق", "زهراء علاء", "باقر منعم", "دعاء رعد",
]


def _demo_houses_fc(rng: random.Random):
    """يولّد شبكة منازل تجريبية (نقاط) في حيّ ببغداد، كلٌّ بمشترك (اسم/حالة/خدمة)."""
    base_lat, base_lon = 33.3120, 44.3600
    step = 0.00045  # ~50م بين المنازل
    feats = []
    for r in range(6):
        for c in range(7):
            lat = base_lat + r * step + rng.uniform(-8e-5, 8e-5)
            lon = base_lon + c * step + rng.uniform(-8e-5, 8e-5)
            active = rng.random() < 0.7
            feats.append({
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [lon, lat]},
                "properties": {
                    "subscriber": rng.choice(_DEMO_NAMES),
                    "status": "active" if active else "expired",
                    "service": "FTTH",
                    "phone": f"07{rng.choice([70, 71, 50, 51])}{rng.randint(1000000, 9999999)}",
                    "speed_mbps": rng.choice([20, 40, 60, 100]),
                },
            })
    center = {"lat": base_lat + 2.5 * step, "lon": base_lon + 3 * step}
    return {"type": "FeatureCollection", "features": feats}, center


@router.post("/gis-layers/demo-houses", dependencies=_admin)
def create_demo_houses(
    db: Session = Depends(get_session),
    identity: dict = Depends(current_identity),
):
    """ينشئ طبقة «منازل تجريبية» (مشتركون على منازل مرقّمة) — لعرض ربط المشترك
    بالعقار (جوهر NAS-IQ). المنازل تُرقّم تلقائياً (NPN + IQ-Pin)."""
    scope_cid, scope_agent = scope_of(identity)
    if scope_agent.strip():
        raise HTTPException(403, "الإنشاء للمديرين فقط")
    rng = random.Random(20260908)
    fc, center = _demo_houses_fc(rng)
    layer = GisLayer(
        name="منازل تجريبية",
        group_name="منازل تجريبية",
        kind="house",
        company_id=scope_cid,
        geojson=json.dumps(fc, ensure_ascii=False),
        feature_count=len(fc["features"]),
    )
    db.add(layer)
    db.commit()
    db.refresh(layer)
    addressing_service.number_layer(db, layer, 10)  # كتلة بغداد
    return {**_layer_meta(layer), "center": center}


@router.get("/addressing/encode")
def addressing_encode(lat: float, lon: float):
    """يحوّل إحداثيات إلى IQ-Pin (رمز شبكي، دقّة ~1م)."""
    if not addr.in_iraq_box(lat, lon):
        raise HTTPException(400, "الإحداثيات خارج صندوق العراق")
    pin = addr.iqpin_encode(lat, lon)
    return {"iqpin": pin, "iqpin_display": addr.iqpin_display(pin),
            "lat": lat, "lon": lon}


@router.get("/addressing/reverse")
def addressing_reverse(code: str):
    """يحوّل IQ-Pin إلى مركز الخلية (lat, lon) — للطوارئ/الملاحة."""
    if len(code.replace("-", "")) > 16:      # حدّ طول (منع DoS رخيص)
        raise HTTPException(400, "رمز IQ-Pin طويل غير صالح")
    try:
        lat, lon = addr.iqpin_decode(code)
    except ValueError as e:
        raise HTTPException(400, str(e))
    return {"lat": lat, "lon": lon, "iqpin_display": addr.iqpin_display(code)}
