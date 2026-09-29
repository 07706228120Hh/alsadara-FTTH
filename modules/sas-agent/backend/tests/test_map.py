"""
اختبارات /api/companies/map وطبقات GIS — test_map.py

تُغطّي:
1. /companies/map يُرجع الطبقات الثلاث (governorates/companies/agents) بإحداثيات صحيحة.
2. التصفية تعمل (governorate / status / access_type / company_id / agent).
3. العزل: مستخدم شركة A لا يرى بيانات B، الوكيل يرى نطاقه فقط.
4. رفع GeoJSON صالح → يُخزَّن ويُقرأ.
5. رفع KML بسيط (LineString) → يتحوّل إلى GeoJSON.
6. ملف تالف → 400.
7. Shapefile → 400 برسالة توجيهية.
8. انحدار: كل ما كان خضراء يبقى خضراء.
"""
from __future__ import annotations

import io
import json

import pytest
from sqlmodel import Session, select

from app.database import engine
from app.models import Agent, Company, GisLayer, Subscriber, User
from app.core import security as sec_module
from app.main import _seed_default_admin


# ─────────────────────────── مساعدات ───────────────────────────

def _create_company(db: Session, name: str, code: str,
                    governorate: str = "بغداد",
                    access_type: str = "ftth") -> Company:
    c = Company(name=name, code=code, governorate=governorate, access_type=access_type)
    db.add(c)
    db.commit()
    db.refresh(c)
    return c


def _create_user(db: Session, username: str, role: str = "admin",
                 company_id=None, agent: str = "") -> User:
    u = User(
        username=username,
        password_hash=sec_module.hash_password("pw123"),
        role=role,
        scope_company_id=company_id,
        scope_agent=agent,
    )
    db.add(u)
    db.commit()
    db.refresh(u)
    return u


def _create_agent(db: Session, company_id: int, username: str,
                  users_count: int = 5) -> Agent:
    mgr_id = abs(company_id * 100 + hash(username) % 100)
    a = Agent(
        company_id=company_id,
        manager_id=mgr_id,
        username=username,
        firstname=username,
        lastname="اختبار",
        users_count=users_count,
    )
    db.add(a)
    db.commit()
    db.refresh(a)
    return a


def _create_subscriber(db: Session, company_id: int,
                        agent_username: str, governorate: str,
                        status: str = "active", online: bool = True,
                        sub_id: int = 9999) -> Subscriber:
    s = Subscriber(
        company_id=company_id,
        sub_id=sub_id,
        username=f"u_{sub_id}",
        agent_username=agent_username,
        governorate=governorate,
        status=status,
        online=online,
    )
    db.add(s)
    db.commit()
    db.refresh(s)
    return s


def _tok(client, username: str, password: str = "pw123") -> dict:
    r = client.post("/api/auth/login", json={"username": username, "password": password})
    assert r.status_code == 200, f"تسجيل دخول فشل لـ {username}: {r.text}"
    return {"Authorization": f"Bearer {r.json()['token']}"}


# ─────────────────────────── Fixture تنظيف ───────────────────────────

@pytest.fixture(autouse=True)
def _clean():
    """تنظيف الجداول المُستخدَمة قبل وبعد كل اختبار."""
    def _do():
        with Session(engine) as db:
            for model in (GisLayer, Subscriber, Agent, Company):
                for row in db.exec(select(model)).all():
                    db.delete(row)
            for u in db.exec(select(User)).all():
                if u.username != "admin":
                    db.delete(u)
            db.commit()
        _seed_default_admin()

    _do()
    yield
    _do()


# ══════════════════════════════════════════════════════════════════════
# 1) /companies/map — البنية الأساسية
# ══════════════════════════════════════════════════════════════════════

def test_map_returns_three_layers(client):
    """الاستجابة تحتوي governorates و companies و agents."""
    r = client.get("/api/companies/map")
    assert r.status_code == 200
    data = r.json()
    assert "governorates" in data
    assert "companies" in data
    assert "agents" in data


def test_map_companies_have_coordinates(client):
    """الشركات التي لها محافظة معروفة تُرجع بإحداثيات."""
    with Session(engine) as db:
        _create_company(db, "شركة-خ", "CX", governorate="بغداد")
        _create_company(db, "شركة-ي", "CY", governorate="البصرة")
    r = client.get("/api/companies/map")
    assert r.status_code == 200
    companies = r.json()["companies"]
    assert len(companies) >= 2
    for c in companies:
        assert c["lat"] is not None
        assert c["lng"] is not None
        assert isinstance(c["lat"], float)
        assert isinstance(c["lng"], float)


