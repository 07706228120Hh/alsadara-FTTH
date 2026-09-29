"""
اختبارات تكامل لـ DfoS — الاستشعار الليفي الموزّع.

تغطّي:
- اختبارات وحدة على طبقة الخدمة (dfos.overview / map_data / dispatch / analyze)
- اختبارات تكامل عبر FastAPI TestClient
"""
import pytest
from app.services import dfos


# ---------------------------------------------------------------------------
# مساعدات
# ---------------------------------------------------------------------------

def _first_threat_event() -> dict:
    """أوّل حدث تهديد في قائمة الأحداث (threat==True)."""
    for e in dfos._EVENTS:
        if e["threat"]:
            return e
    pytest.skip("لا يوجد حدث تهديد في _EVENTS")


def _first_non_threat_event() -> dict:
    """أوّل حدث غير تهديد في قائمة الأحداث (threat==False)."""
    for e in dfos._EVENTS:
        if not e["threat"]:
            return e
    pytest.skip("لا يوجد حدث غير تهديد في _EVENTS")


# ---------------------------------------------------------------------------
# اختبارات وحدة — dfos.overview()
# ---------------------------------------------------------------------------

class TestDfosOverview:
    def test_totals_sensors_count(self):
        """totals.sensors == 5 (مطابقة _SENSOR_DEFS)."""
        t = dfos.overview()["totals"]
        assert t["sensors"] == 5

    def test_totals_cameras_positive(self):
        """totals.cameras > 0."""
        t = dfos.overview()["totals"]
        assert t["cameras"] > 0

    def test_totals_events_count(self):
        """totals.events == 34 (الأحداث المولَّدة)."""
        t = dfos.overview()["totals"]
        assert t["events"] == 34

    def test_totals_threats_positive(self):
        """totals.threats > 0 (يوجد تهديد على الأقل)."""
        t = dfos.overview()["totals"]
        assert t["threats"] > 0

    def test_totals_threats_active_positive(self):
        """totals.threats_active > 0 (يوجد تهديد نشط)."""
        t = dfos.overview()["totals"]
        assert t["threats_active"] > 0

    def test_totals_critical_nonnegative(self):
        """totals.critical >= 0."""
        t = dfos.overview()["totals"]
        assert t["critical"] >= 0

    def test_totals_monitored_routes_positive(self):
        """totals.monitored_routes > 0."""
        t = dfos.overview()["totals"]
        assert t["monitored_routes"] > 0

    def test_totals_monitored_km_positive(self):
        """totals.monitored_km > 0."""
        t = dfos.overview()["totals"]
        assert t["monitored_km"] > 0

    def test_events_is_list(self):
        """overview().events قائمة."""
        result = dfos.overview()
        assert isinstance(result["events"], list)

    def test_events_count_matches_totals(self):
        """عدد الأحداث في القائمة يساوي totals.events."""
        result = dfos.overview()
        assert len(result["events"]) == result["totals"]["events"]

    def test_by_type_nonempty(self):
        """by_type غير فارغة."""
        result = dfos.overview()
        assert len(result["by_type"]) > 0

    def test_deterministic_events_count(self):
        """نداءان متتاليان يعطيان نفس عدد الأحداث."""
        a = len(dfos.overview()["events"])
        b = len(dfos.overview()["events"])
        assert a == b

    def test_deterministic_first_event_id(self):
        """نداءان متتاليان يعطيان نفس معرّف الحدث الأوّل."""
        a = dfos.overview()["events"][0]["id"]
        b = dfos.overview()["events"][0]["id"]
        assert a == b


# ---------------------------------------------------------------------------
# اختبارات وحدة — سلسلة الحزمة الكاملة (workflow) للتهديدات
# ---------------------------------------------------------------------------

