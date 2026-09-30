"""
خدمة الساس الداخلية (SAS Sidecar) — FastAPI على 127.0.0.1:8100
================================================================
خدمة نحيلة تجمع وضعين:
  1. بروكسي بلا حالة (النقاط الأصلية): تستقبل اعتماد SAS4 وتناديه مباشرةً.
  2. طبقة تخزين محلية (النقاط الجديدة): تخزّن مشتركي كل حساب في SQLite محلية
     وتوفّر قراءة/تصريح/مقاطعة بلا نداء SAS.

الأمان:
  - تستمع على 127.0.0.1 فقط (loopback).
  - fail-closed: كل طلب يحمل X-Internal-Secret مطابقاً لـ SADARA_SAS_INTERNAL_SECRET.
  - مقارنة بزمن ثابت (secrets.compare_digest) لمنع هجمات التوقيت.
  - لا تُسجَّل أسرار أو كلمات مرور في أي log.
  - العزل الصارم بـ account_id: كل استعلام مُقيَّد به (لا تُرجع بيانات account آخر).

قاعدة البيانات:
  - SQLite في service/data/sas.db (مسار يُضبط بـ SADARA_SAS_DB_PATH).
  - تُنشأ تلقائياً عند أول تشغيل (DDL في _init_db).
"""
from __future__ import annotations

import json
import logging
import os
import re
import secrets
import sqlite3
import sys
import uuid
from contextlib import contextmanager
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterator, List, Optional

# ── ضبط مسار الاستيراد ────────────────────────────────────────────────────────
_BACKEND_APP = os.path.join(os.path.dirname(__file__), "..", "backend", "app")
if _BACKEND_APP not in sys.path:
    sys.path.insert(0, os.path.abspath(_BACKEND_APP))

from integrations.sas_client import SASClient, SASError        # noqa: E402
from integrations.sas_user_client import SASUserClient          # noqa: E402
from sas_premises import router as _premises_router, PREMISES_DDL  # noqa: E402 — اسم فريد لتفادي تصادم حزمة backend/app/premises عبر sys.path

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

# ── قاعدة البيانات المحلية ────────────────────────────────────────────────────
_DEFAULT_DB = os.path.join(os.path.dirname(__file__), "data", "sas.db")
_DB_PATH: str = os.environ.get("SADARA_SAS_DB_PATH", _DEFAULT_DB)

# سقف المشتركين في كل مزامنة (يتطابق مع sas_subscriber_cap في backend)
_SUBSCRIBER_CAP = 50_000


def _get_conn() -> sqlite3.Connection:
    """يفتح اتصالاً بـ SQLite مع WAL للأداء."""
    conn = sqlite3.connect(_DB_PATH, check_same_thread=False, timeout=15)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    conn.row_factory = sqlite3.Row
    return conn


@contextmanager
def _db() -> Iterator[sqlite3.Connection]:
    """Context manager يمنح اتصالاً يُغلق تلقائياً."""
    conn = _get_conn()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def _init_db() -> None:
    """ينشئ الجداول إن لم تكن موجودة (idempotent)."""
    Path(_DB_PATH).parent.mkdir(parents=True, exist_ok=True)
    with _db() as conn:
        # جداول وحدة العقارات (premises + premises_subscribers + npn_counter)
        conn.executescript(PREMISES_DDL)
        conn.executescript("""
        CREATE TABLE IF NOT EXISTS local_subscribers (
            account_id   TEXT    NOT NULL,
            sub_id       INTEGER NOT NULL,
            username     TEXT    NOT NULL DEFAULT '',
            name         TEXT    NOT NULL DEFAULT '',
            profile      TEXT    NOT NULL DEFAULT '',
            status       TEXT    NOT NULL DEFAULT '',
            online       INTEGER NOT NULL DEFAULT 0,
            enabled      INTEGER NOT NULL DEFAULT 1,
            expiration   TEXT    NOT NULL DEFAULT '',
            phone        TEXT    NOT NULL DEFAULT '',
            city         TEXT    NOT NULL DEFAULT '',
            company_id   TEXT    NOT NULL DEFAULT '',
            owner_user_id TEXT   NOT NULL DEFAULT '',
            raw_json     TEXT    NOT NULL DEFAULT '{}',
            synced_at    TEXT    NOT NULL,
            PRIMARY KEY (account_id, sub_id)
        );

        CREATE INDEX IF NOT EXISTS idx_ls_account
            ON local_subscribers (account_id);
        CREATE INDEX IF NOT EXISTS idx_ls_expiration
            ON local_subscribers (account_id, expiration);
        CREATE INDEX IF NOT EXISTS idx_ls_status
            ON local_subscribers (account_id, status);

        CREATE TABLE IF NOT EXISTS agent_reports (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            account_id      TEXT    NOT NULL,
            company_id      TEXT    NOT NULL DEFAULT '',
            owner_user_id   TEXT    NOT NULL DEFAULT '',
            declared_total  INTEGER NOT NULL,
            declared_active INTEGER NOT NULL DEFAULT 0,
            note            TEXT    NOT NULL DEFAULT '',
            submitted_by    TEXT    NOT NULL DEFAULT '',
            created_at      TEXT    NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_ar_account
            ON agent_reports (account_id, created_at DESC);

        CREATE TABLE IF NOT EXISTS tickets (
            id             INTEGER PRIMARY KEY AUTOINCREMENT,
            company_id     TEXT    NOT NULL,
            owner_user_id  TEXT    NOT NULL,
            subscriber_ref TEXT    NOT NULL DEFAULT '',
            subject        TEXT    NOT NULL,
            body           TEXT    NOT NULL DEFAULT '',
            category       TEXT    NOT NULL DEFAULT 'other',
            priority       TEXT    NOT NULL DEFAULT 'normal',
            status         TEXT    NOT NULL DEFAULT 'open',
            created_by     TEXT    NOT NULL DEFAULT '',
            created_at     TEXT    NOT NULL,
            updated_at     TEXT    NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_tk_owner
            ON tickets (company_id, owner_user_id, status);
        CREATE INDEX IF NOT EXISTS idx_tk_created
            ON tickets (company_id, owner_user_id, created_at DESC);

        CREATE TABLE IF NOT EXISTS ticket_replies (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            ticket_id   INTEGER NOT NULL REFERENCES tickets(id),
            body        TEXT    NOT NULL,
            is_internal INTEGER NOT NULL DEFAULT 0,
            author      TEXT    NOT NULL DEFAULT '',
            created_at  TEXT    NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_tr_ticket
            ON ticket_replies (ticket_id, created_at);
        """)
    logger.info("[DB] قاعدة البيانات جاهزة: %s", _DB_PATH)


# ── قوائم بيضاء للبروكسي العام ────────────────────────────────────────────────
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

_BULK_CAP = 300

# ── مفاتيح الأسرار للحجب ──────────────────────────────────────────────────────
_SECRET_KEYS = re.compile(
    r"(password|secret|api_password|snmp_community|nas_details|\bpin\b)", re.I
)


# ═════════════════════════════════════════════════════════════════════════════
# نماذج Pydantic — النقاط الأصلية
# ═════════════════════════════════════════════════════════════════════════════

