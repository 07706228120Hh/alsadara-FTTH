"""اختبارات محرّك العنونة NAS-IQ — تتحقّق مقابل أمثلة الدراسة الحرفية."""
import math

import httpx
import pytest

from app.services.addressing_service import (
    geojson_bbox,
    parse_overpass_ways,
    fetch_osm_streets,
)
from app.core.addressing import (
    iqpin_encode,
    iqpin_decode,
    iqpin_display,
    luhn_check_digit,
    build_npn,
    npn_display,
    validate_npn,
    polygon_centroid,
    geometry_point,
    number_along_streets,
)


# أمثلة IQ-Pin من الدراسة (ص12-13) — يجب أن تتطابق حرفياً
@pytest.mark.parametrize("lat,lon,expected", [
    (33.3389, 44.4009, "8L8L865FMT"),   # ساحة التحرير، بغداد
    (30.5085, 47.7804, "KMLLP4F462"),   # البصرة
    (36.1911, 44.0092, "4CLC65LJL5"),   # أربيل
    (36.3350, 43.1189, "3JKFC9MLCL"),   # الموصل
])
def test_iqpin_matches_study(lat, lon, expected):
    assert iqpin_encode(lat, lon) == expected


def test_iqpin_display_grouping():
    assert iqpin_display("8L8L865FMT") == "8L8-L86-5FMT"


def test_iqpin_decode_accuracy_under_2m():
    """فكّ الترميز يعيد مركز الخلية ضمن ~1م من نقطة الإدخال."""
    lat, lon = 33.3389, 44.4009
    dlat, dlon = iqpin_decode(iqpin_encode(lat, lon))
    mlat = (dlat - lat) * 111320
    mlon = (dlon - lon) * 111320 * math.cos(math.radians(lat))
    assert math.hypot(mlat, mlon) < 2.0


def test_iqpin_hierarchical_prefix():
    """المواقع المتجاورة في بغداد تتشارك البادئة 8L8 (بحث هرمي)."""
    tahrir = iqpin_encode(33.3389, 44.4009)
    sadr = iqpin_encode(33.3980, 44.4700)
    assert tahrir[:3] == "8L8" and sadr[:3] == "8L8"


def test_iqpin_rejects_out_of_box():
    with pytest.raises(ValueError):
        iqpin_encode(48.0, 2.0)  # باريس — خارج العراق


# NPN + Luhn من الدراسة (ص12، الملحق أ)
def test_luhn_matches_study():
    assert luhn_check_digit("1004839221") == "0"


def test_build_npn_baghdad():
    npn = build_npn(10, 4839221)          # بغداد، تسلسل 04839221
    assert npn == "10048392210"
    assert npn_display(npn) == "10-0483-9221-0"
    assert validate_npn(npn)


def test_validate_npn_detects_typo():
    good = build_npn(10, 4839221)
    bad = good[:5] + ("9" if good[5] != "9" else "8") + good[6:]
    assert validate_npn(good)
    assert not validate_npn(bad)          # Luhn يكشف الخطأ


def test_build_npn_rejects_bad_input():
    with pytest.raises(ValueError):
        build_npn(0, 1)
    with pytest.raises(ValueError):
        build_npn(10, 100_000_000)


# استخراج النقطة من الهندسة
def test_polygon_centroid_square():
    ring = [[44.0, 33.0], [44.0, 33.2], [44.2, 33.2], [44.2, 33.0], [44.0, 33.0]]
    lat, lon = polygon_centroid(ring)
    assert abs(lat - 33.1) < 1e-6 and abs(lon - 44.1) < 1e-6


def test_geometry_point_polygon_then_iqpin():
    ring = [[44.4009, 33.3389], [44.4010, 33.3389],
            [44.4010, 33.3390], [44.4009, 33.3390], [44.4009, 33.3389]]
    lat, lon = geometry_point({"type": "Polygon", "coordinates": [ring]})
    assert 33.33 < lat < 33.34 and 44.40 < lon < 44.41
    assert len(iqpin_encode(lat, lon)) == 10


