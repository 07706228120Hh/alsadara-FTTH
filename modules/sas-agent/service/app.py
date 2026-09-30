"""
خدمة الساس الداخلية (SAS Sidecar) — FastAPI على 127.0.0.1:8100
================================================================
خدمة نحيلة بلا حالة. تستقبل اعتماد SAS4 من بوّابة الصدارة .NET
في كل طلب، تناديه مباشرةً، وتعيد JSON خاماً.

الأمان:
  - تستمع على 127.0.0.1 فقط (loopback — غير قابلة للوصول من الإنترنت).
  - fail-closed: كل طلب يحمل X-Internal-Secret مطابقاً لـ SADARA_SAS_INTERNAL_SECRET.
  - مقارنة بزمن ثابت (secrets.compare_digest) لمنع هجمات التوقيت.
  - لا تُسجَّل أسرار أو كلمات مرور في أي log.
  - بلا حالة: الاعتماد يُستخدم لحظة الطلب فقط، لا يُخزَّن.

استيراد العملاء:
  يضبط sys.path ليشمل backend/app قبل الاستيراد. هذا أنظف من نسخ
  الملفين، إذ يبقى مصدر الحقيقة واحداً ولا تتشعّب التعديلات المستقبلية.
"""
from __future__ import annotations

import logging
import os
import re
import secrets
import sys
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

# ── ضبط مسار الاستيراد ────────────────────────────────────────────────────────
# نضيف backend/app إلى sys.path كي يُحلّ `from integrations.sas_client import …`
# دون تعديل هيكل الحزمة القائمة.
_BACKEND_APP = os.path.join(os.path.dirname(__file__), "..", "backend", "app")
if _BACKEND_APP not in sys.path:
    sys.path.insert(0, os.path.abspath(_BACKEND_APP))

from integrations.sas_client import SASClient, SASError        # noqa: E402
from integrations.sas_user_client import SASUserClient          # noqa: E402

from fastapi import Body, Depends, FastAPI, HTTPException, Request, status  # noqa: E402
from fastapi.responses import JSONResponse                                    # noqa: E402
from pydantic import BaseModel, Field                                         # noqa: E402

# ── إعداد التسجيل ─────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s  %(message)s",
)
logger = logging.getLogger("sas_sidecar")

# ── السرّ الداخلي ─────────────────────────────────────────────────────────────
_INTERNAL_SECRET: str = os.environ.get("SADARA_SAS_INTERNAL_SECRET", "")

# ── قوائم بيضاء للبروكسي العام (منقولة حرفياً من sas_panel.py) ───────────────
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
_GET_ALLOW_RE  = [re.compile(f"^{p}$") for p in _GET_ALLOW]
_POST_ALLOW_RE = [re.compile(f"^{p}$") for p in _POST_ALLOW]

# حقول الوكلاء المسموح بها (قائمة بيضاء لإجراءات manager)
_MANAGER_ACTIONS: Dict[str, str] = {
    "deposit":           "manager/deposit",
    "withdraw":          "manager/withdraw",
    "addRewardPoints":   "manager/addRewardPoints",
    "deductRewardPoints":"manager/deductRewardPoints",
    "payDebt":           "manager/payDebt",
    "add":               "manager",
    "edit":              "manager/{mid}",
    "rename":            "manager/{mid}",
}

# حقول المشتركين القابلة للتعديل (قائمة بيضاء من sas_panel.py)
_UPDATABLE = {
    "enabled", "profile_id", "site_id", "mac_auth", "allowed_macs", "firstname",
    "lastname", "company", "email", "phone", "city", "address", "apartment", "street",
    "contract_id", "national_id", "notes", "simultaneous_sessions", "static_ip",
    "auto_renew", "user_type", "expiration", "password",
}
_UPDATE_BASE = [
    "username", "enabled", "profile_id", "parent_id", "site_id", "mac_auth",
    "allowed_macs", "firstname", "lastname", "company", "email", "phone", "city",
    "address", "apartment", "street", "contract_id", "national_id", "notes",
    "expiration", "simultaneous_sessions", "static_ip", "auto_renew", "user_type",
]

# إجراءات المشترك المفردة (قائمة بيضاء من sas_panel.py)
_USER_ACTIONS: Dict[str, str] = {
    "activate":      "user/activate",
    "extend":        "user/extend",
    "changeProfile": "user/changeProfile",
    "addTraffic":    "user/addTraffic",
    "deposit":       "user/deposit",
    "withdraw":      "user/withdraw",
    "ping":          "user/ping",
    "rename":        "user/rename/{uid}",
}