class _Creds(BaseModel):
    serverUrl: str = Field(..., description="عنوان خادم SAS")
    username:  str = Field(..., description="اسم مستخدم المدير/الوكيل في SAS")
    password:  str = Field(..., description="كلمة المرور — لا تُسجَّل")


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
    days:        int            = Field(default=7, ge=1, le=365)
    query:       Dict[str, Any] = Field(default_factory=dict)


class RenewalBulkRequest(_Creds):
    subscriberIds: List[int]        = Field(...)
    months:        Optional[int]    = Field(default=None, ge=1, le=24)
    profileId:     Optional[Any]    = Field(default=None)
    dryRun:        bool             = Field(default=False)


class UserDetailRequest(_Creds):
    uid: int


class UserOverviewRequest(_Creds):
    uid: int


class UserHistoryRequest(_Creds):
    uid:       int
    page:      int = Field(default=1, ge=1)
    count:     int = Field(default=50, ge=1, le=500)
    sortBy:    str = Field(default="id")
    direction: str = Field(default="desc")
    search:    str = Field(default="")


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


# ═════════════════════════════════════════════════════════════════════════════
# نماذج Pydantic — النقاط الجديدة (التخزين المحلي)
# ═════════════════════════════════════════════════════════════════════════════

class _LocalBase(BaseModel):
    """الحقول الأساسية المشتركة في كل طلبات التخزين المحلي."""
    accountId:    str = Field(..., description="GUID حساب الساس في الصدارة")
    companyId:    str = Field(default="", description="معرّف الشركة (اختياري)")
    ownerUserId:  str = Field(default="", description="معرّف مستخدم الوكيل (اختياري)")


class _LocalCreds(_LocalBase):
    """كريدنشيال SAS مضافة للطلبات التي تحتاج نداء حيّاً."""
    serverUrl: str = Field(..., description="عنوان خادم SAS")
    username:  str = Field(..., description="اسم مستخدم SAS")
    password:  str = Field(..., description="كلمة المرور — لا تُسجَّل")


class AccountTestRequest(_LocalCreds):
    """اختبار اتصال: POST /account/test"""
    pass


class SyncRequest(_LocalCreds):
    """مزامنة مشتركي الحساب: POST /sync"""
    pass


class LocalSubscribersRequest(_LocalBase):
    """استعلام محلي سريع: POST /subscribers/local"""
    search:   Optional[str] = None
    status:   Optional[str] = None   # active | expired | manual
    expiring: Optional[str] = None   # overdue | today | soon3 | soon7
    page:     int = Field(default=1, ge=1)
    count:    int = Field(default=50, ge=1, le=500)


class SubscriberSummaryRequest(_LocalBase):
    """ملخّص مشتركين محلي رخيص: POST /subscribers/summary"""
    pass


class ReportSubmitRequest(_LocalBase):
    """تقديم تصريح: POST /report/submit"""
    declared_total:  int = Field(..., ge=0, le=10_000_000)
    declared_active: int = Field(default=0, ge=0)
    note:            str = Field(default="")
    submitted_by:    str = Field(default="")


class ReportListRequest(_LocalBase):
    """قائمة التصاريح: POST /report/list"""
    pass


class ReconciliationRequest(_LocalBase):
    """مقاطعة: POST /reconciliation — يمكن تمرير creds لجلب عدد حيّ من SAS"""
    # حقول الاعتماد اختيارية: إن غابت يُستخدم العدد المحلي
    serverUrl: Optional[str] = None
    username:  Optional[str] = None
    password:  Optional[str] = None


# ═════════════════════════════════════════════════════════════════════════════
# نماذج Pydantic — التذاكر المحلية (tickets)
# ═════════════════════════════════════════════════════════════════════════════

_TK_CATEGORIES = ("complaint", "outage", "billing", "speed", "other")
_TK_STATUSES   = ("open", "in_progress", "resolved", "closed")
_TK_PRIORITIES = ("low", "normal", "high", "urgent")

_TK_CATEGORY_AR = {
    "complaint": "شكوى", "outage": "انقطاع",
    "billing": "فوترة/رصيد", "speed": "بطء السرعة", "other": "أخرى",
}
_TK_STATUS_AR = {
    "open": "مفتوحة", "in_progress": "قيد المعالجة",
    "resolved": "محلولة", "closed": "مغلقة",
}


class _TkBase(BaseModel):
    """الحقول الأساسية المشتركة لكل نقاط التذاكر."""
    companyId:    str = Field(..., description="معرّف الشركة")
    ownerUserId:  str = Field(..., description="معرّف مستخدم الوكيل (المالك)")


class TicketStatsRequest(_TkBase):
    """POST /tickets/stats"""
    pass


class TicketListRequest(_TkBase):
    """POST /tickets/list"""
    status:   Optional[str] = None
    category: Optional[str] = None
    search:   Optional[str] = None
    page:     int = Field(default=1, ge=1)
    count:    int = Field(default=50, ge=1, le=500)


class TicketCreateRequest(_TkBase):
    """POST /tickets/create"""
    subject:        str = Field(..., min_length=3, max_length=200)
    body:           str = Field(default="", max_length=4000)
    category:       str = Field(default="other")
    priority:       str = Field(default="normal")
    subscriber_ref: str = Field(default="")
    created_by:     str = Field(default="")


class TicketGetRequest(_TkBase):
    """POST /tickets/get"""
    ticket_id: int


class TicketReplyRequest(_TkBase):
    """POST /tickets/reply"""
    ticket_id:   int
    body:        str  = Field(..., min_length=1, max_length=4000)
    is_internal: bool = Field(default=False)
    author:      str  = Field(default="")


class TicketUpdateRequest(_TkBase):
    """POST /tickets/update"""
    ticket_id: int
    status:    Optional[str] = None
    priority:  Optional[str] = None
    category:  Optional[str] = None


# ═════════════════════════════════════════════════════════════════════════════
# Dependency: التحقّق من السرّ (fail-closed)
# ═════════════════════════════════════════════════════════════════════════════

async def verify_internal_secret(request: Request) -> None:
    """
    fail-closed:
      - SADARA_SAS_INTERNAL_SECRET غير مضبوط → 503.
      - رأس غائب أو غير مطابق → 401.
      - مقارنة بزمن ثابت لمنع timing attack.
    """
    if not _INTERNAL_SECRET:
        logger.error("SADARA_SAS_INTERNAL_SECRET غير مضبوط — الخدمة ترفض كل الطلبات")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="الخدمة غير مُهيّأة بأمان — تواصل مع المشرف",
        )
    incoming = request.headers.get("X-Internal-Secret", "")
    if not secrets.compare_digest(incoming, _INTERNAL_SECRET):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="غير مصرّح")


# ═════════════════════════════════════════════════════════════════════════════
# التطبيق
# ═════════════════════════════════════════════════════════════════════════════