def test_map_governorates_have_correct_coords(client):
    """مشترك في بغداد → طبقة المحافظات تحتوي إحداثيات بغداد الصحيحة."""
    with Session(engine) as db:
        ca = _create_company(db, "ش-بغداد", "CB1", governorate="بغداد")
        _create_agent(db, ca.id, "ag1")
        _create_subscriber(db, ca.id, "ag1", "بغداد", sub_id=5001)

    r = client.get("/api/companies/map")
    assert r.status_code == 200
    govs = {g["governorate"]: g for g in r.json()["governorates"]}
    assert "بغداد" in govs
    bg = govs["بغداد"]
    # إحداثيات بغداد من _GOVERNORATES: (33.3152, 44.3661)
    assert abs(bg["lat"] - 33.3152) < 0.01
    assert abs(bg["lng"] - 44.3661) < 0.01


def test_map_agents_layer(client):
    """طبقة الوكلاء تحتوي وكيلاً ذا مشتركين."""
    with Session(engine) as db:
        ca = _create_company(db, "ش-وكيل", "CAG", governorate="البصرة")
        _create_agent(db, ca.id, "ag_basra", users_count=20)
        _create_subscriber(db, ca.id, "ag_basra", "البصرة", sub_id=6001)
        _create_subscriber(db, ca.id, "ag_basra", "البصرة", sub_id=6002)

    r = client.get("/api/companies/map")
    assert r.status_code == 200
    agents = r.json()["agents"]
    names = [a["agent"] for a in agents]
    assert "ag_basra" in names
    ag = next(a for a in agents if a["agent"] == "ag_basra")
    assert ag["governorate"] == "البصرة"
    assert ag["lat"] is not None


# ══════════════════════════════════════════════════════════════════════
# 2) التصفية
# ══════════════════════════════════════════════════════════════════════

def test_map_filter_by_governorate(client):
    """التصفية بالمحافظة تُعيد محافظات البصرة فقط."""
    with Session(engine) as db:
        ca = _create_company(db, "ش-1", "C1", governorate="بغداد")
        cb = _create_company(db, "ش-2", "C2", governorate="البصرة")
        _create_agent(db, ca.id, "ag_bg")
        _create_agent(db, cb.id, "ag_bs")
        _create_subscriber(db, ca.id, "ag_bg", "بغداد", sub_id=7001)
        _create_subscriber(db, cb.id, "ag_bs", "البصرة", sub_id=7002)

    r = client.get("/api/companies/map?governorate=البصرة")
    assert r.status_code == 200
    data = r.json()
    gov_names = {g["governorate"] for g in data["governorates"]}
    assert "بغداد" not in gov_names
    assert "البصرة" in gov_names


def test_map_filter_by_status(client):
    """التصفية بالحالة active تُرجع مشتركين نشطين فقط."""
    with Session(engine) as db:
        ca = _create_company(db, "ش-فلتر", "CF1", governorate="نينوى")
        _create_agent(db, ca.id, "ag_n")
        _create_subscriber(db, ca.id, "ag_n", "نينوى", status="active", sub_id=8001)
        _create_subscriber(db, ca.id, "ag_n", "نينوى", status="expired", sub_id=8002)

    r = client.get("/api/companies/map?status=active")
    assert r.status_code == 200
    govs = {g["governorate"]: g for g in r.json()["governorates"]}
    if "نينوى" in govs:
        # فقط المشترك النشط
        assert govs["نينوى"]["total"] == 1
        assert govs["نينوى"]["active"] == 1


def test_map_filter_by_access_type(client):
    """التصفية بـ access_type=wireless تُرجع شركات الوايرليس فقط."""
    with Session(engine) as db:
        _create_company(db, "ش-ftth", "CFF", governorate="كربلاء", access_type="ftth")
        _create_company(db, "ش-wl", "CWL", governorate="كربلاء", access_type="wireless")

    r = client.get("/api/companies/map?access_type=wireless")
    assert r.status_code == 200
    comps = r.json()["companies"]
    codes = [c["company_id"] for c in comps]
    # كل الشركات المُرجعة يجب أن تكون wireless
    for comp in comps:
        assert comp["access_type"] == "wireless"


def test_map_filter_by_company_id(client):
    """التصفية بـ company_id تُقيّد الشركات للشركة المطلوبة."""
    with Session(engine) as db:
        ca = _create_company(db, "ش-أ", "CA2", governorate="بغداد")
        cb = _create_company(db, "ش-ب", "CB2", governorate="البصرة")
        _create_agent(db, ca.id, "ag_ca")
        _create_agent(db, cb.id, "ag_cb")
        _create_subscriber(db, ca.id, "ag_ca", "بغداد", sub_id=9001)
        _create_subscriber(db, cb.id, "ag_cb", "البصرة", sub_id=9002)

    with Session(engine) as db:
        ca = db.exec(select(Company).where(Company.code == "CA2")).first()

    r = client.get(f"/api/companies/map?company_id={ca.id}")
    assert r.status_code == 200
    comps = r.json()["companies"]
    assert all(c["company_id"] == ca.id for c in comps)