_BULK_CAP = 300   # سقف أمان لعدد المشتركين في العملية الجماعية الواحدة

# ── نماذج Pydantic للطلبات ────────────────────────────────────────────────────


class _Creds(BaseModel):
    """حقول الاعتماد المشتركة في كل الطلبات."""
    serverUrl: str = Field(..., description="عنوان خادم SAS (host أو URL كامل)")
    username:  str = Field(..., description="اسم مستخدم المدير/الوكيل في SAS")
    password:  str = Field(..., description="كلمة المرور — لا تُسجَّل أبداً")


class LoginRequest(_Creds):
    pass


class DashboardRequest(_Creds):
    pass


class SubscribersRequest(_Creds):
    query: Dict[str, Optional[str]] = Field(default_factory=dict)


class ReportRequest(_Creds):
    query: Dict[str, Optional[str]] = Field(default_factory=dict)


class PackagesRequest(_Creds):
    pass


class FinanceRequest(_Creds):
    pass


class SystemHealthRequest(_Creds):
    pass


class RenewalCandidatesRequest(_Creds):
    days:        int                 = Field(default=7, ge=1, le=365)
    query:       Dict[str, Any]      = Field(default_factory=dict)


class RenewalBulkRequest(_Creds):
    subscriberIds: List[int]         = Field(...)
    months:        Optional[int]     = Field(default=None, ge=1, le=24)
    profileId:     Optional[Any]     = Field(default=None)
    dryRun:        bool              = Field(default=False)


# ── نماذج النقاط الجديدة ──────────────────────────────────────────────────────

class UserDetailRequest(_Creds):
    uid: int = Field(..., description="معرّف المشترك في SAS")


class UserOverviewRequest(_Creds):
    uid: int


class UserHistoryRequest(_Creds):
    uid:       int
    page:      int            = Field(default=1, ge=1)
    count:     int            = Field(default=50, ge=1, le=500)
    sortBy:    str            = Field(default="id")
    direction: str            = Field(default="desc")
    search:    str            = Field(default="")


class UserExtendDataRequest(_Creds):
    uid:        int
    profile_id: Optional[int] = Field(default=None)


class UserActionRequest(_Creds):
    uid:     int
    action:  str
    payload: Dict[str, Any] = Field(default_factory=dict)


class UserBulkActionRequest(_Creds):
    action:   str
    user_ids: List[int]
    payload:  Dict[str, Any] = Field(default_factory=dict)


class UserCreateRequest(_Creds):
    payload: Dict[str, Any] = Field(...)


class UserUpdateRequest(_Creds):
    uid:     int
    changes: Dict[str, Any] = Field(...)


class UserDeleteRequest(_Creds):
    uid: int


class UserRefundDataRequest(_Creds):
    uid: int


class UserRefundRequest(_Creds):
    uid: int


class OnlineRequest(_Creds):
    query: Dict[str, Optional[str]] = Field(default_factory=dict)


class ManagersRequest(_Creds):
    query: Dict[str, Optional[str]] = Field(default_factory=dict)


class ManagerActionRequest(_Creds):
    mid:     int
    action:  str
    payload: Dict[str, Any] = Field(default_factory=dict)


class ManagerDeleteRequest(_Creds):
    mid: int


class SasGetRequest(_Creds):
    path: str = Field(..., min_length=1, max_length=200)


class SasPostRequest(_Creds):
    path:    str             = Field(..., min_length=1, max_length=200)
    payload: Dict[str, Any] = Field(default_factory=dict)


# ── التحقّق من رأس X-Internal-Secret (fail-closed) ───────────────────────────

async def verify_internal_secret(request: Request) -> None:
    """
    Dependency يُطبَّق على كل نقطة نهاية.

    fail-closed:
      - إن كان SADARA_SAS_INTERNAL_SECRET غير مضبوط → 503 (الخدمة غير مُهيّأة بأمان).
      - إن غاب الرأس أو لم يطابق → 401.
      - المقارنة بـ secrets.compare_digest لمنع timing attack.
    """
    if not _INTERNAL_SECRET:
        logger.error(
            "SADARA_SAS_INTERNAL_SECRET غير مضبوط — الخدمة ترفض كل الطلبات (fail-closed)"
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="الخدمة غير مُهيّأة بأمان — تواصل مع المشرف",
        )

    incoming = request.headers.get("X-Internal-Secret", "")
    if not secrets.compare_digest(incoming, _INTERNAL_SECRET):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="غير مصرّح",
        )


# ── التطبيق ───────────────────────────────────────────────────────────────────

