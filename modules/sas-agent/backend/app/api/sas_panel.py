"""
واجهة SAS الكاملة (بروكسي حيّ) — مسارات /api/companies/{cid}/sas/*.

تطبيقا الشركات والوكلاء يستهلكان هذه المسارات لعرض/إدارة بيانات SAS مباشرةً كما
تفتح لوحة SAS نفسها: المشتركون بكل الحقول + التفاصيل + الإجراءات + المتصلون +
الوكلاء + الباقات + المالية.

العزل بالنطاق (scope_of):
- جهة رقابية (بلا نطاق): أي شركة — تتصل باعتماد الشركة.
- مستخدم شركة (scope_company_id): شركته فقط — اعتماد الشركة.
- وكيل (scope_agent): شركته + **حساباته على SAS**. الوكيل يربط عدة حسابات SAS (قد تكون
  على خوادم مختلفة)؛ كل مشترك يحمل حسابه المصدر (`_account_id`) فتُدمَج القوائم وتُوجَّه
  أي عملية تلقائياً إلى الحساب/الخادم الصحيح. تحديد الحساب عبر باراميتر `account_id`؛
  عند غيابه: القوائم تُدمَج عبر كل الحسابات، والعمليات على مشترك بعينه تتطلّب تحديده.

الأمان: التطبيقات تكلّم هذا الباكند فقط (لا SAS مباشرةً)؛ بيانات SAS مخزَّنة مشفّرة،
والقراءة تتطلّب viewer والإجراءات (كتابة) تتطلّب operator.
"""
from __future__ import annotations

import contextlib
import logging
import re
from contextlib import asynccontextmanager
from typing import Any, List, Optional
from uuid import uuid4

from fastapi import APIRouter, Body, Depends, HTTPException, Query
from sqlmodel import Session, select

from ..core.auth import current_identity, require_role, scope_of
from ..core.security import decrypt
from ..database import get_session
from ..integrations.sas_client import SASClient, SASError, is_cert_error
from ..models import Company, SasAccount, User
from ..services import sas_sync

router = APIRouter(prefix="/api/companies", tags=["sas-panel"])

_log = logging.getLogger(__name__)

_view = [Depends(require_role("viewer"))]
_oper = [Depends(require_role("operator"))]

# سقف السحب لكل حساب عند دمج القوائم (حماية — الوكيل عادةً بمئات المشتركين لا ملايين)
_MERGE_ACCOUNT_CAP = 3000


# ─────────────────────────────── حلّ النطاق والحساب ───────────────────────────────

def _resolve(db: Session, identity: dict, cid: int,
             account_id: Optional[int] = None
             ) -> tuple[Company, str, Optional[SasAccount], List[SasAccount]]:
    """يتحقّق من النطاق ويحدّد سياق الاتصال بـ SAS.

    يُرجع (الشركة c، وكيل النطاق agent، الحساب المحدَّد acc أو None، كل حسابات الوكيل accounts).
    - جهة رقابية/شركة: acc=None (اعتماد الشركة)، accounts=[].
    - وكيل: accounts = حساباته المضبوطة؛ acc = المحدَّد بـ account_id، أو الوحيد إن كان واحداً،
      وإلا None (عدة حسابات بلا تحديد — القوائم تُدمَج، والعمليات المفردة تتطلّب التحديد)."""
    scope_cid, scope_agent = scope_of(identity)
    if scope_cid is not None and scope_cid != cid:
        raise HTTPException(403, "خارج نطاقك")
    c = db.get(Company, cid)
    if not c:
        raise HTTPException(404, "الشركة غير موجودة")
    if not scope_agent:
        if not c.sas_host or not c.sas_username:
            raise HTTPException(400, "لا توجد بيانات SAS مضبوطة لهذه الشركة")
        return c, "", None, []
    # وكيل: يعمل عبر حساباته الخاصّة على SAS (تسجيل دخوله يحصر الرؤية على مشتركيه)
    u = db.exec(select(User).where(User.username == (identity.get("user") or ""))).first()
    accounts = [a for a in (sas_sync.ensure_agent_accounts(db, u) if u else [])
                if a.enabled and a.sas_host and a.sas_username and a.sas_password_enc]
    if not accounts:
        raise HTTPException(400, "لم تضبط أي حساب SAS بعد — من «حساباتي على SAS» أضِف حساباً")
    acc: Optional[SasAccount] = None
    if account_id is not None:
        acc = next((a for a in accounts if a.id == account_id), None)
        if acc is None:
            raise HTTPException(404, "حساب SAS غير موجود ضمن حساباتك")
    elif len(accounts) == 1:
        acc = accounts[0]
    return c, scope_agent, acc, accounts