app = FastAPI(
    title="Sadara SAS Sidecar",
    description=(
        "خدمة داخلية على 127.0.0.1:8100 — بروكسي بلا حالة + طبقة تخزين SQLite محلية. "
        "تُنادى حصراً من بوّابة الصدارة .NET عبر X-Internal-Secret."
    ),
    version="3.0.0",
    docs_url="/docs" if os.environ.get("SADARA_SAS_DOCS", "0") == "1" else None,
    redoc_url=None,
)

_DEP = [Depends(verify_internal_secret)]


app.include_router(_premises_router)


@app.on_event("startup")
def _startup() -> None:
    _init_db()


# ═════════════════════════════════════════════════════════════════════════════
# Health
# ═════════════════════════════════════════════════════════════════════════════

@app.get("/health", tags=["internal"])
async def health() -> Dict[str, str]:
    return {"status": "ok"}


# ══════════════════════════════════════════════════════════════════════════════
# النقاط الأصلية (بروكسي بلا حالة)
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/login", tags=["sas"], dependencies=_DEP)
async def login(body: LoginRequest) -> Any:
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
    return await _call_sas(body.serverUrl, body.username, body.password, _fetch_dashboard)


@app.post("/subscribers", tags=["sas"], dependencies=_DEP)
async def subscribers(body: SubscribersRequest) -> Any:
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_subscribers, query=body.query)


@app.post("/report", tags=["sas"], dependencies=_DEP)
async def report(body: ReportRequest) -> Any:
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_report, query=body.query)


@app.post("/packages", tags=["sas"], dependencies=_DEP)
async def packages(body: PackagesRequest) -> Any:
    return await _call_sas(body.serverUrl, body.username, body.password, _fetch_packages)


@app.post("/finance", tags=["sas"], dependencies=_DEP)
async def finance(body: FinanceRequest) -> Any:
    return await _call_sas(body.serverUrl, body.username, body.password, _fetch_finance)


@app.post("/system-health", tags=["sas"], dependencies=_DEP)
async def system_health(body: SystemHealthRequest) -> Any:
    return await _call_sas(body.serverUrl, body.username, body.password, _fetch_system_health)


@app.post("/renewal/candidates", tags=["sas"], dependencies=_DEP)
async def renewal_candidates(body: RenewalCandidatesRequest) -> Any:
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_renewal_candidates,
                           days=body.days, extra_query=body.query)


@app.post("/renewal/bulk", tags=["sas"], dependencies=_DEP)
async def renewal_bulk(body: RenewalBulkRequest) -> Any:
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _execute_renewal_bulk,
                           subscriber_ids=body.subscriberIds,
                           months=body.months,
                           profile_id=body.profileId,
                           dry_run=body.dryRun)


@app.post("/users/detail", tags=["sas-users"], dependencies=_DEP)
async def user_detail(body: UserDetailRequest) -> Any:
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_user_detail, uid=body.uid)


@app.post("/users/overview", tags=["sas-users"], dependencies=_DEP)
async def user_overview(body: UserOverviewRequest) -> Any:
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_user_overview, uid=body.uid)


@app.post("/users/history", tags=["sas-users"], dependencies=_DEP)
async def user_history(body: UserHistoryRequest) -> Any:
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_user_history,
                           uid=body.uid, page=body.page, count=body.count,
                           sort_by=body.sortBy, direction=body.direction,
                           search=body.search)


@app.post("/users/extend-data", tags=["sas-users"], dependencies=_DEP)
async def user_extend_data(body: UserExtendDataRequest) -> Any:
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_user_extend_data,
                           uid=body.uid, profile_id=body.profile_id)


@app.post("/users/action", tags=["sas-users"], dependencies=_DEP)
async def user_action(body: UserActionRequest) -> Any:
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


@app.post("/users/create", tags=["sas-users"], dependencies=_DEP)
async def user_create(body: UserCreateRequest) -> Any:
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
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _exec_user_delete, uid=body.uid)


@app.post("/users/refund-data", tags=["sas-users"], dependencies=_DEP)
async def user_refund_data(body: UserRefundDataRequest) -> Any:
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_user_refund_data, uid=body.uid)


@app.post("/users/refund", tags=["sas-users"], dependencies=_DEP)
async def user_refund(body: UserRefundRequest) -> Any:
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _exec_user_refund, uid=body.uid)


@app.post("/online", tags=["sas"], dependencies=_DEP)
async def online(body: OnlineRequest) -> Any:
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_online, query=body.query)


@app.post("/managers", tags=["sas-managers"], dependencies=_DEP)
async def managers(body: ManagersRequest) -> Any:
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _fetch_managers, query=body.query)


@app.post("/managers/action", tags=["sas-managers"], dependencies=_DEP)
async def manager_action(body: ManagerActionRequest) -> Any:
    route_tmpl = _MANAGER_ACTIONS.get(body.action)
    if not route_tmpl:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"إجراء غير مسموح — المتاح: {', '.join(_MANAGER_ACTIONS)}",
        )
    route = route_tmpl.format(mid=body.mid)
    p = dict(body.payload or {})
    if body.action != "add":
        p.setdefault("manager_id", body.mid)
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _exec_manager_action, route=route, payload=p)


@app.post("/managers/delete", tags=["sas-managers"], dependencies=_DEP)
async def manager_delete(body: ManagerDeleteRequest) -> Any:
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _exec_manager_delete, mid=body.mid)


@app.post("/sas/get", tags=["sas-proxy"], dependencies=_DEP)
async def sas_proxy_get(body: SasGetRequest) -> Any:
    p = (body.path or "").strip().strip("/")
    if not any(rx.match(p) for rx in _GET_ALLOW_RE):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="مسار غير مسموح في قائمة _GET_ALLOW")
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _exec_proxy_get, path=p)


@app.post("/sas/post", tags=["sas-proxy"], dependencies=_DEP)
async def sas_proxy_post(body: SasPostRequest) -> Any:
    p = (body.path or "").strip().strip("/")
    if not any(rx.match(p) for rx in _POST_ALLOW_RE):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="مسار غير مسموح في قائمة _POST_ALLOW")
    return await _call_sas(body.serverUrl, body.username, body.password,
                           _exec_proxy_post, path=p, payload=body.payload or {})


# ══════════════════════════════════════════════════════════════════════════════
# النقاط الجديدة — طبقة التخزين المحلي
# ══════════════════════════════════════════════════════════════════════════════

@app.post("/account/test", tags=["local-storage"], dependencies=_DEP)
async def account_test(body: AccountTestRequest) -> Any:
    """
    اختبار اتصال: يسجّل الدخول ويجلب ملخّص المشتركين.

    عقد .NET: POST /account/test  { serverUrl, username, password, accountId, … }
    → { ok, message, subscribers_count? }
    """
    _guard_account_id(body.accountId)
    try:
        async with SASClient(body.serverUrl, body.username, body.password) as sas:
            res = await sas.dashboard_subscribers()
            data = res.get("data", res) if isinstance(res, dict) else {}
            total = _int(data.get("total"))
            return {"ok": True, "message": "الاتصال ناجح", "subscribers_count": total}
    except SASError as exc:
        logger.warning("[test] فشل اختبار الحساب %s: %s",
                       body.accountId[:8], _safe_msg(exc))
        return {"ok": False, "message": "تعذّر الاتصال بنظام الساس"}
    except Exception as exc:
        logger.error("[test] خطأ غير متوقّع للحساب %s: %s",
                     body.accountId[:8], _safe_msg(exc))
        return {"ok": False, "message": "خطأ داخلي — راجع السجلّ"}


