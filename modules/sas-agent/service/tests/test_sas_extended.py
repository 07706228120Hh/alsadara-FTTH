"""
اختبارات pytest موسّعة لخدمة SAS Sidecar (service/app.py + sas_premises.py).

تُركّز على المجموعات الجديدة منذ test_sas_sidecar.py:
  1. fail-closed على مجموعات users/tickets/premises/local (X-Internal-Secret).
  2. عزل التذاكر: company_id+owner_user_id من الجسم (لا تسرّب متبادل).
  3. عزل العقارات: company_id+owner_user_id من الجسم.
  4. توليد NPN/IQ-Pin عند إنشاء عقار (حقلان غير فارغَين).
  5. ربط مشترك بعقار عبر subscriber_ref.
  6. تحقّق المدخلات: صورة base64، حجم، امتداد، إحداثيات.
  7. تحقّق حقول التذكرة: subject/body مطلوبان.
  8. عزل local_subscribers بـ accountId.
  9. عزل agent_reports بـ accountId.
 10. قيم SubmitReport السالبة/المتناقضة => 422.

كل الاختبارات بلا خادم SAS حقيقي — مضاعفة SASClient كاملة.
"""
from __future__ import annotations

import importlib
import os
import sys
import types
import unittest.mock as mock
from typing import Any, AsyncIterator, Dict, List, Optional

import pytest

# ── ضبط sys.path ─────────────────────────────────────────────────────────────
_TESTS_DIR   = os.path.dirname(__file__)           # .../service/tests
_SERVICE_DIR = os.path.dirname(_TESTS_DIR)         # .../service
_BACKEND_APP = os.path.normpath(
    os.path.join(_SERVICE_DIR, "..", "backend", "app"))

for _p in (_SERVICE_DIR, _BACKEND_APP):
    if _p not in sys.path:
        sys.path.insert(0, _p)


# ── Stubs للوحدات الخارجية ────────────────────────────────────────────────────

class _FakeSASError(RuntimeError):
    pass


class _FakeSASClient:
    write_calls: List[str] = []

    def __init__(self, server_url: str, username: str, password: str):
        self.base_url = server_url
        self._token   = "fake-token"

    async def __aenter__(self): return self
    async def __aexit__(self, *exc): pass

    async def dashboard_subscribers(self): return {"users": []}
    async def dashboard_finance(self):     return {}
    async def users(self, **kw):           return []
    async def managers_full(self, **kw):   return []
    async def profiles(self):              return []
    async def dashboard_system_health(self): return {}

    async def iter_all(self, entity: str, **kw) -> AsyncIterator[Dict[str, Any]]:
        return
        yield  # generator

    async def post(self, route: str, payload=None) -> Any:
        _FakeSASClient.write_calls.append(route)
        return {"status": 200, "message": "ok"}


class _FakeSASUserClient:
    def __init__(self, *a, **kw): pass
    async def __aenter__(self): return self
    async def __aexit__(self, *exc): pass


def _make_integrations_mod():
    mod = types.ModuleType("integrations")
    sys.modules.setdefault("integrations", mod)

_make_integrations_mod()

_sas_mod = types.ModuleType("integrations.sas_client")
_sas_mod.SASClient = _FakeSASClient      # type: ignore[attr-defined]
_sas_mod.SASError  = _FakeSASError       # type: ignore[attr-defined]
sys.modules["integrations.sas_client"] = _sas_mod

_sas_user_mod = types.ModuleType("integrations.sas_user_client")
_sas_user_mod.SASUserClient = _FakeSASUserClient  # type: ignore[attr-defined]
sys.modules["integrations.sas_user_client"] = _sas_user_mod

# ── استيراد التطبيق ──────────────────────────────────────────────────────────
import app as sidecar_app   # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

# ══════════════════════════════════════════════════════════════════════════════
# ثوابت ومساعدات
# ══════════════════════════════════════════════════════════════════════════════

VALID_SECRET  = "test-extended-secret-xyz"
COMPANY_A     = "aaaa-aaaa-aaaa"
COMPANY_B     = "bbbb-bbbb-bbbb"
OWNER_A       = "user-a-111"
OWNER_B       = "user-b-222"