app = FastAPI(
    title="Sadara SAS Sidecar",
    description=(
        "خدمة داخلية بلا حالة على 127.0.0.1:8100. "
        "تُنادى حصراً من بوّابة الصدارة .NET عبر X-Internal-Secret."
    ),
    version="2.0.0",
    docs_url="/docs" if os.environ.get("SADARA_SAS_DOCS", "0") == "1" else None,
    redoc_url=None,
)

_DEP = [Depends(verify_internal_secret)]


# ── Health check (بلا مصادقة) ─────────────────────────────────────────────────

@app.get("/health", tags=["internal"])
async def health() -> Dict[str, str]:
    """فحص سريع: يعيد 200 + {"status": "ok"}."""
    return {"status": "ok"}


# ══════════════════════════════════════════════════════════════════════════════
# نقاط النهاية الأصلية
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/login", tags=["sas"], dependencies=_DEP)
async def login(body: LoginRequest) -> Any:
    """
    تسجيل دخول صامت لنظام SAS4 الإداري.

    عقد .NET: POST /login  { serverUrl, username, password }
    → { success, sessionHandle, message }
    """
    try:
        async with SASClient(body.serverUrl, body.username, body.password) as sas:
            token_preview = (sas._token or "")[:4] + "…" if sas._token else "(none)"
            logger.info("تسجيل دخول SAS ناجح [token=%s]", token_preview)
            return {"success": True, "sessionHandle": sas._token, "message": "تم تسجيل الدخول"}
    except SASError as exc:
        logger.warning("فشل تسجيل الدخول SAS: %s", _safe_msg(exc))
        return JSONResponse(
            status_code=status.HTTP_200_OK,
            content={"success": False, "sessionHandle": None,
                     "message": "تعذّر تسجيل الدخول لنظام الساس"},
        )
    except Exception as exc:
        logger.error("خطأ غير متوقّع في /login: %s", _safe_msg(exc))
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY,
                            detail="خدمة الساس غير متاحة حالياً")


@app.post("/dashboard", tags=["sas"], dependencies=_DEP)
async def dashboard(body: DashboardRequest) -> Any:
    """
    لوحة الوكيل: subscribers + finance.

    عقد .NET: POST /dashboard  { serverUrl, username, password }
    → { subscribers: {...}, finance: {...} }
    """
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_dashboard)


@app.post("/subscribers", tags=["sas"], dependencies=_DEP)
async def subscribers(body: SubscribersRequest) -> Any:
    """
    قائمة مشتركي الوكيل مع وسائط استعلام.

    عقد .NET: POST /subscribers  { serverUrl, username, password, query:{page,count,search,…} }
    → JSON خام (SAS index/user)
    """
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_subscribers, query=body.query)


@app.post("/report", tags=["sas"], dependencies=_DEP)
async def report(body: ReportRequest) -> Any:
    """
    تقرير الوكيل (المديرون/البلنك).

    عقد .NET: POST /report  { serverUrl, username, password, query:{} }
    → JSON خام (SAS index/manager)
    """
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_report, query=body.query)


@app.post("/packages", tags=["sas"], dependencies=_DEP)
async def packages(body: PackagesRequest) -> Any:
    """
    قائمة باقات/بروفايلات SAS4.

    عقد .NET: POST /packages  { serverUrl, username, password }
    → JSON خام (مصفوفة [{id, name, …}])
    """
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_packages)


@app.post("/finance", tags=["sas"], dependencies=_DEP)
async def finance(body: FinanceRequest) -> Any:
    """
    ملخّص مالي من advancedDashboard/finance.

    عقد .NET: POST /finance  { serverUrl, username, password }
    → JSON خام
    """
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_finance)


@app.post("/system-health", tags=["sas"], dependencies=_DEP)
async def system_health(body: SystemHealthRequest) -> Any:
    """
    صحّة النظام من advancedDashboard/systemHealth.

    عقد .NET: POST /system-health  { serverUrl, username, password }
    → JSON خام
    """
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_system_health)


@app.post("/renewal/candidates", tags=["sas"], dependencies=_DEP)
async def renewal_candidates(body: RenewalCandidatesRequest) -> Any:
    """
    المشتركون الأقرب انتهاءً خلال `days` يوماً.

    عقد .NET: POST /renewal/candidates  { serverUrl, username, password, days?, query? }
    → [{ id, username, name, expiry, profile }]
    """
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_renewal_candidates,
                           days=body.days, extra_query=body.query)


