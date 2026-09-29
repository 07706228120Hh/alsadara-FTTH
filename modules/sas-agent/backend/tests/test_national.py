"""اختبارات اللوحة الوطنية — التجميع والتصفية والتحليل."""
from app.services import national


def test_overview_totals():
    o = national.overview()
    t = o["totals"]
    assert t["governorates"] == 15
    assert t["companies"] == 5
    assert t["devices"] > 100
    assert t["subscribers"] > 0
    assert t["throughput_gbps"] > 0
    assert len(o["by_governorate"]) == 15
    assert len(o["by_company"]) == 5
    # المحافظات الشمالية محذوفة والشركات المطلوبة مضافة
    gov_names = {g["name"] for g in o["by_governorate"]}
    assert gov_names.isdisjoint({"أربيل", "السليمانية", "دهوك"})
    comp_names = {c["name"] for c in o["by_company"]}
    assert {"الجزيرة", "سوبر سيل"}.issubset(comp_names)
    assert comp_names.isdisjoint({"آسياسيل", "زين العراق", "كورك تيليكوم"})
    # الترتيب تنازلي حسب الحمل
    thr = [g["throughput_gbps"] for g in o["by_governorate"]]
    assert thr == sorted(thr, reverse=True)


def test_access_type_classification():
    o = national.overview()
    types = {x["type"]: x for x in o["by_access_type"]}
    assert set(types) == {"ftth", "wireless"}
    # إيرثلنك تجهّز FTTH فقط، هلا وايرليس فقط
    assert "إيرثلنك" in types["ftth"]["companies"]
    assert "إيرثلنك" not in types["wireless"]["companies"]
    assert "هلا" in types["wireless"]["companies"]
    assert "هلا" not in types["ftth"]["companies"]
    # المجموع عبر الأنواع = إجمالي المشتركين
    assert sum(x["subscribers"] for x in o["by_access_type"]) == o["totals"]["subscribers"]


def test_throughput_series():
    o = national.overview()
    s = o["throughput_series"]
    assert len(s) == 64
    assert all("t" in p and "value" in p for p in s)
    # آخر نقطة تساوي الحمل الحالي
    assert abs(s[-1]["value"] - o["totals"]["throughput_gbps"]) < 0.2
    assert isinstance(o["throughput_change_pct"], (int, float))


def test_deterministic():
    a = national.overview()["totals"]
    b = national.overview()["totals"]
    assert a == b  # بيانات ثابتة بين الطلبات


def test_filter_by_governorate():
    o = national.overview(governorate="بغداد")
    assert o["totals"]["governorates"] == 1
    assert all(d["governorate"] == "بغداد" for d in o["devices"])


def test_filter_by_company():
    o = national.overview(company="إيرثلنك")
    assert o["totals"]["companies"] == 1
    assert all(d["company"] == "إيرثلنك" for d in o["devices"])


def test_analyze_rules():
    r = national.analyze()
    assert r["source"] in ("rules", "claude")
    assert isinstance(r["analysis"], str) and len(r["analysis"]) > 30


def test_api_overview_and_analyze(client):
    r = client.get("/api/national/overview")
    assert r.status_code == 200
    assert r.json()["totals"]["governorates"] == 15

    r2 = client.get("/api/national/overview?governorate=البصرة")
    assert r2.status_code == 200
    assert r2.json()["totals"]["governorates"] == 1

    r3 = client.post("/api/national/analyze")
    assert r3.status_code == 200
    assert "analysis" in r3.json()
