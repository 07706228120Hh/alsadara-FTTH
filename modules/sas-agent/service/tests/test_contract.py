"""
اختبار العقد الدائم (Contract Guard) — يتحقّق من قبول كل النماذج
للحمولات التي ترسلها البوّابة (.NET) بالضبط، وفق SasServiceClient.cs.

المبدأ: نُنشئ جسم الطلب كما تبنيه البوّابة (بنفس الأسماء والأنواع)
ونُؤكّد أن النموذج يُصادق عليه بلا ValidationError.
مع extra="forbid"، أي حقل غير معرَّف يُفشل الاختبار فوراً.

تغطية: كل نقطة في ISasServiceClient (login/dashboard/subscribers/report/
packages/finance/health/renewal/users-*/managers-*/sas-*/local/summary/
report-submit/reconciliation/tickets-*/premises-*/admin).
"""
from __future__ import annotations

import os
import sys
import types
from typing import Any

import pytest
from pydantic import ValidationError

# ── ضبط sys.path ─────────────────────────────────────────────────────────────
_TESTS_DIR   = os.path.dirname(__file__)
_SERVICE_DIR = os.path.dirname(_TESTS_DIR)
_BACKEND_APP = os.path.normpath(os.path.join(_SERVICE_DIR, "..", "backend", "app"))

for _p in (_SERVICE_DIR, _BACKEND_APP):
    if _p not in sys.path:
        sys.path.insert(0, _p)

# ── Stubs للوحدات الخارجية (قبل استيراد app) ──────────────────────────────────
def _ensure_stubs() -> None:
    sys.modules.setdefault("integrations", types.ModuleType("integrations"))

    _sas_mod = types.ModuleType("integrations.sas_client")
    _sas_mod.SASClient = object  # type: ignore[attr-defined]

    class _FakeSASError(RuntimeError):
        pass

    _sas_mod.SASError = _FakeSASError  # type: ignore[attr-defined]
    sys.modules["integrations.sas_client"] = _sas_mod

    _usr_mod = types.ModuleType("integrations.sas_user_client")
    _usr_mod.SASUserClient = object  # type: ignore[attr-defined]
    sys.modules["integrations.sas_user_client"] = _usr_mod

_ensure_stubs()

# ── استيراد النماذج ───────────────────────────────────────────────────────────
import app as sidecar  # noqa: E402
import sas_premises as prem  # noqa: E402

# ── حمولات مشتركة (تعكس القيم الفعلية التي ترسلها البوّابة) ─────────────────
_CREDS = {
    "serverUrl": "http://10.0.0.1:8080",
    "username":  "agent_user",
    "password":  "s3cr3t!",
}
_LOCAL_BASE = {
    "accountId":   "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
    "companyId":   "comp-001",
    "ownerUserId": "user-abc",
}
_TK_BASE = {
    "companyId":   "comp-001",
    "ownerUserId": "user-abc",
}
_PREM_BASE = {
    "companyId":   "comp-001",
    "ownerUserId": "user-abc",
}


def _ok(model_cls, data: dict) -> None:
    """يُؤكّد أن النموذج يقبل البيانات بلا ValidationError."""
    try:
        model_cls(**data)
    except ValidationError as exc:
        pytest.fail(
            f"{model_cls.__name__} رفض حمولة البوّابة:\n{exc}\n\nالبيانات: {data}"
        )


# ══════════════════════════════════════════════════════════════════════════════
# 1) نقاط البروكسي الأصلية (SAS proxy — تحتاج credentials)
# ══════════════════════════════════════════════════════════════════════════════