def test_map_filter_by_agent(client):
    """التصفية بـ agent تُعيد بيانات وكيل بعينه فقط."""
    with Session(engine) as db:
        ca = _create_company(db, "ش-وك", "CAW", governorate="بغداد")
        _create_agent(db, ca.id, "wak1")
        _create_agent(db, ca.id, "wak2")
        _create_subscriber(db, ca.id, "wak1", "بغداد", sub_id=10001)
        _create_subscriber(db, ca.id, "wak2", "بغداد", sub_id=10002)

    r = client.get("/api/companies/map?agent=wak1")
    assert r.status_code == 200
    agents = r.json()["agents"]
    names = {a["agent"] for a in agents}
    assert "wak1" in names
    # wak2 ليس له مشترك بعد الفلتر → لن يظهر
    assert "wak2" not in names


# ══════════════════════════════════════════════════════════════════════
# 3) العزل (Multi-tenant scoping)
# ══════════════════════════════════════════════════════════════════════

@pytest.fixture
def scoped_data(client):
    """ينشئ شركتَي A و B مع مشتركين ومستخدمين مُنطاقَين."""
    with Session(engine) as db:
        ca = _create_company(db, "شركة-أ", "SC_A", governorate="بغداد")
        cb = _create_company(db, "شركة-ب", "SC_B", governorate="البصرة")
        ag_a = _create_agent(db, ca.id, "sc_ag_a")
        ag_b = _create_agent(db, cb.id, "sc_ag_b")
        _create_subscriber(db, ca.id, "sc_ag_a", "بغداد", sub_id=20001)
        _create_subscriber(db, cb.id, "sc_ag_b", "البصرة", sub_id=20002)
        _create_user(db, "sc_user_a", "admin", company_id=ca.id)
        _create_user(db, "sc_agent_a", "operator", company_id=ca.id, agent="sc_ag_a")

    h_gov = _tok(client, "admin", "admin")
    h_a = _tok(client, "sc_user_a")
    h_agent_a = _tok(client, "sc_agent_a")

    with Session(engine) as db:
        ca2 = db.exec(select(Company).where(Company.code == "SC_A")).first()
        cb2 = db.exec(select(Company).where(Company.code == "SC_B")).first()

    return {
        "ca": ca2, "cb": cb2,
        "h_gov": h_gov, "h_a": h_a, "h_agent": h_agent_a,
    }


def test_gov_sees_all_map_layers(client, scoped_data):
    """جهة رقابية ترى كل الشركات في الخريطة."""
    r = client.get("/api/companies/map", headers=scoped_data["h_gov"])
    assert r.status_code == 200
    comps = r.json()["companies"]
    cids = {c["company_id"] for c in comps}
    assert scoped_data["ca"].id in cids
    assert scoped_data["cb"].id in cids


def test_company_user_sees_only_own_data(client, scoped_data):
    """مستخدم شركة A لا يرى بيانات شركة B في الخريطة."""
    r = client.get("/api/companies/map", headers=scoped_data["h_a"])
    assert r.status_code == 200
    comps = r.json()["companies"]
    cids = {c["company_id"] for c in comps}
    assert scoped_data["ca"].id in cids
    assert scoped_data["cb"].id not in cids


def test_company_user_cannot_expand_scope_via_company_id(client, scoped_data):
    """مستخدم شركة A لا يوسّع نطاقه بإرسال company_id=B."""
    cid_b = scoped_data["cb"].id
    r = client.get(f"/api/companies/map?company_id={cid_b}", headers=scoped_data["h_a"])
    assert r.status_code == 200
    comps = r.json()["companies"]
    # يجب ألا يرى شركة B
    cids = {c["company_id"] for c in comps}
    assert cid_b not in cids


def test_agent_sees_only_own_scope(client, scoped_data):
    """مستخدم وكيل يرى فقط بيانات وكيله."""
    r = client.get("/api/companies/map", headers=scoped_data["h_agent"])
    assert r.status_code == 200
    # لا يجب أن ترى بيانات شركة B
    comps = r.json()["companies"]
    cids = {c["company_id"] for c in comps}
    assert scoped_data["cb"].id not in cids
    # طبقة الوكلاء تحتوي فقط sc_ag_a
    agents = r.json()["agents"]
    names = {a["agent"] for a in agents}
    assert "sc_ag_b" not in names


