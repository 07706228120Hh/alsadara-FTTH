"""
اختبارات pytest لنقطة «ملخّص وكلاء الشركة» (البلنك الموحّد لإدارة الوكلاء):

    POST /admin/agents-summary
    body: { companyId, accountIds:[...] }
    → { items:[{account_id, declared_total, declared_active,
                actual_total, actual_active, diff, verdict, last_sync}] }

تُغطّي:
  1. fail-closed:
       - بلا رأس X-Internal-Secret => 401.
       - بلا سرّ مضبوط (سرّ فارغ) => 503.
       - سرّ خاطئ => 401.
  2. تحقّق المدخلات: accountIds فارغة => 422 (Pydantic min_length=1)؛
     accountIds كلّها فراغات => 400.
  3. العزل بالشركة: حسابات تحت company_id=A وحساب تحت company_id=B؛
     استدعاء الملخّص بـ companyId=A وقائمة تضمّ حسابات A و B
     => تعود حسابات A فقط، ولا يظهر حساب B إطلاقاً (لا تسريب).
  4. الحكم (يطابق _compute_verdict، threshold=max(5, 5% من actual)):
       - matched            : |declared - actual| ضمن العتبة.
       - company_suspicious : declared > actual بفارق كبير.
       - agent_suspicious   : declared < actual بفارق كبير.
  5. «لا سجلّات»: حساب بلا local_subscribers وبلا تصريح => لا يظهر إطلاقاً.
  6. حالة حدّية: حساب له تصريح لكن بلا مشتركين => actual=0، ويُدرَج.
  7. حساب مُزامَن بلا تصريح => verdict="no_report" و declared=None.

كل الاختبارات بلا خادم SAS حقيقي — النقطة تقرأ SQLite المحلية فقط.
تعيد استخدام نفس مضاعفات test_sas_extended (استيرادها يضبط الـ stubs في sys.modules).
"""
from __future__ import annotations

import os
import tempfile
from datetime import datetime, timezone
from typing import Dict, List, Optional

import pytest

# استيراد الوحدة الموسّعة أولاً — هي التي تضبط stubs الوحدات الخارجية في sys.modules
# وتستورد التطبيق (sidecar_app) و TestClient والمساعدات المشتركة.
from test_sas_extended import (  # noqa: E402
    sidecar_app,
    _client,
    _post,
    VALID_SECRET,
    COMPANY_A,
    COMPANY_B,
    OWNER_A,
    OWNER_B,
)

# نستورد _compute_verdict من التطبيق مباشرةً للمطابقة المرجعية للحكم.
from app import _compute_verdict  # noqa: E402


# ══════════════════════════════════════════════════════════════════════════════
# مساعدات: قاعدة مؤقتة + إدراج مباشر لمشتركين/تصاريح
# ══════════════════════════════════════════════════════════════════════════════

