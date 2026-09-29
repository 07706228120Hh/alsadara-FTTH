"""اختبارات الوكلاء — التوليد والتجميع والتصفية والتفاصيل."""
from app.services import agents


def test_overview_totals():
    o = agents.overview()
    t = o["totals"]
    assert t["agents"] > 0
    assert t["subscribers"] > 0
    assert t["active_subscribers"] <= t["subscribers"]
    assert t["companies"] == 5
    assert len(o["by_company"]) == 5
    # مجموع مشتركي الشركات = الإجمالي
    assert sum(c["subscribers"] for c in o["by_company"]) == t["subscribers"]
    # القائمة مرتّبة تنازلياً حسب عدد المشتركين
    counts = [a["subscriber_count"] for a in o["agents"]]
    assert counts == sorted(counts, reverse=True)
    # لا تُسرَّب قائمة المشتركين الكاملة في القائمة
    assert all("subscribers" not in a for a in o["agents"])


def test_service_type_within_company_access():
    """نوع خدمة كل وكيل ضمن ما تجهّزه شركته."""
    from app.services import national
    o = agents.overview()
    by_id_company = {a["id"]: a["company"] for a in o["agents"]}
    for a in agents._AGENTS:
        allowed = set(national._COMPANY_ACCESS[a["company"]])
        assert set(a["service_types"]).issubset(allowed)
        assert by_id_company[a["id"]] == a["company"]


def test_deterministic():
    a = agents.overview()["totals"]
    b = agents.overview()["totals"]
    assert a == b


def test_filter_by_company():
    o = agents.overview(company="إيرثلنك")
    assert o["totals"]["companies"] == 1
    assert all(a["company"] == "إيرثلنك" for a in o["agents"])
    # إيرثلنك FTTH فقط
    assert all(a["service_types"] == ["ftth"] for a in o["agents"])


def test_filter_by_governorate():
    o = agents.overview(governorate="بغداد")
    assert o["totals"]["governorates"] == 1
    assert all(a["governorate"] == "بغداد" for a in o["agents"])


def test_by_service_type_distribution():
    o = agents.overview()
    assert sum(x["subscribers"] for x in o["by_service_type"]) == o["totals"]["subscribers"]
    types = {x["type"] for x in o["by_service_type"]}
    assert types.issubset({"ftth", "wireless"})


def test_detail_has_subscribers():
    o = agents.overview()
    aid = o["agents"][0]["id"]
    d = agents.detail(aid)
    assert d is not None
    assert d["id"] == aid
    assert len(d["subscribers"]) == d["subscriber_count"]
    # كل مشترك يحمل الحقول المطلوبة (بما فيها عنوان IP)
    s = d["subscribers"][0]
    for k in ("name", "phone", "ip", "mac", "service_type", "service_label",
              "plan", "monthly_fee", "status"):
        assert k in s
    # صيغة IP رباعية صحيحة ضمن نطاق CGNAT
    octets = s["ip"].split(".")
    assert len(octets) == 4 and all(o.isdigit() for o in octets)
    assert octets[0] == "100"
    assert sum(x["subscribers"] for x in d["by_service_type"]) == d["subscriber_count"]


def test_detail_filter():
    o = agents.overview()
    aid = o["agents"][0]["id"]
    d = agents.detail(aid, status="active")
    assert all(s["status"] == "active" for s in d["subscribers"])


def test_detail_unknown():
    assert agents.detail("AG-9999") is None


def test_agents_have_handle():
    """كل وكيل له مُعرّف «@» مسجَّل لدى شركته (فريد)."""
    handles = [a["handle"] for a in agents._AGENTS]
    assert all(h.startswith("@") for h in handles)
    assert len(set(handles)) == len(handles)  # فريدة


def test_agent_names_are_male():
    """أسماء الوكلاء ذكور فقط — لا أسماء نسائية."""
    female = {"فاطمة", "زينب", "مريم", "نور", "سارة", "رقية", "هدى", "آية",
              "دعاء", "ريم"}
    for a in agents._AGENTS:
        first = a["name"].split()[0]
        assert first not in female, f"اسم وكيل نسائي: {a['name']}"
        assert first in agents._MALE_FIRST_NAMES


def test_api(client):
    r = client.get("/api/agents/overview")
    assert r.status_code == 200
    assert r.json()["totals"]["agents"] > 0

    r2 = client.get("/api/agents/overview?company=هلا")
    assert r2.status_code == 200
    assert r2.json()["totals"]["companies"] == 1

    aid = r.json()["agents"][0]["id"]
    r3 = client.get(f"/api/agents/{aid}")
    assert r3.status_code == 200
    assert r3.json()["id"] == aid
    assert isinstance(r3.json()["subscribers"], list)

    r4 = client.get("/api/agents/AG-9999")
    assert r4.status_code == 404