@app.post("/sync", tags=["local-storage"], dependencies=_DEP)
async def sync(body: SyncRequest) -> Any:
    """
    مزامنة مشتركي الحساب من SAS → local_subscribers.

    الاستراتيجية: حذف سجلّات الحساب ثم إدراج (delete+insert أنظف من upsert للـ raw_json).
    يُعيد { count, expiry:{overdue,today,soon3,soon7}, synced_at }.

    عقد .NET: POST /sync  { serverUrl, username, password, accountId, companyId?, ownerUserId? }
    """
    _guard_account_id(body.accountId)
    account_id   = body.accountId
    company_id   = body.companyId   or ""
    owner_user_id = body.ownerUserId or ""

    # جلب المشتركين من SAS
    rows: List[dict] = []
    try:
        async with SASClient(body.serverUrl, body.username, body.password) as sas:
            async for row in sas.iter_users(count=1000):
                rows.append(row)
                if len(rows) >= _SUBSCRIBER_CAP:
                    logger.warning("[sync] الحساب %s تجاوز سقف %d مشترك",
                                   account_id[:8], _SUBSCRIBER_CAP)
                    break
    except SASError as exc:
        logger.warning("[sync] فشل جلب مشتركي الحساب %s: %s",
                       account_id[:8], _safe_msg(exc))
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY,
                            detail="تعذّر جلب المشتركين من نظام الساس")
    except Exception as exc:
        logger.error("[sync] خطأ غير متوقّع للحساب %s: %s",
                     account_id[:8], _safe_msg(exc))
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY,
                            detail="خدمة الساس غير متاحة حالياً")

    synced_at = _utcnow_iso()

    with _db() as conn:
        # حذف القديم أولاً (معزول بـ account_id)
        conn.execute("DELETE FROM local_subscribers WHERE account_id = ?", (account_id,))
        # إدراج الجديد
        for u in rows:
            uid = _int(u.get("id"))
            if not uid:
                continue
            name = " ".join(filter(None, [
                str(u.get("firstname") or ""),
                str(u.get("lastname") or ""),
            ])).strip() or str(u.get("username") or "")
            profile = ""
            pdet = u.get("profile_details") or {}
            if isinstance(pdet, dict):
                profile = str(pdet.get("name") or u.get("profile") or "")
            else:
                profile = str(u.get("profile") or "")
            _st = u.get("status")
            if isinstance(_st, dict):
                sub_status = "active" if _st.get("status") else "expired"
            else:
                sub_status = "active" if str(_st or "").strip().lower() in (
                    "active", "1", "true") else "expired"
            online  = 1 if str(u.get("online_status") or "").lower() in (
                "online", "1", "true") else 0
            enabled = 1 if bool(u.get("enabled", True)) else 0
            # حجب الأسرار في raw_json قبل التخزين
            safe_raw = json.dumps(_redact(u), ensure_ascii=False)
            conn.execute("""
                INSERT INTO local_subscribers
                    (account_id, sub_id, username, name, profile, status,
                     online, enabled, expiration, phone, city,
                     company_id, owner_user_id, raw_json, synced_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, (
                account_id, uid,
                str(u.get("username") or ""),
                name, profile, sub_status,
                online, enabled,
                str(u.get("expiration") or ""),
                str(u.get("phone") or ""),
                str(u.get("city") or ""),
                company_id, owner_user_id,
                safe_raw, synced_at,
            ))

    # حساب عدّادات الانتهاء من السجلّات المُخزَّنة (بلا نداء SAS)
    with _db() as conn:
        cur = conn.execute(
            "SELECT expiration FROM local_subscribers WHERE account_id = ?",
            (account_id,))
        expiry = _expiry_counts([r[0] for r in cur.fetchall()])

    logger.info("[sync] الحساب %s: %d مشترك مُزامَن", account_id[:8], len(rows))
    return {"count": len(rows), "expiry": expiry, "synced_at": synced_at}


@app.post("/subscribers/local", tags=["local-storage"], dependencies=_DEP)
async def subscribers_local(body: LocalSubscribersRequest) -> Any:
    """
    استعلام محلي سريع (بلا نداء SAS) مع فلترة + بحث + ترقيم.

    يُعيد:
      { total, page, count, expiry:{…}, subscribers:[…] }

    عقد .NET: POST /subscribers/local
      { accountId, search?, status?, expiring?, page?, count? }
    """
    _guard_account_id(body.accountId)
    account_id = body.accountId

    with _db() as conn:
        # بناء الاستعلام الأساسي مع فلتر account_id (عزل صارم)
        sql  = "SELECT * FROM local_subscribers WHERE account_id = ?"
        args: list = [account_id]

        if body.status:
            sql += " AND status = ?"
            args.append(body.status)

        rows_raw = conn.execute(sql, args).fetchall()

    rows = [dict(r) for r in rows_raw]

    # البحث النصي (بعد الجلب — SQLite بلا FTS هنا)
    if body.search:
        s = body.search.strip().lower()
        rows = [r for r in rows if
                s in (r.get("username") or "").lower() or
                s in (r.get("name") or "").lower() or
                s in (r.get("phone") or "").lower()]

    # فلتر الانتهاء
    if body.expiring:
        win = body.expiring.strip()
        today = datetime.now(timezone.utc).date()
        rows = [r for r in rows if _in_window(_days_left(r.get("expiration", ""), today), win)]
        rows.sort(key=lambda r: (_days_left(r.get("expiration", ""), today) or 9999))

    total = len(rows)

    # ترقيم
    page  = max(1, body.page)
    count = max(1, min(body.count, 500))
    start = (page - 1) * count
    page_rows = rows[start:start + count]

    # عدّادات الانتهاء من كل سجلّات الحساب (ليست من الصفحة فقط)
    expiry = _expiry_counts([r.get("expiration", "") for r in rows])

    # إزالة raw_json من المخرجات (لا يُعاد للعميل)
    for r in page_rows:
        r.pop("raw_json", None)

    return {
        "total": total, "page": page, "count": count,
        "expiry": expiry,
        "subscribers": page_rows,
    }


@app.post("/subscribers/summary", tags=["local-storage"], dependencies=_DEP)
async def subscribers_summary(body: SubscriberSummaryRequest) -> Any:
    """
    ملخّص مشتركين محلي رخيص — بلا أي نداء SAS4.

    يحسب الإحصاءات من جدول local_subscribers (المزامَن مسبقاً) فقط.
    آمن للاستدعاء الدوري (auto-refresh).

    حساب فارغ (لا سجلّات) → كل الأصفار و last_sync=null (لا خطأ).

    عقد .NET: POST /subscribers/summary  { accountId }
    → {
        "total": int,
        "active": int,
        "expired": int,
        "online": int,
        "expiry": {"overdue": int, "today": int, "soon3": int, "soon7": int},
        "last_sync": "YYYY-MM-DD HH:MM:SS" | null
      }
    """
    _guard_account_id(body.accountId)
    account_id = body.accountId

    with _db() as conn:
        rows = conn.execute(
            "SELECT status, online, expiration, synced_at "
            "FROM local_subscribers WHERE account_id = ?",
            (account_id,),
        ).fetchall()

    if not rows:
        return {
            "total":   0,
            "active":  0,
            "expired": 0,
            "online":  0,
            "expiry":  {"overdue": 0, "today": 0, "soon3": 0, "soon7": 0},
            "last_sync": None,
        }

    total   = len(rows)
    active  = sum(1 for r in rows if r["status"] == "active")
    expired = sum(1 for r in rows if r["status"] == "expired")
    online  = sum(1 for r in rows if r["online"] == 1)

    # منطق الانتهاء: يُعيد استخدام _expiry_counts المشتركة (نفس منطق /sync)
    expiry = _expiry_counts([r["expiration"] for r in rows])

    # أحدث synced_at لهذا الحساب
    last_sync = max(
        (r["synced_at"] for r in rows if r["synced_at"]),
        default=None,
    )

    logger.debug(
        "[subscribers/summary] account=%s total=%d active=%d online=%d",
        account_id[:8], total, active, online,
    )
    return {
        "total":     total,
        "active":    active,
        "expired":   expired,
        "online":    online,
        "expiry":    expiry,
        "last_sync": last_sync,
    }


@app.post("/report/submit", tags=["local-storage"], dependencies=_DEP)
async def report_submit(body: ReportSubmitRequest) -> Any:
    """
    تخزين تصريح الوكيل (البلنك).

    يُعيد السجلّ المُنشأ.

    عقد .NET: POST /report/submit
      { accountId, companyId?, ownerUserId?, declared_total, declared_active, note?, submitted_by? }
    """
    _guard_account_id(body.accountId)
    if body.declared_active > body.declared_total:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="declared_active يجب أن يكون <= declared_total",
        )
    created_at = _utcnow_iso()
    with _db() as conn:
        cur = conn.execute("""
            INSERT INTO agent_reports
                (account_id, company_id, owner_user_id,
                 declared_total, declared_active, note, submitted_by, created_at)
            VALUES (?,?,?,?,?,?,?,?)
        """, (
            body.accountId,
            body.companyId or "",
            body.ownerUserId or "",
            body.declared_total,
            body.declared_active,
            body.note or "",
            body.submitted_by or "",
            created_at,
        ))
        row_id = cur.lastrowid
        rec = dict(conn.execute(
            "SELECT * FROM agent_reports WHERE id = ?", (row_id,)
        ).fetchone())
    logger.info("[report] تصريح جديد للحساب %s: total=%d",
                body.accountId[:8], body.declared_total)
    return rec


@app.post("/report/list", tags=["local-storage"], dependencies=_DEP)
async def report_list(body: ReportListRequest) -> Any:
    """
    آخر تصاريح الحساب (ترتيب زمني تنازلي).

    عقد .NET: POST /report/list  { accountId }
    → { reports:[…], count }
    """
    _guard_account_id(body.accountId)
    with _db() as conn:
        rows = conn.execute("""
            SELECT * FROM agent_reports
            WHERE account_id = ?
            ORDER BY created_at DESC
            LIMIT 100
        """, (body.accountId,)).fetchall()
    return {"reports": [dict(r) for r in rows], "count": len(rows)}


@app.post("/reconciliation", tags=["local-storage"], dependencies=_DEP)
async def reconciliation(body: ReconciliationRequest) -> Any:
    """
    مقاطعة تصريح الوكيل مقابل عدد المشتركين الفعلي.

    منطق الحكم (مُطابَق من companies.py):
      - no_report: لا تصريح.
      - matched: |diff| <= max(5, 5% من actual).
      - company_suspicious: الوكيل يصرّح أكثر مما تُظهره الشركة (diff > 0).
      - agent_suspicious: الوكيل يصرّح أقل (diff < 0).

    مصدر العدد الفعلي:
      - إن أُرسلت creds → جلب حيّ من SAS.
      - وإلا → عدّ المشتركين المحليين.

    عقد .NET: POST /reconciliation  { accountId, serverUrl?, username?, password? }
    → { declared, actual, diff, verdict, source }
    """
    _guard_account_id(body.accountId)

    # مصدر العدد الفعلي
    source = "local"
    actual: Optional[int] = None

    has_creds = bool(body.serverUrl and body.username and body.password)

    if has_creds:
        try:
            async with SASClient(body.serverUrl, body.username, body.password) as sas:
                res = await sas.dashboard_subscribers()
                data = res.get("data", res) if isinstance(res, dict) else {}
                actual = _int(data.get("total"))
                source = "live_sas"
        except Exception as exc:
            logger.warning("[reconciliation] فشل الجلب الحيّ للحساب %s — تراجع للمحلي: %s",
                           body.accountId[:8], _safe_msg(exc))
            # تراجع للعدّ المحلي

    if actual is None:
        with _db() as conn:
            row = conn.execute(
                "SELECT COUNT(*) FROM local_subscribers WHERE account_id = ?",
                (body.accountId,),
            ).fetchone()
            actual = row[0] if row else 0

    # آخر تصريح
    with _db() as conn:
        rep_row = conn.execute("""
            SELECT declared_total, declared_active, created_at
            FROM agent_reports
            WHERE account_id = ?
            ORDER BY created_at DESC
            LIMIT 1
        """, (body.accountId,)).fetchone()

    if rep_row is None:
        return {
            "declared": None,
            "actual": actual,
            "diff": None,
            "verdict": "no_report",
            "source": source,
            "last_report_ts": None,
        }

    declared       = rep_row[0]
    declared_active = rep_row[1]
    last_report_ts  = rep_row[2]
    diff           = declared - actual
    verdict        = _compute_verdict(declared, actual)

    return {
        "declared":        declared,
        "declared_active": declared_active,
        "actual":          actual,
        "diff":            diff,
        "verdict":         verdict,
        "source":          source,
        "last_report_ts":  last_report_ts,
    }


# ══════════════════════════════════════════════════════════════════════════════
# ملخّص وكلاء الشركة (البلنك الموحّد) — POST /admin/agents-summary
# ══════════════════════════════════════════════════════════════════════════════

# الحدّ الأقصى لعدد accountIds في طلب واحد (حماية من الاستعلامات الضخمة)
_AGENTS_SUMMARY_CAP = 500


def _compute_verdict(declared: int, actual: int) -> str:
    """
    يحسب الحكم بناءً على الفارق بين التصريح والعدد الفعلي.

    مُستخرَج من منطق /reconciliation لإعادة الاستخدام:
      - matched: |diff| <= max(5, 5% من actual).
      - company_suspicious: الوكيل يصرّح أكثر مما تُظهره الشركة (diff > 0).
      - agent_suspicious: الوكيل يصرّح أقل (diff < 0 وخارج النطاق).
    """
    diff = declared - actual
    threshold = max(5, int(actual * 0.05))
    if abs(diff) <= threshold:
        return "matched"
    if diff > 0:
        return "company_suspicious"
    return "agent_suspicious"


class AgentsSummaryRequest(BaseModel):
    """
    طلب ملخّص وكلاء الشركة.

    companyId  : معرّف الشركة — يُستخدَم لعزل كل استعلام.
    accountIds : قائمة معرّفات حسابات SAS تخصّ هذه الشركة (حدّ 500).
    """
    companyId:  str           = Field(..., min_length=1, max_length=128,
                                      description="معرّف الشركة")
    accountIds: List[str]     = Field(..., min_length=1,
                                      description="قائمة account_id (GUID أو معرّف)")


@app.post("/admin/agents-summary", tags=["admin"], dependencies=_DEP)
async def agents_summary(body: AgentsSummaryRequest) -> Any:
    """
    ملخّص وكلاء الشركة (البلنك الموحّد).

    لكل account_id في القائمة (المُقيَّدة بـ company_id):
      - آخر تصريح (declared_total / declared_active) من agent_reports.
      - العدد الفعلي = COUNT من local_subscribers لذلك الحساب.
      - العدد النشط = COUNT WHERE status='active'.
      - الفارق والحكم بنفس منطق /reconciliation.
      - آخر وقت مزامنة (MAX synced_at).

    العزل الصارم:
      - كل استعلام يحمل WHERE company_id = ? AND account_id IN (...).
      - أي account_id لا ينتمي لـ company_id يُتجاهَل تلقائياً (لا يظهر في النتائج).
      - حدّ 500 حساب لكل طلب.

    fail-closed: تتطلّب X-Internal-Secret (كبقية النقاط).

    عقد: POST /admin/agents-summary  { companyId, accountIds:[…] }
    → { items:[{account_id, declared_total, declared_active, actual_total,
                actual_active, diff, verdict, last_sync}] }
    """
    company_id = (body.companyId or "").strip()
    if not company_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="companyId مطلوب",
        )

    # تنظيف المعرّفات وإزالة المكرَّرات مع الحفاظ على الترتيب — ثم تطبيق السقف
    seen: set = set()
    clean_ids: List[str] = []
    for aid in (body.accountIds or []):
        aid = (aid or "").strip()
        if aid and len(aid) <= 128 and aid not in seen:
            seen.add(aid)
            clean_ids.append(aid)
        if len(clean_ids) >= _AGENTS_SUMMARY_CAP:
            break

    if not clean_ids:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="accountIds لا تحتوي على معرّفات صالحة",
        )

    # ── استعلامات SQLite — جميعها مُقيَّدة بـ company_id ──────────────────────
    placeholders = ",".join("?" * len(clean_ids))

    with _db() as conn:
        # 1) آخر تصريح لكل حساب ضمن الشركة (subquery يأخذ السجلّ الأحدث لكل account_id)
        rep_rows = conn.execute(f"""
            SELECT ar.account_id,
                   ar.declared_total,
                   ar.declared_active,
                   ar.created_at  AS report_ts
            FROM   agent_reports ar
            JOIN   (
                SELECT account_id, MAX(created_at) AS max_ts
                FROM   agent_reports
                WHERE  company_id  = ?
                  AND  account_id  IN ({placeholders})
                GROUP  BY account_id
            ) latest
              ON  ar.account_id = latest.account_id
             AND  ar.created_at = latest.max_ts
             AND  ar.company_id = ?
        """, [company_id, *clean_ids, company_id]).fetchall()

        # 2) عدد المشتركين الكلي والنشط لكل حساب ضمن الشركة
        sub_rows = conn.execute(f"""
            SELECT account_id,
                   COUNT(*)                                          AS total,
                   SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) AS active,
                   MAX(synced_at)                                    AS last_sync
            FROM   local_subscribers
            WHERE  company_id  = ?
              AND  account_id  IN ({placeholders})
            GROUP  BY account_id
        """, [company_id, *clean_ids]).fetchall()

    # ── بناء فهارس سريعة بدلاً من المسح المتكرّر ─────────────────────────────
    rep_by_account: Dict[str, dict] = {
        r["account_id"]: {
            "declared_total":  r["declared_total"],
            "declared_active": r["declared_active"],
            "report_ts":       r["report_ts"],
        }
        for r in rep_rows
    }

    sub_by_account: Dict[str, dict] = {
        r["account_id"]: {
            "actual_total":  int(r["total"]  or 0),
            "actual_active": int(r["active"] or 0),
            "last_sync":     r["last_sync"],
        }
        for r in sub_rows
    }

    # ── تجميع النتائج — فقط الحسابات المطلوبة التي تخصّ الشركة ────────────────
    # (أي account_id لم يرد في rep_by_account ولا sub_by_account = لا ينتمي
    # للشركة أو غير مزامَن — يُدرَج بقيم افتراضية صفرية + حكم no_report)
    items: List[Dict[str, Any]] = []
    for aid in clean_ids:
        rep = rep_by_account.get(aid)
        sub = sub_by_account.get(aid, {"actual_total": 0, "actual_active": 0, "last_sync": None})

        actual_total  = sub["actual_total"]
        actual_active = sub["actual_active"]
        last_sync     = sub["last_sync"]

        if rep is None:
            # لا تصريح — نُدرجه فقط إن كان للحساب سجلّات في local_subscribers
            # (أي تمّت مزامنته وينتمي للشركة)؛ account_id بلا سجلّات = خارج الشركة → تجاهل
            if sub["last_sync"] is None:
                # لا سجلّات محلية = لا ينتمي للشركة أو لم يُزامَن قطّ → تجاهل
                continue
            items.append({
                "account_id":      aid,
                "declared_total":  None,
                "declared_active": None,
                "actual_total":    actual_total,
                "actual_active":   actual_active,
                "diff":            None,
                "verdict":         "no_report",
                "last_sync":       last_sync,
            })
        else:
            declared_total  = rep["declared_total"]
            declared_active = rep["declared_active"]
            diff            = declared_total - actual_total
            verdict         = _compute_verdict(declared_total, actual_total)
            items.append({
                "account_id":      aid,
                "declared_total":  declared_total,
                "declared_active": declared_active,
                "actual_total":    actual_total,
                "actual_active":   actual_active,
                "diff":            diff,
                "verdict":         verdict,
                "last_sync":       last_sync,
            })

    logger.info(
        "[agents-summary] company=%s requested=%d returned=%d",
        company_id[:8], len(clean_ids), len(items),
    )
    return {"items": items}


# ══════════════════════════════════════════════════════════════════════════════
# نقاط التذاكر المحلية — POST /tickets/…
# ══════════════════════════════════════════════════════════════════════════════

def _guard_ticket_owner(company_id: str, owner_user_id: str) -> None:
    """يتحقّق أن company_id و owner_user_id غير فارغَين — يرمي 400 إن أخفق."""
    if not (company_id or "").strip():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="companyId مطلوب")
    if not (owner_user_id or "").strip():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="ownerUserId مطلوب")


def _get_owned_ticket(conn: sqlite3.Connection,
                      company_id: str, owner_user_id: str,
                      ticket_id: int) -> sqlite3.Row:
    """
    يجلب التذكرة ويتحقّق ملكيتها (company_id + owner_user_id).
    يرمي 404 إن لم توجد أو لم تخصّ هذا المالك — لا يكشف وجود تذاكر آخرين.
    """
    row = conn.execute(
        "SELECT * FROM tickets WHERE id = ? AND company_id = ? AND owner_user_id = ?",
        (ticket_id, company_id, owner_user_id),
    ).fetchone()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="التذكرة غير موجودة")
    return row


def _ticket_to_dict(row: sqlite3.Row,
                    replies: Optional[List[dict]] = None,
                    hide_internal: bool = False) -> dict:
    d = dict(row)
    d["category_ar"] = _TK_CATEGORY_AR.get(d.get("category", ""), d.get("category", ""))
    d["status_ar"]   = _TK_STATUS_AR.get(d.get("status", ""),   d.get("status", ""))
    if replies is not None:
        visible = [r for r in replies if not (hide_internal and r.get("is_internal"))]
        d["replies"] = visible
    return d


@app.post("/tickets/stats", tags=["tickets"], dependencies=_DEP)
async def tickets_stats(body: TicketStatsRequest) -> Any:
    """
    إحصاءات موجزة للوحة الوكيل.

    عقد: POST /tickets/stats  { companyId, ownerUserId }
    → { total, open, in_progress, resolved, closed }
    """
    _guard_ticket_owner(body.companyId, body.ownerUserId)
    with _db() as conn:
        rows = conn.execute(
            "SELECT status FROM tickets WHERE company_id = ? AND owner_user_id = ?",
            (body.companyId, body.ownerUserId),
        ).fetchall()
    counts: Dict[str, int] = {s: 0 for s in _TK_STATUSES}
    for r in rows:
        s = r[0] if r[0] in counts else "open"
        counts[s] += 1
    return {"total": len(rows), **counts}


@app.post("/tickets/list", tags=["tickets"], dependencies=_DEP)
async def tickets_list(body: TicketListRequest) -> Any:
    """
    قائمة مُرقَّمة بتذاكر الوكيل مع فلترة اختيارية.

    عقد: POST /tickets/list  { companyId, ownerUserId, status?, category?, search?, page?, count? }
    → { total, page, count, tickets:[…] }
    """
    _guard_ticket_owner(body.companyId, body.ownerUserId)
    # العزل الصارم: كل استعلام يحمل company_id و owner_user_id
    sql  = ("SELECT * FROM tickets "
            "WHERE company_id = ? AND owner_user_id = ?")
    args: list = [body.companyId, body.ownerUserId]

    if body.status:
        if body.status not in _TK_STATUSES:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                                detail=f"حالة غير معروفة — المتاح: {', '.join(_TK_STATUSES)}")
        sql  += " AND status = ?"
        args.append(body.status)

    if body.category:
        if body.category not in _TK_CATEGORIES:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                                detail=f"تصنيف غير معروف — المتاح: {', '.join(_TK_CATEGORIES)}")
        sql  += " AND category = ?"
        args.append(body.category)

    sql += " ORDER BY created_at DESC"

    with _db() as conn:
        rows = [dict(r) for r in conn.execute(sql, args).fetchall()]

    # البحث النصي
    if body.search:
        s = body.search.strip().lower()
        rows = [r for r in rows if
                s in (r.get("subject") or "").lower() or
                s in (r.get("body") or "").lower() or
                s in (r.get("subscriber_ref") or "").lower() or
                s in (r.get("created_by") or "").lower()]

    total = len(rows)
    page  = max(1, body.page)
    count = max(1, min(body.count, 500))
    start = (page - 1) * count
    page_rows = [_ticket_to_dict(r) for r in rows[start:start + count]]  # type: ignore[arg-type]

    return {"total": total, "page": page, "count": count, "tickets": page_rows}


@app.post("/tickets/create", tags=["tickets"], dependencies=_DEP)
async def tickets_create(body: TicketCreateRequest) -> Any:
    """
    فتح تذكرة جديدة (تخزين محلي — بلا نداء SAS).

    عقد: POST /tickets/create  { companyId, ownerUserId, subject, body, category?, priority?,
                                   subscriber_ref?, created_by? }
    → التذكرة المُنشأة
    """
    _guard_ticket_owner(body.companyId, body.ownerUserId)
    if body.category not in _TK_CATEGORIES:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"تصنيف غير معروف — المتاح: {', '.join(_TK_CATEGORIES)}")
    if body.priority not in _TK_PRIORITIES:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"أولوية غير معروفة — المتاح: {', '.join(_TK_PRIORITIES)}")

    now = _utcnow_iso()
    with _db() as conn:
        cur = conn.execute("""
            INSERT INTO tickets
                (company_id, owner_user_id, subscriber_ref, subject, body,
                 category, priority, status, created_by, created_at, updated_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?)
        """, (
            body.companyId, body.ownerUserId,
            body.subscriber_ref or "",
            body.subject.strip(), body.body.strip(),
            body.category, body.priority, "open",
            body.created_by or "", now, now,
        ))
        row_id = cur.lastrowid
        row = conn.execute(
            "SELECT * FROM tickets WHERE id = ?", (row_id,)
        ).fetchone()

    logger.info("[tickets] تذكرة جديدة #%d لـ company=%s owner=%s",
                row_id, body.companyId[:8], body.ownerUserId[:8])
    return _ticket_to_dict(row, replies=[])


@app.post("/tickets/get", tags=["tickets"], dependencies=_DEP)
async def tickets_get(body: TicketGetRequest) -> Any:
    """
    تفاصيل تذكرة واحدة + ردودها (الردود الداخلية مخفية).

    عقد: POST /tickets/get  { companyId, ownerUserId, ticket_id }
    → التذكرة + قائمة الردود (is_internal محذوفة)
    """
    _guard_ticket_owner(body.companyId, body.ownerUserId)
    with _db() as conn:
        # التحقق من الملكية: company_id + owner_user_id (عزل صارم)
        row = _get_owned_ticket(conn, body.companyId, body.ownerUserId, body.ticket_id)
        replies_raw = conn.execute(
            "SELECT * FROM ticket_replies WHERE ticket_id = ? ORDER BY created_at",
            (body.ticket_id,),
        ).fetchall()

    replies = [dict(r) for r in replies_raw]
    # إخفاء الردود الداخلية (is_internal=1) عند إرجاع البيانات للعميل
    return _ticket_to_dict(row, replies=replies, hide_internal=True)


@app.post("/tickets/reply", tags=["tickets"], dependencies=_DEP)
async def tickets_reply(body: TicketReplyRequest) -> Any:
    """
    إضافة ردّ على تذكرة.

    عقد: POST /tickets/reply  { companyId, ownerUserId, ticket_id, body, is_internal?, author? }
    → { id, ticket_id, status }
    """
    _guard_ticket_owner(body.companyId, body.ownerUserId)
    now = _utcnow_iso()
    with _db() as conn:
        # التحقق من الملكية قبل الكتابة
        ticket_row = _get_owned_ticket(conn, body.companyId, body.ownerUserId, body.ticket_id)
        cur = conn.execute("""
            INSERT INTO ticket_replies (ticket_id, body, is_internal, author, created_at)
            VALUES (?,?,?,?,?)
        """, (
            body.ticket_id,
            body.body.strip(),
            1 if body.is_internal else 0,
            body.author or "",
            now,
        ))
        reply_id = cur.lastrowid
        # ردّ عام على تذكرة مفتوحة → تنتقل لـ in_progress تلقائياً
        current_status = ticket_row["status"]
        if not body.is_internal and current_status == "open":
            current_status = "in_progress"
            conn.execute(
                "UPDATE tickets SET status = ?, updated_at = ? WHERE id = ?",
                (current_status, now, body.ticket_id),
            )
        else:
            conn.execute(
                "UPDATE tickets SET updated_at = ? WHERE id = ?",
                (now, body.ticket_id),
            )

    logger.info("[tickets] ردّ #%d على تذكرة #%d (is_internal=%s)",
                reply_id, body.ticket_id, body.is_internal)
    return {"id": reply_id, "ticket_id": body.ticket_id, "status": current_status}


@app.post("/tickets/update", tags=["tickets"], dependencies=_DEP)
async def tickets_update(body: TicketUpdateRequest) -> Any:
    """
    تحديث حالة/أولوية/تصنيف تذكرة.

    عقد: POST /tickets/update  { companyId, ownerUserId, ticket_id, status?, priority?, category? }
    → التذكرة المحدَّثة
    """
    _guard_ticket_owner(body.companyId, body.ownerUserId)
    if not any([body.status, body.priority, body.category]):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="لا تغييرات — أرسل status أو priority أو category")

    if body.status is not None and body.status not in _TK_STATUSES:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"حالة غير معروفة — المتاح: {', '.join(_TK_STATUSES)}")
    if body.priority is not None and body.priority not in _TK_PRIORITIES:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"أولوية غير معروفة — المتاح: {', '.join(_TK_PRIORITIES)}")
    if body.category is not None and body.category not in _TK_CATEGORIES:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"تصنيف غير معروف — المتاح: {', '.join(_TK_CATEGORIES)}")

    now = _utcnow_iso()
    with _db() as conn:
        # التحقق من الملكية قبل التعديل
        _get_owned_ticket(conn, body.companyId, body.ownerUserId, body.ticket_id)

        parts = ["updated_at = ?"]
        vals:  list = [now]
        if body.status is not None:
            parts.append("status = ?");   vals.append(body.status)
        if body.priority is not None:
            parts.append("priority = ?"); vals.append(body.priority)
        if body.category is not None:
            parts.append("category = ?"); vals.append(body.category)
        # شرط العزل مُكرَّر في UPDATE أيضاً (دفاع في العمق)
        vals.extend([body.ticket_id, body.companyId, body.ownerUserId])
        conn.execute(
            f"UPDATE tickets SET {', '.join(parts)} "
            f"WHERE id = ? AND company_id = ? AND owner_user_id = ?",
            vals,
        )
        row = conn.execute(
            "SELECT * FROM tickets WHERE id = ?", (body.ticket_id,)
        ).fetchone()

    logger.info("[tickets] تحديث تذكرة #%d لـ company=%s",
                body.ticket_id, body.companyId[:8])
    return _ticket_to_dict(row)


# ══════════════════════════════════════════════════════════════════════════════
# دوال مساعدة مشتركة
# ══════════════════════════════════════════════════════════════════════════════

def _guard_account_id(account_id: str) -> None:
    """يتحقّق من صحّة account_id (غير فارغ، طول معقول) — يرمي 400 إن أخفق."""
    aid = (account_id or "").strip()
    if not aid or len(aid) > 128:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="accountId غير صالح — يجب أن يكون GUID أو معرّفاً غير فارغ",
        )


def _utcnow_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")


def _int(v: Any, d: int = 0) -> int:
    try:
        return int(v)
    except (TypeError, ValueError):
        return d


# ── منطق الانتهاء (مُقتبَس من expiry.py) ─────────────────────────────────────

def _parse_expiry(expiration: str) -> Optional[datetime]:
    s = (expiration or "").strip()
    if len(s) < 10:
        return None
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(s[:len(fmt)], fmt)
        except ValueError:
            continue
    return None


def _days_left(expiration: str, today: Optional[date] = None) -> Optional[int]:
    dt = _parse_expiry(expiration)
    if dt is None:
        return None
    today = today or datetime.now(timezone.utc).date()
    return (dt.date() - today).days


def _in_window(dl: Optional[int], window: str) -> bool:
    if dl is None:
        return False
    if window == "overdue":
        return dl < 0
    if window == "today":
        return dl == 0
    if window == "soon3":
        return 0 <= dl <= 3
    if window == "soon7":
        return 0 <= dl <= 7
    return True


def _expiry_counts(expirations: List[str]) -> dict:
    today = datetime.now(timezone.utc).date()
    c = {"overdue": 0, "today": 0, "soon3": 0, "soon7": 0}
    for e in expirations:
        dl = _days_left(e, today)
        if dl is None:
            continue
        if dl < 0:
            c["overdue"] += 1
        elif dl == 0:
            c["today"]  += 1
            c["soon3"]  += 1
            c["soon7"]  += 1
        elif dl <= 3:
            c["soon3"]  += 1
            c["soon7"]  += 1
        elif dl <= 7:
            c["soon7"]  += 1
    return c


# ── حجب الأسرار ───────────────────────────────────────────────────────────────

def _redact(obj: Any) -> Any:
    if isinstance(obj, dict):
        return {k: ("***" if _SECRET_KEYS.search(str(k)) else _redact(v))
                for k, v in obj.items()}
    if isinstance(obj, list):
        return [_redact(x) for x in obj]
    return obj


def _safe_msg(exc: Exception) -> str:
    msg = str(exc)
    for kw in ("password", "كلمة المرور", "token", "secret"):
        if kw.lower() in msg.lower():
            return "[رسالة محجوبة لاحتوائها كلمة محجوبة]"
    return msg[:300]


# ── غلاف SAS المشترك ──────────────────────────────────────────────────────────

async def _call_sas(server_url: str, username: str, password: str,
                    fetcher, **kwargs) -> Any:
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
            logger.warning("renewal/candidates: تجاوز حدّ %d — إيقاف الجلب", MAX_RECORDS)
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
                    + (f" — months={months}"        if months      else "")
                    + (f" — profileId={profile_id}" if profile_id  else "")
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
                sc = resp.get("status") or resp.get("statusCode")
                if sc is not None and int(sc) >= 400:
                    ok = False
                elif resp.get("success") is False:
                    ok = False
            msg = str(resp.get("message") or resp.get("msg") or "تمّ") if isinstance(resp, dict) else ""
            results.append({"id": sub_id, "ok": ok, "message": msg})
        except SASError as exc:
            results.append({"id": sub_id, "ok": False, "message": _safe_msg(exc)})
        except Exception as exc:
            results.append({"id": sub_id, "ok": False, "message": "خطأ داخلي"})

    return results


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