@app.post("/renewal/bulk", tags=["sas"], dependencies=_DEP)
async def renewal_bulk(body: RenewalBulkRequest) -> Any:
    """
    تجديد/تفعيل مجموعة مشتركين دفعةً (idempotent بـ uuid5، فشل جزئي).

    عقد .NET: POST /renewal/bulk  { serverUrl, username, password,
                                    subscriberIds:[], months?, profileId?, dryRun? }
    → [{ id, ok, message }]
    """
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _execute_renewal_bulk,
                           subscriber_ids=body.subscriberIds,
                           months=body.months,
                           profile_id=body.profileId,
                           dry_run=body.dryRun)


# ══════════════════════════════════════════════════════════════════════════════
# تفاصيل المشترك (قراءة)
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/users/detail", tags=["sas-users"], dependencies=_DEP)
async def user_detail(body: UserDetailRequest) -> Any:
    """
    كل بيانات مشترك (GET user/{id}).

    عقد .NET: POST /users/detail  { serverUrl, username, password, uid }
    → JSON خام المشترك (مُنقَّى من كلمات المرور/أسرار NAS)
    """
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_user_detail, uid=body.uid)


@app.post("/users/overview", tags=["sas-users"], dependencies=_DEP)
async def user_overview(body: UserOverviewRequest) -> Any:
    """
    نظرة عامة على مشترك (GET user/overview/{id}).

    عقد .NET: POST /users/overview  { serverUrl, username, password, uid }
    → JSON خام (مُنقَّى)
    """
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_user_overview, uid=body.uid)


@app.post("/users/history", tags=["sas-users"], dependencies=_DEP)
async def user_history(body: UserHistoryRequest) -> Any:
    """
    سجلّ المشترك (POST index/UserHistory/{id}).

    عقد .NET: POST /users/history  { serverUrl, username, password, uid,
                                     page?, count?, sortBy?, direction?, search? }
    → JSON خام (بيانات الصفحة)
    """
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_user_history,
                           uid=body.uid, page=body.page, count=body.count,
                           sort_by=body.sortBy, direction=body.direction,
                           search=body.search)


@app.post("/users/extend-data", tags=["sas-users"], dependencies=_DEP)
async def user_extend_data(body: UserExtendDataRequest) -> Any:
    """
    بيانات التمديد + الباقات المسموحة (لملء نموذج التجديد).

    عقد .NET: POST /users/extend-data  { serverUrl, username, password, uid, profile_id? }
    → { extension: {...}, allowed_extensions: {...}|null }
    """
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_user_extend_data,
                           uid=body.uid, profile_id=body.profile_id)


# ══════════════════════════════════════════════════════════════════════════════
# إجراءات المشترك المفردة والجماعية (كتابة)
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/users/action", tags=["sas-users"], dependencies=_DEP)
async def user_action(body: UserActionRequest) -> Any:
    """
    تنفيذ إجراء SAS على مشترك واحد.

    الإجراءات المسموحة: activate · extend · changeProfile · addTraffic ·
                        deposit · withdraw · ping · rename

    عقد .NET: POST /users/action  { serverUrl, username, password,
                                    uid, action, payload? }
    → JSON خام من SAS
    """
    route = _USER_ACTIONS.get(body.action)
    if not route:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"إجراء غير مسموح — المتاح: {', '.join(_USER_ACTIONS)}",
        )
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _exec_user_action,
                           uid=body.uid, route=route, payload=body.payload)


@app.post("/users/bulk-action", tags=["sas-users"], dependencies=_DEP)
async def user_bulk_action(body: UserBulkActionRequest) -> Any:
    """
    تنفيذ إجراء واحد على عدة مشتركين دفعةً (حدّ أقصى 300).

    - كل مشترك يحصل على transaction_id فريد (idempotent).
    - فشل جزئي: لا يوقف الدفعة.

    عقد .NET: POST /users/bulk-action  { serverUrl, username, password,
                                         action, user_ids:[], payload? }
    → { action, total, ok, failed, results:[{user_id, ok, error?}] }
    """
    route = _USER_ACTIONS.get(body.action)
    if not route:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"إجراء غير مسموح — المتاح: {', '.join(_USER_ACTIONS)}",
        )
    ids = list(dict.fromkeys(int(u) for u in (body.user_ids or [])))[:_BULK_CAP]
    if not ids:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="لا مشتركين محدَّدين")
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _exec_bulk_action,
                           action=body.action, route=route,
                           ids=ids, payload=body.payload)