def _require_acc(agent: str, acc: Optional[SasAccount],
                 accounts: List[SasAccount]) -> Optional[SasAccount]:
    """لعملية على مشترك بعينه: الوكيل متعدّد الحسابات يجب أن يحدّد الحساب (account_id)."""
    if agent and acc is None:
        raise HTTPException(400, "حدّد حساب SAS (account_id) — لديك أكثر من حساب مربوط")
    return acc


def _default_acc(agent: str, acc: Optional[SasAccount],
                 accounts: List[SasAccount]) -> Optional[SasAccount]:
    """لقراءات عامّة (باقات/مالية/تفاصيل النظام): استخدم المحدَّد أو أول حساب مضبوط."""
    if agent and acc is None and accounts:
        return accounts[0]
    return acc


async def _open_sas(host: str, user: str, pwd: str, https: bool, verify: bool) -> SASClient:
    """يفتح جلسة SAS (يسجّل الدخول). يُغلق الاتصال بأمان إن فشل الدخول (لا تسرّب مقبس)."""
    sas = SASClient(host, user, pwd, https=https, verify_tls=verify)
    try:
        await sas.__aenter__()
        return sas
    except BaseException:
        with contextlib.suppress(Exception):
            await sas.__aexit__(None, None, None)
        raise


@asynccontextmanager
async def _sas_for(c: Optional[Company], acc: Optional[SasAccount]):
    """عميل SAS: حساب الوكيل المحدَّد (إن وُجد) وإلا خادم الشركة.

    يتسامح مع الشهادات الذاتية التوقيع: إن فشل التحقّق من الشهادة يعيد المحاولة بلا تحقّق TLS
    (كما تفعل المزامنة تماماً)، ويحوّل فشل الاتصال/المصادقة إلى 502 مفهومة بدل 500 غير معالَج
    (لأن فتح الجلسة يقع خارج _guard)."""
    if acc is not None:
        host, https, verify, user = acc.sas_host, acc.sas_https, acc.sas_verify_tls, acc.sas_username
        pwd = decrypt(acc.sas_password_enc) if acc.sas_password_enc else ""
    else:
        host, https, verify, user = c.sas_host, c.sas_https, c.sas_verify_tls, c.sas_username
        pwd = decrypt(c.sas_password_enc) if c.sas_password_enc else ""
    try:
        try:
            sas = await _open_sas(host, user, pwd, https, verify)
        except Exception as e:                       # noqa: BLE001
            if verify and is_cert_error(e):          # شهادة ذاتية → أعِد بلا تحقّق TLS
                sas = await _open_sas(host, user, pwd, https, False)
            else:
                raise
    except SASError as e:
        raise HTTPException(502, f"SAS: {e}")
    except HTTPException:
        raise
    except Exception as e:                           # noqa: BLE001
        raise HTTPException(502, f"تعذّر الاتصال بـ SAS: {e}")
    try:
        yield sas
    finally:
        with contextlib.suppress(Exception):
            await sas.__aexit__(None, None, None)


def _tag(rows: list, acc: SasAccount) -> list:
    """يَسِم كل صفّ بمصدر حسابه كي توجَّه العمليات وتُعرَض شارة المصدر في الواجهة."""
    label = acc.label or acc.sas_username
    out = []
    for r in rows:
        if isinstance(r, dict):
            r = dict(r)
            r["_account_id"] = acc.id
            r["_account_label"] = label
        out.append(r)
    return out


async def _guard(coro):
    """يلفّ نداء SAS ويحوّل أخطاءه إلى 502 مفهومة."""
    try:
        return await coro
    except SASError as e:
        raise HTTPException(502, f"SAS: {e}")
    except HTTPException:
        raise
    except Exception as e:  # noqa: BLE001
        raise HTTPException(502, f"تعذّر الاتصال بـ SAS: {e}")


def _rows_total(res: Any) -> tuple[list, Optional[int]]:
    if isinstance(res, dict):
        return list(res.get("data", []) or []), res.get("total")
    return (list(res) if isinstance(res, list) else []), None


# حجب الأسرار قبل إرسالها للتطبيق: كلمة مرور المشترك الظاهرة (overview)، وبيانات الـ NAS
# في المتصلين (secret/api_password/snmp_community)، وأي مفتاح حسّاس آخر. المفتاح المطابق
# يُستبدل بـ "***" (nas_details تُحجب كاملةً لأن اسم المفتاح نفسه يطابق).
_SECRET_KEYS = re.compile(r"(password|secret|api_password|snmp_community|nas_details|\bpin\b)", re.I)


def _redact(obj: Any) -> Any:
    if isinstance(obj, dict):
        return {k: ("***" if _SECRET_KEYS.search(str(k)) else _redact(v)) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_redact(x) for x in obj]
    return obj


# ─────────────────────────── دمج المشتركين عبر الحسابات ───────────────────────────

