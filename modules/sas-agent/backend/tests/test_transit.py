"""
اختبارات تكامل للترانزيت والبوابات الدولية.

تغطّي:
- اختبارات وحدة على طبقة الخدمة (transit.overview / diagnose / analyze)
- اختبارات تكامل عبر FastAPI TestClient
"""
import pytest
from app.services import transit


# ---------------------------------------------------------------------------
# اختبارات وحدة — transit.overview()
# ---------------------------------------------------------------------------

class TestTransitOverview:
    def test_returns_ten_gateways(self):
        """overview() بلا تصفية يُرجع 10 بوابات (مطابقة _GATEWAY_META)."""
        result = transit.overview()
        assert len(result["gateways"]) == 10

    def test_totals_keys_present(self):
        """حقل totals يحوي المفاتيح المطلوبة."""
        t = transit.overview()["totals"]
        required = {"gateways", "capacity_gbps", "traffic_gbps",
                    "utilization_pct", "avg_latency_ms", "countries"}
        assert required.issubset(t.keys())

    def test_totals_gateways_count(self):
        """totals.gateways == 10 (إجمالي البوابات)."""
        t = transit.overview()["totals"]
        assert t["gateways"] == 10

    def test_totals_capacity_positive(self):
        """السعة الإجمالية > 0 Gbps."""
        t = transit.overview()["totals"]
        assert t["capacity_gbps"] > 0

    def test_totals_traffic_positive(self):
        """حجم الحركة الإجمالي > 0 Gbps (بوابة واحدة على الأقل تعمل)."""
        t = transit.overview()["totals"]
        assert t["traffic_gbps"] > 0

    def test_totals_countries_count(self):
        """عدد الدول المميّزة > 1 (يوجد أكثر من دولة واحدة)."""
        t = transit.overview()["totals"]
        assert t["countries"] > 1

    def test_throughput_series_nonempty(self):
        """throughput_series ليست فارغة."""
        result = transit.overview()
        assert len(result["throughput_series"]) > 0

    def test_throughput_series_has_t_and_value(self):
        """كل نقطة في السلسلة الزمنية تملك مفتاحَي t و value."""
        series = transit.overview()["throughput_series"]
        for point in series:
            assert "t" in point and "value" in point

    def test_by_country_nonempty(self):
        """by_country غير فارغة ومجمّعة حسب الدولة."""
        bc = transit.overview()["by_country"]
        assert len(bc) > 0

    def test_by_country_has_country_key(self):
        """كل عنصر في by_country يملك مفتاح country."""
        for entry in transit.overview()["by_country"]:
            assert "country" in entry

    def test_deterministic_traffic_gbps(self):
        """نداءان متتاليان يعطيان نفس traffic_gbps (البيانات حتمية)."""
        a = transit.overview()["totals"]["traffic_gbps"]
        b = transit.overview()["totals"]["traffic_gbps"]
        assert a == b

    def test_scope_country_none_by_default(self):
        """scope.country == None عند الاستدعاء بلا تصفية."""
        assert transit.overview()["scope"]["country"] is None


# ---------------------------------------------------------------------------
# اختبارات وحدة — transit.overview(country=...)
# ---------------------------------------------------------------------------

class TestTransitOverviewFilter:
    def test_filter_turkey_returns_only_turkey(self):
        """overview(country='تركيا') يُرجع بوابات تركيا فقط."""
        result = transit.overview(country="تركيا")
        gateways = result["gateways"]
        assert len(gateways) > 0
        for g in gateways:
            assert g["country"] == "تركيا"

    def test_filter_turkey_scope_set(self):
        """scope.country يعكس الفلتر المُطبَّق."""
        result = transit.overview(country="تركيا")
        assert result["scope"]["country"] == "تركيا"

    def test_filter_turkey_totals_reflect_subset(self):
        """totals.gateways == عدد بوابات تركيا فعلياً."""
        result = transit.overview(country="تركيا")
        assert result["totals"]["gateways"] == len(result["gateways"])

    def test_filter_turkey_by_country_single(self):
        """by_country يحوي دولة واحدة عند التصفية بتركيا."""
        result = transit.overview(country="تركيا")
        assert len(result["by_country"]) == 1
        assert result["by_country"][0]["country"] == "تركيا"

    def test_filter_unknown_country_returns_empty(self):
        """تصفية بدولة غير موجودة تُرجع قائمة بوابات فارغة."""
        result = transit.overview(country="بلد_وهمي")
        assert result["gateways"] == []