class _Base:
    """قاعدة SQLite مؤقتة لكل اختبار (معزولة)."""

    def setup_method(self):
        import sas_premises as _pm
        self._tmp = tempfile.mktemp(suffix=".db")
        sidecar_app._DB_PATH = self._tmp
        _pm._DB_PATH = self._tmp
        sidecar_app._init_db()

    def teardown_method(self):
        try:
            os.unlink(self._tmp)
        except OSError:
            pass

    # ── إدراج مشتركين محليين لحساب معيّن ضمن شركة ────────────────────────────
    def _insert_subscribers(
        self,
        account_id: str,
        company_id: str,
        total: int,
        active: int,
        owner: str = OWNER_A,
        synced_at: Optional[str] = None,
        sub_id_base: int = 0,
    ) -> None:
        """
        يدرج `total` مشتركاً للحساب، منهم `active` بحالة 'active' والباقي 'expired'.

        ملاحظة: المفتاح الأساسي (account_id, sub_id). عند إدراج مشتركين لنفس
        account_id عبر شركتَين في اختبار واحد، يجب اختلاف نطاقات sub_id
        (عبر sub_id_base) وإلا استبدلت صفوف الشركة الثانية صفوف الأولى
        (INSERT OR REPLACE) — وهذا أثر تصميم PK لا علاقة له بعزل الشركة.
        """
        synced_at = synced_at or datetime.now(timezone.utc).isoformat()
        with sidecar_app._db() as conn:
            for i in range(total):
                status = "active" if i < active else "expired"
                sub_id = sub_id_base + i
                conn.execute(
                    """
                    INSERT OR REPLACE INTO local_subscribers
                        (account_id, sub_id, username, name, profile, status, online,
                         enabled, expiration, phone, city, company_id, owner_user_id,
                         raw_json, synced_at)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                    """,
                    (account_id, sub_id, f"user{sub_id}", "اسم", "basic", status, 0,
                     1, "2027-01-01", "", "", company_id, owner, "{}", synced_at),
                )

    # ── إدراج تصريح (report) لحساب ─────────────────────────────────────────────
    def _insert_report(
        self,
        account_id: str,
        company_id: str,
        declared_total: int,
        declared_active: int,
        owner: str = OWNER_A,
        created_at: Optional[str] = None,
    ) -> None:
        created_at = created_at or datetime.now(timezone.utc).isoformat()
        with sidecar_app._db() as conn:
            conn.execute(
                """
                INSERT INTO agent_reports
                    (account_id, company_id, owner_user_id,
                     declared_total, declared_active, note, submitted_by, created_at)
                VALUES (?,?,?,?,?,?,?,?)
                """,
                (account_id, company_id, owner, declared_total, declared_active,
                 "", owner, created_at),
            )

    @staticmethod
    def _items_by_account(resp) -> Dict[str, dict]:
        data = resp.json()
        items = data.get("items", [])
        return {it["account_id"]: it for it in items}


# ══════════════════════════════════════════════════════════════════════════════
# 1) fail-closed
# ══════════════════════════════════════════════════════════════════════════════

class TestAgentsSummaryFailClosed(_Base):

    def test_no_secret_returns_401(self):
        c = _client(VALID_SECRET)
        resp = c.post("/admin/agents-summary",
                      json={"companyId": COMPANY_A, "accountIds": ["acc-1"]})
        assert resp.status_code == 401, resp.text

    def test_empty_secret_returns_503(self):
        c = _client("")  # سرّ فارغ => الخدمة غير مُهيّأة => 503
        resp = c.post("/admin/agents-summary",
                      json={"companyId": COMPANY_A, "accountIds": ["acc-1"]},
                      headers={"X-Internal-Secret": "anything"})
        assert resp.status_code == 503, resp.text

    def test_wrong_secret_returns_401(self):
        resp = _client(VALID_SECRET).post(
            "/admin/agents-summary",
            json={"companyId": COMPANY_A, "accountIds": ["acc-1"]},
            headers={"X-Internal-Secret": "WRONG"})
        assert resp.status_code == 401, resp.text


# ══════════════════════════════════════════════════════════════════════════════
# 2) تحقّق المدخلات
# ══════════════════════════════════════════════════════════════════════════════

class TestAgentsSummaryValidation(_Base):

    def test_empty_account_ids_returns_422(self):
        """accountIds=[] => Pydantic min_length=1 => 422."""
        resp = _post("/admin/agents-summary",
                     {"companyId": COMPANY_A, "accountIds": []})
        assert resp.status_code == 422, resp.text

    def test_missing_company_id_returns_422(self):
        resp = _post("/admin/agents-summary",
                     {"accountIds": ["acc-1"]})
        assert resp.status_code == 422, resp.text

    def test_all_blank_account_ids_returns_400(self):
        """accountIds كلّها فراغات => لا معرّفات صالحة => 400."""
        resp = _post("/admin/agents-summary",
                     {"companyId": COMPANY_A, "accountIds": ["", "   "]})
        assert resp.status_code == 400, resp.text


