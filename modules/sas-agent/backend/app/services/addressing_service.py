"""خدمة ترقيم الطبقات — تربط محرّك العنونة NAS-IQ بطبقات GIS المخزّنة.

تأخذ طبقة مبانٍ (GeoJSON مخزّن) وتكتب لكل ميزة داخل صندوق العراق:
  npn / npn_display / iqpin / iqpin_display  (+ hno/street_side/street_name عند
  توفّر طبقة شوارع). تُخصَّص أرقام NPN تسلسلياً من عدّاد المحافظة (NpnCounter).
"""
from __future__ import annotations

import json
import threading
from typing import Optional, Tuple

import httpx
from sqlmodel import Session

from ..models import GisLayer, NpnCounter

# قفل عملية واحد يُسلسل حجز كتلة NPN (يمنع تكرار الرقم تحت التزامن على نفس
# العملية). ملاحظة: لا يصمد عبر عدّة عمليات/خوادم — عند النشر الأفقي (المرحلة E)
# يجب استبداله بتخصيص ذرّي على مستوى القاعدة (UPDATE … RETURNING / تسلسل).
_npn_lock = threading.Lock()
from ..core.addressing import (
    build_npn,
    npn_display,
    iqpin_encode,
    iqpin_display,
    geometry_point,
    in_iraq_box,
    number_along_streets,
)


def allocate_npns(db: Session, gov_code: int, count: int) -> list:
    """يحجز `count` رقم NPN متتالياً من كتلة المحافظة (ذرّياً) ويقدّم العدّاد.

    الحجز يُثبَّت فوراً (commit) داخل القفل لضمان تفرّد NPN حتى لو فشل ما بعده
    (قد تُهدر أرقام عند الفشل الجزئي — مقبول، أفضل من التكرار)."""
    with _npn_lock:
        ctr = db.get(NpnCounter, gov_code)
        if ctr is None:
            ctr = NpnCounter(gov_code=gov_code, next_seq=0)
        start = ctr.next_seq
        ctr.next_seq = start + count
        db.add(ctr)
        db.commit()          # ثبّت الحجز قبل تحرير القفل
        db.refresh(ctr)
    return [build_npn(gov_code, start + i) for i in range(count)]


def _streets_from_layer(layer: Optional[GisLayer]) -> list:
    """يستخرج محاور الشوارع (LineString) من طبقة GIS كمدخل لترقيم الشوارع."""
    if layer is None:
        return []
    try:
        fc = json.loads(layer.geojson)
    except json.JSONDecodeError:
        return []
    streets = []
    for i, f in enumerate(fc.get("features", [])):
        geom = (f or {}).get("geometry") or {}
        props = (f or {}).get("properties") or {}
        name = props.get("name") or props.get("street_name") or f"st{i}"
        if geom.get("type") == "LineString" and isinstance(geom.get("coordinates"), list):
            streets.append({"id": f"{layer.id}:{i}", "name": name,
                            "coords": geom["coordinates"]})
        elif geom.get("type") == "MultiLineString" and isinstance(geom.get("coordinates"), list):
            for j, line in enumerate(geom["coordinates"]):
                streets.append({"id": f"{layer.id}:{i}:{j}", "name": name,
                                "coords": line})
    return streets


def number_layer(db: Session, layer: GisLayer, gov_code: int,
                 street_layer: Optional[GisLayer] = None) -> dict:
    """يُرقّم مباني الطبقة (NPN + IQ-Pin + رقم دار اختياري) ويعيد ملخّصاً.

    يكتب النتائج في خصائص كل ميزة داخل geojson الطبقة (لا يمسّ الهندسة).
    الميزات خارج صندوق العراق تُتخطّى (تُبلَّغ في skipped).
    """
    fc = json.loads(layer.geojson)
    feats = fc.get("features", [])

    # المباني القابلة للترقيم (نقطة داخل صندوق العراق)
    targets = []  # (feature_index, lat, lon)
    skipped = 0
    for idx, f in enumerate(feats):
        try:
            lat, lon = geometry_point((f or {}).get("geometry") or {})
        except (ValueError, TypeError, KeyError):
            skipped += 1
            continue
        if not in_iraq_box(lat, lon):
            skipped += 1
            continue
        targets.append((idx, lat, lon))

    if not targets:
        return {"numbered": 0, "skipped": skipped, "streets_used": 0,
                "with_house_no": 0}

    # ترقيم الشوارع (اختياري)
    street_res = {}
    streets = _streets_from_layer(street_layer)
    if streets:
        buildings = [{"id": idx, "lat": lat, "lon": lon}
                     for idx, lat, lon in targets]
        street_res = number_along_streets(buildings, streets)

    # تخصيص NPN + كتابة الخصائص
    npns = allocate_npns(db, gov_code, len(targets))
    with_hno = 0
    for (idx, lat, lon), npn in zip(targets, npns):
        props = feats[idx].setdefault("properties", {})
        props["npn"] = npn
        props["npn_display"] = npn_display(npn)
        pin = iqpin_encode(lat, lon)
        props["iqpin"] = pin
        props["iqpin_display"] = iqpin_display(pin)
        sr = street_res.get(idx)
        if sr and "hno" in sr:
            props["hno"] = sr["hno"]
            props["street_side"] = sr["side"]
            if sr.get("street_name"):
                props["street_name"] = sr["street_name"]
            with_hno += 1

    layer.geojson = json.dumps(fc, ensure_ascii=False)
    db.add(layer)
    db.commit()
    return {"numbered": len(targets), "skipped": skipped,
            "streets_used": len(streets), "with_house_no": with_hno,
            "gov_code": gov_code}


