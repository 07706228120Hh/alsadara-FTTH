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


# نماذج نقاط النهاية الجديدة ─────────────────────────────────────────────────

class PackagesRequest(BaseModel):
    serverUrl: str
    username: str
    password: str


class FinanceRequest(BaseModel):
    serverUrl: str
    username: str
    password: str


class SystemHealthRequest(BaseModel):
    serverUrl: str
    username: str
    password: str


class RenewalCandidatesRequest(BaseModel):
    serverUrl: str
    username: str
    password: str
    days: int = Field(default=7, ge=1, le=365, description="عدد الأيام — يُعيد المشتركين الذين ينتهي اشتراكهم خلالها")
    query: Dict[str, Any] = Field(default_factory=dict, description="معاملات إضافية تُمرَّر لـ SAS index/user")


class RenewalBulkRequest(BaseModel):
    serverUrl: str
    username: str
    password: str
    subscriberIds: List[int] = Field(..., description="قائمة معرّفات المشتركين")
    months: Optional[int] = Field(default=None, ge=1, le=24, description="عدد الأشهر للتمديد (اختياري)")
    profileId: Optional[Any] = Field(default=None, description="معرّف الباقة (اختياري — للتفعيل بباقة محدّدة)")
    dryRun: bool = Field(default=False, description="إن صحيح: أعِد ما سيُنفَّذ دون تنفيذ فعلي")


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


# ── /packages ─────────────────────────────────────────────────────────────────

@app.post("/packages", tags=["sas"], dependencies=[Depends(verify_internal_secret)])
async def packages(body: PackagesRequest) -> Any:
    """
    قائمة باقات/بروفايلات SAS4 عبر GET list/profile/0.
    يعيد JSON خاماً كما يُعيده الخادم.

    عقد .NET:
      POST /packages  { serverUrl, username, password }
      → JSON خام (مصفوفة [{id, name, …}])
    """
    return await _call_sas(
        body.serverUrl, body.username, body.password,
        _fetch_packages,
    )


# ── /finance ──────────────────────────────────────────────────────────────────

@app.post("/finance", tags=["sas"], dependencies=[Depends(verify_internal_secret)])
async def finance(body: FinanceRequest) -> Any:
    """
    ملخّص مالي من advancedDashboard/finance.
    يعيد JSON خاماً.

    عقد .NET:
      POST /finance  { serverUrl, username, password }
      → JSON خام
    """
    return await _call_sas(
        body.serverUrl, body.username, body.password,
        _fetch_finance,
    )


# ── /system-health ────────────────────────────────────────────────────────────

@app.post("/system-health", tags=["sas"], dependencies=[Depends(verify_internal_secret)])
async def system_health(body: SystemHealthRequest) -> Any:
    """
    صحّة النظام من advancedDashboard/systemHealth.
    يعيد JSON خاماً.

    عقد .NET:
      POST /system-health  { serverUrl, username, password }
      → JSON خام
    """
    return await _call_sas(
        body.serverUrl, body.username, body.password,
        _fetch_system_health,
    )


# ── /renewal/candidates ───────────────────────────────────────────────────────

@app.post("/renewal/candidates", tags=["sas"], dependencies=[Depends(verify_internal_secret)])
async def renewal_candidates(body: RenewalCandidatesRequest) -> Any:
    """
    المشتركون الأقرب انتهاءً خلال `days` يوماً القادمة.
    يجلب القائمة من SAS (مع دعم معاملات query الإضافية) ثم يفلترها ويرتّبها محلياً
    حسب تاريخ الانتهاء — إذ لا يوفّر SAS4 فلترة زمنية مباشرة على index/user.

    عقد .NET:
      POST /renewal/candidates  { serverUrl, username, password, days?, query? }
      → [{id, username, name, expiry, profile}]
    """
    return await _call_sas(
        body.serverUrl, body.username, body.password,
        _fetch_renewal_candidates,
        days=body.days,
        extra_query=body.query,
    )


# ── /renewal/bulk ─────────────────────────────────────────────────────────────

