"""
بوابة المشترك عبر SAS — مسارات /api/subscriber/sas/*.

يدخل المشترك التطبيق بـ OTP (انظر subscriber.py). هذا الراوتر يمنحه بيانات وعمليات
بوابته في SAS، بمصدرٍ مزدوج (قرار «الاثنان معاً»):
  - **مربوط**: عبر بوابته الحقيقية (SASUserClient على /user/api) بعد ربط اعتماده مرة واحدة.
  - **غير مربوط**: عرضٌ فقط عبر واجهة الإدارة (SASClient) بحساب مدير الشركة، مصفّىً على
    معرّف المشترك (sub_id/username). العمليات الكتابية تتطلّب الربط دائماً.

الأمان:
  - `require_subscriber`: توكن OTP فقط (توكنات الموظّفين مرفوضة).
  - `_owned_account`: المشترك لا يمسّ إلا حساباً يطابق رقم هاتفه (phone_norm).
  - لا بروكسي مسار حرّ للمشترك — الدوال المسمّاة في العميلين هي القائمة البيضاء.
  - `_redact`: حجب أي أسرار (كلمات مرور/nas_details/pin) قبل الإرجاع.
  - `transaction_id` فريد يمنع تكرار العمليات المالية (409).
"""
from __future__ import annotations

import re
from contextlib import asynccontextmanager
from typing import Any, Optional

from fastapi import APIRouter, Body, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlmodel import Session, select

from ..core import security
from ..core.auth import require_subscriber
from ..database import get_session
from ..integrations.sas_client import SASClient, SASError
from ..integrations.sas_user_client import SASUserClient
from ..models import Company, SasPortalAudit, Subscriber

router = APIRouter(prefix="/api/subscriber/sas", tags=["subscriber-portal"])


# ─────────────────────────────── مساعدات ───────────────────────────────

def _owned_account(db: Session, identity: dict, account_id: int) -> Subscriber:
    """يُرجع حساب المشترك بعد التأكّد أنه يخصّ رقم هاتفه (وإلا 404)."""
    acc = db.get(Subscriber, account_id)
    if not acc or acc.phone_norm != identity.get("phone"):
        raise HTTPException(404, "الحساب غير موجود أو لا يخصّ هذا الرقم")
    return acc


def _company_or_400(db: Session, acc: Subscriber) -> Company:
    c = db.get(Company, acc.company_id) if acc.company_id else None
    if not c or not c.sas_host:
        raise HTTPException(400, "شركتك لم تضبط اتصال SAS بعد")
    return c


def _linked(acc: Subscriber) -> bool:
    return bool(acc.sas_username and acc.sas_password_enc)


def _require_linked(acc: Subscriber) -> None:
    if not _linked(acc):
        raise HTTPException(409, "هذه العملية تتطلّب ربط حساب بوابة SAS أولاً (من «ربط الحساب»)")


_SECRET_KEYS = re.compile(r"(password|secret|api_password|snmp_community|nas_details|\bpin\b)", re.I)


def _redact(obj: Any) -> Any:
    """حجب المفاتيح الحسّاسة تكرارياً قبل إرجاع بيانات SAS للمشترك."""
    if isinstance(obj, dict):
        return {k: ("***" if _SECRET_KEYS.search(str(k)) else _redact(v)) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_redact(x) for x in obj]
    return obj


async def _guard(coro):
    try:
        return await coro
    except SASError as e:
        raise HTTPException(502, f"SAS: {e}")
    except HTTPException:
        raise
    except Exception as e:  # noqa: BLE001
        raise HTTPException(502, f"تعذّر الاتصال بـ SAS: {e}")


@asynccontextmanager
async def _portal(company: Company, acc: Subscriber):
    """عميل بوابة المشترك باعتماده المخزَّن المفكوك."""
    pwd = security.decrypt(acc.sas_password_enc) if acc.sas_password_enc else ""
    async with SASUserClient(company.sas_host, acc.sas_username, pwd,
                             https=company.sas_https, verify_tls=company.sas_verify_tls) as p:
        yield p