async def _fetch_account_rows(acc: SasAccount, kind: str, search: str,
                              sort_by: str, direction: str) -> list:
    """يسحب كل صفوف حساب واحد (مشتركون=user أو متصلون=online) مع الوسم بالمصدر — أفضل-جهد."""
    rows: list = []
    async with _sas_for(None, acc) as sas:
        page = 1
        while len(rows) < _MERGE_ACCOUNT_CAP:
            if kind == "online":
                res = await sas.online(page=page, count=500, search=search)
            else:
                res = await sas.users(page=page, count=500, search=search,
                                      sort_by=sort_by, direction=direction)
            chunk, total = _rows_total(res)
            rows.extend(_tag(chunk, acc))
            if len(chunk) < 500 or (total is not None and page * 500 >= int(total)):
                break
            page += 1
    return rows


async def _merged_rows(accounts: List[SasAccount], kind: str, page: int, count: int,
                       search: str, sort_by: str, direction: str) -> tuple[list, int]:
    """يدمج صفوف كل الحسابات (فشل حساب لا يُسقط البقية)، يفرز، ثم يُرقّم في الذاكرة."""
    all_rows: list = []
    for acc in accounts:
        try:
            all_rows.extend(await _fetch_account_rows(acc, kind, search, sort_by, direction))
        except Exception as e:  # noqa: BLE001 — تخطّي الحساب الفاشل وإكمال البقية
            _log.warning("[SAS] تعذّر سحب %s من حساب %s: %s", kind, acc.sas_username, e)
            continue

    reverse = (direction or "asc").strip().lower() == "desc"

    def _key(r):
        v = r.get(sort_by) if isinstance(r, dict) else None
        if isinstance(v, bool):
            return (0, int(v))
        if isinstance(v, (int, float)):
            return (0, v)
        return (1, str(v) if v is not None else "")
    try:
        all_rows.sort(key=_key, reverse=reverse)
    except Exception:  # noqa: BLE001 — الفرز أفضل-جهد
        pass
    total = len(all_rows)
    start = max(0, (page - 1) * count)
    return all_rows[start:start + count], total


# ─────────────────────── حسابات الوكيل (للفلتر/الشارة في الواجهة) ───────────────────────

@router.get("/{cid}/sas/accounts", dependencies=_view)
def sas_accounts(cid: int, db: Session = Depends(get_session),
                 identity: dict = Depends(current_identity)):
    """حسابات SAS المتاحة في هذا السياق (للفلتر أعلى اللوحة).
    الوكيل: كل حساباته المضبوطة؛ الشركة/الجهة الرقابية: حساب الشركة الواحد."""
    scope_cid, scope_agent = scope_of(identity)
    if scope_cid is not None and scope_cid != cid:
        raise HTTPException(403, "خارج نطاقك")
    if scope_agent:
        u = db.exec(select(User).where(User.username == (identity.get("user") or ""))).first()
        accounts = sas_sync.ensure_agent_accounts(db, u) if u else []
        return {"is_agent": True, "accounts": [{
            "id": a.id, "label": a.label or a.sas_username,
            "sas_username": a.sas_username, "sas_host": a.sas_host,
            "enabled": a.enabled,
            "configured": bool(a.sas_host and a.sas_username and a.sas_password_enc),
        } for a in accounts]}
    c = db.get(Company, cid)
    if not c:
        raise HTTPException(404, "الشركة غير موجودة")
    return {"is_agent": False, "accounts": [{
        "id": None, "label": c.name, "sas_username": c.sas_username,
        "sas_host": c.sas_host, "enabled": c.enabled,
        "configured": bool(c.sas_host and c.sas_username),
    }]}


# ─────────────────────────── لوحات ملخّصة ───────────────────────────

def _sum_dashboards(dicts: List[dict]) -> dict:
    """يجمع حقول ملخّص المشتركين العددية عبر عدة حسابات (عرض «كل الحسابات»)."""
    keys = ["total", "active", "expired", "online", "offline",
            "expiring_today", "expiring_soon", "fup", "managers"]
    agg = {k: 0 for k in keys}
    for d in dicts:
        if not isinstance(d, dict):
            continue
        for k in keys:
            try:
                agg[k] += int(d.get(k) or 0)
            except (TypeError, ValueError):
                pass
    return agg


@router.get("/{cid}/sas/dashboard", dependencies=_view)
async def sas_dashboard(cid: int, account_id: Optional[int] = Query(None),
                        db: Session = Depends(get_session),
                        identity: dict = Depends(current_identity)):
    """ملخّص المشتركين (advancedDashboard/subscribers). الوكيل متعدّد الحسابات بلا تحديد →
    مجموع كل حساباته."""
    c, agent, acc, accounts = _resolve(db, identity, cid, account_id)
    if agent and acc is None and len(accounts) > 1:
        parts = []
        for a in accounts:
            try:
                async with _sas_for(c, a) as sas:
                    res = await sas.dashboard_subscribers()
                parts.append(res.get("data", res) if isinstance(res, dict) else {})
            except Exception as e:  # noqa: BLE001
                _log.warning("[SAS] تعذّر ملخّص حساب %s: %s", a.sas_username, e)
        return _sum_dashboards(parts)
    acc = _default_acc(agent, acc, accounts)
    async with _sas_for(c, acc) as sas:
        res = await _guard(sas.dashboard_subscribers())
    return res.get("data", res) if isinstance(res, dict) else res