# ══════════════════════════════════════════════════════════════════════════════
# 3) العزل بالشركة — لا تسريب لحسابات شركة أخرى
# ══════════════════════════════════════════════════════════════════════════════

class TestAgentsSummaryCompanyIsolation(_Base):

    def test_company_a_only_no_leak_of_company_b(self):
        """
        حسابان (a1, a2) تحت الشركة A، وحساب (b1) تحت الشركة B.
        الاستعلام بـ companyId=A وقائمة [a1, a2, b1] => يعود a1 و a2 فقط،
        ولا يظهر b1 إطلاقاً (لا تسريب حتى لو طُلب صراحةً).
        """
        # الشركة A: حسابان لهما مشتركون + تصاريح
        self._insert_subscribers("a1", COMPANY_A, total=100, active=90, owner=OWNER_A)
        self._insert_report("a1", COMPANY_A, declared_total=100, declared_active=90, owner=OWNER_A)
        self._insert_subscribers("a2", COMPANY_A, total=50, active=40, owner=OWNER_A)
        self._insert_report("a2", COMPANY_A, declared_total=48, declared_active=38, owner=OWNER_A)

        # الشركة B: حساب له مشتركون + تصريح (يجب ألا يظهر مطلقاً)
        self._insert_subscribers("b1", COMPANY_B, total=200, active=180, owner=OWNER_B)
        self._insert_report("b1", COMPANY_B, declared_total=200, declared_active=180, owner=OWNER_B)

        resp = _post("/admin/agents-summary",
                     {"companyId": COMPANY_A, "accountIds": ["a1", "a2", "b1"]})
        assert resp.status_code == 200, resp.text

        by_acc = self._items_by_account(resp)
        assert "a1" in by_acc, "حساب A1 يجب أن يظهر"
        assert "a2" in by_acc, "حساب A2 يجب أن يظهر"
        assert "b1" not in by_acc, "حساب الشركة B لا يجب أن يظهر إطلاقاً (تسريب!)"

        # لا يظهر أي رقم من أرقام الشركة B (200/180) — تأكيد إضافي على العزل.
        for it in by_acc.values():
            assert it.get("actual_total") != 200, "تسرّبت أرقام الشركة B إلى النتائج"

    def test_company_b_data_not_counted_under_company_a_same_account_id(self):
        """
        حالة أشدّ: نفس account_id مُستعمَل في الشركتَين (تصادم اسمي).
        الاستعلام بـ companyId=A يجب أن يحسب مشتركي/تصاريح A فقط لذلك المعرّف.
        """
        shared = "shared-acc"
        # A: 10 مشتركين ، B: 999 مشتركاً بنفس المعرّف — بنطاقَي sub_id منفصلين
        # حتى تتعايش صفوف الشركتَين (المفتاح account_id+sub_id) ويُختبَر فلتر company_id فعلاً.
        self._insert_subscribers(shared, COMPANY_A, total=10, active=10, owner=OWNER_A, sub_id_base=0)
        self._insert_report(shared, COMPANY_A, declared_total=10, declared_active=10, owner=OWNER_A)
        self._insert_subscribers(shared, COMPANY_B, total=999, active=999, owner=OWNER_B, sub_id_base=1000)

        resp = _post("/admin/agents-summary",
                     {"companyId": COMPANY_A, "accountIds": [shared]})
        assert resp.status_code == 200, resp.text
        by_acc = self._items_by_account(resp)
        assert shared in by_acc
        assert by_acc[shared]["actual_total"] == 10, \
            f"يجب حساب مشتركي الشركة A فقط، وجد: {by_acc[shared]}"


# ══════════════════════════════════════════════════════════════════════════════
# 4) الحكم (verdict) — مطابقة _compute_verdict
# ══════════════════════════════════════════════════════════════════════════════