@asynccontextmanager
async def _admin(company: Company):
    """عميل إداري بحساب مدير الشركة (لمسار العرض دون ربط)."""
    pwd = security.decrypt(company.sas_password_enc) if company.sas_password_enc else ""
    async with SASClient(company.sas_host, company.sas_username, pwd,
                         https=company.sas_https, verify_tls=company.sas_verify_tls) as s:
        yield s


def _unwrap(res: Any) -> Any:
    return res.get("data", res) if isinstance(res, dict) else res


def _check_txid(db: Session, txid: Optional[str]) -> None:
    if txid and db.exec(select(SasPortalAudit)
                        .where(SasPortalAudit.transaction_id == txid)).first():
        raise HTTPException(409, "هذه العملية نُفّذت مسبقاً (معرّف المعاملة مكرّر)")


def _audit(db: Session, acc: Subscriber, action: str,
           txid: Optional[str], status: str, detail: str = "") -> None:
    db.add(SasPortalAudit(account_id=acc.id, action=action,
                          transaction_id=(txid or None), status=status, detail=detail[:500]))
    db.commit()


# ─────────────────────────── الربط (مرة واحدة) ───────────────────────────

class LinkIn(BaseModel):
    account_id: int
    sas_username: str = Field(min_length=1, max_length=128)
    sas_password: str = Field(min_length=1, max_length=256)


@router.post("/link")
async def link_account(body: LinkIn, identity: dict = Depends(require_subscriber),
                       db: Session = Depends(get_session)):
    """ربط اعتماد بوابة SAS بحساب المشترك (يُختبر الدخول قبل الحفظ)."""
    acc = _owned_account(db, identity, body.account_id)
    company = _company_or_400(db, acc)
    try:
        async with SASUserClient(company.sas_host, body.sas_username, body.sas_password,
                                 https=company.sas_https, verify_tls=company.sas_verify_tls) as p:
            await p.dashboard()                       # تأكيد أن الاعتماد يعمل فعلاً
    except SASError as e:
        raise HTTPException(400, f"فشل الدخول لبوابة SAS — تحقّق من بياناتك: {e}")
    except Exception as e:  # noqa: BLE001
        raise HTTPException(502, f"تعذّر الاتصال ببوابة SAS: {e}")
    acc.sas_username = body.sas_username
    acc.sas_password_enc = security.encrypt(body.sas_password)
    db.add(acc); db.commit()
    _audit(db, acc, "link", None, "ok")
    return {"linked": True, "sas_username": acc.sas_username}


@router.get("/link/{account_id}")
async def link_status(account_id: int, identity: dict = Depends(require_subscriber),
                      db: Session = Depends(get_session)):
    """حالة الربط (بلا كشف كلمة المرور)."""
    acc = _owned_account(db, identity, account_id)
    return {"linked": _linked(acc), "sas_username": acc.sas_username or ""}


@router.delete("/link/{account_id}")
async def unlink_account(account_id: int, identity: dict = Depends(require_subscriber),
                         db: Session = Depends(get_session)):
    """فكّ الربط ومسح الاعتماد المخزَّن."""
    acc = _owned_account(db, identity, account_id)
    acc.sas_username = ""
    acc.sas_password_enc = ""
    db.add(acc); db.commit()
    return {"linked": False}


# ─────────────────────────── العرض (مصدر مزدوج) ───────────────────────────