@router.get("/{cid}/sas/finance", dependencies=_view)
async def sas_finance(cid: int, account_id: Optional[int] = Query(None),
                      db: Session = Depends(get_session),
                      identity: dict = Depends(current_identity)):
    """ملخّص مالي (advancedDashboard/finance). الوكيل متعدّد الحسابات بلا تحديد → أول حساب."""
    c, agent, acc, accounts = _resolve(db, identity, cid, account_id)
    acc = _default_acc(agent, acc, accounts)
    async with _sas_for(c, acc) as sas:
        res = await _guard(sas.dashboard_finance())
    return res.get("data", res) if isinstance(res, dict) else res


# ─────────────────────────── المشتركون ───────────────────────────

@router.get("/{cid}/sas/users", dependencies=_view)
async def sas_users(cid: int,
                    page: int = Query(1, ge=1),
                    count: int = Query(50, ge=1, le=500),
                    search: str = "",
                    sort_by: str = "id",
                    direction: str = "asc",
                    account_id: Optional[int] = Query(None),
                    db: Session = Depends(get_session),
                    identity: dict = Depends(current_identity)):
    """قائمة المشتركين (index/user) بكل الحقول، بترقيم/بحث/فرز.
    الوكيل بلا تحديد حساب → **مدموجة عبر كل حساباته** (كل صفّ موسوم بـ _account_id)."""
    c, agent, acc, accounts = _resolve(db, identity, cid, account_id)
    if agent and acc is None:
        rows, total = await _merged_rows(accounts, "user", page, count, search, sort_by, direction)
        return {"data": _redact(rows), "total": total, "page": page, "count": count}
    async with _sas_for(c, acc) as sas:
        res = await _guard(sas.users(page=page, count=count, search=search,
                                     sort_by=sort_by, direction=direction))
    rows, total = _rows_total(res)
    if acc is not None:
        rows = _tag(rows, acc)
    return {"data": _redact(rows), "total": total, "page": page, "count": count}


@router.get("/{cid}/sas/users/{uid}", dependencies=_view)
async def sas_user_detail(cid: int, uid: int, account_id: Optional[int] = Query(None),
                          db: Session = Depends(get_session),
                          identity: dict = Depends(current_identity)):
    """كل بيانات مشترك (GET user/{id}) من حسابه الصحيح."""
    c, agent, acc, accounts = _resolve(db, identity, cid, account_id)
    acc = _require_acc(agent, acc, accounts)
    async with _sas_for(c, acc) as sas:
        res = await _guard(sas.user(uid))
    data = res.get("data", res) if isinstance(res, dict) else res
    return _redact(data)


@router.get("/{cid}/sas/users/{uid}/overview", dependencies=_view)
async def sas_user_overview(cid: int, uid: int, account_id: Optional[int] = Query(None),
                            db: Session = Depends(get_session),
                            identity: dict = Depends(current_identity)):
    """نظرة عامة على مشترك (GET user/overview/{id})."""
    c, agent, acc, accounts = _resolve(db, identity, cid, account_id)
    acc = _require_acc(agent, acc, accounts)
    async with _sas_for(c, acc) as sas:
        res = await _guard(sas.get(f"user/overview/{uid}"))
    data = res.get("data", res) if isinstance(res, dict) else res
    return _redact(data)


@router.get("/{cid}/sas/users/{uid}/history", dependencies=_view)
async def sas_user_history(cid: int, uid: int, account_id: Optional[int] = Query(None),
                           db: Session = Depends(get_session),
                           identity: dict = Depends(current_identity)):
    """سجلّ المشترك (POST index/UserHistory/{id})."""
    c, agent, acc, accounts = _resolve(db, identity, cid, account_id)
    acc = _require_acc(agent, acc, accounts)
    async with _sas_for(c, acc) as sas:
        res = await _guard(sas.post(f"index/UserHistory/{uid}",
                                    {"page": 1, "count": 50, "sortBy": "id",
                                     "direction": "desc", "search": ""}))
    return res