def test_unknown_governorate_ignored(client):
    """محافظة غير موجودة في _GOVERNORATES تُتجاهل ولا تُسبّب خطأ."""
    with Session(engine) as db:
        ca = _create_company(db, "ش-مجهول", "CUK", governorate="محافظة_وهمية")
        _create_agent(db, ca.id, "ag_uk")
        _create_subscriber(db, ca.id, "ag_uk", "محافظة_وهمية", sub_id=30001)

    r = client.get("/api/companies/map")
    assert r.status_code == 200
    # الشركة ذات المحافظة المجهولة لا تظهر في طبقة الشركات (بلا إحداثيات)
    comps = r.json()["companies"]
    for c in comps:
        assert c["governorate"] != "محافظة_وهمية"


# ══════════════════════════════════════════════════════════════════════
# 4) رفع GeoJSON صالح → يُخزَّن ويُقرأ
# ══════════════════════════════════════════════════════════════════════

_VALID_GEOJSON = {
    "type": "FeatureCollection",
    "features": [
        {
            "type": "Feature",
            "geometry": {
                "type": "LineString",
                "coordinates": [[44.3661, 33.3152], [44.3700, 33.3200]],
            },
            "properties": {"name": "خط-ألياف-1"},
        }
    ],
}


def test_upload_valid_geojson(client):
    """رفع GeoJSON صالح → 200 ويُخزَّن."""
    content = json.dumps(_VALID_GEOJSON, ensure_ascii=False).encode()
    r = client.post(
        "/api/companies/gis-layers",
        data={"name": "خط-اختبار", "kind": "fiber"},
        files={"file": ("test.geojson", io.BytesIO(content), "application/json")},
    )
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["feature_count"] == 1
    assert data["name"] == "خط-اختبار"


def test_upload_geojson_then_read_full(client):
    """رفع GeoJSON صالح ثم قراءته بالكامل عبر GET /gis-layers/{id}."""
    content = json.dumps(_VALID_GEOJSON, ensure_ascii=False).encode()
    r = client.post(
        "/api/companies/gis-layers",
        data={"name": "طبقة-كاملة", "kind": "fiber"},
        files={"file": ("layer.geojson", io.BytesIO(content), "application/json")},
    )
    assert r.status_code == 200
    layer_id = r.json()["id"]

    r2 = client.get(f"/api/companies/gis-layers/{layer_id}")
    assert r2.status_code == 200
    body = r2.json()
    assert body["geojson"]["type"] == "FeatureCollection"
    assert len(body["geojson"]["features"]) == 1


def test_upload_geojson_appears_in_list(client):
    """الطبقة المرفوعة تظهر في قائمة GET /gis-layers."""
    content = json.dumps(_VALID_GEOJSON, ensure_ascii=False).encode()
    client.post(
        "/api/companies/gis-layers",
        data={"name": "طبقة-قائمة"},
        files={"file": ("f.geojson", io.BytesIO(content), "application/json")},
    )
    r = client.get("/api/companies/gis-layers")
    assert r.status_code == 200
    names = [l["name"] for l in r.json()["layers"]]
    assert "طبقة-قائمة" in names


def test_upload_geojson_single_feature(client):
    """رفع Feature واحد (بدل FeatureCollection) → يُحوَّل ويُخزَّن."""
    single_feature = {
        "type": "Feature",
        "geometry": {"type": "Point", "coordinates": [44.3661, 33.3152]},
        "properties": {"name": "نقطة"},
    }
    content = json.dumps(single_feature).encode()
    r = client.post(
        "/api/companies/gis-layers",
        data={"name": "نقطة-واحدة"},
        files={"file": ("pt.geojson", io.BytesIO(content), "application/json")},
    )
    assert r.status_code == 200
    assert r.json()["feature_count"] == 1


def test_delete_gis_layer(client):
    """حذف طبقة GIS → 200 ثم 404 عند القراءة."""
    content = json.dumps(_VALID_GEOJSON, ensure_ascii=False).encode()
    r = client.post(
        "/api/companies/gis-layers",
        data={"name": "للحذف"},
        files={"file": ("del.geojson", io.BytesIO(content), "application/json")},
    )
    layer_id = r.json()["id"]
    rd = client.delete(f"/api/companies/gis-layers/{layer_id}")
    assert rd.status_code == 200
    assert rd.json()["ok"] is True
    r2 = client.get(f"/api/companies/gis-layers/{layer_id}")
    assert r2.status_code == 404


# ══════════════════════════════════════════════════════════════════════
# 5) رفع KML → تحويل صحيح
# ══════════════════════════════════════════════════════════════════════