async def _display(db: Session, acc: Subscriber, kind: str, **kw) -> Any:
    """يجلب بيانات عرض المشترك من بوابته (إن مربوط) وإلا من واجهة الإدارة مصفّاةً عليه."""
    company = _company_or_400(db, acc)
    if _linked(acc):
        async with _portal(company, acc) as p:
            if kind == "balance":
                return _redact(_unwrap(await _guard(p.dashboard())))
            if kind == "invoices":
                return _redact(await _guard(p.invoices(page=kw.get("page", 1))))
            if kind == "sessions":
                return _redact(await _guard(p.sessions()))
            if kind == "traffic":
                return _redact(_unwrap(await _guard(
                    p.traffic(month=kw.get("month"), year=kw.get("year")))))
            if kind == "packages":
                return _redact(_unwrap(await _guard(p.packages())))
    # مسار العرض دون ربط: واجهة الإدارة بحساب الشركة، مصفّىً على معرّف المشترك
    if not (company.sas_username and company.sas_password_enc):
        raise HTTPException(409, "اربط حساب بوابة SAS لعرض هذه البيانات (أو لم تُضبط بيانات شركتك)")
    uid = acc.sub_id
    uname = acc.username
    async with _admin(company) as s:
        if kind == "balance":
            return _redact(_unwrap(await _guard(s.get(f"user/overview/{uid}"))))
        if kind == "invoices":                        # أقرب مكافئ إداري: دفتر القيود المالية
            return _redact(await _guard(s.post(f"index/UserJournal/{uid}",
                {"page": kw.get("page", 1), "count": 20, "sortBy": "id", "direction": "desc"})))
        if kind == "sessions":
            res = await _guard(s.online(page=1, count=200, search=uname))
            rows = res.get("data", res) if isinstance(res, dict) else res
            rows = [r for r in (rows or []) if str(r.get("username") or "") == uname]
            return _redact({"data": rows, "total": len(rows)})
        if kind == "traffic":
            return _redact(_unwrap(await _guard(s.post("user/traffic",
                {"user_id": uid, "report_type": "daily",
                 "month": kw.get("month"), "year": kw.get("year")}))))
        if kind == "packages":
            return _redact(_unwrap(await _guard(s.profiles())))
    raise HTTPException(400, "نوع عرض غير معروف")


@router.get("/{account_id}/balance")
async def portal_balance(account_id: int, identity: dict = Depends(require_subscriber),
                         db: Session = Depends(get_session)):
    return await _display(db, _owned_account(db, identity, account_id), "balance")


@router.get("/{account_id}/invoices")
async def portal_invoices(account_id: int, page: int = 1,
                          identity: dict = Depends(require_subscriber),
                          db: Session = Depends(get_session)):
    return await _display(db, _owned_account(db, identity, account_id), "invoices", page=page)


@router.get("/{account_id}/sessions")
async def portal_sessions(account_id: int, identity: dict = Depends(require_subscriber),
                          db: Session = Depends(get_session)):
    return await _display(db, _owned_account(db, identity, account_id), "sessions")


@router.get("/{account_id}/traffic")
async def portal_traffic(account_id: int, month: Optional[int] = None, year: Optional[int] = None,
                         identity: dict = Depends(require_subscriber),
                         db: Session = Depends(get_session)):
    return await _display(db, _owned_account(db, identity, account_id), "traffic",
                          month=month, year=year)


@router.get("/{account_id}/packages")
async def portal_packages(account_id: int, identity: dict = Depends(require_subscriber),
                          db: Session = Depends(get_session)):
    return await _display(db, _owned_account(db, identity, account_id), "packages")


# ─────────────────────────── عمليات كتابية (تتطلّب ربطاً) ───────────────────────────

class ChangePwIn(BaseModel):
    new_password: str = Field(min_length=1, max_length=256)
    current_password: Optional[str] = None
    transaction_id: Optional[str] = None


class RedeemIn(BaseModel):
    pin: str = Field(min_length=1, max_length=64)
    transaction_id: str = Field(min_length=1, max_length=64)   # مالي → مطلوب


class ChangeSubIn(BaseModel):
    new_service: Any
    current_password: Optional[str] = None
    transaction_id: str = Field(min_length=1, max_length=64)   # مالي → مطلوب


class ExtendIn(BaseModel):
    profile_id: Any
    current_password: Optional[str] = None
    transaction_id: str = Field(min_length=1, max_length=64)


class ActivateIn(BaseModel):
    uuid: str = Field(min_length=1, max_length=64)             # يمنع التكرار (من الواجهة)
    current_password: Optional[str] = None


