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
import secrets
import sys
from typing import Any, Dict, Optional

# ── ضبط مسار الاستيراد ────────────────────────────────────────────────────────
# نضيف backend/app إلى sys.path كي يُحلّ `from integrations.sas_client import …`
# دون تعديل هيكل الحزمة القائمة.
_BACKEND_APP = os.path.join(os.path.dirname(__file__), "..", "backend", "app")
if _BACKEND_APP not in sys.path:
    sys.path.insert(0, os.path.abspath(_BACKEND_APP))

from integrations.sas_client import SASClient, SASError        # noqa: E402
from integrations.sas_user_client import SASUserClient          # noqa: E402

from fastapi import Depends, FastAPI, HTTPException, Request, status  # noqa: E402
from fastapi.responses import JSONResponse                             # noqa: E402
from pydantic import BaseModel, Field                                  # noqa: E402

# ── إعداد التسجيل ─────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s  %(message)s",
)
logger = logging.getLogger("sas_sidecar")

# ── السرّ الداخلي ─────────────────────────────────────────────────────────────
_INTERNAL_SECRET: str = os.environ.get("SADARA_SAS_INTERNAL_SECRET", "")

# ── نماذج Pydantic للطلبات ────────────────────────────────────────────────────


class LoginRequest(BaseModel):
    serverUrl: str = Field(..., description="عنوان خادم SAS (host أو URL كامل)")
    username: str = Field(..., description="اسم مستخدم المدير/الوكيل في SAS")
    password: str = Field(..., description="كلمة المرور — لا تُسجَّل أبداً")


class DashboardRequest(BaseModel):
    serverUrl: str
    username: str
    password: str


class SubscribersRequest(BaseModel):
    serverUrl: str
    username: str
    password: str
    query: Dict[str, Optional[str]] = Field(default_factory=dict)


class ReportRequest(BaseModel):
    serverUrl: str
    username: str
    password: str
    query: Dict[str, Optional[str]] = Field(default_factory=dict)


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
        # لا نكشف سبب الرفض بدقّة (هل الرأس غائب أم خاطئ)
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
    version="1.0.0",
    # نُخفي docs في البيئة التشغيلية؛ يمكن تفعيلها للتطوير عبر متغيّر بيئة
    docs_url="/docs" if os.environ.get("SADARA_SAS_DOCS", "0") == "1" else None,
    redoc_url=None,
)


# ── Health check (بلا مصادقة — للتأكد من أن العملية تعمل) ────────────────────

@app.get("/health", tags=["internal"])
async def health() -> Dict[str, str]:
    """
    فحص سريع: يعيد 200 + {"status": "ok"}.
    لا يكشف أي معلومات حساسة.
    """
    return {"status": "ok"}


# ── /login ────────────────────────────────────────────────────────────────────

@app.post("/login", tags=["sas"], dependencies=[Depends(verify_internal_secret)])
async def login(body: LoginRequest) -> Any:
    """
    تسجيل دخول صامت لنظام SAS4 الإداري.
    يعيد {"success": true, "message": "..."} أو يرمي HTTP 502 عند فشل SAS.

    مطابقة عقد .NET:
      POST /login  { serverUrl, username, password }
      → SasLoginResult(Success, SessionHandle, Message)
    """
    try:
        async with SASClient(body.serverUrl, body.username, body.password) as sas:
            # SASClient.__aenter__ يستدعي login() ويخزّن التوكن — نجاح = توكن موجود
            token_preview = (sas._token or "")[:4] + "…" if sas._token else "(none)"
            logger.info("تسجيل دخول SAS ناجح [token=%s]", token_preview)
            return {"success": True, "sessionHandle": sas._token, "message": "تم تسجيل الدخول"}
    except SASError as exc:
        logger.warning("فشل تسجيل الدخول SAS: %s", _safe_msg(exc))
        return JSONResponse(
            status_code=status.HTTP_200_OK,
            content={"success": False, "sessionHandle": None, "message": "تعذّر تسجيل الدخول لنظام الساس"},
        )
    except Exception as exc:
        logger.error("خطأ غير متوقّع في /login: %s", _safe_msg(exc))
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY,
                            detail="خدمة الساس غير متاحة حالياً")


