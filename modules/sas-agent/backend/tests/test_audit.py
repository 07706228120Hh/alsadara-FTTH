"""اختبارات التدقيق — مطابقة أعداد الوكلاء مقابل الشركات والأحكام."""
from app.services import audit


def test_overview_structure():
    o = audit.overview()
    t = o["totals"]
    assert t["agents"] > 0
    # الأحكام الثلاثة تُغطّي كل الوكلاء
    assert t["matched"] + t["company_suspicious"] + t["agent_suspicious"] == t["agents"]
    assert t["diff"] == t["agent_reported"] - t["company_reported"]
    assert len(o["by_company"]) == 5
    assert set(o["status_labels"]) == {"matched", "company_suspicious", "agent_suspicious"}


def test_status_logic():
    """diff = agent_reported - company_reported يحدّد الحكم."""
    for r in audit._AUDIT:
        diff = r["agent_reported"] - r["company_reported"]
        assert r["diff"] == diff
        if diff == 0:
            assert r["status"] == "matched"
        elif diff > 0:
            # الوكيل أكثر من الشركة → الوكيل مشبوه
            assert r["status"] == "agent_suspicious"
        else:
            # الوكيل أقل من الشركة → الشركة مشبوهة
            assert r["status"] == "company_suspicious"


def test_company_verdict_consistency():
    o = audit.overview()
    for c in o["by_company"]:
        diff = c["agent_reported"] - c["company_reported"]
        assert c["diff"] == diff
        if diff == 0:
            assert c["verdict"] == "matched"
        elif diff > 0:
            assert c["verdict"] == "agent_suspicious"
        else:
            assert c["verdict"] == "company_suspicious"
        # مجموع الأحكام لكل شركة = عدد وكلائها
        assert c["matched"] + c["company_suspicious"] + c["agent_suspicious"] == c["agents"]


def test_totals_equal_company_sums():
    o = audit.overview()
    assert sum(c["agent_reported"] for c in o["by_company"]) == o["totals"]["agent_reported"]
    assert sum(c["company_reported"] for c in o["by_company"]) == o["totals"]["company_reported"]


def test_agent_reported_matches_subscriber_count():
    """ما يذكره الوكيل = عدد مشتركيه الفعلي."""
    from app.services import agents
    by_id = {a["id"]: a["subscriber_count"] for a in agents._AGENTS}
    for r in audit._AUDIT:
        assert r["agent_reported"] == by_id[r["agent_id"]]
        assert r["handle"].startswith("@")


def test_traffic_dimension():
    """التدقيق يشمل حجم البيانات (Gbps) إضافةً لعدد المشتركين."""
    o = audit.overview()
    t = o["totals"]
    assert t["agent_traffic"] >= 0 and t["company_traffic"] >= 0
    assert t["traffic_matched"] + t["traffic_company_suspicious"] + \
        t["traffic_agent_suspicious"] == t["agents"]
    # منطق حجم البيانات لكل وكيل متّسق مع الفرق
    for r in audit._AUDIT:
        assert "agent_traffic" in r and "company_traffic" in r
        d = r["traffic_diff"]
        if abs(d) < 0.05:
            assert r["traffic_status"] == "matched"
        elif d > 0:
            assert r["traffic_status"] == "agent_suspicious"
        else:
            assert r["traffic_status"] == "company_suspicious"
    # مجاميع الشركات لحجم البيانات
    for c in o["by_company"]:
        assert "agent_traffic" in c and "traffic_verdict" in c


def test_deterministic():
    a = audit.overview()["totals"]
    b = audit.overview()["totals"]
    assert a == b


def test_filter_by_company():
    o = audit.overview(company="إيرثلنك")
    assert o["totals"]["companies"] == 1
    assert all(r["company"] == "إيرثلنك" for r in o["agents"])
    assert len(o["by_company"]) == 1


def test_api(client):
    r = client.get("/api/audit/overview")
    assert r.status_code == 200
    assert r.json()["totals"]["agents"] > 0
    assert "by_company" in r.json()

    r2 = client.get("/api/audit/overview?company=هلا")
    assert r2.status_code == 200
    assert r2.json()["totals"]["companies"] == 1