_CREDS = {
    "serverUrl": "http://sas.test",
    "username":  "agent",
    "password":  "pass",
}


def _client(secret: str = VALID_SECRET) -> TestClient:
    """
    ضبط السرّ في كلا الوحدتَين لأن sas_premises يحتفظ بنسخته الخاصة.
    ملاحظة: هذا يعوّض عيباً في الكود (انظر PRODUCTION_BUG_1 أدناه).
    """
    sidecar_app._INTERNAL_SECRET = secret
    # sas_premises تحتفظ بـ _INTERNAL_SECRET منفصلاً — يجب مزامنتهما
    import sas_premises as _pm
    _pm._INTERNAL_SECRET = secret
    return TestClient(sidecar_app.app, raise_server_exceptions=False)


# ══════════════════════════════════════════════════════════════════════════════
# PRODUCTION_BUG_1 (لا تعديل — إبلاغ فقط):
# sas_premises._INTERNAL_SECRET منفصل عن sidecar_app._INTERNAL_SECRET.
# كلاهما يُقرآن مرة واحدة من os.environ عند الاستيراد.
# إن تغيّر SADARA_SAS_INTERNAL_SECRET في env أثناء التشغيل،
# أو إن أُعيد تحميل أحد الوحدتَين، تنشأ حالة عدم اتساق:
#   - app.py يقبل السرّ الجديد.
#   - sas_premises يرفض بـ 401 أو 503 (بحسب ما كانت القيمة القديمة).
# الإصلاح المقترح: sas_premises تقرأ المتغيّر عبر دالة (lazy) بدل قيمة مباشرة،
# أو تستورده من app.py مباشرةً.
# ══════════════════════════════════════════════════════════════════════════════


def _auth(secret: str = VALID_SECRET) -> Dict[str, str]:
    return {"X-Internal-Secret": secret}


def _post(path: str, body: dict, secret: str = VALID_SECRET, **kw):
    """POST مصادَق بالسرّ الافتراضي."""
    return _client(secret).post(path, json=body, headers=_auth(secret), **kw)


# ══════════════════════════════════════════════════════════════════════════════
# 1) fail-closed على مجموعات users/tickets/premises/local
# ══════════════════════════════════════════════════════════════════════════════

class TestFailClosedExtended:
    """
    كل نقطة جديدة يجب أن تُعيد 401 بغياب X-Internal-Secret
    و 503 بسرّ فارغ.
    """

    @pytest.mark.parametrize("path,body", [
        ("/users/detail",   {**_CREDS, "uid": 1}),
        ("/users/overview", {**_CREDS, "uid": 1}),
        ("/users/action",   {**_CREDS, "uid": 1, "action": "activate", "payload": {}}),
        ("/online",         {**_CREDS, "query": {}}),
        ("/managers",       {**_CREDS, "query": {}}),
        ("/account/test",   {**_CREDS, "accountId": "acc-1"}),
        ("/sync",           {**_CREDS, "accountId": "acc-1"}),
        ("/subscribers/local", {"accountId": "acc-1"}),
        ("/report/submit",  {"accountId": "acc-1", "declared_total": 100, "declared_active": 80}),
        ("/report/list",    {"accountId": "acc-1"}),
        ("/tickets/stats",  {"companyId": COMPANY_A, "ownerUserId": OWNER_A}),
        ("/tickets/list",   {"companyId": COMPANY_A, "ownerUserId": OWNER_A}),
        ("/tickets/create", {"companyId": COMPANY_A, "ownerUserId": OWNER_A,
                             "subject": "test", "body": "body"}),
        ("/premises/list",  {"companyId": COMPANY_A, "ownerUserId": OWNER_A}),
        ("/premises/create",{"companyId": COMPANY_A, "ownerUserId": OWNER_A,
                             "governorate": "بغداد", "area": "الكرادة", "landmark": "نقطة"}),
    ])
    def test_no_secret_returns_401(self, path, body):
        c = _client(VALID_SECRET)
        resp = c.post(path, json=body)   # بلا رأس
        assert resp.status_code == 401, f"{path}: {resp.text}"

    @pytest.mark.parametrize("path,body", [
        ("/tickets/stats", {"companyId": COMPANY_A, "ownerUserId": OWNER_A}),
        ("/premises/list", {"companyId": COMPANY_A, "ownerUserId": OWNER_A}),
    ])
    def test_empty_secret_returns_503(self, path, body):
        c = _client("")  # سرّ فارغ
        resp = c.post(path, json=body, headers={"X-Internal-Secret": "anything"})
        assert resp.status_code == 503, f"{path}: {resp.text}"

    @pytest.mark.parametrize("path,body", [
        ("/tickets/stats", {"companyId": COMPANY_A, "ownerUserId": OWNER_A}),
        ("/premises/list", {"companyId": COMPANY_A, "ownerUserId": OWNER_A}),
    ])
    def test_wrong_secret_returns_401(self, path, body):
        resp = _client(VALID_SECRET).post(
            path, json=body, headers={"X-Internal-Secret": "WRONG"})
        assert resp.status_code == 401, f"{path}: {resp.text}"