class TestDfosWorkflow:
    def test_threat_event_has_nonempty_workflow(self):
        """حدث تهديد يملك workflow غير None."""
        result = dfos.overview()
        threat_events = [e for e in result["events"] if e["threat"]]
        assert len(threat_events) > 0
        for e in threat_events:
            assert e["workflow"] is not None

    def test_workflow_has_required_keys(self):
        """workflow يملك المفاتيح الخمسة: alarm, agent, location, camera, ticket."""
        result = dfos.overview()
        threat_events = [e for e in result["events"] if e["threat"]]
        for e in threat_events:
            wf = e["workflow"]
            assert {"alarm", "agent", "location", "camera", "ticket"}.issubset(wf.keys())

    def test_non_threat_event_workflow_is_none(self):
        """حدث غير تهديد له workflow == None."""
        result = dfos.overview()
        non_threats = [e for e in result["events"] if not e["threat"]]
        assert len(non_threats) > 0
        for e in non_threats:
            assert e["workflow"] is None

    def test_ticket_has_required_fields(self):
        """ticket في workflow يملك الحقول المطلوبة بالقيم الصحيحة."""
        result = dfos.overview()
        threat_events = [e for e in result["events"] if e["threat"]]
        for e in threat_events:
            ticket = e["workflow"]["ticket"]
            assert "id" in ticket
            assert "type" in ticket
            assert "company" in ticket
            assert "severity" in ticket
            assert "sla_hours" in ticket
            assert ticket["auto"] is True
            assert ticket["dispatched"] is False

    def test_ticket_sla_hours_positive(self):
        """sla_hours في التذكرة > 0."""
        result = dfos.overview()
        threat_events = [e for e in result["events"] if e["threat"]]
        for e in threat_events:
            assert e["workflow"]["ticket"]["sla_hours"] > 0

    def test_ticket_id_starts_with_inc(self):
        """معرّف التذكرة التلقائية يبدأ بـ INC-D."""
        result = dfos.overview()
        threat_events = [e for e in result["events"] if e["threat"]]
        for e in threat_events:
            assert e["workflow"]["ticket"]["id"].startswith("INC-D")

    def test_alarm_has_severity_and_source_type(self):
        """alarm في workflow يملك severity و source_type."""
        result = dfos.overview()
        threat_events = [e for e in result["events"] if e["threat"]]
        for e in threat_events:
            alarm = e["workflow"]["alarm"]
            assert "severity" in alarm
            assert alarm["source_type"] == "dfos"

    def test_location_has_required_fields(self):
        """location في workflow يملك lat و lng و route و governorate و position_km."""
        result = dfos.overview()
        threat_events = [e for e in result["events"] if e["threat"]]
        for e in threat_events:
            loc = e["workflow"]["location"]
            assert {"lat", "lng", "route", "governorate", "position_km"}.issubset(loc.keys())


# ---------------------------------------------------------------------------
# اختبارات وحدة — dfos.map_data()
# ---------------------------------------------------------------------------

class TestDfosMapData:
    def test_map_has_routes(self):
        """map_data() يحوي routes > 0."""
        m = dfos.map_data()
        assert "routes" in m
        assert len(m["routes"]) > 0

    def test_map_has_sensors(self):
        """map_data() يحوي sensors."""
        m = dfos.map_data()
        assert "sensors" in m

    def test_map_has_cameras(self):
        """map_data() يحوي cameras."""
        m = dfos.map_data()
        assert "cameras" in m

    def test_map_has_events(self):
        """map_data() يحوي events."""
        m = dfos.map_data()
        assert "events" in m

    def test_routes_have_coordinates(self):
        """كل مسار في map_data() يملك coordinates غير فارغة."""
        m = dfos.map_data()
        for r in m["routes"]:
            assert "coordinates" in r
            assert len(r["coordinates"]) > 0

    def test_events_have_lat_lng(self):
        """كل حدث في map_data().events يملك lat و lng."""
        m = dfos.map_data()
        for e in m["events"]:
            assert "lat" in e and "lng" in e

    def test_map_filter_by_governorate(self):
        """map_data(governorate=...) يصفّي الأحداث للمحافظة المطلوبة."""
        all_govs = {e["governorate"] for e in dfos._EVENTS}
        gov = next(iter(all_govs))
        m = dfos.map_data(governorate=gov)
        for e in m["events"]:
            assert e["governorate"] == gov