class TestCredentialEndpointsContract:
    """كل النقاط التي تمرّر credentials في الجسم."""

    def test_login(self):
        """POST /login — { serverUrl, username, password }"""
        _ok(sidecar.LoginRequest, _CREDS)

    def test_dashboard(self):
        """POST /dashboard — { serverUrl, username, password, query:{} }"""
        _ok(sidecar.DashboardRequest, {**_CREDS, "query": {}})

    def test_dashboard_no_query(self):
        """POST /dashboard — بلا query (اختياري)"""
        _ok(sidecar.DashboardRequest, _CREDS)

    def test_subscribers(self):
        """POST /subscribers — { serverUrl, username, password, query:{} }"""
        _ok(sidecar.SubscribersRequest, {
            **_CREDS,
            "query": {"page": "1", "count": "50", "search": None},
        })

    def test_subscribers_empty_query(self):
        _ok(sidecar.SubscribersRequest, {**_CREDS, "query": {}})

    def test_report(self):
        """POST /report — { serverUrl, username, password, query:{} }"""
        _ok(sidecar.ReportRequest, {
            **_CREDS,
            "query": {"page": "1", "count": "100"},
        })

    def test_packages(self):
        """POST /packages — { serverUrl, username, password, query:{} }"""
        _ok(sidecar.PackagesRequest, {**_CREDS, "query": {}})

    def test_packages_no_query(self):
        _ok(sidecar.PackagesRequest, _CREDS)

    def test_finance(self):
        """POST /finance — { serverUrl, username, password, query:{} }"""
        _ok(sidecar.FinanceRequest, {**_CREDS, "query": {}})

    def test_finance_no_query(self):
        _ok(sidecar.FinanceRequest, _CREDS)

    def test_system_health(self):
        """POST /system-health — { serverUrl, username, password, query:{} }"""
        _ok(sidecar.SystemHealthRequest, {**_CREDS, "query": {}})

    def test_system_health_no_query(self):
        _ok(sidecar.SystemHealthRequest, _CREDS)

    def test_renewal_candidates_no_query(self):
        """POST /renewal/candidates — { serverUrl, username, password, days, query:null }"""
        _ok(sidecar.RenewalCandidatesRequest, {**_CREDS, "days": 7})

    def test_renewal_candidates_query_string(self):
        """البوّابة قد ترسل query كسلسلة نصية — يجب أن يُقبَل"""
        _ok(sidecar.RenewalCandidatesRequest, {**_CREDS, "days": 7, "query": "some-filter"})

    def test_renewal_candidates_query_null(self):
        """null صريح — يُقبَل"""
        _ok(sidecar.RenewalCandidatesRequest, {**_CREDS, "days": None, "query": None})

    def test_renewal_candidates_query_dict(self):
        """query كقاموس — يُقبَل"""
        _ok(sidecar.RenewalCandidatesRequest, {**_CREDS, "days": 30, "query": {"filter": "x"}})

    def test_renewal_bulk(self):
        """POST /renewal/bulk — subscriberIds كـ string[] من البوّابة"""
        _ok(sidecar.RenewalBulkRequest, {
            **_CREDS,
            "subscriberIds": ["101", "202", "303"],  # البوّابة ترسل strings
            "months": 1,
            "profileId": None,
            "dryRun": False,
        })

    def test_renewal_bulk_int_ids(self):
        """subscriberIds كـ int[] — يُقبَل أيضاً"""
        _ok(sidecar.RenewalBulkRequest, {
            **_CREDS,
            "subscriberIds": [1, 2, 3],
            "months": 3,
            "dryRun": True,
        })


# ══════════════════════════════════════════════════════════════════════════════
# 2) نقاط المشتركين (users-*)
# ══════════════════════════════════════════════════════════════════════════════

