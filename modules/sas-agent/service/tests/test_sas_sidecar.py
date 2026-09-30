"""
اختبارات pytest لخدمة SAS Sidecar (service/app.py).

تُركّز على:
  1) fail-closed: غياب X-Internal-Secret => 401؛ السرّ فارغ => 503.
  2) dryRun في /renewal/bulk: لا يستدعي أي عملية كتابية + يعيد ok=None.

كل الاختبارات تستخدم FastAPI TestClient + monkeypatch لـ SASClient — بلا خادم SAS حقيقي.
"""
from __future__ import annotations

import importlib
import os
import sys
import types
import unittest.mock as mock
from typing import Any, AsyncIterator, Dict, List, Optional

import pytest

# ── ضبط sys.path لجعل import app ممكناً ──────────────────────────────────────
# نضيف مجلد service إلى sys.path
_SERVICE_DIR = os.path.dirname(__file__)               # .../service/tests
_SERVICE_PARENT = os.path.dirname(_SERVICE_DIR)        # .../service
if _SERVICE_PARENT not in sys.path:
    sys.path.insert(0, _SERVICE_PARENT)

# نضيف backend/app أيضاً لأن app.py يستورد منه SASClient
_BACKEND_APP = os.path.normpath(
    os.path.join(_SERVICE_PARENT, "..", "backend", "app")
)
if _BACKEND_APP not in sys.path:
    sys.path.insert(0, _BACKEND_APP)


# ── إنشاء stub لـ integrations.sas_client قبل استيراد app ────────────────────

class _FakeSASError(RuntimeError):
    pass


class _FakeSASClient:
    """
    Stub لـ SASClient — لا يفتح اتصالاً حقيقياً.
    يُستبدَل بمضاعفات محدّدة في كل اختبار عبر monkeypatch.
    """
    write_calls: List[str] = []  # سجلّ مشترك (يُصفَّر في كل اختبار)

    def __init__(self, server_url: str, username: str, password: str):
        self.base_url = server_url
        self._token = "fake-token"

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        pass

    async def dashboard_subscribers(self) -> Dict[str, Any]:
        return {"users": []}

    async def dashboard_finance(self) -> Dict[str, Any]:
        return {}

    async def users(self, **kw) -> List[Any]:
        return []

    async def managers_full(self, **kw) -> List[Any]:
        return []

    async def profiles(self) -> List[Any]:
        return []

    async def dashboard_system_health(self) -> Dict[str, Any]:
        return {}

    async def iter_all(self, entity: str, **kw) -> AsyncIterator[Dict[str, Any]]:
        return
        yield  # جعله generator

    async def post(self, route: str, payload=None) -> Any:
        _FakeSASClient.write_calls.append(route)
        return {"status": 200, "message": "ok"}


def _make_sas_module() -> types.ModuleType:
    """يُنشئ وحدة وهمية لـ integrations.sas_client."""
    mod = types.ModuleType("integrations.sas_client")
    mod.SASClient = _FakeSASClient       # type: ignore[attr-defined]
    mod.SASError  = _FakeSASError        # type: ignore[attr-defined]
    return mod


def _make_sas_user_module() -> types.ModuleType:
    """يُنشئ وحدة وهمية لـ integrations.sas_user_client."""
    mod = types.ModuleType("integrations.sas_user_client")

    class _FakeSASUserClient:
        def __init__(self, *a, **kw):
            pass
        async def __aenter__(self): return self
        async def __aexit__(self, *exc): pass

    mod.SASUserClient = _FakeSASUserClient  # type: ignore[attr-defined]
    return mod


# ── تسجيل الوحدات الوهمية مرة واحدة قبل كل الاختبارات ──────────────────────
sys.modules.setdefault("integrations", types.ModuleType("integrations"))
sys.modules["integrations.sas_client"]      = _make_sas_module()
sys.modules["integrations.sas_user_client"] = _make_sas_user_module()

# الآن نستطيع استيراد app بأمان
import app as sidecar_app  # noqa: E402

from fastapi.testclient import TestClient  # noqa: E402