# ---------------------------------------------------------------------------
# اختبارات وحدة — dfos.dispatch()
# ---------------------------------------------------------------------------

class TestDfosDispatch:
    def test_dispatch_threat_returns_ticket_with_inc_id(self):
        """dispatch() لحدث تهديد يُنشئ تذكرة فعلية بمعرّف يبدأ بـ INC-M."""
        threat = _first_threat_event()
        result = dfos.dispatch(threat["id"])
        assert "ticket" in result
        # التذكرة المُنشأة عبر create_issue تستخدم INC-M (manual)
        assert result["ticket"]["id"].startswith("INC-M")

    def test_dispatch_returns_nonempty_message(self):
        """dispatch() يُرجع رسالة message غير فارغة."""
        threat = _first_threat_event()
        result = dfos.dispatch(threat["id"])
        assert isinstance(result["message"], str)
        assert len(result["message"]) > 10

    def test_dispatch_result_has_event_id(self):
        """نتيجة dispatch() تحوي event_id صحيحاً."""
        threat = _first_threat_event()
        result = dfos.dispatch(threat["id"])
        assert result["event_id"] == threat["id"]

    def test_dispatch_marks_event_dispatched_in_overview(self):
        """بعد dispatch()، overview() يُظهر dispatched==True للحدث المُصعَّد."""
        threat = _first_threat_event()
        # نُصعَّد أولاً
        dfos.dispatch(threat["id"])
        # الآن نتحقق من overview
        result = dfos.overview()
        matched = [e for e in result["events"] if e["id"] == threat["id"]]
        assert len(matched) == 1
        e = matched[0]
        assert e["workflow"] is not None
        assert e["workflow"]["ticket"]["dispatched"] is True

    def test_dispatch_non_threat_raises_value_error(self):
        """dispatch() على حدث غير تهديد يرفع ValueError."""
        non_threat = _first_non_threat_event()
        with pytest.raises(ValueError):
            dfos.dispatch(non_threat["id"])

    def test_dispatch_unknown_id_raises_value_error(self):
        """dispatch() على معرّف غير موجود يرفع ValueError."""
        with pytest.raises(ValueError):
            dfos.dispatch("DFOS-EVT-99999")

    def test_dispatch_error_message_for_non_threat(self):
        """رسالة ValueError لحدث غير تهديد تُفيد بعدم التصعيد."""
        non_threat = _first_non_threat_event()
        with pytest.raises(ValueError, match="تهديد"):
            dfos.dispatch(non_threat["id"])

    def test_dispatch_error_message_for_unknown_id(self):
        """رسالة ValueError للمعرّف غير المعروف تُشير للمشكلة."""
        with pytest.raises(ValueError, match="غير معروف"):
            dfos.dispatch("DFOS-EVT-XXXXX")


# ---------------------------------------------------------------------------
# اختبارات تكامل — FastAPI TestClient
# ---------------------------------------------------------------------------