class TestUsersContract:
    """uid يُرسَل كنص من البوّابة (C# string uid)."""

    def test_user_detail(self):
        _ok(sidecar.UserDetailRequest, {**_CREDS, "uid": "1234"})

    def test_user_detail_int_uid(self):
        _ok(sidecar.UserDetailRequest, {**_CREDS, "uid": 1234})

    def test_user_overview(self):
        _ok(sidecar.UserOverviewRequest, {**_CREDS, "uid": "5678"})

    def test_user_history(self):
        _ok(sidecar.UserHistoryRequest, {**_CREDS, "uid": "99"})

    def test_user_extend_data(self):
        _ok(sidecar.UserExtendDataRequest, {**_CREDS, "uid": "42"})

    def test_user_action_activate(self):
        _ok(sidecar.UserActionRequest, {
            **_CREDS, "uid": "7", "action": "activate", "payload": {}
        })

    def test_user_bulk_action(self):
        """user_ids كـ string[] من البوّابة"""
        _ok(sidecar.UserBulkActionRequest, {
            **_CREDS,
            "user_ids": ["1", "2", "3"],
            "action": "activate",
            "payload": {},
        })

    def test_user_create(self):
        _ok(sidecar.UserCreateRequest, {
            **_CREDS,
            "payload": {"username": "newuser", "password": "pass123"},
        })

    def test_user_update(self):
        _ok(sidecar.UserUpdateRequest, {
            **_CREDS, "uid": "55", "changes": {"phone": "07701234567"}
        })

    def test_user_delete(self):
        _ok(sidecar.UserDeleteRequest, {**_CREDS, "uid": "88"})

    def test_user_refund_data(self):
        _ok(sidecar.UserRefundDataRequest, {**_CREDS, "uid": "11"})

    def test_user_refund(self):
        _ok(sidecar.UserRefundRequest, {**_CREDS, "uid": "22"})


# ══════════════════════════════════════════════════════════════════════════════
# 3) نقاط الوكلاء/المدراء (managers-*)
# ══════════════════════════════════════════════════════════════════════════════

class TestManagersContract:
    """mid يُرسَل كنص من البوّابة."""

    def test_managers_no_query(self):
        """POST /managers — { serverUrl, username, password } بلا query"""
        _ok(sidecar.ManagersRequest, _CREDS)

    def test_managers_action(self):
        _ok(sidecar.ManagerActionRequest, {
            **_CREDS, "mid": "77", "action": "deposit", "payload": {"amount": 100}
        })

    def test_manager_delete(self):
        _ok(sidecar.ManagerDeleteRequest, {**_CREDS, "mid": "33"})


# ══════════════════════════════════════════════════════════════════════════════
# 4) البروكسي العام (sas-*)
# ══════════════════════════════════════════════════════════════════════════════

class TestSasProxyContract:

    def test_sas_get(self):
        _ok(sidecar.SasGetRequest, {**_CREDS, "path": "auth"})

    def test_sas_post(self):
        _ok(sidecar.SasPostRequest, {**_CREDS, "path": "some/path", "payload": {"k": "v"}})

    def test_sas_post_no_payload(self):
        _ok(sidecar.SasPostRequest, {**_CREDS, "path": "report/depodrawal"})


# ══════════════════════════════════════════════════════════════════════════════
# 5) نقاط التخزين المحلي (local/summary/sync/account-test)
# ══════════════════════════════════════════════════════════════════════════════