class TestAgentsSummaryVerdict(_Base):

    def test_matched_within_threshold(self):
        """
        actual=100 => threshold = max(5, 5) = 5.
        declared=103 => |diff|=3 <= 5 => matched.
        """
        assert _compute_verdict(103, 100) == "matched"  # مطابقة مرجعية

        self._insert_subscribers("acc-m", COMPANY_A, total=100, active=95)
        self._insert_report("acc-m", COMPANY_A, declared_total=103, declared_active=95)

        resp = _post("/admin/agents-summary",
                     {"companyId": COMPANY_A, "accountIds": ["acc-m"]})
        by_acc = self._items_by_account(resp)
        assert by_acc["acc-m"]["verdict"] == "matched", by_acc["acc-m"]
        assert by_acc["acc-m"]["diff"] == 3
        assert by_acc["acc-m"]["actual_total"] == 100
        assert by_acc["acc-m"]["declared_total"] == 103

    def test_company_suspicious_declared_much_higher(self):
        """
        actual=100 (threshold=5)، declared=200 => diff=+100 > 5 => company_suspicious.
        """
        assert _compute_verdict(200, 100) == "company_suspicious"

        self._insert_subscribers("acc-c", COMPANY_A, total=100, active=100)
        self._insert_report("acc-c", COMPANY_A, declared_total=200, declared_active=150)

        resp = _post("/admin/agents-summary",
                     {"companyId": COMPANY_A, "accountIds": ["acc-c"]})
        by_acc = self._items_by_account(resp)
        assert by_acc["acc-c"]["verdict"] == "company_suspicious", by_acc["acc-c"]
        assert by_acc["acc-c"]["diff"] == 100

    def test_agent_suspicious_declared_much_lower(self):
        """
        actual=100 (threshold=5)، declared=40 => diff=-60 خارج العتبة => agent_suspicious.
        """
        assert _compute_verdict(40, 100) == "agent_suspicious"

        self._insert_subscribers("acc-a", COMPANY_A, total=100, active=90)
        self._insert_report("acc-a", COMPANY_A, declared_total=40, declared_active=30)

        resp = _post("/admin/agents-summary",
                     {"companyId": COMPANY_A, "accountIds": ["acc-a"]})
        by_acc = self._items_by_account(resp)
        assert by_acc["acc-a"]["verdict"] == "agent_suspicious", by_acc["acc-a"]
        assert by_acc["acc-a"]["diff"] == -60

    def test_threshold_scales_with_five_percent(self):
        """
        actual=1000 => threshold = max(5, 50) = 50.
        declared=1040 => |diff|=40 <= 50 => matched (رغم فارق 40).
        """
        assert _compute_verdict(1040, 1000) == "matched"

        self._insert_subscribers("acc-big", COMPANY_A, total=1000, active=1000)
        self._insert_report("acc-big", COMPANY_A, declared_total=1040, declared_active=1000)

        resp = _post("/admin/agents-summary",
                     {"companyId": COMPANY_A, "accountIds": ["acc-big"]})
        by_acc = self._items_by_account(resp)
        assert by_acc["acc-big"]["verdict"] == "matched", by_acc["acc-big"]


# ══════════════════════════════════════════════════════════════════════════════
# 5) «لا سجلّات» + حالات حدّية للإدراج/الإسقاط
# ══════════════════════════════════════════════════════════════════════════════