_SIMPLE_KML = """<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>اختبار</name>
    <Placemark>
      <name>خط الألياف الرئيسي</name>
      <LineString>
        <coordinates>
          44.3661,33.3152,0
          44.3700,33.3200,0
          44.3750,33.3250,0
        </coordinates>
      </LineString>
    </Placemark>
  </Document>
</kml>""".encode("utf-8")


def test_upload_kml_converts_to_geojson(client):
    """رفع KML بسيط (LineString) → يتحوّل إلى GeoJSON FeatureCollection."""
    r = client.post(
        "/api/companies/gis-layers",
        data={"name": "خط-kml"},
        files={"file": ("fiber.kml", io.BytesIO(_SIMPLE_KML), "application/vnd.google-earth.kml+xml")},
    )
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["feature_count"] == 1

    layer_id = data["id"]
    r2 = client.get(f"/api/companies/gis-layers/{layer_id}")
    assert r2.status_code == 200
    fc = r2.json()["geojson"]
    assert fc["type"] == "FeatureCollection"
    feat = fc["features"][0]
    assert feat["geometry"]["type"] == "LineString"
    assert len(feat["geometry"]["coordinates"]) == 3


def test_upload_kml_with_point(client):
    """KML يحتوي Point → يتحوّل بشكل صحيح."""
    kml = """<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <Placemark>
      <name>نقطة توزيع</name>
      <Point>
        <coordinates>44.3661,33.3152,0</coordinates>
      </Point>
    </Placemark>
  </Document>
</kml>""".encode("utf-8")
    r = client.post(
        "/api/companies/gis-layers",
        data={"name": "نقطة-kml"},
        files={"file": ("pt.kml", io.BytesIO(kml), "application/vnd.google-earth.kml+xml")},
    )
    assert r.status_code == 200
    fc_id = r.json()["id"]
    r2 = client.get(f"/api/companies/gis-layers/{fc_id}")
    feat = r2.json()["geojson"]["features"][0]
    assert feat["geometry"]["type"] == "Point"


# ══════════════════════════════════════════════════════════════════════
# 6) ملفات تالفة/غير صالحة → 400
# ══════════════════════════════════════════════════════════════════════

def test_upload_invalid_json_returns_400(client):
    """GeoJSON تالف JSON → 400."""
    r = client.post(
        "/api/companies/gis-layers",
        data={"name": "تالف"},
        files={"file": ("bad.geojson", io.BytesIO(b"not valid json {{{"), "application/json")},
    )
    assert r.status_code == 400


def test_upload_wrong_geojson_type_returns_400(client):
    """GeoJSON بنوع غير مدعوم (GeometryCollection) → 400."""
    bad = {"type": "GeometryCollection", "geometries": []}
    r = client.post(
        "/api/companies/gis-layers",
        data={"name": "خاطئ"},
        files={"file": ("bad.geojson", io.BytesIO(json.dumps(bad).encode()), "application/json")},
    )
    assert r.status_code == 400


def test_upload_bad_kml_returns_400(client):
    """KML تالف XML → 400."""
    bad_kml = b"<kml><Document><Placemark><LineString>NOTVALID"
    r = client.post(
        "/api/companies/gis-layers",
        data={"name": "kml-تالف"},
        files={"file": ("bad.kml", io.BytesIO(bad_kml), "application/vnd.google-earth.kml+xml")},
    )
    assert r.status_code == 400


def test_upload_kml_with_dtd_entity_rejected(client):
    """KML يحتوي DTD/كيانات داخلية (billion-laughs) → 400 (defusedxml يرفض)."""
    payload = (
        '<?xml version="1.0"?>'
        '<!DOCTYPE kml [<!ENTITY a "AAAA">]>'
        '<kml xmlns="http://www.opengis.net/kml/2.2"><Document>'
        '<Placemark><name>&a;</name>'
        '<Point><coordinates>44.3,33.3,0</coordinates></Point>'
        '</Placemark></Document></kml>'
    ).encode("utf-8")
    r = client.post(
        "/api/companies/gis-layers",
        data={"name": "خبيث"},
        files={"file": ("evil.kml", io.BytesIO(payload),
                        "application/vnd.google-earth.kml+xml")},
    )
    assert r.status_code == 400


def test_upload_geojson_strips_html_from_properties(client):
    """خصائص GeoJSON تُعقَّم: وسوم HTML تُجرَّد (دفاع ضد Stored XSS)."""
    fc = {
        "type": "FeatureCollection",
        "features": [{
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [44.3, 33.3]},
            "properties": {"name": "<img src=x onerror=alert(1)>خط"},
        }],
    }
    r = client.post(
        "/api/companies/gis-layers",
        data={"name": "تعقيم"},
        files={"file": ("x.geojson", io.BytesIO(json.dumps(fc).encode()),
                        "application/json")},
    )
    assert r.status_code == 200, r.text
    layer_id = r.json()["id"]
    got = client.get(f"/api/companies/gis-layers/{layer_id}").json()["geojson"]
    name = got["features"][0]["properties"]["name"]
    assert "<" not in name and ">" not in name
    assert "خط" in name