# ---------------------------------------------------------------------------
# اختبارات وحدة — transit.diagnose()
# ---------------------------------------------------------------------------

class TestTransitDiagnose:
    def test_health_is_critical(self):
        """health == 'critical' لوجود بوابة سورية ساقطة (forced=down في _GATEWAY_META)."""
        result = transit.diagnose()
        assert result["health"] == "critical"

    def test_findings_contains_critical_for_down_gateway(self):
        """findings تحوي نتيجة severity==critical مصدرها البوابة الساقطة."""
        findings = transit.diagnose()["findings"]
        critical = [f for f in findings if f["severity"] == "critical"]
        assert len(critical) > 0
        # أقل نتيجة حرجة واحدة على الأقل يجب أن تشير لبوابة ساقطة
        assert any("ساقطة" in f["message"] for f in critical)

    def test_finding_has_required_keys(self):
        """كل نتيجة في findings تملك المفاتيح الأربعة المطلوبة."""
        findings = transit.diagnose()["findings"]
        assert len(findings) > 0
        for f in findings:
            assert {"severity", "source", "message", "action"}.issubset(f.keys())

    def test_findings_sorted_critical_first(self):
        """النتائج مرتّبة: critical قبل major قبل warning."""
        findings = transit.diagnose()["findings"]
        _order = {"critical": 0, "major": 1, "warning": 2, "minor": 3}
        ranks = [_order.get(f["severity"], 9) for f in findings]
        assert ranks == sorted(ranks)

    def test_gateways_have_health_field(self):
        """كل بوابة في نتيجة diagnose() تملك حقل health."""
        gateways = transit.diagnose()["gateways"]
        for g in gateways:
            assert "health" in g
            assert g["health"] in ("healthy", "degraded", "critical")

    def test_down_gateway_health_is_critical(self):
        """البوابة الساقطة (سوريا TR2) تُشخَّص بـ health==critical."""
        gateways = transit.diagnose()["gateways"]
        down = [g for g in gateways if g["status"] == "down"]
        assert len(down) > 0
        for g in down:
            assert g["health"] == "critical"

    def test_verdict_nonempty(self):
        """حقل verdict غير فارغ."""
        result = transit.diagnose()
        assert isinstance(result["verdict"], str) and len(result["verdict"]) > 5

    def test_filter_by_gateway_id(self):
        """التصفية بـ gateway_id يُرجع بوابة واحدة فقط."""
        result = transit.diagnose(gateway_id="GW-TR1")
        assert len(result["gateways"]) == 1
        assert result["gateways"][0]["id"] == "GW-TR1"

    def test_filter_by_country(self):
        """التصفية بـ country يُقيّد النتائج لتلك الدولة."""
        result = transit.diagnose(country="الكويت")
        for g in result["gateways"]:
            assert g["country"] == "الكويت"


# ---------------------------------------------------------------------------
# اختبارات وحدة — transit.analyze()
# ---------------------------------------------------------------------------

