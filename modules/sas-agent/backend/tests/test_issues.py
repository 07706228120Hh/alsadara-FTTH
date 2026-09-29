"""اختبارات مشاكل الشركات ومستوى الخدمة (SLA) — التصنيف والتجميع والتقرير والتحليل."""
from app.services import issues


def test_overview_totals():
    o = issues.overview()
    t = o["totals"]
    assert t["total"] > 0
    # الحالات الثلاث تُغطّي كل البلاغات
    assert t["on_time"] + t["breached"] + t["in_progress"] == t["total"]
    assert 0 <= t["sla_compliance_pct"] <= 100
    assert t["avg_resolution_hours"] >= 0
    assert len(o["by_company"]) == 5
    assert set(o["status_labels"]) == {"on_time", "breached", "in_progress"}


def test_status_classification_rules():
    """التحقّق من منطق التصنيف: SLA و resolution_hours و opened_hours_ago."""
    for it in issues._ISSUES:
        sla = it["sla_hours"]
        rh = it["resolution_hours"]
        if rh is not None:
            # محلول: on_time إن ضمن المهلة، breached إن تجاوزها
            assert it["status"] == ("on_time" if rh <= sla else "breached")
        else:
            # مفتوح: breached إن تجاوز المهلة، وإلا in_progress
            assert it["status"] == (
                "breached" if it["opened_hours_ago"] > sla else "in_progress")


def test_deterministic():
    a = issues.overview()["totals"]
    b = issues.overview()["totals"]
    assert a == b  # بيانات ثابتة بين الطلبات


def test_filter_by_company():
    o = issues.overview(company="إيرثلنك")
    assert o["totals"]["companies"] == 1
    assert len(o["by_company"]) == 1
    assert o["by_company"][0]["name"] == "إيرثلنك"


def test_filter_by_governorate():
    o = issues.overview(governorate="بغداد")
    assert o["totals"]["governorates"] == 1
    assert all(i["governorate"] == "بغداد" for i in o["recent"])


def test_sla_compliance_math():
    o = issues.overview()
    for c in o["by_company"]:
        decided = c["on_time"] + c["breached"]
        expected = round(c["on_time"] / decided * 100, 1) if decided else 100.0
        assert c["sla_compliance_pct"] == expected


def test_trend_series():
    o = issues.overview()
    tr = o["trend"]
    assert len(tr) == 14
    assert all("opened" in d and "resolved" in d for d in tr)
    assert tr[-1]["day"] == "اليوم"


def test_distributions():
    o = issues.overview()
    assert sum(x["count"] for x in o["by_type"]) == o["totals"]["total"]
    assert sum(x["count"] for x in o["by_severity"]) == o["totals"]["total"]
    # مرتّبة تنازلياً
    counts = [x["count"] for x in o["by_type"]]
    assert counts == sorted(counts, reverse=True)


def test_report_markdown():
    r = issues.report(company="هلا")
    assert "markdown" in r and isinstance(r["markdown"], str)
    assert "SLA" in r["markdown"] or "الالتزام" in r["markdown"]
    assert "هلا" in r["title"]


def test_analyze_rules():
    r = issues.analyze()
    assert r["source"] in ("rules", "claude")
    assert isinstance(r["analysis"], str) and len(r["analysis"]) > 30


def test_analyze_structured():
    """التحليل يُرجع بنية غنية: تفصيل لكل شركة + أبرز النقاط + قراءة مُهيكلة."""
    r = issues.analyze()
    assert {"companies", "highlights", "insights", "recommendations",
            "totals", "headline"}.issubset(r.keys())
    # تفصيل لكل شركة (٦ شركات) بتقييم وترتيب وقراءة تلقائية
    assert len(r["companies"]) == 5
    ranks = sorted(c["rank"] for c in r["companies"])
    assert ranks == list(range(1, 6))
    for c in r["companies"]:
        assert c["grade_key"] in ("excellent", "good", "poor")
        assert isinstance(c["note"], str) and c["note"]
    # أبرز النقاط
    h = r["highlights"]
    assert set(h.keys()) == {"worst_company", "best_company",
                             "worst_governorate", "top_type"}
    # القراءة المُهيكلة
    assert isinstance(r["insights"], list) and len(r["insights"]) >= 2
    assert isinstance(r["recommendations"], list)


def test_analyze_structured_filtered():
    """التصفية بشركة تُبقي شركة واحدة في التفصيل مع بنية سليمة."""
    r = issues.analyze(company="هلا")
    assert len(r["companies"]) == 1
    assert r["companies"][0]["name"] == "هلا"
    assert r["companies"][0]["grade_key"] in ("excellent", "good", "poor")


def test_api_overview_report_analyze(client):
    r = client.get("/api/issues/overview")
    assert r.status_code == 200
    assert r.json()["totals"]["total"] > 0

    r2 = client.get("/api/issues/overview?company=الجزيرة")
    assert r2.status_code == 200
    assert r2.json()["totals"]["companies"] == 1

    r3 = client.get("/api/issues/report?governorate=البصرة")
    assert r3.status_code == 200
    assert "markdown" in r3.json()

    r4 = client.post("/api/issues/analyze")
    assert r4.status_code == 200
    assert "analysis" in r4.json()