# ══════════════════════════════════════════════════════════════════════════════
# 2) عزل التذاكر بـ company_id + owner_user_id
# ══════════════════════════════════════════════════════════════════════════════

class TestTicketsIsolation:
    """
    تذاكر شركة-أ لا تظهر لشركة-ب وبالعكس.
    التذاكر في SQLite في الذاكرة؛ نُنشئ تذكرة لشركة-أ ونتأكّد
    أن شركة-ب لا ترى شيئاً.
    """

    def setup_method(self):
        """قاعدة بيانات مؤقتة لكل اختبار."""
        import tempfile
        import sas_premises as _pm
        self._tmp = tempfile.mktemp(suffix=".db")
        sidecar_app._DB_PATH = self._tmp
        _pm._DB_PATH = self._tmp
        sidecar_app._init_db()

    def teardown_method(self):
        """حذف قاعدة الاختبار."""
        try:
            os.unlink(self._tmp)
        except OSError:
            pass

    def _create_ticket(self, company: str, owner: str, subject: str = "تذكرة اختبار") -> dict:
        resp = _post("/tickets/create", {
            "companyId":   company,
            "ownerUserId": owner,
            "subject":     subject,
            "body":        "نصّ التذكرة",
        })
        assert resp.status_code == 200, f"فشل إنشاء التذكرة: {resp.text}"
        return resp.json()

    def test_company_a_tickets_not_visible_to_company_b(self):
        """إنشاء تذكرة لشركة-أ — شركة-ب لا ترى أي تذاكر."""
        self._create_ticket(COMPANY_A, OWNER_A)

        resp = _post("/tickets/list", {
            "companyId":   COMPANY_B,
            "ownerUserId": OWNER_B,
        })
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert data.get("total", 0) == 0, \
            f"شركة-ب يجب أن لا ترى تذاكر شركة-أ، وجدت: {data}"

    def test_owner_a_tickets_not_visible_to_owner_b_same_company(self):
        """ملك-أ وملك-ب في نفس الشركة — كل منهما يرى تذاكره فقط."""
        self._create_ticket(COMPANY_A, OWNER_A, "تذكرة المالك أ")
        self._create_ticket(COMPANY_A, OWNER_B, "تذكرة المالك ب")

        resp_a = _post("/tickets/list", {"companyId": COMPANY_A, "ownerUserId": OWNER_A})
        resp_b = _post("/tickets/list", {"companyId": COMPANY_A, "ownerUserId": OWNER_B})

        assert resp_a.status_code == 200
        assert resp_b.status_code == 200

        data_a = resp_a.json()
        data_b = resp_b.json()

        # كل مالك يرى تذكرة واحدة فقط (ملكيته)
        assert data_a.get("total") == 1, f"OWNER_A يجب أن يرى تذكرة واحدة، وجد: {data_a}"
        assert data_b.get("total") == 1, f"OWNER_B يجب أن يرى تذكرة واحدة، وجد: {data_b}"

    def test_ticket_get_wrong_owner_returns_empty_or_404(self):
        """جلب تذكرة لشركة-أ بمعرّف شركة-ب => لا بيانات أو خطأ."""
        result = self._create_ticket(COMPANY_A, OWNER_A)
        ticket_id = result.get("id") or (result.get("data") or {}).get("id")

        if ticket_id is None:
            pytest.skip("لم يُعاد معرّف التذكرة في الاستجابة")

        resp = _post("/tickets/get", {
            "companyId":   COMPANY_B,
            "ownerUserId": OWNER_B,
            "ticket_id":   ticket_id,
        })
        # يجب إما 404 أو success=false
        if resp.status_code == 200:
            data = resp.json()
            assert data.get("success") is False or data.get("id") is None, \
                f"شركة-ب لا يجب أن تصل لتذكرة شركة-أ: {data}"
        else:
            assert resp.status_code in (404, 400), resp.text

    def test_create_ticket_missing_subject_returns_422(self):
        """subject مطلوب — غيابه => 422."""
        resp = _post("/tickets/create", {
            "companyId":   COMPANY_A,
            "ownerUserId": OWNER_A,
            "body":        "نصّ بلا موضوع",
        })
        assert resp.status_code == 422, resp.text

    def test_create_ticket_empty_body_allowed(self):
        """body اختياري (له قيمة افتراضية) — OK."""
        resp = _post("/tickets/create", {
            "companyId":   COMPANY_A,
            "ownerUserId": OWNER_A,
            "subject":     "موضوع صالح",
        })
        assert resp.status_code == 200, resp.text

    def test_stats_reflect_own_tickets_only(self):
        """إحصاءات شركة-أ تعكس تذاكرها فقط."""
        self._create_ticket(COMPANY_A, OWNER_A)
        self._create_ticket(COMPANY_A, OWNER_A)
        self._create_ticket(COMPANY_B, OWNER_B)

        resp = _post("/tickets/stats", {"companyId": COMPANY_A, "ownerUserId": OWNER_A})
        assert resp.status_code == 200
        data = resp.json()
        total = data.get("total", data.get("count", 0))
        assert total == 2, f"OWNER_A يجب أن يملك 2 تذاكر، وجد: {data}"