@app.post("/renewal/bulk", tags=["sas"], dependencies=[Depends(verify_internal_secret)])
async def renewal_bulk(body: RenewalBulkRequest) -> Any:
    """
    تجديد/تفعيل مجموعة مشتركين دفعةً واحدة.

    - كل مشترك يحصل على uuid مستقل مشتقّ من (serverUrl + subscriberId + وقت الدقيقة)
      لمنع تنفيذ نفس الطلب مرتين (idempotent على مستوى الدقيقة).
    - إن dryRun=true: لا يُنفَّذ أي إجراء فعلي، فقط تُعاد قائمة ما كان سيُنفَّذ.
    - الفشل الجزئي لا يوقف الدفعة — كل مشترك يُعالَج باستقلالية.
    - كلمة المرور لا تُسجَّل في أي حالة.

    عقد .NET:
      POST /renewal/bulk  { serverUrl, username, password,
                            subscriberIds:[], months?, profileId?, dryRun? }
      → [{id, ok, message}]
    """
    return await _call_sas(
        body.serverUrl, body.username, body.password,
        _execute_renewal_bulk,
        subscriber_ids=body.subscriberIds,
        months=body.months,
        profile_id=body.profileId,
        dry_run=body.dryRun,
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


async def _fetch_packages(sas: SASClient) -> Any:
    """يستدعي GET list/profile/0 ويعيد JSON خاماً (مصفوفة الباقات)."""
    return await sas.profiles()


async def _fetch_finance(sas: SASClient) -> Any:
    """يستدعي GET advancedDashboard/finance ويعيد JSON خاماً."""
    return await sas.dashboard_finance()


async def _fetch_system_health(sas: SASClient) -> Any:
    """يستدعي GET advancedDashboard/systemHealth ويعيد JSON خاماً."""
    return await sas.dashboard_system_health()


async def _fetch_renewal_candidates(
    sas: SASClient,
    days: int,
    extra_query: Dict[str, Any],
) -> List[Dict[str, Any]]:
    """
    يجلب المشتركين من SAS ثم يفلترهم محلياً حسب تاريخ الانتهاء.

    SAS4 لا يوفّر فلترة زمنية مباشرة على index/user، لذا نجلب صفحات
    كافية (حدّ أقصى 2000 سجل) ثم نفلتر ونرتّب ونبسّط النتيجة.

    حقل التاريخ المتوقَّع: `expiration` (ISO أو YYYY-MM-DD HH:MM:SS).
    """
    now = datetime.now(timezone.utc)
    candidates: List[Dict[str, Any]] = []

    # نستخدم iter_all لعبور كل الصفحات — نوقف عند 2000 سجل كحماية
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

        # محاولة تحليل التاريخ (يدعم ISO 8601 وصيغة MySQL YYYY-MM-DD HH:MM:SS)
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
        # نأخذ المشتركين المنتهين حديثاً (حتى 0) والمنتهين خلال days
        if delta <= days * 86400:
            name = " ".join(filter(None, [
                row.get("firstname", ""),
                row.get("lastname", ""),
            ])).strip() or row.get("username", "")
            candidates.append({
                "id": row.get("id"),
                "username": row.get("username"),
                "name": name,
                "expiry": raw_exp,
                "profile": row.get("profile") or row.get("profile_name"),
            })

    # ترتيب تصاعدي حسب تاريخ الانتهاء (الأقرب أولاً)
    candidates.sort(key=lambda r: str(r.get("expiry") or ""))
    return candidates


async def _execute_renewal_bulk(
    sas: SASClient,
    subscriber_ids: List[int],
    months: Optional[int],
    profile_id: Optional[Any],
    dry_run: bool,
) -> List[Dict[str, Any]]:
    """
    ينفّذ تجديد/تفعيل لكل معرّف في القائمة عبر SASUserClient.

    idempotency: uuid مشتقّ من (serverUrl + subscriberId + دقيقة الطلب) —
    يمنع تنفيذ نفس العملية مرتين خلال نفس الدقيقة إن أُعيد الطلب.

    dryRun: يعيد قائمة ما كان سيُنفَّذ دون أي اتصال كتابي.
    فشل جزئي: الخطأ في مشترك واحد لا يوقف بقية الدفعة.
    """
    # مفتاح idempotency: دقيقة الطلب (تقريب) + معرّف الخادم + المشترك
    minute_key = datetime.now(timezone.utc).strftime("%Y%m%d%H%M")
    base_uuid_ns = uuid.NAMESPACE_URL

    results: List[Dict[str, Any]] = []

    if dry_run:
        for sub_id in subscriber_ids:
            op_uuid = str(uuid.uuid5(base_uuid_ns, f"{sas.base_url}:{sub_id}:{minute_key}"))
            action = "extend" if months is not None else "activate"
            results.append({
                "id": sub_id,
                "ok": None,
                "message": f"[dryRun] سيُنفَّذ {action} — uuid={op_uuid}"
                           + (f" — months={months}" if months else "")
                           + (f" — profileId={profile_id}" if profile_id else ""),
            })
        return results

    # جلب بيانات كل مشترك لنبني SASUserClient بحساب المشترك نفسه
    # ملاحظة: SASUserClient يعمل بحساب المشترك، لكن هنا لدينا حساب الوكيل/المدير فقط.
    # نستخدم العميل الإداري (SASClient) لتنفيذ العمليات عبر /admin/api/ مباشرةً
    # حين لا يتوفّر حساب المشترك — نستدعي POST index/user/{id}/renew أو ما يعادله.
    # بما أن SAS4 يوفّر عملية التمديد عبر بوابة المشترك فقط، نستخدم
    # SASUserClient مع بيانات الاعتماد الإدارية كمشترك وكيل (Reseller).
    # في بيئات SAS4 الحقيقية، الوكيل يمدّد بحسابه الإداري عبر extend/activate.
    for sub_id in subscriber_ids:
        op_uuid = str(uuid.uuid5(base_uuid_ns, f"{sas.base_url}:{sub_id}:{minute_key}"))
        try:
            # نستخدم العميل الإداري (sas) لتنفيذ التمديد إداريّاً
            # إن كان months محدَّداً: extend — وإلا: activate
            if months is not None:
                # POST user/{id}/extend مع profile_id إن وُجد
                payload: Dict[str, Any] = {"uuid": op_uuid}
                if profile_id is not None:
                    payload["profile_id"] = profile_id
                resp = await sas.post(f"user/{sub_id}/extend", payload)
            else:
                # POST user/{id}/activate
                resp = await sas.post(f"user/{sub_id}/activate", {"uuid": op_uuid})

            ok = True
            if isinstance(resp, dict):
                # SAS4 يعيد {"status":200, "message":"..."} أو {"success":true}
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


def _safe_msg(exc: Exception) -> str:
    """يعيد رسالة الخطأ بعد تنظيف أي تسريب محتمل للاعتماد (حذر إضافي)."""
    msg = str(exc)
    # لا تُضمَّن كلمات مرور — SASError لا تضمّنها أصلاً، لكن نُصفّي احتياطاً
    for kw in ("password", "كلمة المرور", "token", "secret"):
        if kw.lower() in msg.lower():
            return "[رسالة محجوبة لاحتوائها كلمة محجوبة]"
    return msg[:300]