def test_upload_out_of_range_coords_returns_400(client):
    """إحداثيات خارج النطاق → 400."""
    bad_fc = {
        "type": "FeatureCollection",
        "features": [{
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [999.0, 999.0]},
            "properties": {},
        }],
    }
    r = client.post(
        "/api/companies/gis-layers",
        data={"name": "خارج-النطاق"},
        files={"file": ("oor.geojson", io.BytesIO(json.dumps(bad_fc).encode()), "application/json")},
    )
    assert r.status_code == 400


def test_upload_geojson_with_utf8_bom_ok(client):
    """GeoJSON مع UTF-8 BOM (تصدير QGIS/ويندوز) → يُقبل (utf-8-sig)."""
    fc = {
        "type": "FeatureCollection",
        "features": [{
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [44.3, 33.3]},
            "properties": {"name": "نقطة"},
        }],
    }
    raw = b"\xef\xbb\xbf" + json.dumps(fc).encode("utf-8")  # BOM في المقدّمة
    r = client.post(
        "/api/companies/gis-layers",
        data={"name": "bom"},
        files={"file": ("bom.geojson", io.BytesIO(raw), "application/json")},
    )
    assert r.status_code == 200, r.text
    assert r.json()["feature_count"] == 1


def _pt_geojson():
    return json.dumps({
        "type": "FeatureCollection",
        "features": [{
            "type": "Feature",
            "geometry": {"type": "Point", "coordinates": [44.3, 33.3]},
            "properties": {},
        }],
    }).encode()


def test_upload_with_free_text_group(client):
    """المستوى/المجموعة نصّ حرّ (مثل «الباك بون») — يُحفظ ويُعاد."""
    r = client.post(
        "/api/companies/gis-layers",
        data={"name": "خط ظهري", "group": "الباك بون"},
        files={"file": ("bb.geojson", io.BytesIO(_pt_geojson()), "application/json")},
    )
    assert r.status_code == 200, r.text
    assert r.json()["group_name"] == "الباك بون"
    # يظهر في القائمة بحقل group_name
    layers = client.get("/api/companies/gis-layers").json()["layers"]
    assert any(l["group_name"] == "الباك بون" for l in layers)


def test_upload_without_group_defaults(client):
    """بلا group وبلا شركة → المجموعة الافتراضية «عامّة»."""
    r = client.post(
        "/api/companies/gis-layers",
        data={"name": "بلا مجموعة"},
        files={"file": ("x.geojson", io.BytesIO(_pt_geojson()), "application/json")},
    )
    assert r.status_code == 200, r.text
    assert r.json()["group_name"] == "عامّة"


def test_number_layer_assigns_npn_iqpin(client):
    """ترقيم طبقة مبانٍ → كل ميزة تحصل NPN + IQ-Pin (NAS-IQ)."""
    fc = {"type": "FeatureCollection", "features": [
        {"type": "Feature",
         "geometry": {"type": "Point", "coordinates": [44.4009, 33.3389]},
         "properties": {}},  # ساحة التحرير
        {"type": "Feature",
         "geometry": {"type": "Point", "coordinates": [44.4700, 33.3980]},
         "properties": {}},  # مدينة الصدر
    ]}
    r = client.post(
        "/api/companies/gis-layers",
        data={"name": "مباني", "group": "تجربة"},
        files={"file": ("b.geojson", io.BytesIO(json.dumps(fc).encode()),
                        "application/json")},
    )
    assert r.status_code == 200, r.text
    lid = r.json()["id"]
    n = client.post(f"/api/companies/gis-layers/{lid}/number", json={"gov": "بغداد"})
    assert n.status_code == 200, n.text
    assert n.json()["numbered"] == 2
    got = client.get(f"/api/companies/gis-layers/{lid}").json()["geojson"]
    p0 = got["features"][0]["properties"]
    assert p0["iqpin"] == "8L8L865FMT"          # مطابق للدراسة
    assert p0["npn_display"].startswith("10-")   # بغداد = كتلة 10
    assert len(p0["npn"]) == 11


def test_number_layer_skips_out_of_box(client):
    """ميزة خارج العراق تُتخطّى (لا NPN)."""
    fc = {"type": "FeatureCollection", "features": [
        {"type": "Feature",
         "geometry": {"type": "Point", "coordinates": [-1.5, 53.8]},  # بريطانيا
         "properties": {}},
    ]}
    r = client.post(
        "/api/companies/gis-layers",
        data={"name": "أجنبي"},
        files={"file": ("o.geojson", io.BytesIO(json.dumps(fc).encode()),
                        "application/json")},
    )
    lid = r.json()["id"]
    n = client.post(f"/api/companies/gis-layers/{lid}/number", json={"gov_code": 10})
    assert n.status_code == 200
    assert n.json()["numbered"] == 0 and n.json()["skipped"] == 1