@router.get("/{cid}/sas/users/{uid}/extend-data", dependencies=_view)
async def sas_user_extend_data(cid: int, uid: int, profile_id: Optional[int] = None,
                               account_id: Optional[int] = Query(None),
                               db: Session = Depends(get_session),
                               identity: dict = Depends(current_identity)):
    """بيانات التمديد + الباقات المسموحة (لِمَلء نموذج التجديد قبل التنفيذ)."""
    c, agent, acc, accounts = _resolve(db, identity, cid, account_id)
    acc = _require_acc(agent, acc, accounts)
    async with _sas_for(c, acc) as sas:
        ext = await _guard(sas.get(f"user/extensionData/{uid}"))
        allowed = None
        if profile_id is not None:
            allowed = await _guard(sas.get(f"allowedExtensions/{profile_id}"))
    return {"extension": ext, "allowed_extensions": allowed}


# إجراءات المشترك (كتابة) — قائمة بيضاء لمسارات SAS
_USER_ACTIONS: dict[str, str] = {
    "activate": "user/activate",
    "extend": "user/extend",
    "changeProfile": "user/changeProfile",
    "addTraffic": "user/addTraffic",
    "deposit": "user/deposit",
    "withdraw": "user/withdraw",
    "ping": "user/ping",
    "rename": "user/rename/{uid}",
}   # إنشاء مشترك له نقطة صريحة POST /{cid}/sas/users (بلا حقن user_id)


@router.post("/{cid}/sas/users/{uid}/action", dependencies=_oper)
async def sas_user_action(cid: int, uid: int,
                          action: str = Body(..., embed=True),
                          payload: dict = Body(default={}, embed=True),
                          account_id: Optional[int] = Body(default=None, embed=True),
                          db: Session = Depends(get_session),
                          identity: dict = Depends(current_identity)):
    """تنفيذ إجراء SAS على مشترك (تفعيل/تمديد/تغيير باقة/رصيد/ترافيك/إعادة تسمية)
    — يُوجَّه تلقائياً إلى حساب المشترك (account_id)."""
    c, agent, acc, accounts = _resolve(db, identity, cid, account_id)
    acc = _require_acc(agent, acc, accounts)
    route = _USER_ACTIONS.get(action)
    if not route:
        raise HTTPException(400, f"إجراء غير مسموح — المتاح: {', '.join(_USER_ACTIONS)}")
    async with _sas_for(c, acc) as sas:
        body = {"user_id": uid, **(payload or {})}
        res = await _guard(sas.post(route.format(uid=uid), body))
    return res


_BULK_CAP = 300     # سقف أمان لعدد المشتركين في العملية الواحدة


@router.post("/{cid}/sas/users/bulk-action", dependencies=_oper)
async def sas_bulk_action(cid: int,
                          action: str = Body(..., embed=True),
                          user_ids: list[int] = Body(..., embed=True),
                          payload: dict = Body(default={}, embed=True),
                          account_id: Optional[int] = Body(default=None, embed=True),
                          db: Session = Depends(get_session),
                          identity: dict = Depends(current_identity)):
    """تنفيذ إجراء واحد على عدة مشتركين دفعةً — كلهم على **حساب واحد** (account_id).

    - لكل مشترك `transaction_id` فريد (يمنع تكرار الخصم عند إعادة المحاولة).
    - أفضل-جهد: لا يُفشل الكلّ بفشل عنصر؛ يُعيد نتيجة كل مشترك على حدة (ok/error)."""
    c, agent, acc, accounts = _resolve(db, identity, cid, account_id)
    acc = _require_acc(agent, acc, accounts)
    route = _USER_ACTIONS.get(action)
    if not route:
        raise HTTPException(400, f"إجراء غير مسموح — المتاح: {', '.join(_USER_ACTIONS)}")
    ids = list(dict.fromkeys(int(u) for u in (user_ids or [])))[:_BULK_CAP]   # إزالة التكرار + سقف
    if not ids:
        raise HTTPException(400, "لا مشتركين محدَّدين")
    results: list[dict] = []
    ok = 0
    async with _sas_for(c, acc) as sas:
        for uid in ids:
            try:
                # payload أولاً ثم transaction_id فريد لكل مشترك (لا يُدهَس)
                body = {"user_id": uid, **(payload or {}), "transaction_id": uuid4().hex}
                await _guard(sas.post(route.format(uid=uid), body))
                ok += 1
                results.append({"user_id": uid, "ok": True})
            except HTTPException as e:
                results.append({"user_id": uid, "ok": False, "error": str(e.detail)})
            except Exception as e:                 # noqa: BLE001
                results.append({"user_id": uid, "ok": False, "error": str(e)[:200]})
    return {"action": action, "total": len(ids), "ok": ok,
            "failed": len(ids) - ok, "results": results}