# ══════════════════════ استيراد محاور الشوارع من OSM ══════════════════════
_OVERPASS_URL = "https://overpass-api.de/api/interpreter"
_MAX_BBOX_DEG2 = 0.5   # سقف مساحة الصندوق (درجة²) — يمنع استعلامات ضخمة


def _coords_iter(geom: dict):
    """يمرّ على كل [lon, lat] في هندسة GeoJSON (أي نوع)."""
    c = (geom or {}).get("coordinates")
    if c is None:
        return

    def walk(x):
        if isinstance(x, list) and x and isinstance(x[0], (int, float)):
            if len(x) >= 2:
                yield x
        elif isinstance(x, list):
            for sub in x:
                yield from walk(sub)
    yield from walk(c)


def geojson_bbox(fc: dict) -> Optional[Tuple[float, float, float, float]]:
    """صندوق (south, west, north, east) لكل ميزات FeatureCollection."""
    s = w = n = e = None
    for f in fc.get("features", []):
        for lon, lat in _coords_iter((f or {}).get("geometry") or {}):
            lon = float(lon); lat = float(lat)
            s = lat if s is None else min(s, lat)
            n = lat if n is None else max(n, lat)
            w = lon if w is None else min(w, lon)
            e = lon if e is None else max(e, lon)
    if s is None:
        return None
    return (s, w, n, e)


def parse_overpass_ways(data: dict) -> dict:
    """يحوّل استجابة Overpass (out geom) إلى GeoJSON FeatureCollection (LineString)."""
    feats = []
    for el in data.get("elements", []):
        if el.get("type") != "way":
            continue
        geom = el.get("geometry") or []
        coords = [[p["lon"], p["lat"]] for p in geom
                  if "lon" in p and "lat" in p]
        if len(coords) < 2:
            continue
        tags = el.get("tags") or {}
        name = tags.get("name") or tags.get("name:ar") or tags.get("ref") \
            or tags.get("highway") or "شارع"
        feats.append({
            "type": "Feature",
            "geometry": {"type": "LineString", "coordinates": coords},
            "properties": {"name": name, "osm_id": el.get("id")},
        })
    return {"type": "FeatureCollection", "features": feats}


def fetch_osm_streets(bbox: Tuple[float, float, float, float],
                      timeout: float = 40.0, transport=None) -> dict:
    """يجلب محاور الشوارع (highway) من OSM/Overpass ضمن الصندوق → GeoJSON.

    يرفع ValueError إن كان الصندوق كبيراً جداً أو تعذّر الاتصال."""
    s, w, n, e = bbox
    if (n - s) * (e - w) > _MAX_BBOX_DEG2:
        raise ValueError("المنطقة كبيرة جداً لاستيراد الشوارع — قسّمها")
    query = (
        f"[out:json][timeout:30];"
        f'(way["highway"]({s},{w},{n},{e}););'
        f"out geom;"
    )
    headers = {
        # Overpass يحجب UA الافتراضي؛ يتطلّب تعريفاً واضحاً + Accept
        "User-Agent": "iraq-digital-platform-NAS-IQ/1.0 (national addressing; contact admin)",
        "Accept": "application/json",
    }
    try:
        client = (httpx.Client(timeout=timeout, transport=transport, headers=headers)
                  if transport is not None
                  else httpx.Client(timeout=timeout, headers=headers))
        with client:
            resp = client.post(_OVERPASS_URL, data={"data": query})
            resp.raise_for_status()
            data = resp.json()
    except Exception as ex:  # noqa: BLE001
        raise ValueError(f"تعذّر جلب الشوارع من OSM: {ex}")
    return parse_overpass_ways(data)


def import_streets_layer(db: Session, building_layer: GisLayer,
                         transport=None) -> Optional[GisLayer]:
    """ينشئ طبقة شوارع (من OSM) تغطّي امتداد طبقة المباني ويحفظها.

    يعيد الطبقة الجديدة، أو يرفع ValueError عند الفشل/غياب الإحداثيات."""
    try:
        fc = json.loads(building_layer.geojson)
    except json.JSONDecodeError:
        raise ValueError("طبقة المباني تالفة")
    bbox = geojson_bbox(fc)
    if bbox is None:
        raise ValueError("لا إحداثيات في طبقة المباني")
    streets = fetch_osm_streets(bbox, transport=transport)
    layer = GisLayer(
        name=f"شوارع {building_layer.name}",
        group_name="الشوارع",
        kind="street",
        company_id=building_layer.company_id,
        geojson=json.dumps(streets, ensure_ascii=False),
        feature_count=len(streets.get("features", [])),
    )
    db.add(layer)
    db.commit()
    db.refresh(layer)
    return layer