@router.post("/{account_id}/change-password")
async def portal_change_password(account_id: int, body: ChangePwIn,
                                 identity: dict = Depends(require_subscriber),
                                 db: Session = Depends(get_session)):
    acc = _owned_account(db, identity, account_id)
    _require_linked(acc)
    company = _company_or_400(db, acc)
    _check_txid(db, body.transaction_id)
    try:
        async with _portal(company, acc) as p:
            res = await p.change_password(body.new_password, body.current_password or True)
    except SASError as e:
        _audit(db, acc, "change_password", body.transaction_id, "failed", str(e))
        raise HTTPException(502, f"بوابة SAS: {e}")
    # حدّث الاعتماد المخزَّن كي لا يفشل الدخول بعد التغيير
    acc.sas_password_enc = security.encrypt(body.new_password)
    db.add(acc); db.commit()
    _audit(db, acc, "change_password", body.transaction_id, "ok")
    return {"ok": True, "result": res}


@router.post("/{account_id}/redeem")
async def portal_redeem(account_id: int, body: RedeemIn,
                        identity: dict = Depends(require_subscriber),
                        db: Session = Depends(get_session)):
    acc = _owned_account(db, identity, account_id)
    _require_linked(acc)
    company = _company_or_400(db, acc)
    _check_txid(db, body.transaction_id)
    try:
        async with _portal(company, acc) as p:
            res = await p.redeem(body.pin)
    except SASError as e:
        _audit(db, acc, "redeem", body.transaction_id, "failed", str(e))
        raise HTTPException(502, f"بوابة SAS: {e}")
    _audit(db, acc, "redeem", body.transaction_id, "ok")
    return {"ok": True, "result": res}


@router.post("/{account_id}/change-subscription")
async def portal_change_subscription(account_id: int, body: ChangeSubIn,
                                     identity: dict = Depends(require_subscriber),
                                     db: Session = Depends(get_session)):
    acc = _owned_account(db, identity, account_id)
    _require_linked(acc)
    company = _company_or_400(db, acc)
    _check_txid(db, body.transaction_id)
    try:
        async with _portal(company, acc) as p:
            res = await p.change_subscription(body.new_service, body.current_password or True)
    except SASError as e:
        _audit(db, acc, "change_subscription", body.transaction_id, "failed", str(e))
        raise HTTPException(502, f"بوابة SAS: {e}")
    _audit(db, acc, "change_subscription", body.transaction_id, "ok")
    return {"ok": True, "result": res}


@router.post("/{account_id}/extend")
async def portal_extend(account_id: int, body: ExtendIn,
                        identity: dict = Depends(require_subscriber),
                        db: Session = Depends(get_session)):
    acc = _owned_account(db, identity, account_id)
    _require_linked(acc)
    company = _company_or_400(db, acc)
    _check_txid(db, body.transaction_id)
    try:
        async with _portal(company, acc) as p:
            res = await p.extend(body.profile_id, body.current_password or True)
    except SASError as e:
        _audit(db, acc, "extend", body.transaction_id, "failed", str(e))
        raise HTTPException(502, f"بوابة SAS: {e}")
    _audit(db, acc, "extend", body.transaction_id, "ok")
    return {"ok": True, "result": res}


@router.post("/{account_id}/activate")
async def portal_activate(account_id: int, body: ActivateIn,
                          identity: dict = Depends(require_subscriber),
                          db: Session = Depends(get_session)):
    acc = _owned_account(db, identity, account_id)
    _require_linked(acc)
    company = _company_or_400(db, acc)
    _check_txid(db, body.uuid)                          # uuid نفسه يمنع التكرار
    try:
        async with _portal(company, acc) as p:
            res = await p.activate(body.uuid, body.current_password or True)
    except SASError as e:
        _audit(db, acc, "activate", body.uuid, "failed", str(e))
        raise HTTPException(502, f"بوابة SAS: {e}")
    _audit(db, acc, "activate", body.uuid, "ok")
    return {"ok": True, "result": res}