class TestTransitAnalyze:
    def test_works_without_api_key(self):
        """analyze() يُنتج ناتجاً بلا ANTHROPIC_API_KEY (مسار القواعد المحلية)."""
        result = transit.analyze()
        assert "source" in result
        assert result["source"] in ("rules", "claude")

    def test_local_rules_path_gives_rules_source(self, monkeypatch):
        """عند غياب عميل AI يُستخدم مسار القواعد المحلية — source == 'rules'."""
        # نجبر _get_client على إرجاع None لضمان المسار المحلي
        import app.services.ai_assistant as ai_mod
        monkeypatch.setattr(ai_mod, "_get_client", lambda: None)
        result = transit.analyze()
        assert result["source"] == "rules"

    def test_analysis_text_nonempty(self, monkeypatch):
        """نص التحليل غير فارغ (المسار المحلي)."""
        import app.services.ai_assistant as ai_mod
        monkeypatch.setattr(ai_mod, "_get_client", lambda: None)
        result = transit.analyze()
        assert isinstance(result["analysis"], str)
        assert len(result["analysis"]) > 30

    def test_totals_included_in_response(self, monkeypatch):
        """الاستجابة تحتوي على totals."""
        import app.services.ai_assistant as ai_mod
        monkeypatch.setattr(ai_mod, "_get_client", lambda: None)
        result = transit.analyze()
        assert "totals" in result

    def test_filter_by_country_propagates(self, monkeypatch):
        """analyze(country='تركيا') يُصفّي البيانات لتركيا (totals.gateways مقيّد)."""
        import app.services.ai_assistant as ai_mod
        monkeypatch.setattr(ai_mod, "_get_client", lambda: None)
        result_all = transit.analyze()
        result_tr = transit.analyze(country="تركيا")
        assert result_tr["totals"]["gateways"] < result_all["totals"]["gateways"]


# ---------------------------------------------------------------------------
# اختبارات تكامل — FastAPI TestClient
# ---------------------------------------------------------------------------

class TestTransitAPI:
    def test_get_overview_200(self, client):
        """GET /api/transit/overview يُرجع 200."""
        r = client.get("/api/transit/overview")
        assert r.status_code == 200

    def test_get_overview_has_gateways(self, client):
        """استجابة overview تحوي قائمة gateways."""
        r = client.get("/api/transit/overview")
        body = r.json()
        assert "gateways" in body
        assert len(body["gateways"]) == 10

    def test_get_overview_has_totals(self, client):
        """استجابة overview تحوي totals بالمفاتيح المطلوبة."""
        r = client.get("/api/transit/overview")
        t = r.json()["totals"]
        required = {"gateways", "capacity_gbps", "traffic_gbps",
                    "utilization_pct", "avg_latency_ms", "countries"}
        assert required.issubset(t.keys())

    def test_get_overview_filter_country(self, client):
        """overview?country=تركيا يُصفّي البوابات لتركيا."""
        r = client.get("/api/transit/overview", params={"country": "تركيا"})
        assert r.status_code == 200
        body = r.json()
        for g in body["gateways"]:
            assert g["country"] == "تركيا"

    def test_post_diagnose_200(self, client):
        """POST /api/transit/diagnose يُرجع 200."""
        r = client.post("/api/transit/diagnose")
        assert r.status_code == 200

    def test_post_diagnose_structure(self, client):
        """استجابة diagnose تحوي health و findings و gateways."""
        r = client.post("/api/transit/diagnose")
        body = r.json()
        assert "health" in body
        assert "findings" in body
        assert "gateways" in body

    def test_post_diagnose_health_critical(self, client):
        """health == 'critical' في استجابة diagnose (بوابة ساقطة موجودة)."""
        r = client.post("/api/transit/diagnose")
        assert r.json()["health"] == "critical"

    def test_post_diagnose_filter_gateway_id(self, client):
        """diagnose?gateway_id=GW-TR3 يُصفّي لبوابة واحدة."""
        r = client.post("/api/transit/diagnose", params={"gateway_id": "GW-TR3"})
        assert r.status_code == 200
        body = r.json()
        assert len(body["gateways"]) == 1

    def test_post_analyze_200(self, client):
        """POST /api/transit/analyze يُرجع 200."""
        r = client.post("/api/transit/analyze")
        assert r.status_code == 200

    def test_post_analyze_has_analysis_and_source(self, client):
        """استجابة analyze تحوي analysis و source."""
        r = client.post("/api/transit/analyze")
        body = r.json()
        assert "analysis" in body
        assert "source" in body
        assert body["source"] in ("rules", "claude")

    def test_post_analyze_analysis_nonempty(self, client):
        """نص analysis غير فارغ."""
        r = client.post("/api/transit/analyze")
        assert len(r.json()["analysis"]) > 10