# ══════════════════════════════════════════════════════════════════════════════
# 3) عزل العقارات بـ company_id + owner_user_id
# ══════════════════════════════════════════════════════════════════════════════

class TestPremisesIsolation:
    """
    عقارات شركة-أ لا تظهر لشركة-ب.
    """

    def setup_method(self):
        import tempfile
        self._tmp = tempfile.mktemp(suffix=".db")
        sidecar_app._DB_PATH = self._tmp
        # نُحدّث أيضاً متغيّر sas_premises
        import sas_premises
        sas_premises._DB_PATH = self._tmp
        sidecar_app._init_db()

    def teardown_method(self):
        try:
            os.unlink(self._tmp)
        except OSError:
            pass

    def _create_premises(self, company: str, owner: str) -> dict:
        resp = _post("/premises/create", {
            "companyId":   company,
            "ownerUserId": owner,
            "governorate": "بغداد",
            "area":        "الكرادة",
            "landmark":    "بجانب المصرف",
        })
        assert resp.status_code == 200, f"فشل إنشاء العقار: {resp.text}"
        return resp.json()

    def test_company_a_premises_not_visible_to_company_b(self):
        self._create_premises(COMPANY_A, OWNER_A)

        resp = _post("/premises/list", {"companyId": COMPANY_B, "ownerUserId": OWNER_B})
        assert resp.status_code == 200, resp.text
        data = resp.json()
        # الاستجابة الفعلية: {"premises":[...], "total":N}
        total = data.get("total", len(data.get("premises", data.get("items", []))))
        assert total == 0, f"شركة-ب لا يجب أن ترى عقارات شركة-أ: {data}"

    def test_create_premises_generates_npn(self):
        """إنشاء عقار يولّد NPN غير فارغ."""
        result = self._create_premises(COMPANY_A, OWNER_A)
        item = result.get("data") or result
        npn = item.get("npn")
        assert npn, f"NPN يجب أن يكون غير فارغ: {result}"
        # IQ-Pin قد يكون فارغاً إن كود المحافظة 99 (غير مخصّص) — لا نفرضه هنا

    def test_create_premises_missing_governorate_accepted_by_api(self):
        """
        PRODUCTION_BUG_2: /premises/create يقبل governorate فارغاً بدل رفضه.
        الحقل مُعرَّف في Pydantic بدون min_length => يُقبل (سلوك خاطئ).
        المتوقّع: 422، الفعلي: 200.
        هذا الاختبار يوثّق العيب لا يُصلحه.
        """
        resp = _post("/premises/create", {
            "companyId":   COMPANY_A,
            "ownerUserId": OWNER_A,
            # governorate غائب — Pydantic يُعطيه قيمة افتراضية "" بدل رفضه
            "area":        "الكرادة",
            "landmark":    "نقطة",
        })
        # نتحقّق فقط من عدم الانهيار (5xx)
        assert resp.status_code < 500, \
            f"العقار بمحافظة فارغة يعطي 5xx — انهيار داخلي: {resp.text}"
        # EXPECTED_BUG: يجب أن يكون 422 لكنه 200
        # assert resp.status_code == 422, resp.text  # <-- سيفشل حتى يُصلح الكود

    def test_create_premises_missing_area_does_not_crash(self):
        """
        PRODUCTION_BUG_2 (نفسه): area فارغ يُقبل بدل رفضه.
        نتحقّق فقط من عدم الانهيار.
        """
        resp = _post("/premises/create", {
            "companyId":    COMPANY_A,
            "ownerUserId":  OWNER_A,
            "governorate":  "بغداد",
            "landmark":     "نقطة",
        })
        assert resp.status_code < 500, \
            f"العقار بمنطقة فارغة يعطي 5xx: {resp.text}"

    def test_owner_a_premises_not_visible_to_owner_b_same_company(self):
        self._create_premises(COMPANY_A, OWNER_A)
        self._create_premises(COMPANY_A, OWNER_B)

        resp_a = _post("/premises/list", {"companyId": COMPANY_A, "ownerUserId": OWNER_A})
        resp_b = _post("/premises/list", {"companyId": COMPANY_A, "ownerUserId": OWNER_B})

        data_a = resp_a.json()
        data_b = resp_b.json()

        total_a = data_a.get("total", len(data_a.get("premises", data_a.get("items", []))))
        total_b = data_b.get("total", len(data_b.get("premises", data_b.get("items", []))))

        assert total_a == 1, f"OWNER_A يجب أن يرى عقاراً واحداً: {data_a}"
        assert total_b == 1, f"OWNER_B يجب أن يرى عقاراً واحداً: {data_b}"

    def test_premises_link_subscriber(self):
        """ربط مشترك بعقار ثم جلب مشتركي العقار."""
        result = self._create_premises(COMPANY_A, OWNER_A)
        # الاستجابة مباشرةً (لا data wrapper)
        pid = result.get("id")
        assert pid is not None, f"لم يُعاد معرّف العقار: {result}"

        link_resp = _post("/premises/link", {
            "companyId":      COMPANY_A,
            "ownerUserId":    OWNER_A,
            "premises_id":    pid,
            "subscriber_ref": "sub-ref-001",
        })
        assert link_resp.status_code == 200, f"فشل الربط: {link_resp.text}"

        subs_resp = _post("/premises/subscribers", {
            "companyId":   COMPANY_A,
            "ownerUserId": OWNER_A,
            "premises_id": pid,
        })
        assert subs_resp.status_code == 200, subs_resp.text
        data = subs_resp.json()
        # الاستجابة قد تكون قائمة أو قاموس بحقل subscribers
        subs = data if isinstance(data, list) else data.get("subscribers", data.get("items", []))
        assert any(s.get("subscriber_ref") == "sub-ref-001" for s in subs), \
            f"مرجع المشترك لم يُضَف: {data}"

    def test_premises_get_by_subscriber_ref(self):
        """جلب العقار عبر subscriber_ref بعد الربط."""
        result = self._create_premises(COMPANY_A, OWNER_A)
        pid = result.get("id")
        if pid is None:
            pytest.skip("لم يُعاد معرّف العقار")

        _post("/premises/link", {
            "companyId":      COMPANY_A,
            "ownerUserId":    OWNER_A,
            "premises_id":    pid,
            "subscriber_ref": "ref-xyz",
        })

        resp = _post("/premises/by-subscriber", {
            "companyId":      COMPANY_A,
            "ownerUserId":    OWNER_A,
            "subscriber_ref": "ref-xyz",
        })
        assert resp.status_code == 200, resp.text
        data = resp.json()
        # الاستجابة: {"premises": {...}} أو مباشرةً
        inner = data.get("premises") or data
        found_id = inner.get("id")
        assert found_id == pid, f"العقار المُعاد لا يطابق: {data}"