# ══════════════════════════════════════════════════════════════════════════════
# إنشاء / تعديل / حذف / استرداد المشترك
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/users/create", tags=["sas-users"], dependencies=_DEP)
async def user_create(body: UserCreateRequest) -> Any:
    """
    إنشاء مشترك جديد (POST user).

    عقد .NET: POST /users/create  { serverUrl, username, password, payload:{…} }
    → JSON خام من SAS
    """
    p = dict(body.payload or {})
    if not str(p.get("username") or "").strip():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="اسم المستخدم مطلوب")
    if not str(p.get("password") or ""):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="كلمة المرور مطلوبة")
    p.setdefault("confirm_password", p.get("password"))
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _exec_user_create, payload=p)


@app.post("/users/update", tags=["sas-users"], dependencies=_DEP)
async def user_update(body: UserUpdateRequest) -> Any:
    """
    تعديل مشترك عبر «تحميل-دمج-حفظ» (الحقول المسموحة فقط).

    يجلب البيانات الحالية أولاً لمنع مسح الحقول غير المُغيَّرة.

    عقد .NET: POST /users/update  { serverUrl, username, password, uid, changes:{…} }
    → JSON خام من SAS
    """
    bad = set(body.changes) - _UPDATABLE
    if bad:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"حقول غير قابلة للتعديل: {', '.join(sorted(bad))}",
        )
    if not body.changes:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="لا تغييرات")
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _exec_user_update, uid=body.uid, changes=body.changes)


@app.post("/users/delete", tags=["sas-users"], dependencies=_DEP)
async def user_delete(body: UserDeleteRequest) -> Any:
    """
    حذف مشترك (DELETE user/{id}).

    عقد .NET: POST /users/delete  { serverUrl, username, password, uid }
    → JSON خام من SAS
    """
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _exec_user_delete, uid=body.uid)


@app.post("/users/refund-data", tags=["sas-users"], dependencies=_DEP)
async def user_refund_data(body: UserRefundDataRequest) -> Any:
    """
    بيانات الإلغاء/الاسترداد قبل التنفيذ (GET user/refundData/{id}).

    عقد .NET: POST /users/refund-data  { serverUrl, username, password, uid }
    → JSON خام (مُنقَّى)
    """
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_user_refund_data, uid=body.uid)


@app.post("/users/refund", tags=["sas-users"], dependencies=_DEP)
async def user_refund(body: UserRefundRequest) -> Any:
    """
    تنفيذ الإلغاء والاسترداد (GET user/refund/{id}).

    عقد .NET: POST /users/refund  { serverUrl, username, password, uid }
    → JSON خام من SAS
    """
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _exec_user_refund, uid=body.uid)


# ══════════════════════════════════════════════════════════════════════════════
# المتصلون الآن
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/online", tags=["sas"], dependencies=_DEP)
async def online(body: OnlineRequest) -> Any:
    """
    الجلسات المتصلة الآن (index/online).

    عقد .NET: POST /online  { serverUrl, username, password, query:{page,count,search,…} }
    → JSON خام (مُنقَّى)
    """
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_online, query=body.query)


# ══════════════════════════════════════════════════════════════════════════════
# الوكلاء (managers)
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/managers", tags=["sas-managers"], dependencies=_DEP)
async def managers(body: ManagersRequest) -> Any:
    """
    قائمة الوكلاء الكاملة (POST index/manager).

    عقد .NET: POST /managers  { serverUrl, username, password, query:{page,count,search,…} }
    → JSON خام { data:[…], total }
    """
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_managers, query=body.query)


@app.post("/managers/action", tags=["sas-managers"], dependencies=_DEP)
async def manager_action(body: ManagerActionRequest) -> Any:
    """
    إجراء على وكيل: deposit · withdraw · addRewardPoints · deductRewardPoints ·
                    payDebt · add · edit · rename.

    عقد .NET: POST /managers/action  { serverUrl, username, password,
                                       mid, action, payload? }
    → JSON خام من SAS
    """
    route_tmpl = _MANAGER_ACTIONS.get(body.action)
    if not route_tmpl:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"إجراء غير مسموح — المتاح: {', '.join(_MANAGER_ACTIONS)}",
        )
    route = route_tmpl.format(mid=body.mid)
    p = dict(body.payload or {})
    if body.action != "add":   # الإضافة إنشاء جديد بلا manager_id
        p.setdefault("manager_id", body.mid)
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _exec_manager_action, route=route, payload=p)


@app.post("/managers/delete", tags=["sas-managers"], dependencies=_DEP)
async def manager_delete(body: ManagerDeleteRequest) -> Any:
    """
    حذف وكيل (DELETE manager/{id}).

    عقد .NET: POST /managers/delete  { serverUrl, username, password, mid }
    → JSON خام من SAS
    """
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _exec_manager_delete, mid=body.mid)