def test_addressing_encode_reverse(client):
    """encode/reverse للعنونة (IQ-Pin ↔ إحداثيات)."""
    e = client.get("/api/companies/addressing/encode",
                   params={"lat": 33.3389, "lon": 44.4009})
    assert e.status_code == 200 and e.json()["iqpin"] == "8L8L865FMT"
    rv = client.get("/api/companies/addressing/reverse",
                    params={"code": "8L8-L86-5FMT"})
    assert rv.status_code == 200 and abs(rv.json()["lat"] - 33.3389) < 0.01


def test_demo_houses_are_numbered_subscribers(client):
    """منازل تجريبية: تُنشأ كمشتركين على منازل، ومرقّمة تلقائياً (NPN+IQ-Pin)."""
    r = client.post("/api/companies/gis-layers/demo-houses")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["feature_count"] == 42
    assert body["group_name"] == "منازل تجريبية"
    assert "center" in body
    lid = body["id"]
    got = client.get(f"/api/companies/gis-layers/{lid}").json()["geojson"]
    p = got["features"][0]["properties"]
    assert p["subscriber"] and p["status"] in ("active", "expired")
    assert len(p["npn"]) == 11 and len(p["iqpin"]) == 10
    assert p["iqpin"].startswith("8L")  # كتلة بغداد (المستوى 2)
    assert p["npn_display"].startswith("10-")


def test_addressing_reverse_rejects_long_code(client):
    """رمز reverse طويل جداً → 400 (منع DoS)."""
    r = client.get("/api/companies/addressing/reverse",
                   params={"code": "8L" * 50})
    assert r.status_code == 400


def test_number_two_layers_no_npn_overlap(client):
    """طبقتان في نفس المحافظة → NPN غير متداخلة (العدّاد يتقدّم ذرّياً)."""
    def mk(lon):
        return {"type": "FeatureCollection", "features": [
            {"type": "Feature",
             "geometry": {"type": "Point", "coordinates": [lon, 33.33]},
             "properties": {}}]}
    npns = []
    for i in range(2):
        r = client.post(
            "/api/companies/gis-layers", data={"name": f"L{i}"},
            files={"file": (f"l{i}.geojson",
                            io.BytesIO(json.dumps(mk(44.40 + i * 0.001)).encode()),
                            "application/json")})
        lid = r.json()["id"]
        client.post(f"/api/companies/gis-layers/{lid}/number",
                    json={"gov_code": 10})
        g = client.get(f"/api/companies/gis-layers/{lid}").json()["geojson"]
        npns.append(g["features"][0]["properties"]["npn"])
    assert npns[0] != npns[1]


def test_number_layer_requires_valid_gov(client):
    fc = {"type": "FeatureCollection", "features": [
        {"type": "Feature",
         "geometry": {"type": "Point", "coordinates": [44.40, 33.33]},
         "properties": {}}]}
    r = client.post(
        "/api/companies/gis-layers", data={"name": "x"},
        files={"file": ("x.geojson", io.BytesIO(json.dumps(fc).encode()),
                        "application/json")})
    lid = r.json()["id"]
    n = client.post(f"/api/companies/gis-layers/{lid}/number", json={})
    assert n.status_code == 400


# ══════════════════════════════════════════════════════════════════════
# 7) Shapefile → 400 برسالة توجيهية
# ══════════════════════════════════════════════════════════════════════

def test_upload_shapefile_zip_returns_400(client):
    """Shapefile .zip → 400 برسالة تحويل."""
    r = client.post(
        "/api/companies/gis-layers",
        data={"name": "شيب-فايل"},
        files={"file": ("roads.zip", io.BytesIO(b"PK\x03\x04fake"), "application/zip")},
    )
    assert r.status_code == 400
    assert "QGIS" in r.json().get("detail", "")


def test_upload_shapefile_shp_returns_400(client):
    """Shapefile .shp → 400 برسالة تحويل."""
    r = client.post(
        "/api/companies/gis-layers",
        data={"name": "شيب"},
        files={"file": ("roads.shp", io.BytesIO(b"\x00\x00\x27\x0afakeshp"), "application/octet-stream")},
    )
    assert r.status_code == 400
    assert "GeoJSON" in r.json().get("detail", "")