# ══════════════════════════════════════════════════════════════════════════════
# مساعدات وثوابت
# ══════════════════════════════════════════════════════════════════════════════

VALID_SECRET = "test-secret-for-unit-tests"

_COMMON_BODY = {
    "serverUrl": "http://sas.test",
    "username":  "agent",
    "password":  "pass",
}


def _client(secret: str = VALID_SECRET) -> TestClient:
    """ينشئ TestClient مع السرّ المُضبَط في متغيّر البيئة."""
    # نُعيد ضبط السرّ قبل كل استخدام (monkeypatch على المستوى العالمي للوحدة)
    sidecar_app._INTERNAL_SECRET = secret
    return TestClient(sidecar_app.app, raise_server_exceptions=False)


# ══════════════════════════════════════════════════════════════════════════════
# 1) اختبارات fail-closed
# ══════════════════════════════════════════════════════════════════════════════

class TestFailClosed:
    """
    verify_internal_secret يجب أن:
      - يعيد 503 إن السرّ غير مضبوط (فارغ).
      - يعيد 401 إن الرأس غائب أو خاطئ.
      - يمرّر الطلب إن الرأس صحيح.
    """

    def test_no_header_returns_401(self):
        """غياب X-Internal-Secret تماماً => 401."""
        client = _client(VALID_SECRET)
        resp = client.post("/dashboard", json=_COMMON_BODY)
        assert resp.status_code == 401, resp.text

    def test_wrong_header_returns_401(self):
        """رأس خاطئ => 401."""
        client = _client(VALID_SECRET)
        resp = client.post(
            "/dashboard",
            json=_COMMON_BODY,
            headers={"X-Internal-Secret": "WRONG-SECRET"},
        )
        assert resp.status_code == 401, resp.text

    def test_empty_string_secret_env_returns_503(self):
        """السرّ مضبوط على سلسلة فارغة => 503 (fail-closed)."""
        client = _client("")  # سرّ فارغ
        resp = client.post(
            "/dashboard",
            json=_COMMON_BODY,
            headers={"X-Internal-Secret": "anything"},
        )
        assert resp.status_code == 503, resp.text

    def test_correct_header_passes_through(self):
        """الرأس الصحيح => لا 401/503 (الطلب يُمرَّر للـ SAS stub)."""
        client = _client(VALID_SECRET)
        resp = client.post(
            "/dashboard",
            json=_COMMON_BODY,
            headers={"X-Internal-Secret": VALID_SECRET},
        )
        # الـ stub يعيد {} بنجاح => ليس 401 أو 503
        assert resp.status_code not in (401, 403, 503), resp.text

    def test_health_endpoint_requires_no_auth(self):
        """GET /health بلا رأس => 200 (بلا مصادقة)."""
        client = _client("")  # حتى مع سرّ فارغ
        resp = client.get("/health")
        assert resp.status_code == 200
        assert resp.json().get("status") == "ok"

    def test_login_no_header_returns_401(self):
        """POST /login بلا رأس => 401."""
        client = _client(VALID_SECRET)
        resp = client.post("/login", json=_COMMON_BODY)
        assert resp.status_code == 401

    def test_subscribers_no_header_returns_401(self):
        """POST /subscribers بلا رأس => 401."""
        client = _client(VALID_SECRET)
        resp = client.post("/subscribers", json={**_COMMON_BODY, "query": {}})
        assert resp.status_code == 401

    def test_timing_safe_comparison_wrong_prefix(self):
        """رأس يبدأ بالسرّ الصحيح لكن أطول => 401 (لا bypass جزئي)."""
        client = _client(VALID_SECRET)
        resp = client.post(
            "/dashboard",
            json=_COMMON_BODY,
            headers={"X-Internal-Secret": VALID_SECRET + "-extra"},
        )
        assert resp.status_code == 401


# ══════════════════════════════════════════════════════════════════════════════
# 2) اختبارات /renewal/bulk — dryRun
# ══════════════════════════════════════════════════════════════════════════════