@router.post("/{cid}/sas/users", dependencies=_oper)
async def sas_create_user(cid: int,
                          payload: dict = Body(..., embed=True),
                          account_id: Optional[int] = Body(default=None, embed=True),
                          db: Session = Depends(get_session),
                          identity: dict = Depends(current_identity)):
    """إنشاء مشترك جديد (SAS: POST user) بحمولة كاملة — بلا حقن user_id.
    للوكيل: يُنشأ تحت الحساب المحدَّد تلقائياً (تسجيل دخول الحساب هو المدير المالك) —
    لا يُقبل parent_id منه. للشركة/الجهة الرقابية: parent_id مطلوب."""
    c, agent, acc, accounts = _resolve(db, identity, cid, account_id)
    acc = _require_acc(agent, acc, accounts)
    body = dict(payload or {})
    if not str(body.get("username") or "").strip():
        raise HTTPException(400, "اسم المستخدم مطلوب")
    if not str(body.get("password") or ""):
        raise HTTPException(400, "كلمة المرور مطلوبة")
    body.setdefault("confirm_password", body.get("password"))
    if agent:
        # حساب الوكيل هو المدير المُصادَق → SAS يُسند المشترك إليه؛ لا نقبل parent_id منه.
        body.pop("parent_id", None)
    elif not body.get("parent_id"):
        raise HTTPException(400, "معرّف الوكيل المالك (parent_id) مطلوب")
    async with _sas_for(c, acc) as sas:
        res = await _guard(sas.post("user", body))
    return res


# تعديل مشترك (SAS يحفظ بإعادة POST user مع id). الحقول القابلة للتغيير من العميل:
_UPDATABLE = {"enabled", "profile_id", "site_id", "mac_auth", "allowed_macs", "firstname",
              "lastname", "company", "email", "phone", "city", "address", "apartment", "street",
              "contract_id", "national_id", "notes", "simultaneous_sessions", "static_ip",
              "auto_renew", "user_type", "expiration", "password"}
# حقول تُرسَل دائماً من القيمة الحالية كي لا يمسحها الحفظ (SAS يعامل الغائب كـ null):
_UPDATE_BASE = ["username", "enabled", "profile_id", "parent_id", "site_id", "mac_auth",
                "allowed_macs", "firstname", "lastname", "company", "email", "phone", "city",
                "address", "apartment", "street", "contract_id", "national_id", "notes",
                "expiration", "simultaneous_sessions", "static_ip", "auto_renew", "user_type"]


@router.post("/{cid}/sas/users/{uid}/update", dependencies=_oper)
async def sas_update_user(cid: int, uid: int,
                          changes: dict = Body(..., embed=True),
                          account_id: Optional[int] = Body(default=None, embed=True),
                          db: Session = Depends(get_session),
                          identity: dict = Depends(current_identity)):
    """تعديل مشترك عبر «تحميل-دمج-حفظ»: يجلب بياناته الحالية، يدمج التغييرات، ثم يعيد
    حفظها (POST user مع id) — دون مسح بقية الحقول. يُوجَّه إلى حساب المشترك (account_id)."""
    c, agent, acc, accounts = _resolve(db, identity, cid, account_id)
    acc = _require_acc(agent, acc, accounts)
    bad = set(changes) - _UPDATABLE
    if bad:
        raise HTTPException(400, f"حقول غير قابلة للتعديل: {', '.join(sorted(bad))}")
    if not changes:
        raise HTTPException(400, "لا تغييرات")
    async with _sas_for(c, acc) as sas:
        cur = await _guard(sas.user(uid))
        data = cur.get("data", cur) if isinstance(cur, dict) else cur
        if not isinstance(data, dict):
            raise HTTPException(404, "المشترك غير موجود")
        body: dict[str, Any] = {"id": uid}
        for k in _UPDATE_BASE:                 # القيم الحالية أولاً (منع المسح)
            body[k] = data.get(k)
        for k, v in changes.items():           # ثم التغييرات
            body[k] = v
        if changes.get("password"):            # تأكيد كلمة المرور مطلوب عند تغييرها
            body["confirm_password"] = changes["password"]
        res = await _guard(sas.post("user", body))
    return res


@router.get("/{cid}/sas/users/{uid}/refund-data", dependencies=_view)
async def sas_user_refund_data(cid: int, uid: int, account_id: Optional[int] = Query(None),
                               db: Session = Depends(get_session),
                               identity: dict = Depends(current_identity)):
    """بيانات الإلغاء/الاسترداد قبل التنفيذ (GET user/refundData/{id})."""
    c, agent, acc, accounts = _resolve(db, identity, cid, account_id)
    acc = _require_acc(agent, acc, accounts)
    async with _sas_for(c, acc) as sas:
        res = await _guard(sas.get(f"user/refundData/{uid}"))
    return res.get("data", res) if isinstance(res, dict) else res


@router.post("/{cid}/sas/users/{uid}/refund", dependencies=_oper)
async def sas_user_refund(cid: int, uid: int, account_id: Optional[int] = Body(default=None, embed=True),
                          db: Session = Depends(get_session),
                          identity: dict = Depends(current_identity)):
    """تنفيذ الإلغاء والاسترداد (SAS: GET user/refund/{id}) — إجراء مالي (operator)."""
    c, agent, acc, accounts = _resolve(db, identity, cid, account_id)
    acc = _require_acc(agent, acc, accounts)
    async with _sas_for(c, acc) as sas:
        res = await _guard(sas.get(f"user/refund/{uid}"))
    return res