def test_upload_unknown_extension_returns_400(client):
    """امتداد غير معروف → 400."""
    r = client.post(
        "/api/companies/gis-layers",
        data={"name": "مجهول"},
        files={"file": ("data.csv", io.BytesIO(b"lat,lng\n33.31,44.36"), "text/csv")},
    )
    assert r.status_code == 400


# ══════════════════════════════════════════════════════════════════════
# 8) عزل طبقات GIS
# ══════════════════════════════════════════════════════════════════════

def test_gis_layer_scope_company_user_sees_public_and_own(client):
    """مستخدم شركة يرى الطبقات العامّة + طبقات شركته فقط."""
    content = json.dumps(_VALID_GEOJSON, ensure_ascii=False).encode()

    with Session(engine) as db:
        ca = _create_company(db, "ش-gis", "CGIS", governorate="بغداد")
        cb = _create_company(db, "ش-gis2", "CGIS2", governorate="البصرة")
        _create_user(db, "gis_user_a", "admin", company_id=ca.id)

    with Session(engine) as db:
        ca = db.exec(select(Company).where(Company.code == "CGIS")).first()
        cb = db.exec(select(Company).where(Company.code == "CGIS2")).first()

    h_a = _tok(client, "gis_user_a")
    h_gov = _tok(client, "admin", "admin")

    # رفع طبقة عامّة (company_id=None)
    client.post(
        "/api/companies/gis-layers",
        data={"name": "طبقة-عامّة"},
        files={"file": ("pub.geojson", io.BytesIO(content), "application/json")},
        headers=h_gov,
    )
    # رفع طبقة لشركة A
    client.post(
        "/api/companies/gis-layers",
        data={"name": "طبقة-أ", "company_id": str(ca.id)},
        files={"file": ("a.geojson", io.BytesIO(content), "application/json")},
        headers=h_gov,
    )
    # رفع طبقة لشركة B
    client.post(
        "/api/companies/gis-layers",
        data={"name": "طبقة-ب", "company_id": str(cb.id)},
        files={"file": ("b.geojson", io.BytesIO(content), "application/json")},
        headers=h_gov,
    )

    # مستخدم A يرى العامّة + طبقة-أ فقط
    r = client.get("/api/companies/gis-layers", headers=h_a)
    assert r.status_code == 200
    names = {l["name"] for l in r.json()["layers"]}
    assert "طبقة-عامّة" in names
    assert "طبقة-أ" in names
    assert "طبقة-ب" not in names


def test_gis_layer_company_user_cannot_read_other_company(client):
    """مستخدم شركة A لا يقرأ طبقة شركة B عبر GET /gis-layers/{id}."""
    content = json.dumps(_VALID_GEOJSON, ensure_ascii=False).encode()

    with Session(engine) as db:
        ca = _create_company(db, "ش-rA", "CGRA", governorate="بغداد")
        cb = _create_company(db, "ش-rB", "CGRB", governorate="البصرة")
        _create_user(db, "grA_user", "admin", company_id=ca.id)

    with Session(engine) as db:
        ca = db.exec(select(Company).where(Company.code == "CGRA")).first()
        cb = db.exec(select(Company).where(Company.code == "CGRB")).first()

    h_gov = _tok(client, "admin", "admin")
    h_a = _tok(client, "grA_user")

    # رفع طبقة لشركة B بواسطة الجهة الرقابية
    r = client.post(
        "/api/companies/gis-layers",
        data={"name": "طبقة-B-private", "company_id": str(cb.id)},
        files={"file": ("b.geojson", io.BytesIO(content), "application/json")},
        headers=h_gov,
    )
    assert r.status_code == 200
    b_layer_id = r.json()["id"]

    # مستخدم A لا يستطيع قراءتها
    r2 = client.get(f"/api/companies/gis-layers/{b_layer_id}", headers=h_a)
    assert r2.status_code == 404


# ══════════════════════════════════════════════════════════════════════
# 9) انحدار — المسارات القديمة لا تزال تعمل
# ══════════════════════════════════════════════════════════════════════

def test_regression_companies_list(client):
    """/api/companies لا يزال يعمل."""
    r = client.get("/api/companies")
    assert r.status_code == 200


def test_regression_subscribers_map(client):
    """/api/companies/subscribers/map لا يزال يعمل."""
    r = client.get("/api/companies/subscribers/map")
    assert r.status_code == 200
    assert "points" in r.json()


def test_regression_national_overview(client):
    """/api/companies/overview/national لا يزال يعمل."""
    r = client.get("/api/companies/overview/national")
    assert r.status_code == 200


def test_regression_agents(client):
    """/api/companies/agents/all لا يزال يعمل."""
    r = client.get("/api/companies/agents/all")
    assert r.status_code == 200
    assert "agents" in r.json()
