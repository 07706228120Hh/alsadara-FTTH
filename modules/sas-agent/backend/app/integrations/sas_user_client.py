"""
عميل بوابة المشترك في SAS4 (User Portal) — الاتصال بواجهة `/user/api/` الخاصّة
بالمشترك النهائي (بخلاف `SASClient` الذي يكلّم الواجهة الإدارية `/admin/api/`).

المرجع الكامل: backend/knowledge/sas4/sas4_api_full_reference.md (مجلد User Portal، #6–#22)

الفروق عن العميل الإداري:
  - القاعدة:      http(s)://<host>/user/api/index.php/api/<route>
  - تسجيل الدخول: POST auth/login  → {"status":200,"token":"<JWT>"}
  - باقي الآلية (تشفير الحمولة OpenSSL AES، Bearer، مغلّف data/pagination) مطابقة،
    لذا نعيد استخدام sas_encrypt/sas_decrypt/SASError/is_cert_error من sas_client.

الاستخدام:
    async with SASUserClient("sas.company.iq", "user1", "pw") as portal:
        bal = await portal.dashboard()          # الرصيد
        inv = await portal.invoices(page=1)      # الفواتير
"""
from __future__ import annotations

import asyncio
import contextlib
import json
import re
from typing import Any, Dict, Optional

import httpx

# نعيد استخدام منطق التشفير والأخطاء من العميل الإداري (نفس المفتاح ونفس الصيغة)
from .sas_client import SASError, is_cert_error, sas_encrypt  # noqa: F401


class SASUserClient:
    """عميل بوابة المشترك — يحاكي SASClient لكن على مسار /user/api/ ودخول auth/login."""

    def __init__(self, host: str, username: str, password: str, *,
                 https: bool = False, timeout: float = 20.0, verify_tls: bool = True,
                 transport: Optional[httpx.BaseTransport] = None):
        raw = (host or "").strip()
        forced_https = raw.lower().startswith("https://")
        raw = re.sub(r"^https?://", "", raw)          # إزالة البروتوكول إن وُجد
        raw = raw.split("/")[0]                          # إبقاء المضيف (والمنفذ) فقط
        raw = raw.rstrip(":/").strip()
        scheme = "https" if (https or forced_https) else "http"
        self.base_url = f"{scheme}://{raw}/user/api/index.php/api/"
        self.username = username
        self.password = password
        self._token: Optional[str] = None
        self._http = httpx.AsyncClient(timeout=timeout, verify=verify_tls, transport=transport)

    async def __aenter__(self) -> "SASUserClient":
        await self.login()
        return self

    async def __aexit__(self, *exc) -> None:
        with contextlib.suppress(Exception):
            await asyncio.shield(self._http.aclose())

    # ── الأساسيات ──
    def _headers(self) -> Dict[str, str]:
        h = {"Accept": "application/json"}
        if self._token:
            h["Authorization"] = f"Bearer {self._token}"
        return h

    async def post(self, route: str, payload: Optional[Dict[str, Any]] = None) -> Any:
        body = {"payload": sas_encrypt(json.dumps(payload or {}, ensure_ascii=False))}
        r = await self._http.post(self.base_url + route, json=body, headers=self._headers())
        return self._unwrap(r, route)

    async def get(self, route: str, params: Optional[Dict[str, Any]] = None) -> Any:
        r = await self._http.get(self.base_url + route, params=params, headers=self._headers())
        return self._unwrap(r, route)

    @staticmethod
    def _unwrap(r: httpx.Response, route: str) -> Any:
        if r.status_code == 401:
            raise SASError(f"بوابة SAS رفضت المصادقة على {route} (401) — بيانات دخول المشترك خاطئة أو انتهى التوكن")
        if r.status_code == 404:
            raise SASError(
                f"بوابة SAS أعادت 404 على {route} — قد تكون بوابة المشترك (/user/api) غير مفعّلة على هذا الخادم")

        def _snip(txt: str) -> str:
            t = (txt or "").strip()
            return "استجابة HTML (صفحة خطأ/تحويل)" if t[:1] == "<" else t[:200]
        if r.status_code >= 400:
            raise SASError(f"بوابة SAS أعادت {r.status_code} على {route}: {_snip(r.text)}")
        try:
            return r.json()
        except ValueError:
            raise SASError(f"استجابة غير JSON من {route}: {_snip(r.text)}")

    async def login(self, language: str = "ar") -> str:
        data = await self.post("auth/login",
                               {"username": self.username, "password": self.password,
                                "language": language})
        token = data.get("token") if isinstance(data, dict) else None
        if not token:
            raise SASError(f"دخول بوابة المشترك لم يُرجع توكناً: {data}")
        self._token = token
        return token

    # ── قراءة (GET) ──
    async def dashboard(self) -> Any:
        """معلومات الرصيد/الاشتراك (#18 GET dashboard)."""
        return await self.get("dashboard")

    async def user_details(self) -> Any:
        """تفاصيل المشترك وصلاحياته (#17 GET user)."""
        return await self.get("user")

    async def services(self) -> Any:
        """الباقات/الخدمات المتاحة للتغيير (#19 GET service)."""
        return await self.get("service")

    async def packages(self) -> Any:
        """الباقات (#20 GET packages)."""
        return await self.get("packages")

    async def extensions(self, profile_id: int) -> Any:
        """التمديدات المتاحة لباقة (#22 GET extensions/{id})."""
        return await self.get(f"extensions/{profile_id}")

    # ── قوائم بترقيم (POST) ──
    async def invoices(self, *, page: int = 1, count: int = 10,
                       sort_by: str = "id", direction: str = "desc") -> Any:
        """فواتير المشترك (#8 POST index/invoice)."""
        return await self.post("index/invoice", {"page": page, "count": count,
                                                 "sortBy": sort_by, "direction": direction})

    async def sessions(self, *, page: int = 1, count: int = 10,
                       sort_by: str = "radacctid", direction: str = "desc") -> Any:
        """جلسات المشترك النشطة (#10 POST index/session)."""
        return await self.post("index/session", {"page": page, "count": count,
                                                 "sortBy": sort_by, "direction": direction})

    async def traffic(self, *, report_type: str = "daily",
                      month: Optional[int] = None, year: Optional[int] = None) -> Any:
        """استهلاك المشترك (#11 POST traffic) — rx/tx لآخر 30 يوماً."""
        return await self.post("traffic", {"report_type": report_type,
                                           "month": month, "year": year, "user_id": None})

    # ── عمليات كتابية ──
    async def redeem(self, pin: str) -> Any:
        """تعبئة كرت (#12 POST redeem)."""
        return await self.post("redeem", {"pin": pin})

    async def change_subscription(self, new_service: Any, current_password: Any = True) -> Any:
        """تغيير الاشتراك (#9 POST service)."""
        return await self.post("service", {"new_service": new_service,
                                           "current_password": current_password})

    async def change_password(self, new_password: str, current_password: Any = True) -> Any:
        """تغيير كلمة المرور (#15 POST user) — {key:'password', value:<new>}."""
        return await self.post("user", {"key": "password", "value": new_password,
                                        "current_password": current_password})

    async def activate(self, uuid: str, current_password: Any = True) -> Any:
        """تفعيل الاشتراك وخصم الرصيد (#13 POST user/activate) — uuid يمنع التكرار."""
        return await self.post("user/activate", {"uuid": uuid,
                                                 "current_password": current_password})

    async def extend(self, profile_id: Any, current_password: Any = True) -> Any:
        """تفعيل تمديد (#14 POST user/extend)."""
        return await self.post("user/extend", {"profile_id": profile_id,
                                               "current_password": current_password})