@router.delete("/{cid}/sas/users/{uid}", dependencies=_oper)
async def sas_delete_user(cid: int, uid: int, account_id: Optional[int] = Query(None),
                          db: Session = Depends(get_session),
                          identity: dict = Depends(current_identity)):
    """حذف مشترك (SAS: DELETE user/{id}) — يُوجَّه إلى حساب المشترك (account_id)."""
    c, agent, acc, accounts = _resolve(db, identity, cid, account_id)
    acc = _require_acc(agent, acc, accounts)
    async with _sas_for(c, acc) as sas:
        res = await _guard(sas.delete(f"user/{uid}"))
    return res


# ─────────────────────────── المتصلون الآن ───────────────────────────

@router.get("/{cid}/sas/online", dependencies=_view)
async def sas_online(cid: int,
                     page: int = Query(1, ge=1),
                     count: int = Query(100, ge=1, le=500),
                     search: str = "",
                     account_id: Optional[int] = Query(None),
                     db: Session = Depends(get_session),
                     identity: dict = Depends(current_identity)):
    """الجلسات المتصلة الآن (index/online). الوكيل بلا تحديد → مدموجة عبر كل حساباته."""
    c, agent, acc, accounts = _resolve(db, identity, cid, account_id)
    if agent and acc is None:
        rows, total = await _merged_rows(accounts, "online", page, count, search, "id", "asc")
        return {"data": _redact(rows), "total": total, "page": page, "count": count}
    async with _sas_for(c, acc) as sas:
        res = await _guard(sas.online(page=page, count=count, search=search))
    rows, total = _rows_total(res)
    if acc is not None:
        rows = _tag(rows, acc)
    return {"data": _redact(rows), "total": total, "page": page, "count": count}


# ─────────────────────────── الوكلاء والباقات ───────────────────────────

@router.get("/{cid}/sas/managers", dependencies=_view)
async def sas_managers(cid: int,
                       page: int = Query(1, ge=1),
                       count: int = Query(200, ge=1, le=500),
                       db: Session = Depends(get_session),
                       identity: dict = Depends(current_identity)):
    """قائمة الوكلاء الكاملة (index/manager). لا تُتاح للوكيل (يرى مشتركيه لا أقرانه)."""
    c, agent, acc, accounts = _resolve(db, identity, cid)
    if agent:
        raise HTTPException(403, "غير متاح للوكيل")
    async with _sas_for(c, acc) as sas:
        res = await _guard(sas.managers_full(page=page, count=count))
    rows, total = _rows_total(res)
    return {"data": rows, "total": total, "page": page, "count": count}


@router.get("/{cid}/sas/profiles", dependencies=_view)
async def sas_profiles(cid: int, account_id: Optional[int] = Query(None),
                       db: Session = Depends(get_session),
                       identity: dict = Depends(current_identity)):
    """قائمة الباقات (list/profile/0) للحساب المحدَّد (أو أول حساب للوكيل)."""
    c, agent, acc, accounts = _resolve(db, identity, cid, account_id)
    acc = _default_acc(agent, acc, accounts)
    async with _sas_for(c, acc) as sas:
        res = await _guard(sas.profiles())
    return res.get("data", res) if isinstance(res, dict) else res


# ─────────────── بروكسي عامّ مُقيَّد بقائمة بيضاء (قراءة تفاصيل SAS) ───────────────
_GET_ALLOW = [
    r"auth",
    r"user/\d+",
    r"user/overview/\d+",
    r"user/activationData/\d+",
    r"user/extensionData/\d+",
    r"user/refundData/\d+",
    r"user/refund/\d+",
    r"allowedExtensions/\d+",
    r"mac/\d+",
    r"customRadiusAttribute/user/\d+",
    r"list/profile/\d+",
    r"site",
    r"manager/tree",
    r"usersReport/summary",
    r"usersReport/perManager",
    r"usersReport/map",
    r"syslog/events",
    r"resources/menu",
    r"resources/languages",
    r"resources/language/[\w-]+",
    r"advancedDashboard/(?:subscribers|finance|systemHealth|CpuUsage|MemoryUsage|DiskUsage)",
]
_POST_ALLOW = [
    r"index/UserHistory/\d+",
    r"index/UserJournal/\d+",
    r"index/UserSessions(?:/\d+)?",
    r"index/UserInvoices(?:/\d+)?",
    r"index/UserReceipts/\d+",
    r"index/UserDocuments/\d+",
    r"index/Quota/\d+",
    r"user/traffic",
    r"userNetworksTraffic",
    r"index/activations",
    r"index/ManagerInvoices(?:/\d+)?",
    r"index/ManagerReceipts(?:/\d+)?",
    r"index/ManagerJournal(?:/\d+)?",
    r"index/ManagerDebtsJournal",
    r"index/dataExportJob",
    r"report/depodrawal",
    r"report/activations",
    r"report/profits",
    r"usersReport/registration",
    r"usersReport/perProfile",
    r"index/userauthlog",
    r"index/syslog",
]
_GET_ALLOW_RE = [re.compile(f"^{p}$") for p in _GET_ALLOW]
_POST_ALLOW_RE = [re.compile(f"^{p}$") for p in _POST_ALLOW]
_AGENT_BLOCKED = re.compile(r"^(?:manager/|index/manager)")