class TestLocalStorageContract:

    def test_account_test_no_account_id(self):
        """POST /account/test — البوّابة لا ترسل accountId"""
        _ok(sidecar.AccountTestRequest, _CREDS)

    def test_account_test_with_account_id(self):
        """POST /account/test — مع accountId اختياري"""
        _ok(sidecar.AccountTestRequest, {**_CREDS, "accountId": "some-guid"})

    def test_sync(self):
        """POST /sync — { serverUrl, username, password, accountId }"""
        _ok(sidecar.SyncRequest, {**_CREDS, "accountId": "acc-guid"})

    def test_sync_with_optional_fields(self):
        _ok(sidecar.SyncRequest, {
            **_CREDS,
            "accountId": "acc-guid",
            "companyId": "comp-1",
            "ownerUserId": "usr-1",
        })

    def test_local_subscribers_minimal(self):
        """POST /subscribers/local — { accountId } فقط"""
        _ok(sidecar.LocalSubscribersRequest, {"accountId": "acc-1"})

    def test_local_subscribers_full(self):
        _ok(sidecar.LocalSubscribersRequest, {
            "accountId":   "acc-1",
            "search":      "جان",
            "status":      "active",
            "expiring":    "soon7",
            "page":        2,
            "count":       100,
        })

    def test_local_subscribers_null_fields(self):
        """البوّابة ترسل null لحقول اختيارية (WhenWritingNull)"""
        _ok(sidecar.LocalSubscribersRequest, {
            "accountId": "acc-1",
            "search": None,
            "status": None,
            "expiring": None,
            "page": None,
            "count": None,
        })

    def test_subscriber_summary(self):
        """POST /subscribers/summary — { accountId }"""
        _ok(sidecar.SubscriberSummaryRequest, {"accountId": "acc-2"})

    def test_report_submit_minimal(self):
        """POST /report/submit — { accountId, companyId, ownerUserId, declared_total, declared_active }"""
        _ok(sidecar.ReportSubmitRequest, {
            "accountId":       "acc-1",
            "companyId":       "comp-1",
            "ownerUserId":     "usr-1",
            "declared_total":  500,
            "declared_active": 400,
        })

    def test_report_submit_full(self):
        _ok(sidecar.ReportSubmitRequest, {
            "accountId":       "acc-1",
            "companyId":       "comp-1",
            "ownerUserId":     "usr-1",
            "declared_total":  500,
            "declared_active": 400,
            "note":            "ملاحظة",
            "submitted_by":    "admin",
        })

    def test_report_list(self):
        """POST /report/list — { accountId }"""
        _ok(sidecar.ReportListRequest, {"accountId": "acc-1"})

    def test_reconciliation_with_creds(self):
        """POST /reconciliation — { accountId, serverUrl, username, password }"""
        _ok(sidecar.ReconciliationRequest, {
            "accountId": "acc-1",
            "serverUrl": "http://sas.local",
            "username":  "agent",
            "password":  "pass",
        })

    def test_reconciliation_no_creds(self):
        """POST /reconciliation — بلا creds (يستخدم العدّ المحلي)"""
        _ok(sidecar.ReconciliationRequest, {"accountId": "acc-1"})


# ══════════════════════════════════════════════════════════════════════════════
# 6) نقاط التذاكر (tickets-*)
# ══════════════════════════════════════════════════════════════════════════════

class TestTicketsContract:
    """ticket_id يُرسَل كنص من البوّابة (C# string ticketId)."""

    def test_tickets_stats(self):
        """POST /tickets/stats — { companyId, ownerUserId }"""
        _ok(sidecar.TicketStatsRequest, _TK_BASE)

    def test_tickets_list_minimal(self):
        _ok(sidecar.TicketListRequest, _TK_BASE)

    def test_tickets_list_full(self):
        _ok(sidecar.TicketListRequest, {
            **_TK_BASE,
            "status":   "open",
            "category": "billing",
            "search":   "مشكلة",
            "page":     1,
            "count":    50,
        })

    def test_tickets_list_null_string_optionals(self):
        """البوّابة تُسقط null بـ WhenWritingNull — str? يُرسَل null لكن int? يُسقَط"""
        # status/category/search هي Optional[str] → null مقبول
        # page/count هي int? → WhenWritingNull تُسقطها (لا تُرسَل null)
        _ok(sidecar.TicketListRequest, {
            **_TK_BASE,
            "status": None, "category": None, "search": None,
            # page و count غائبتان (مُسقَطتان بـ WhenWritingNull من .NET)
        })

    def test_tickets_get(self):
        """ticket_id كنص"""
        _ok(sidecar.TicketGetRequest, {**_TK_BASE, "ticket_id": "42"})

    def test_tickets_get_int(self):
        _ok(sidecar.TicketGetRequest, {**_TK_BASE, "ticket_id": 42})

    def test_tickets_create_minimal(self):
        _ok(sidecar.TicketCreateRequest, {
            **_TK_BASE,
            "subject": "مشكلة الشبكة",
            "body":    "الإنترنت لا يعمل",
        })

    def test_tickets_create_full(self):
        _ok(sidecar.TicketCreateRequest, {
            **_TK_BASE,
            "subject":        "مشكلة",
            "body":           "وصف",
            "category":       "outage",
            "priority":       "high",
            "subscriber_ref": "user123",
            "created_by":     "staff-user",
        })

    def test_tickets_reply(self):
        # is_internal هو bool? في C# — WhenWritingNull تُسقطه إن null
        _ok(sidecar.TicketReplyRequest, {
            **_TK_BASE,
            "ticket_id": "10",
            "body":      "شكراً، تمّت المعالجة",
            # is_internal غائب (مُسقَط بـ WhenWritingNull)
            "author":     "support",
        })

    def test_tickets_update(self):
        _ok(sidecar.TicketUpdateRequest, {
            **_TK_BASE,
            "ticket_id": "5",
            "status":    "resolved",
            "priority":  None,
            "category":  None,
        })