# ترقيم الشوارع: فردي جهة، زوجي الأخرى، تسلسلي على طول الشارع
def test_street_numbering_odd_even():
    street = {"id": "s1", "name": "شارع أ",
              "coords": [[44.400, 33.330], [44.410, 33.330]]}  # غرب→شرق
    buildings = [
        {"id": "n1", "lat": 33.331, "lon": 44.401},  # شمال (يسار)
        {"id": "n2", "lat": 33.331, "lon": 44.403},
        {"id": "n3", "lat": 33.331, "lon": 44.405},
        {"id": "s1b", "lat": 33.329, "lon": 44.402},  # جنوب (يمين)
        {"id": "s2b", "lat": 33.329, "lon": 44.404},
    ]
    res = number_along_streets(buildings, [street])
    # الشمال = يسار = فردي بترتيب المسافة
    assert res["n1"]["hno"] == 1 and res["n1"]["side"] == "left"
    assert res["n2"]["hno"] == 3
    assert res["n3"]["hno"] == 5
    # الجنوب = يمين = زوجي
    assert res["s1b"]["hno"] == 2 and res["s1b"]["side"] == "right"
    assert res["s2b"]["hno"] == 4
    assert res["n1"]["street_name"] == "شارع أ"


def test_street_numbering_skips_far_buildings():
    street = {"id": "s1", "name": "أ", "coords": [[44.40, 33.33], [44.41, 33.33]]}
    far = [{"id": "x", "lat": 34.50, "lon": 45.90}]  # بعيد جداً
    assert number_along_streets(far, [street], max_dist_m=200) == {}


# استيراد شوارع OSM (بلا شبكة — دوال نقية + MockTransport)
def test_geojson_bbox():
    fc = {"type": "FeatureCollection", "features": [
        {"type": "Feature",
         "geometry": {"type": "Point", "coordinates": [44.4, 33.3]},
         "properties": {}},
        {"type": "Feature",
         "geometry": {"type": "LineString",
                      "coordinates": [[44.5, 33.4], [44.6, 33.2]]},
         "properties": {}},
    ]}
    assert geojson_bbox(fc) == (33.2, 44.4, 33.4, 44.6)


def test_parse_overpass_ways():
    data = {"elements": [
        {"type": "way", "id": 1,
         "tags": {"highway": "residential", "name": "شارع أ"},
         "geometry": [{"lat": 33.3, "lon": 44.4}, {"lat": 33.31, "lon": 44.41}]},
        {"type": "way", "id": 2, "tags": {"highway": "service"},
         "geometry": [{"lat": 33.3, "lon": 44.4}]},  # نقطة واحدة → تُتجاهَل
        {"type": "node", "id": 3},
    ]}
    fc = parse_overpass_ways(data)
    assert len(fc["features"]) == 1
    f = fc["features"][0]
    assert f["geometry"]["type"] == "LineString"
    assert f["properties"]["name"] == "شارع أ"
    assert f["geometry"]["coordinates"][0] == [44.4, 33.3]


def test_fetch_osm_streets_mock():
    sample = {"elements": [
        {"type": "way", "id": 1,
         "tags": {"highway": "residential", "name": "X"},
         "geometry": [{"lat": 33.3, "lon": 44.4}, {"lat": 33.31, "lon": 44.41}]}]}
    tr = httpx.MockTransport(lambda req: httpx.Response(200, json=sample))
    fc = fetch_osm_streets((33.3, 44.4, 33.32, 44.42), transport=tr)
    assert len(fc["features"]) == 1


def test_fetch_osm_streets_rejects_huge_bbox():
    with pytest.raises(ValueError):
        fetch_osm_streets((28.0, 38.0, 38.0, 50.0))  # كل العراق → كبير جداً