@router.get("/{cid}/sas/get", dependencies=_view)
async def sas_get(cid: int, path: str = Query(..., min_length=1, max_length=120),
                  account_id: Optional[int] = Query(None),
                  db: Session = Depends(get_session),
                  identity: dict = Depends(current_identity)):
    """بروكسي GET مُقيَّد بقائمة بيضاء لقراءة تفاصيل SAS."""
    c, agent, acc, accounts = _resolve(db, identity, cid, account_id)
    acc = _default_acc(agent, acc, accounts)
    p = path.strip().strip("/")
    if not any(rx.match(p) for rx in _GET_ALLOW_RE):
        raise HTTPException(400, "مسار غير مسموح")
    if agent and _AGENT_BLOCKED.match(p):
        raise HTTPException(403, "غير متاح للوكيل")
    async with _sas_for(c, acc) as sas:
        res = await _guard(sas.get(p))
    return _redact(res)


@router.post("/{cid}/sas/post", dependencies=_view)
async def sas_post(cid: int,
                   path: str = Body(..., embed=True),
                   payload: dict = Body(default={}, embed=True),
                   account_id: Optional[int] = Body(default=None, embed=True),
                   db: Session = Depends(get_session),
                   identity: dict = Depends(current_identity)):
    """بروكسي POST مُقيَّد بقائمة بيضاء (قوائم بترقيم: سجلّ/قيود/ترافيك)."""
    c, agent, acc, accounts = _resolve(db, identity, cid, account_id)
    acc = _default_acc(agent, acc, accounts)
    p = (path or "").strip().strip("/")
    if not any(rx.match(p) for rx in _POST_ALLOW_RE):
        raise HTTPException(400, "مسار غير مسموح")
    async with _sas_for(c, acc) as sas:
        res = await _guard(sas.post(p, payload or {}))
    return _redact(res)


# إجراءات الوكلاء (كتابة) — للشركة/الجهة الرقابية فقط (لا الوكيل)
_MANAGER_ACTIONS: dict[str, str] = {
    "deposit": "manager/deposit",
    "withdraw": "manager/withdraw",
    "addRewardPoints": "manager/addRewardPoints",
    "deductRewardPoints": "manager/deductRewardPoints",
    "payDebt": "manager/payDebt",
    "add": "manager",
    "edit": "manager/{mid}",
    "rename": "manager/{mid}",
}


@router.post("/{cid}/sas/managers/{mid}/action", dependencies=_oper)
async def sas_manager_action(cid: int, mid: int,
                             action: str = Body(..., embed=True),
                             payload: dict = Body(default={}, embed=True),
                             db: Session = Depends(get_session),
                             identity: dict = Depends(current_identity)):
    """إجراء على وكيل (إيداع/سحب/نقاط/سداد دين/إضافة/تعديل) — لا يُتاح للوكيل."""
    c, agent, acc, accounts = _resolve(db, identity, cid)
    if agent:
        raise HTTPException(403, "إدارة الوكلاء غير متاحة للوكيل")
    route = _MANAGER_ACTIONS.get(action)
    if not route:
        raise HTTPException(400, f"إجراء غير مسموح — المتاح: {', '.join(_MANAGER_ACTIONS)}")
    body = dict(payload or {})
    if action != "add":                       # الإضافة إنشاء جديد بلا manager_id
        body.setdefault("manager_id", mid)
    async with _sas_for(c, acc) as sas:
        res = await _guard(sas.post(route.format(mid=mid), body))
    return res


@router.delete("/{cid}/sas/managers/{mid}", dependencies=_oper)
async def sas_delete_manager(cid: int, mid: int, db: Session = Depends(get_session),
                             identity: dict = Depends(current_identity)):
    """حذف وكيل (SAS: DELETE manager/{id}) — لا يُتاح للوكيل."""
    c, agent, acc, accounts = _resolve(db, identity, cid)
    if agent:
        raise HTTPException(403, "إدارة الوكلاء غير متاحة للوكيل")
    async with _sas_for(c, acc) as sas:
        res = await _guard(sas.delete(f"manager/{mid}"))
    return res