class TestDfosAPI:
    def test_get_overview_200(self, client):
        """GET /api/dfos/overview يُرجع 200."""
        r = client.get("/api/dfos/overview")
        assert r.status_code == 200

    def test_get_overview_has_totals(self, client):
        """استجابة overview تحوي totals."""
        r = client.get("/api/dfos/overview")
        body = r.json()
        assert "totals" in body

    def test_get_overview_totals_sensors(self, client):
        """totals.sensors == 5."""
        r = client.get("/api/dfos/overview")
        assert r.json()["totals"]["sensors"] == 5

    def test_get_overview_has_events(self, client):
        """استجابة overview تحوي قائمة events."""
        r = client.get("/api/dfos/overview")
        assert "events" in r.json()

    def test_get_overview_threats_only_filter(self, client):
        """overview?threats_only=true يُرجع تهديدات فقط."""
        r = client.get("/api/dfos/overview", params={"threats_only": "true"})
        assert r.status_code == 200
        for e in r.json()["events"]:
            assert e["threat"] is True

    def test_get_map_200(self, client):
        """GET /api/dfos/map يُرجع 200."""
        r = client.get("/api/dfos/map")
        assert r.status_code == 200

    def test_get_map_has_routes(self, client):
        """استجابة map تحوي routes."""
        r = client.get("/api/dfos/map")
        body = r.json()
        assert "routes" in body
        assert len(body["routes"]) > 0

    def test_get_map_has_sensors_and_cameras(self, client):
        """استجابة map تحوي sensors و cameras."""
        r = client.get("/api/dfos/map")
        body = r.json()
        assert "sensors" in body
        assert "cameras" in body

    def test_post_analyze_200(self, client):
        """POST /api/dfos/analyze يُرجع 200."""
        r = client.post("/api/dfos/analyze")
        assert r.status_code == 200

    def test_post_analyze_has_analysis_and_source(self, client):
        """استجابة analyze تحوي analysis و source."""
        r = client.post("/api/dfos/analyze")
        body = r.json()
        assert "analysis" in body
        assert "source" in body
        assert body["source"] in ("rules", "claude")

    def test_post_analyze_analysis_nonempty(self, client):
        """نص analysis غير فارغ."""
        r = client.post("/api/dfos/analyze")
        assert len(r.json()["analysis"]) > 10

    def test_post_dispatch_threat_via_service(self):
        """تصعيد حدث تهديد مباشرة عبر الخدمة (لتجنّب تعقيدات المصادقة في operator)."""
        # نجد أوّل حدث تهديد
        threat = _first_threat_event()
        result = dfos.dispatch(threat["id"])
        # التذكرة تُنشأ بمعرّف صالح
        assert result["ticket"]["id"].startswith("INC-M")
        assert result["event_id"] == threat["id"]

    def test_get_event_detail_200(self, client):
        """GET /api/dfos/events/{id} يُرجع 200 لحدث موجود."""
        threat = _first_threat_event()
        r = client.get(f"/api/dfos/events/{threat['id']}")
        assert r.status_code == 200

    def test_get_event_detail_404_unknown(self, client):
        """GET /api/dfos/events/{id} يُرجع 404 لحدث غير موجود."""
        r = client.get("/api/dfos/events/DFOS-EVT-99999")
        assert r.status_code == 404

    def test_post_dispatch_via_endpoint_in_mock_mode(self, client):
        """POST /api/dfos/{id}/dispatch يُرجع 200 في وضع المحاكاة (dev role = admin >= operator)."""
        threat = _first_threat_event()
        r = client.post(f"/api/dfos/{threat['id']}/dispatch")
        # في وضع المحاكاة بلا API_TOKEN، الهوية dev=admin تحقّق شرط operator
        assert r.status_code == 200
        body = r.json()
        assert "ticket" in body
        assert body["ticket"]["id"].startswith("INC-M")

    def test_post_dispatch_non_threat_returns_400(self, client):
        """POST /api/dfos/{id}/dispatch لحدث غير تهديد يُرجع 400."""
        non_threat = _first_non_threat_event()
        r = client.post(f"/api/dfos/{non_threat['id']}/dispatch")
        assert r.status_code == 400

    def test_post_dispatch_unknown_id_returns_400(self, client):
        """POST /api/dfos/DFOS-EVT-99999/dispatch يُرجع 400."""
        r = client.post("/api/dfos/DFOS-EVT-99999/dispatch")
        assert r.status_code == 400