# ══════════════════════════════════════════════════════════════════════════════
# 7) نقاط العقارات (premises-*)
# ══════════════════════════════════════════════════════════════════════════════

class TestPremisesContract:
    """premises_id يُرسَل كنص من البوّابة."""

    def test_premises_list_minimal(self):
        _ok(prem.PremListRequest, _PREM_BASE)

    def test_premises_list_full(self):
        _ok(prem.PremListRequest, {
            **_PREM_BASE,
            "search":    "بغداد",
            "ownership": "owned",
            "ptype":     "residential",
            "page":      1,
            "count":     50,
        })

    def test_premises_list_null_string_optionals(self):
        # search/ownership/ptype هي Optional[str] → null مقبول
        # page/count هي int? → WhenWritingNull تُسقطها
        _ok(prem.PremListRequest, {
            **_PREM_BASE,
            "search": None, "ownership": None, "ptype": None,
            # page و count غائبتان (مُسقَطتان)
        })

    def test_premises_create_minimal(self):
        """POST /premises/create بلا created_by"""
        _ok(prem.PremCreateRequest, {
            **_PREM_BASE,
            "governorate": "بغداد",
            "area":        "الكرادة",
            "landmark":    "بجانب الجامعة",
        })

    def test_premises_create_with_created_by(self):
        """POST /premises/create مع created_by من البوّابة"""
        _ok(prem.PremCreateRequest, {
            **_PREM_BASE,
            "governorate": "البصرة",
            "area":        "الجبيلة",
            "landmark":    "",
            "lat":         30.5,
            "lon":         47.8,
            "phone":       "07701234567",
            "ownership":   "rent",
            "ptype":       "commercial",
            "created_by":  "staff-user-id",
        })

    def test_premises_create_null_geo_and_created_by(self):
        """WhenWritingNull تُسقط double? و string? عند null — فالحقول ببساطة غائبة"""
        # lat/lon هي double? → WhenWritingNull تُسقطها إن null
        # phone/ownership/ptype هي string? → تُسقَط أيضاً
        # ما يُرسَل فعلاً: governorate + area + landmark فقط
        _ok(prem.PremCreateRequest, {
            **_PREM_BASE,
            "governorate": "نينوى",
            "area":        "الموصل الجديدة",
            "landmark":    "قرب المستشفى",
            # بقية الحقول مُسقَطة بـ WhenWritingNull
        })

    def test_premises_get(self):
        """premises_id كنص"""
        _ok(prem.PremGetRequest, {**_PREM_BASE, "premises_id": "15"})

    def test_premises_get_int(self):
        _ok(prem.PremGetRequest, {**_PREM_BASE, "premises_id": 15})

    def test_premises_update(self):
        _ok(prem.PremUpdateRequest, {
            **_PREM_BASE,
            "premises_id": "7",
            "governorate": "أربيل",
            "area":        "عنكاوا",
        })

    def test_premises_delete(self):
        _ok(prem.PremDeleteRequest, {**_PREM_BASE, "premises_id": "3"})

    def test_premises_photo_upload(self):
        import base64
        b64 = base64.b64encode(b"fake-image-data").decode()
        _ok(prem.PremPhotoUploadRequest, {
            **_PREM_BASE,
            "premises_id": "9",
            "image_b64":   b64,
            "ext":         "jpg",
        })

    def test_premises_photo_get(self):
        _ok(prem.PremPhotoGetRequest, {**_PREM_BASE, "premises_id": "9"})

    def test_premises_link(self):
        _ok(prem.PremLinkRequest, {
            **_PREM_BASE,
            "premises_id":    "4",
            "subscriber_ref": "user-ref-001",
        })

    def test_premises_unlink(self):
        _ok(prem.PremUnlinkRequest, {
            **_PREM_BASE,
            "premises_id":    "4",
            "subscriber_ref": "user-ref-001",
        })

    def test_premises_subscribers(self):
        _ok(prem.PremSubscribersRequest, {**_PREM_BASE, "premises_id": "4"})

    def test_premises_by_subscriber(self):
        _ok(prem.PremBySubscriberRequest, {
            **_PREM_BASE,
            "subscriber_ref": "sub-abc",
        })

    def test_premises_link_candidates_minimal(self):
        _ok(prem.PremLinkCandidatesRequest, _PREM_BASE)

    def test_premises_link_candidates_with_search(self):
        _ok(prem.PremLinkCandidatesRequest, {**_PREM_BASE, "search": "محمد", "limit": 20})