# ── /dashboard ────────────────────────────────────────────────────────────────

@app.post("/dashboard", tags=["sas"], dependencies=[Depends(verify_internal_secret)])
async def dashboard(body: DashboardRequest) -> Any:
    """
    جلب بيانات لوحة الوكيل (advancedDashboard/subscribers + finance).
    يعيد JSON خاماً كما يُعيده SAS4.

    مطابقة عقد .NET:
      POST /dashboard  { serverUrl, username, password }
      → string (JSON خام)
    """
    return await _call_sas(
        body.serverUrl, body.username, body.password,
        _fetch_dashboard,
    )


# ── /subscribers ──────────────────────────────────────────────────────────────

@app.post("/subscribers", tags=["sas"], dependencies=[Depends(verify_internal_secret)])
async def subscribers(body: SubscribersRequest) -> Any:
    """
    جلب قائمة مشتركي الوكيل مع وسائط استعلام (بحث/صفحة/حجم/…).
    يمرّر حقول query إلى POST index/user في SAS4.

    مطابقة عقد .NET:
      POST /subscribers  { serverUrl, username, password, query:{} }
      → string (JSON خام)
    """
    return await _call_sas(
        body.serverUrl, body.username, body.password,
        _fetch_subscribers,
        query=body.query,
    )


# ── /report ───────────────────────────────────────────────────────────────────

@app.post("/report", tags=["sas"], dependencies=[Depends(verify_internal_secret)])
async def report(body: ReportRequest) -> Any:
    """
    جلب تقرير الوكيل (التصريح/البلنك) مع وسائط استعلام (فترة/…).
    يمرّر حقول query إلى POST index/manager في SAS4 (تقرير الوكيل).

    مطابقة عقد .NET:
      POST /report  { serverUrl, username, password, query:{} }
      → string (JSON خام)
    """
    return await _call_sas(
        body.serverUrl, body.username, body.password,
        _fetch_report,
        query=body.query,
    )


# ── دوال مساعدة داخلية ────────────────────────────────────────────────────────

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
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="تعذّر جلب البيانات من خدمة الساس",
        )
    except Exception as exc:
        logger.error("خطأ غير متوقّع في نداء SAS: %s", _safe_msg(exc))
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="خدمة الساس غير متاحة حالياً",
        )


async def _fetch_dashboard(sas: SASClient) -> Dict[str, Any]:
    """يجمع subscribers + finance من advancedDashboard في استجابة واحدة."""
    subscribers_data = await sas.dashboard_subscribers()
    try:
        finance_data = await sas.dashboard_finance()
    except SASError:
        finance_data = {}
    return {"subscribers": subscribers_data, "finance": finance_data}


async def _fetch_subscribers(sas: SASClient,
                              query: Dict[str, Optional[str]]) -> Any:
    """يستدعي POST index/user مع معاملات query (page, count, search, …)."""
    page = int(query.get("page") or 1)
    count = int(query.get("count") or 50)
    search = str(query.get("search") or "")
    sort_by = str(query.get("sortBy") or "id")
    direction = str(query.get("direction") or "asc")
    return await sas.users(page=page, count=count, search=search,
                           sort_by=sort_by, direction=direction)


async def _fetch_report(sas: SASClient,
                        query: Dict[str, Optional[str]]) -> Any:
    """يستدعي POST index/manager مع معاملات query للحصول على بيانات التقرير."""
    page = int(query.get("page") or 1)
    count = int(query.get("count") or 100)
    search = str(query.get("search") or "")
    return await sas.managers_full(page=page, count=count, search=search)


def _safe_msg(exc: Exception) -> str:
    """يعيد رسالة الخطأ بعد تنظيف أي تسريب محتمل للاعتماد (حذر إضافي)."""
    msg = str(exc)
    # لا تُضمَّن كلمات مرور — SASError لا تضمّنها أصلاً، لكن نُصفّي احتياطاً
    for kw in ("password", "كلمة المرور", "token", "secret"):
        if kw.lower() in msg.lower():
            return "[رسالة محجوبة لاحتوائها كلمة محجوبة]"
    return msg[:300]