# ══════════════════════════════════════════════════════════════════════════════
# البروكسي العام المقيَّد بقائمة بيضاء
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/sas/get", tags=["sas-proxy"], dependencies=_DEP)
async def sas_proxy_get(body: SasGetRequest) -> Any:
    """
    بروكسي GET مُقيَّد بـ _GET_ALLOW.

    عقد .NET: POST /sas/get  { serverUrl, username, password, path }
    → JSON خام (مُنقَّى)

    يرفض أي مسار خارج القائمة البيضاء بـ 400.
    """
    p = (body.path or "").strip().strip("/")
    if not any(rx.match(p) for rx in _GET_ALLOW_RE):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="مسار غير مسموح في قائمة _GET_ALLOW")
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _exec_proxy_get, path=p)


@app.post("/sas/post", tags=["sas-proxy"], dependencies=_DEP)
async def sas_proxy_post(body: SasPostRequest) -> Any:
    """
    بروكسي POST مُقيَّد بـ _POST_ALLOW.

    عقد .NET: POST /sas/post  { serverUrl, username, password, path, payload? }
    → JSON خام (مُنقَّى)

    يرفض أي مسار خارج القائمة البيضاء بـ 400.
    """
    p = (body.path or "").strip().strip("/")
    if not any(rx.match(p) for rx in _POST_ALLOW_RE):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="مسار غير مسموح في قائمة _POST_ALLOW")
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _exec_proxy_post, path=p, payload=body.payload or {})


# ══════════════════════════════════════════════════════════════════════════════
# دوال مساعدة داخلية
# ══════════════════════════════════════════════════════════════════════════════

async def _call_sas(server_url: str, username: str, password: str,
                    fetcher, **kwargs) -> Any:
    """
    غلاف مشترك: يفتح SASClient ويُفوّض لـ fetcher، يُترجم SASError إلى 502.
    لا يُسجَّل username/password — يُسجَّل المسار فقط.
    """
    try:
        async with SASClient(server_url, username, password) as sas:
            return await fetcher(sas, **kwargs)
    except SASError as exc:
        logger.warning("فشل نداء SAS: %s", _safe_msg(exc))
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY,
                            detail="تعذّر جلب البيانات من خدمة الساس")
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("خطأ غير متوقّع في نداء SAS: %s", _safe_msg(exc))
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY,
                            detail="خدمة الساس غير متاحة حالياً")


# ── حجب الأسرار (منقول حرفياً من sas_panel.py) ───────────────────────────────
_SECRET_KEYS = re.compile(
    r"(password|secret|api_password|snmp_community|nas_details|\bpin\b)", re.I
)


def _redact(obj: Any) -> Any:
    """يستبدل قيم المفاتيح الحسّاسة بـ '***' بشكل متكرّر على أي بنية JSON."""
    if isinstance(obj, dict):
        return {k: ("***" if _SECRET_KEYS.search(str(k)) else _redact(v))
                for k, v in obj.items()}
    if isinstance(obj, list):
        return [_redact(x) for x in obj]
    return obj


def _safe_msg(exc: Exception) -> str:
    """يعيد رسالة الخطأ بعد تنظيف أي تسريب محتمل للاعتماد."""
    msg = str(exc)
    for kw in ("password", "كلمة المرور", "token", "secret"):
        if kw.lower() in msg.lower():
            return "[رسالة محجوبة لاحتوائها كلمة محجوبة]"
    return msg[:300]


# ── Fetchers الأصليون ──────────────────────────────────────────────────────────

async def _fetch_dashboard(sas: SASClient) -> Dict[str, Any]:
    subscribers_data = await sas.dashboard_subscribers()
    try:
        finance_data = await sas.dashboard_finance()
    except SASError:
        finance_data = {}
    return {"subscribers": subscribers_data, "finance": finance_data}


async def _fetch_subscribers(sas: SASClient,
                              query: Dict[str, Optional[str]]) -> Any:
    page      = int(query.get("page")      or 1)
    count     = int(query.get("count")     or 50)
    search    = str(query.get("search")    or "")
    sort_by   = str(query.get("sortBy")    or "id")
    direction = str(query.get("direction") or "asc")
    return await sas.users(page=page, count=count, search=search,
                           sort_by=sort_by, direction=direction)


async def _fetch_report(sas: SASClient,
                        query: Dict[str, Optional[str]]) -> Any:
    page   = int(query.get("page")   or 1)
    count  = int(query.get("count")  or 100)
    search = str(query.get("search") or "")
    return await sas.managers_full(page=page, count=count, search=search)