class TestAgentsSummaryPresence(_Base):

    def test_account_with_no_records_does_not_appear(self):
        """
        حساب مطلوب لكن بلا مشتركين وبلا تصريح => لا يظهر إطلاقاً (يُسقَط).
        """
        # نُدرج حساباً واحداً حقيقياً (acc-real) وحساباً وهمياً (ghost) بلا سجلّات.
        self._insert_subscribers("acc-real", COMPANY_A, total=10, active=10)
        self._insert_report("acc-real", COMPANY_A, declared_total=10, declared_active=10)

        resp = _post("/admin/agents-summary",
                     {"companyId": COMPANY_A, "accountIds": ["acc-real", "ghost"]})
        assert resp.status_code == 200, resp.text
        by_acc = self._items_by_account(resp)
        assert "acc-real" in by_acc
        assert "ghost" not in by_acc, "حساب بلا أي سجلّات يجب ألا يظهر"

    def test_synced_account_without_report_is_no_report(self):
        """
        حساب مُزامَن (له مشتركون) لكن بلا تصريح => يظهر بـ verdict='no_report'
        و declared_total/active = None.
        """
        self._insert_subscribers("acc-nr", COMPANY_A, total=30, active=20)
        # لا تصريح

        resp = _post("/admin/agents-summary",
                     {"companyId": COMPANY_A, "accountIds": ["acc-nr"]})
        by_acc = self._items_by_account(resp)
        assert "acc-nr" in by_acc, "الحساب المُزامَن يجب أن يظهر"
        it = by_acc["acc-nr"]
        assert it["verdict"] == "no_report", it
        assert it["declared_total"] is None
        assert it["declared_active"] is None
        assert it["actual_total"] == 30
        assert it["actual_active"] == 20
        assert it["diff"] is None

    def test_latest_report_is_used(self):
        """
        عند وجود عدّة تصاريح لنفس الحساب => يُستخدم الأحدث (MAX created_at).
        """
        self._insert_subscribers("acc-lt", COMPANY_A, total=100, active=100)
        # تصريح قديم ثم أحدث
        self._insert_report("acc-lt", COMPANY_A, declared_total=10, declared_active=5,
                            created_at="2026-01-01T00:00:00+00:00")
        self._insert_report("acc-lt", COMPANY_A, declared_total=98, declared_active=95,
                            created_at="2026-06-01T00:00:00+00:00")

        resp = _post("/admin/agents-summary",
                     {"companyId": COMPANY_A, "accountIds": ["acc-lt"]})
        by_acc = self._items_by_account(resp)
        assert by_acc["acc-lt"]["declared_total"] == 98, \
            f"يجب استخدام أحدث تصريح: {by_acc['acc-lt']}"
        assert by_acc["acc-lt"]["verdict"] == "matched"  # |98-100|=2 <= 5


# ══════════════════════════════════════════════════════════════════════════════
# 6) شكل الاستجابة (contract)
# ══════════════════════════════════════════════════════════════════════════════

class TestAgentsSummaryContract(_Base):

    def test_item_has_all_contract_fields(self):
        self._insert_subscribers("acc-x", COMPANY_A, total=20, active=15)
        self._insert_report("acc-x", COMPANY_A, declared_total=20, declared_active=15)

        resp = _post("/admin/agents-summary",
                     {"companyId": COMPANY_A, "accountIds": ["acc-x"]})
        assert resp.status_code == 200, resp.text
        data = resp.json()
        assert "items" in data and isinstance(data["items"], list)
        it = data["items"][0]
        for field in (
            "account_id", "declared_total", "declared_active",
            "actual_total", "actual_active", "diff", "verdict", "last_sync",
        ):
            assert field in it, f"الحقل المفقود من العقد: {field} — {it}"

    def test_duplicate_account_ids_deduplicated(self):
        """معرّفات مكرّرة في الطلب => عنصر واحد فقط في الرد."""
        self._insert_subscribers("acc-d", COMPANY_A, total=10, active=10)
        self._insert_report("acc-d", COMPANY_A, declared_total=10, declared_active=10)

        resp = _post("/admin/agents-summary",
                     {"companyId": COMPANY_A, "accountIds": ["acc-d", "acc-d", "acc-d"]})
        by_acc = self._items_by_account(resp)
        # عنصر واحد فقط
        assert len(resp.json()["items"]) == 1, resp.json()
        assert "acc-d" in by_acc