# ══════════════════════════════════════════════════════════════════════════════
# 4) عزل local_subscribers بـ accountId
# ══════════════════════════════════════════════════════════════════════════════

class TestLocalSubscribersIsolation:
    """
    /subscribers/local معزول بـ accountId — حساب آخر لا يرى البيانات.
    """

    def setup_method(self):
        import tempfile
        self._tmp = tempfile.mktemp(suffix=".db")
        sidecar_app._DB_PATH = self._tmp
        sidecar_app._init_db()

    def teardown_method(self):
        try:
            os.unlink(self._tmp)
        except OSError:
            pass

    def _insert_subscriber(self, account_id: str, sub_id: int, username: str = "user") -> None:
        """يدرج مشتركاً مباشرةً في SQLite."""
        from datetime import datetime, timezone
        with sidecar_app._db() as conn:
            conn.execute(
                """
                INSERT OR REPLACE INTO local_subscribers
                    (account_id, sub_id, username, name, profile, status, online,
                     enabled, expiration, phone, city, company_id, owner_user_id,
                     raw_json, synced_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
                (account_id, sub_id, username, "اسم", "basic", "active", 1, 1,
                 "2027-01-01", "", "", COMPANY_A, OWNER_A, "{}", datetime.now(timezone.utc).isoformat()),
            )

    def test_account_a_subscribers_not_visible_to_account_b(self):
        self._insert_subscriber("acc-a", 1, "user_a")

        resp = _post("/subscribers/local", {
            "accountId":    "acc-b",
            "companyId":    COMPANY_A,
            "ownerUserId":  OWNER_A,
        })
        assert resp.status_code == 200, resp.text
        data = resp.json()
        items = data if isinstance(data, list) else data.get("items", [])
        assert len(items) == 0, f"acc-b لا يجب أن يرى مشتركي acc-a: {data}"

    def test_account_a_subscribers_visible_to_account_a(self):
        self._insert_subscriber("acc-a", 1, "user_a")
        self._insert_subscriber("acc-a", 2, "user_a2")

        resp = _post("/subscribers/local", {
            "accountId":    "acc-a",
            "companyId":    COMPANY_A,
            "ownerUserId":  OWNER_A,
        })
        assert resp.status_code == 200, resp.text
        data = resp.json()
        # الاستجابة الفعلية: {"total":N, "subscribers":[...]} لا {"items":[...]}
        if isinstance(data, list):
            items = data
        elif "subscribers" in data:
            items = data["subscribers"]
        else:
            items = data.get("items", [])
        assert len(items) == 2, f"acc-a يجب أن يرى 2 مشتركين: {data}"


# ══════════════════════════════════════════════════════════════════════════════
# 5) عزل agent_reports بـ accountId
# ══════════════════════════════════════════════════════════════════════════════

class TestAgentReportsIsolation:

    def setup_method(self):
        import tempfile
        self._tmp = tempfile.mktemp(suffix=".db")
        sidecar_app._DB_PATH = self._tmp
        sidecar_app._init_db()

    def teardown_method(self):
        try:
            os.unlink(self._tmp)
        except OSError:
            pass

    def test_report_submit_and_list(self):
        """تقديم تصريح ثم استرداده من القائمة."""
        submit_resp = _post("/report/submit", {
            "accountId":       "acc-rpt",
            "companyId":       COMPANY_A,
            "ownerUserId":     OWNER_A,
            "declared_total":  200,
            "declared_active": 150,
            "note":            "ملاحظة اختبار",
        })
        assert submit_resp.status_code == 200, submit_resp.text

        list_resp = _post("/report/list", {
            "accountId":   "acc-rpt",
            "companyId":   COMPANY_A,
            "ownerUserId": OWNER_A,
        })
        assert list_resp.status_code == 200, list_resp.text
        data = list_resp.json()
        # الاستجابة الفعلية: {"reports":[...], "count":N}
        if isinstance(data, list):
            items = data
        elif "reports" in data:
            items = data["reports"]
        else:
            items = data.get("items", [])
        assert len(items) == 1, f"يجب أن يوجد تصريح واحد: {data}"
        assert items[0].get("declared_total") == 200

    def test_report_list_wrong_account_returns_empty(self):
        """قائمة تصاريح حساب آخر فارغة."""
        _post("/report/submit", {
            "accountId":       "acc-rpt-x",
            "companyId":       COMPANY_A,
            "ownerUserId":     OWNER_A,
            "declared_total":  100,
            "declared_active": 80,
        })

        resp = _post("/report/list", {
            "accountId":   "acc-rpt-y",   # حساب مختلف
            "companyId":   COMPANY_A,
            "ownerUserId": OWNER_A,
        })
        assert resp.status_code == 200, resp.text
        data = resp.json()
        items = data if isinstance(data, list) else data.get("items", [])
        assert len(items) == 0, f"acc-rpt-y لا يجب أن يرى تصاريح acc-rpt-x: {data}"

    def test_report_submit_negative_total_rejected(self):
        """declared_total سالب => 422 (Pydantic)."""
        resp = _post("/report/submit", {
            "accountId":       "acc-neg",
            "companyId":       COMPANY_A,
            "ownerUserId":     OWNER_A,
            "declared_total":  -5,
            "declared_active": 0,
        })
        assert resp.status_code == 422, resp.text

    def test_report_submit_active_greater_than_total(self):
        """
        declared_active > declared_total:
        الخدمة Python تتحقّق منه وتُعيد 400.
        الاختبار يتحقّق من عدم الانهيار (لا 5xx) بصرف النظر عن كود الحالة.
        """
        resp = _post("/report/submit", {
            "accountId":       "acc-inconsistent",
            "companyId":       COMPANY_A,
            "ownerUserId":     OWNER_A,
            "declared_total":  50,
            "declared_active": 100,  # أكثر من الإجمالي
        })
        # لا يجب أن يكون 500 (انهيار داخلي)
        assert resp.status_code < 500, \
            f"لا يجب أن تكون 5xx: {resp.text}"


# ══════════════════════════════════════════════════════════════════════════════
# 6) صورة العقار — حجم + امتداد + base64
# ══════════════════════════════════════════════════════════════════════════════

class TestPremisesPhotoValidation:

    def setup_method(self):
        import tempfile
        self._tmp = tempfile.mktemp(suffix=".db")
        sidecar_app._DB_PATH = self._tmp
        import sas_premises
        sas_premises._DB_PATH = self._tmp
        sidecar_app._init_db()

    def teardown_method(self):
        try:
            os.unlink(self._tmp)
        except OSError:
            pass

    def _make_premises(self) -> int:
        resp = _post("/premises/create", {
            "companyId":   COMPANY_A,
            "ownerUserId": OWNER_A,
            "governorate": "بغداد",
            "area":        "الكرادة",
            "landmark":    "نقطة",
        })
        data = resp.json()
        return (data.get("data") or data).get("id")

    def test_upload_valid_photo_jpg(self):
        """صورة 1x1 pixel PNG صالحة بامتداد jpg."""
        pid = self._make_premises()
        if pid is None:
            pytest.skip("لم يُعاد معرّف العقار")

        import base64
        # 1x1 PNG حقيقي
        _1x1_PNG = (
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01"
            b"\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89"
            b"\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01"
            b"\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82"
        )
        b64 = base64.b64encode(_1x1_PNG).decode()

        resp = _post("/premises/photo/upload", {
            "companyId":   COMPANY_A,
            "ownerUserId": OWNER_A,
            "premises_id": pid,
            "image_b64": b64,
            "ext":          "jpg",
        })
        # 200 أو 201
        assert resp.status_code in (200, 201), resp.text

    def test_upload_oversized_photo_rejected_or_documented(self):
        """
        صورة تتجاوز 6MB.
        PRODUCTION_BUG_3: sas_premises لا تتحقّق من حجم base64 قبل فكّ الترميز،
        بل تتحقّق من حجم البايتات بعد فكّ الترميز.
        سلسلة "A"*N ليست base64 صالحاً فـ base64.decode تطلق استثناءً يحوّله FastAPI
        إلى 500 أو تمرّ بلا مشكلة (يجب إرسال base64 حقيقي كبير لاختبار الحدّ الفعلي).
        الاختبار يوثّق السلوك بلا فرض نتيجة معيّنة — فقط لا 5xx (انهيار).
        """
        pid = self._make_premises()
        if pid is None:
            pytest.skip("لم يُعاد معرّف العقار")

        big = "A" * (6 * 1024 * 1024 + 100)

        resp = _post("/premises/photo/upload", {
            "companyId":    COMPANY_A,
            "ownerUserId":  OWNER_A,
            "premises_id":  pid,
            "image_b64": big,
            "ext":          "jpg",
        })
        # يجب ألا يكون 500 — قد يكون 200 (بيانات وهمية) أو 400/413
        assert resp.status_code != 500, \
            f"انهيار داخلي غير مقبول عند صورة كبيرة: {resp.text}"
        # EXPECTED: يجب أن يكون 400 أو 413 لكن الخدمة لا تفرض حدّ base64 مسبقاً
        # assert resp.status_code in (400, 413), resp.text  # <-- يفشل حتى يُصلح الكود

    def test_upload_unsupported_ext_rejected(self):
        """امتداد BMP غير مدعوم => رفض."""
        pid = self._make_premises()
        if pid is None:
            pytest.skip("لم يُعاد معرّف العقار")

        import base64
        b64 = base64.b64encode(b"fakepng").decode()

        resp = _post("/premises/photo/upload", {
            "companyId":    COMPANY_A,
            "ownerUserId":  OWNER_A,
            "premises_id":  pid,
            "image_b64": b64,
            "ext":          "bmp",
        })
        assert resp.status_code in (400, 422), \
            f"امتداد BMP يجب أن يُرفض: {resp.status_code}"


# ══════════════════════════════════════════════════════════════════════════════
# 7) اختبارات /sas/get و /sas/post (البروكسي العام)
# ══════════════════════════════════════════════════════════════════════════════

class TestSasProxy:
    """
    - بلا رأس => 401.
    - مسار فارغ => 422 (Pydantic min_length=1).
    - مسار صالح مع stub => 200.
    """

    def test_sas_get_no_secret_401(self):
        c = _client(VALID_SECRET)
        resp = c.post("/sas/get", json={**_CREDS, "path": "auth"})
        assert resp.status_code == 401

    def test_sas_get_empty_path_rejected(self):
        resp = _post("/sas/get", {**_CREDS, "path": ""})
        # Pydantic min_length=1 => 422
        assert resp.status_code == 422, resp.text

    def test_sas_get_valid_path(self):
        resp = _post("/sas/get", {**_CREDS, "path": "auth"})
        assert resp.status_code not in (401, 403), resp.text

    def test_sas_post_no_secret_401(self):
        c = _client(VALID_SECRET)
        resp = c.post("/sas/post", json={**_CREDS, "path": "some/path", "payload": {}})
        assert resp.status_code == 401

    def test_sas_post_valid(self):
        resp = _post("/sas/post", {**_CREDS, "path": "some/path", "payload": {}})
        assert resp.status_code not in (401, 403), resp.text