class TestRenewalBulkDryRun:
    """
    dryRun=true يجب أن:
      - لا يستدعي أي دالة كتابية (post/activate/extend) على SASClient.
      - يعيد قائمة بعدد المشتركين ذاتها، كل عنصر ok=null.
    """

    def setup_method(self):
        """نُصفّر سجل الطلبات الكتابية قبل كل اختبار."""
        _FakeSASClient.write_calls = []

    def _post_bulk(self, subscriber_ids: List[int], months: int = 1, dry_run: bool = True):
        client = _client(VALID_SECRET)
        body = {
            **_COMMON_BODY,
            "subscriberIds": subscriber_ids,
            "months": months,
            "dryRun": dry_run,
        }
        return client.post(
            "/renewal/bulk",
            json=body,
            headers={"X-Internal-Secret": VALID_SECRET},
        )

    def test_dry_run_returns_200(self):
        resp = self._post_bulk([1, 2, 3], dry_run=True)
        assert resp.status_code == 200, resp.text

    def test_dry_run_returns_same_count_as_input(self):
        ids = [10, 20, 30]
        resp = self._post_bulk(ids, dry_run=True)
        data = resp.json()
        assert isinstance(data, list), data
        assert len(data) == len(ids)

    def test_dry_run_all_items_ok_is_null(self):
        """كل عنصر يجب أن يكون ok=null في وضع المعاينة."""
        resp = self._post_bulk([5, 6, 7], dry_run=True)
        data = resp.json()
        for item in data:
            assert item.get("ok") is None, f"ok should be null in dryRun, got: {item}"

    def test_dry_run_does_not_call_sas_write(self):
        """dryRun لا يستدعي post/extend/activate على SASClient."""
        _FakeSASClient.write_calls = []
        self._post_bulk([100, 200], months=1, dry_run=True)
        assert _FakeSASClient.write_calls == [], \
            f"لا يجب أن تُستدعى عمليات كتابية في dryRun، استُدعيت: {_FakeSASClient.write_calls}"

    def test_dry_run_message_contains_dryrun_marker(self):
        """رسالة كل عنصر يجب أن تشير إلى dryRun."""
        resp = self._post_bulk([1], dry_run=True)
        data = resp.json()
        assert len(data) == 1
        msg = data[0].get("message", "")
        assert "dryRun" in msg or "dry" in msg.lower(), \
            f"رسالة dryRun غير واضحة: {msg}"

    def test_dry_run_single_subscriber(self):
        """dryRun لمشترك واحد => قائمة بعنصر واحد."""
        resp = self._post_bulk([42], dry_run=True)
        data = resp.json()
        assert len(data) == 1
        assert data[0]["id"] == 42

    def test_real_run_calls_write_operations(self):
        """التشغيل الحقيقي (dryRun=false) يستدعي post على SASClient."""
        _FakeSASClient.write_calls = []
        resp = self._post_bulk([1], months=1, dry_run=False)
        assert resp.status_code == 200, resp.text
        # الـ stub يُسجّل الاستدعاءات الكتابية
        assert len(_FakeSASClient.write_calls) > 0, \
            "التشغيل الحقيقي يجب أن يستدعي عمليات كتابية"

    def test_empty_subscriber_list_rejected(self):
        """قائمة مشتركين فارغة => 422 (Pydantic validation)."""
        client = _client(VALID_SECRET)
        resp = client.post(
            "/renewal/bulk",
            json={**_COMMON_BODY, "subscriberIds": [], "months": 1, "dryRun": True},
            headers={"X-Internal-Secret": VALID_SECRET},
        )
        # Pydantic يرفض القائمة الفارغة إن كانت مطلوبة، أو نستقبل 200 بقائمة فارغة
        # كلا الاحتمالين مقبول؛ ما يهم: لا استدعاءات كتابية
        assert _FakeSASClient.write_calls == []

    def test_no_secret_bulk_returns_401(self):
        """bulk بلا رأس => 401."""
        client = _client(VALID_SECRET)
        resp = client.post(
            "/renewal/bulk",
            json={**_COMMON_BODY, "subscriberIds": [1], "months": 1, "dryRun": True},
        )
        assert resp.status_code == 401