# ══════════════════════════════════════════════════════════════════════════════
# 8) نقطة الأدمن (admin)
# ══════════════════════════════════════════════════════════════════════════════

class TestAdminContract:

    def test_agents_summary(self):
        """POST /admin/agents-summary — { companyId, accountIds:[...] }"""
        _ok(sidecar.AgentsSummaryRequest, {
            "companyId":  "comp-001",
            "accountIds": [
                "aaaaaaaa-1111-2222-3333-444444444444",
                "bbbbbbbb-5555-6666-7777-888888888888",
            ],
        })

    def test_agents_summary_single_account(self):
        _ok(sidecar.AgentsSummaryRequest, {
            "companyId":  "comp-x",
            "accountIds": ["single-account-id"],
        })


# ══════════════════════════════════════════════════════════════════════════════
# 9) تحقّق extra="forbid" — أي حقل زائد يُفشل النموذج
# ══════════════════════════════════════════════════════════════════════════════

class TestExtraForbid:
    """يتأكّد أن extra="forbid" فعّال فعلاً."""

    def test_extra_field_in_creds_rejected(self):
        with pytest.raises(ValidationError) as exc_info:
            sidecar.LoginRequest(**_CREDS, unknownField="value")
        assert "extra_forbidden" in str(exc_info.value) or "Extra" in str(exc_info.value) or "unexpected" in str(exc_info.value).lower()

    def test_extra_field_in_local_base_rejected(self):
        with pytest.raises(ValidationError):
            sidecar.SubscriberSummaryRequest(
                accountId="acc-1",
                unknownExtra="should-fail",
            )

    def test_extra_field_in_tk_base_rejected(self):
        with pytest.raises(ValidationError):
            sidecar.TicketStatsRequest(
                companyId="c",
                ownerUserId="u",
                sneakyField="bad",
            )

    def test_extra_field_in_prem_base_rejected(self):
        with pytest.raises(ValidationError):
            prem.PremListRequest(
                companyId="c",
                ownerUserId="u",
                intruder="data",
            )