async def _fetch_packages(sas: SASClient) -> Any:
    return await sas.profiles()


async def _fetch_finance(sas: SASClient) -> Any:
    return await sas.dashboard_finance()


async def _fetch_system_health(sas: SASClient) -> Any:
    return await sas.dashboard_system_health()


async def _fetch_renewal_candidates(
    sas: SASClient,
    days: int,
    extra_query: Dict[str, Any],
) -> List[Dict[str, Any]]:
    now = datetime.now(timezone.utc)
    candidates: List[Dict[str, Any]] = []
    MAX_RECORDS = 2000
    fetched = 0
    async for row in sas.iter_all("user", count=200, **extra_query):
        fetched += 1
        if fetched > MAX_RECORDS:
            logger.warning("renewal/candidates: تجاوز حدّ %d سجل — إيقاف الجلب", MAX_RECORDS)
            break
        raw_exp = row.get("expiration") or row.get("expire") or ""
        if not raw_exp:
            continue
        exp_dt: Optional[datetime] = None
        for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
            try:
                parsed = datetime.strptime(str(raw_exp)[:19], fmt)
                exp_dt = parsed.replace(tzinfo=timezone.utc)
                break
            except ValueError:
                continue
        if exp_dt is None:
            continue
        delta = (exp_dt - now).total_seconds()
        if delta <= days * 86400:
            name = " ".join(filter(None, [
                row.get("firstname", ""),
                row.get("lastname", ""),
            ])).strip() or row.get("username", "")
            candidates.append({
                "id":       row.get("id"),
                "username": row.get("username"),
                "name":     name,
                "expiry":   raw_exp,
                "profile":  row.get("profile") or row.get("profile_name"),
            })
    candidates.sort(key=lambda r: str(r.get("expiry") or ""))
    return candidates


async def _execute_renewal_bulk(
    sas: SASClient,
    subscriber_ids: List[int],
    months: Optional[int],
    profile_id: Optional[Any],
    dry_run: bool,
) -> List[Dict[str, Any]]:
    minute_key   = datetime.now(timezone.utc).strftime("%Y%m%d%H%M")
    base_uuid_ns = uuid.NAMESPACE_URL
    results: List[Dict[str, Any]] = []

    if dry_run:
        for sub_id in subscriber_ids:
            op_uuid = str(uuid.uuid5(base_uuid_ns, f"{sas.base_url}:{sub_id}:{minute_key}"))
            action  = "extend" if months is not None else "activate"
            results.append({
                "id":      sub_id,
                "ok":      None,
                "message": (
                    f"[dryRun] سيُنفَّذ {action} — uuid={op_uuid}"
                    + (f" — months={months}"       if months      else "")
                    + (f" — profileId={profile_id}" if profile_id else "")
                ),
            })
        return results

    for sub_id in subscriber_ids:
        op_uuid = str(uuid.uuid5(base_uuid_ns, f"{sas.base_url}:{sub_id}:{minute_key}"))
        try:
            if months is not None:
                payload_body: Dict[str, Any] = {"uuid": op_uuid}
                if profile_id is not None:
                    payload_body["profile_id"] = profile_id
                resp = await sas.post(f"user/{sub_id}/extend", payload_body)
            else:
                resp = await sas.post(f"user/{sub_id}/activate", {"uuid": op_uuid})

            ok = True
            if isinstance(resp, dict):
                status_code = resp.get("status") or resp.get("statusCode")
                if status_code is not None and int(status_code) >= 400:
                    ok = False
                elif resp.get("success") is False:
                    ok = False
            msg = ""
            if isinstance(resp, dict):
                msg = str(resp.get("message") or resp.get("msg") or "تمّ")
            results.append({"id": sub_id, "ok": ok, "message": msg})

        except SASError as exc:
            logger.warning("renewal/bulk: فشل المشترك %d: %s", sub_id, _safe_msg(exc))
            results.append({"id": sub_id, "ok": False, "message": _safe_msg(exc)})
        except Exception as exc:
            logger.error("renewal/bulk: خطأ غير متوقّع للمشترك %d: %s", sub_id, _safe_msg(exc))
            results.append({"id": sub_id, "ok": False, "message": "خطأ داخلي"})

    return results


# ── Fetchers/Executors الجديدة ─────────────────────────────────────────────────

async def _fetch_user_detail(sas: SASClient, uid: int) -> Any:
    res  = await sas.user(uid)
    data = res.get("data", res) if isinstance(res, dict) else res
    return _redact(data)


async def _fetch_user_overview(sas: SASClient, uid: int) -> Any:
    res  = await sas.get(f"user/overview/{uid}")
    data = res.get("data", res) if isinstance(res, dict) else res
    return _redact(data)


async def _fetch_user_history(sas: SASClient, uid: int, page: int, count: int,
                               sort_by: str, direction: str, search: str) -> Any:
    return await sas.post(f"index/UserHistory/{uid}", {
        "page": page, "count": count,
        "sortBy": sort_by, "direction": direction, "search": search,
    })


async def _fetch_user_extend_data(sas: SASClient, uid: int,
                                   profile_id: Optional[int]) -> Any:
    ext     = await sas.get(f"user/extensionData/{uid}")
    allowed = None
    if profile_id is not None:
        allowed = await sas.get(f"allowedExtensions/{profile_id}")
    return {"extension": ext, "allowed_extensions": allowed}


async def _exec_user_action(sas: SASClient, uid: int,
                             route: str, payload: Dict[str, Any]) -> Any:
    body = {"user_id": uid, **(payload or {})}
    return await sas.post(route.format(uid=uid), body)


async def _exec_bulk_action(sas: SASClient, action: str, route: str,
                             ids: List[int], payload: Dict[str, Any]) -> Dict[str, Any]:
    results: List[Dict[str, Any]] = []
    ok = 0
    for uid in ids:
        try:
            body = {"user_id": uid, **(payload or {}),
                    "transaction_id": uuid.uuid4().hex}
            await sas.post(route.format(uid=uid), body)
            ok += 1
            results.append({"user_id": uid, "ok": True})
        except (SASError, Exception) as exc:
            results.append({"user_id": uid, "ok": False,
                            "error": _safe_msg(exc)})
    return {"action": action, "total": len(ids),
            "ok": ok, "failed": len(ids) - ok, "results": results}


async def _exec_user_create(sas: SASClient, payload: Dict[str, Any]) -> Any:
    return await sas.post("user", payload)


async def _exec_user_update(sas: SASClient, uid: int,
                             changes: Dict[str, Any]) -> Any:
    cur  = await sas.user(uid)
    data = cur.get("data", cur) if isinstance(cur, dict) else cur
    if not isinstance(data, dict):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="المشترك غير موجود")
    body: Dict[str, Any] = {"id": uid}
    for k in _UPDATE_BASE:
        body[k] = data.get(k)
    for k, v in changes.items():
        body[k] = v
    if changes.get("password"):
        body["confirm_password"] = changes["password"]
    return await sas.post("user", body)


async def _exec_user_delete(sas: SASClient, uid: int) -> Any:
    return await sas.delete(f"user/{uid}")


async def _fetch_user_refund_data(sas: SASClient, uid: int) -> Any:
    res  = await sas.get(f"user/refundData/{uid}")
    data = res.get("data", res) if isinstance(res, dict) else res
    return _redact(data)


async def _exec_user_refund(sas: SASClient, uid: int) -> Any:
    return await sas.get(f"user/refund/{uid}")


async def _fetch_online(sas: SASClient,
                         query: Dict[str, Optional[str]]) -> Any:
    page   = int(query.get("page")   or 1)
    count  = int(query.get("count")  or 100)
    search = str(query.get("search") or "")
    res    = await sas.online(page=page, count=count, search=search)
    rows   = res.get("data", res) if isinstance(res, dict) else res
    total  = res.get("total")      if isinstance(res, dict) else None
    return {"data": _redact(rows), "total": total, "page": page, "count": count}


async def _fetch_managers(sas: SASClient,
                           query: Dict[str, Optional[str]]) -> Any:
    page   = int(query.get("page")   or 1)
    count  = int(query.get("count")  or 200)
    search = str(query.get("search") or "")
    res    = await sas.managers_full(page=page, count=count, search=search)
    rows   = res.get("data", res) if isinstance(res, dict) else res
    total  = res.get("total")      if isinstance(res, dict) else None
    return {"data": rows, "total": total, "page": page, "count": count}


async def _exec_manager_action(sas: SASClient,
                                route: str, payload: Dict[str, Any]) -> Any:
    return await sas.post(route, payload)


async def _exec_manager_delete(sas: SASClient, mid: int) -> Any:
    return await sas.delete(f"manager/{mid}")


async def _exec_proxy_get(sas: SASClient, path: str) -> Any:
    res = await sas.get(path)
    return _redact(res)


async def _exec_proxy_post(sas: SASClient, path: str,
                            payload: Dict[str, Any]) -> Any:
    res = await sas.post(path, payload)
    return _redact(res)
