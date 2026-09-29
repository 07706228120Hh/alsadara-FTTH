"""
DfoS — الاستشعار الليفي الموزّع (Distributed Fiber Optic Sensing).

يحوّل كابل الألياف نفسه إلى مستشعر اهتزاز موزّع يكشف الأحداث الفيزيائية على طول
المسار (حفر، قطع، تسلّق، مرور آليات...). يبني هذا الملف صورة حتمية للنظام كاملاً
فوق مسارات الألياف المعرّفة في `national._ROUTES`:

    ليف مراقبة داخل الكابل → جهاز DfoS (interrogator) → خادم تصنيف الاهتزازات
      → منصّة GIS للمسارات → [إنذار الصيانة · إشعار الوكيل · موقع على الخريطة
                              · تشغيل أقرب كاميرا · فتح تذكرة حادث تلقائياً]

لكل حدث تهديد تُبنى «سلسلة الحزمة الكاملة» أعلاه حتمياً. التذكرة التلقائية
محتسبة داخل الحدث (بلا تلويث للتخزين)، ويوفّر `dispatch()` تصعيداً صريحاً يُنشئ
تذكرة فعلية في سجلّ المشاكل. كل الأرقام تُشتق من بذرة ثابتة فتبقى مستقرّة.
"""
import math
import random
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional

from . import national
from . import agents as agents_svc
from . import issues as issues_svc

# ── تصنيف الاهتزازات: (المفتاح، الوسم، الشدّة، تهديد؟، مدى التردد Hz، الوصف) ──
# الشدّة من مفردات الواجهة: critical / major / warning / minor
_EVENT_TYPES = [
    ("fiber_cut", "قطع ليف", "critical", True, (5, 40),
     "توقيع اهتزاز قطع مفاجئ يتبعه فقد إشارة."),
    ("excavator", "حفّار / معدّة ثقيلة", "critical", True, (8, 60),
     "اهتزاز دوري عالي السعة قرب المسار — خطر قطع وشيك."),
    ("manual_digging", "حفر يدوي", "major", True, (10, 80),
     "نمط ضربات متقطّع يدلّ على حفر يدوي فوق الكابل."),
    ("tampering", "عبث / تسلّق على غرفة تفتيش", "major", True, (20, 120),
     "اهتزاز موضعي على غرفة تفتيش (Handhole) — محاولة وصول."),
    ("vehicle", "مرور آليات", "minor", False, (1, 15),
     "توقيع مرور مركبات فوق مسار الكابل — ضمن الطبيعي."),
    ("machinery", "معدّات قريبة", "warning", False, (15, 90),
     "اهتزاز معدّات على مسافة — مراقبة احترازية."),
    ("footsteps", "حركة مشاة", "minor", False, (1, 8),
     "توقيع خطى مشاة قرب المسار — ضمن الطبيعي."),
]
_EVENT_META = {e[0]: e for e in _EVENT_TYPES}

# ترجمة شدّة الحدث إلى شدّة بلاغ سجلّ المشاكل (issues)
_SEVERITY_TO_ISSUE = {
    "critical": "حرج", "major": "عالٍ", "warning": "متوسط", "minor": "منخفض",
}
# نوع بلاغ المشاكل حسب صنف الحدث
_TYPE_TO_ISSUE = {
    "fiber_cut": "قطع ألياف (Fiber Cut)",
    "excavator": "قطع ألياف (Fiber Cut)",
    "manual_digging": "قطع ألياف (Fiber Cut)",
    "tampering": "إنذار جهاز (Hardware)",
}

_STATUS_LABELS = {
    "active": "نشط",
    "acknowledged": "قيد المعالجة",
    "resolved": "مُغلق",
}


# ---------------------------------------------------------------------------
# هندسة المسارات (تحديد الموقع على طول الليف)
# ---------------------------------------------------------------------------

def _seg_km(a, b) -> float:
    """مسافة تقريبية (كم) بين نقطتين (equirectangular)."""
    (la1, ln1), (la2, ln2) = a, b
    x = math.radians(ln2 - ln1) * math.cos(math.radians((la1 + la2) / 2))
    y = math.radians(la2 - la1)
    return math.sqrt(x * x + y * y) * 6371.0


def _route_length_km(coords: List) -> float:
    return sum(_seg_km(coords[i], coords[i + 1]) for i in range(len(coords) - 1))


def _point_on_route(coords: List, frac: float):
    """إحداثيات نقطة على نسبة [0..1] من طول المسار (lat, lng)."""
    if not coords:
        return (0.0, 0.0)
    if len(coords) == 1:
        return tuple(coords[0])
    total = _route_length_km(coords)
    target = max(0.0, min(1.0, frac)) * total
    acc = 0.0
    for i in range(len(coords) - 1):
        seg = _seg_km(coords[i], coords[i + 1])
        if acc + seg >= target and seg > 0:
            t = (target - acc) / seg
            la = coords[i][0] + (coords[i + 1][0] - coords[i][0]) * t
            ln = coords[i][1] + (coords[i + 1][1] - coords[i][1]) * t
            return (round(la, 6), round(ln, 6))
        acc += seg
    return tuple(coords[-1])


def _nearest_governorate(lat: float, lng: float) -> str:
    best, bestd = national._GOVERNORATES[0][0], 1e9
    for name, _w, glat, glng in national._GOVERNORATES:
        d = (lat - glat) ** 2 + (lng - glng) ** 2
        if d < bestd:
            best, bestd = name, d
    return best


def _company_for_gov(gov: str) -> str:
    """الشركة صاحبة أكبر جهاز OLT في المحافظة (لإسناد التذكرة/الوكيل)."""
    best = None
    for d in national._FLEET:
        if d["governorate"] != gov:
            continue
        if best is None or d["subscribers"] > best["subscribers"]:
            best = d
    return best["company"] if best else national._COMPANIES[0]


# ---------------------------------------------------------------------------
# البنية الثابتة: أجهزة DfoS والكاميرات
# ---------------------------------------------------------------------------

def _monitored_routes() -> List[Dict]:
    """المسارات الخاضعة للاستشعار: الدولية + بين المحافظات + شبكات الشركات."""
    return [r for r in national._ROUTES
            if r["type"] in ("international", "inter_governorate", "network")]


_ROUTES_BY_ID = {r["id"]: r for r in national._ROUTES}

# (المعرّف، الموقع، المحافظة، lat, lng, مسارات مراقَبة، مدى الاستشعار كم)
_SENSOR_DEFS = [
    ("DFOS-01", "مركز السيطرة الوطني — بغداد", "بغداد", 33.3152, 44.3661,
     ["intl-0", "intl-1", "intl-2", "intl-3"], 120),
    ("DFOS-02", "عقدة البصرة الحدودية", "البصرة", 30.5156, 47.7804,
     ["intl-4", "intl-5"], 140),
    ("DFOS-03", "عقدة الموصل الشمالية", "نينوى", 36.3356, 43.1358,
     ["intl-2", "intl-9"], 95),
    ("DFOS-04", "عقدة كركوك", "كركوك", 35.4669, 44.3923,
     ["intl-7", "intl-8"], 110),
    ("DFOS-05", "عقدة الأنبار الغربية", "الأنبار", 33.4256, 43.3006,
     ["intl-0", "intl-1"], 130),
]


def _build_sensors() -> List[Dict]:
    rng = random.Random(20260726)
    sensors: List[Dict] = []
    for i, (sid, site, gov, lat, lng, routes, rng_km) in enumerate(_SENSOR_DEFS):
        # جهاز واحد متدهور لأغراض العرض، والبقية متصلة
        status = "degraded" if i == 3 else "online"
        sensors.append({
            "id": sid,
            "name": site,
            "governorate": gov,
            "lat": lat,
            "lng": lng,
            "routes": routes,
            "range_km": rng_km,
            "channels": rng.choice([2, 4, 4, 8]),
            "sample_rate_hz": rng.choice([1000, 2000, 5000]),
            "status": status,
        })
    return sensors


_SENSORS = _build_sensors()
_SENSOR_BY_ROUTE: Dict[str, str] = {}
for _s in _SENSORS:
    for _rid in _s["routes"]:
        _SENSOR_BY_ROUTE.setdefault(_rid, _s["id"])


def _build_cameras() -> List[Dict]:
    """كاميرات مراقبة موزّعة على المسارات الدولية (نقطتان لكل مسار)."""
    rng = random.Random(20260727)
    cams: List[Dict] = []
    intl = [r for r in national._ROUTES if r["type"] == "international"]
    cid = 0
    for r in intl:
        for frac in (0.35, 0.72):
            cid += 1
            lat, lng = _point_on_route(r["coordinates"], frac)
            cams.append({
                "id": f"CAM-{cid:03d}",
                "name": f"كاميرا {r['name'].split(':')[0]} م{cid}",
                "route_id": r["id"],
                "frac": frac,
                "lat": lat,
                "lng": lng,
                "type": rng.choice(["PTZ", "PTZ", "ثابتة"]),
                "status": "online" if rng.random() > 0.12 else "offline",
            })
    # كاميرات مدنية عند مراكز المحافظات — لتغطية الأحداث خارج المسارات الدولية
    for name, _w, lat, lng in national._GOVERNORATES:
        cid += 1
        cams.append({
            "id": f"CAM-{cid:03d}",
            "name": f"كاميرا مدينة {name}",
            "route_id": None,
            "frac": None,
            "lat": round(lat + rng.uniform(-0.03, 0.03), 6),
            "lng": round(lng + rng.uniform(-0.03, 0.03), 6),
            "type": rng.choice(["PTZ", "ثابتة"]),
            "status": "online" if rng.random() > 0.10 else "offline",
        })
    return cams


_CAMERAS = _build_cameras()


def _nearest_camera(lat: float, lng: float, route_id: Optional[str]) -> Optional[Dict]:
    """أقرب كاميرا متصلة (تُفضّل كاميرات نفس المسار)."""
    pool = [c for c in _CAMERAS if c["status"] == "online"]
    if not pool:
        return None
    same = [c for c in pool if c["route_id"] == route_id]
    search = same or pool
    best, bestd = None, 1e18
    for c in search:
        d = _seg_km((lat, lng), (c["lat"], c["lng"]))
        if d < bestd:
            best, bestd = c, d
    if best is None:
        return None
    return {
        "id": best["id"], "name": best["name"], "type": best["type"],
        "distance_km": round(bestd, 2), "status": "triggered",
        "lat": best["lat"], "lng": best["lng"],
    }


def _nearest_agent(gov: str, company: str, rng: random.Random) -> Optional[Dict]:
    """أقرب وكيل مسؤول: نفس المحافظة والشركة، ثم المحافظة، ثم أي وكيل نشط."""
    pool = agents_svc._AGENTS
    same = [a for a in pool if a["governorate"] == gov and a["company"] == company
            and a["status"] == "active"]
    by_gov = [a for a in pool if a["governorate"] == gov and a["status"] == "active"]
    active = [a for a in pool if a["status"] == "active"]
    chosen = (same or by_gov or active or pool)
    if not chosen:
        return None
    a = chosen[rng.randrange(len(chosen))]
    return {
        "id": a["id"], "name": a["name"], "office": a["office"],
        "company": a["company"], "governorate": a["governorate"],
        "phone": a["phone"], "distance_km": round(rng.uniform(0.8, 18.0), 1),
    }


# ---------------------------------------------------------------------------
# الأحداث + سلسلة الحزمة الكاملة
# ---------------------------------------------------------------------------

_NOW = datetime.now(timezone.utc)


def _age_label(minutes: int) -> str:
    if minutes < 60:
        return f"منذ {minutes} دقيقة"
    if minutes < 1440:
        return f"منذ {minutes // 60} ساعة"
    return f"منذ {minutes // 1440} يوم"


def _build_events() -> List[Dict]:
    rng = random.Random(20260728)  # بذرة ثابتة → أحداث مستقرّة
    routes = _monitored_routes()
    # ترجيح: المسارات الدولية أكثر عرضة للرصد الحرج
    weights = [3 if r["type"] == "international"
               else (2 if r["type"] == "inter_governorate" else 1)
               for r in routes]
    type_keys = [e[0] for e in _EVENT_TYPES]
    # ترجيح الأنواع: التهديدات أندر من الأحداث الطبيعية
    type_weights = [0.10, 0.08, 0.12, 0.10, 0.24, 0.16, 0.20]

    events: List[Dict] = []
    for i in range(34):
        route = rng.choices(routes, weights)[0]
        coords = route["coordinates"]
        frac = rng.uniform(0.05, 0.95)
        lat, lng = _point_on_route(coords, frac)
        gov = _nearest_governorate(lat, lng)
        position_km = round(_route_length_km(coords) * frac, 2)

        key = rng.choices(type_keys, type_weights)[0]
        _k, label, severity, threat, freq_rng, desc = _EVENT_META[key]
        amplitude = round(rng.uniform(0.3, 1.0)
                          * (1.4 if threat else 0.7), 2)  # سعة نسبية 0..~1.4
        freq_hz = round(rng.uniform(*freq_rng), 1)
        confidence = round(rng.uniform(0.82, 0.99) if threat
                           else rng.uniform(0.60, 0.90), 2)
        # التهديدات أحدث (حتى 10 ساعات) فيبقى منها نشط؛ الأحداث الطبيعية أقدم
        minutes_ago = rng.randint(2, 600) if threat else rng.randint(30, 60 * 36)
        occurred_at = (_NOW - timedelta(minutes=minutes_ago)).isoformat(
            timespec="seconds")

        sensor_id = _SENSOR_BY_ROUTE.get(route["id"])
        if sensor_id is None:
            # أقرب جهاز حسب المسافة لأول إحداثي
            sensor_id = min(_SENSORS,
                            key=lambda s: _seg_km((lat, lng), (s["lat"], s["lng"]))
                            )["id"]

        company = (route.get("company") if route["type"] == "network"
                   else _company_for_gov(gov)) or national._COMPANIES[0]
        if company not in national._COMPANIES:
            company = _company_for_gov(gov)

        # حالة الحدث: التهديدات الحديثة (< 5 ساعات) نشطة، ثم قيد المعالجة؛
        # والأحداث الطبيعية غالباً مُغلقة.
        if threat:
            status = "active" if minutes_ago < 300 else "acknowledged"
        else:
            status = "resolved" if rng.random() > 0.25 else "acknowledged"

        eid = f"DFOS-EVT-{i + 1:05d}"
        event = {
            "id": eid,
            "route_id": route["id"],
            "route_name": route["name"],
            "route_type": route["type"],
            "sensor_id": sensor_id,
            "type": key,
            "type_label": label,
            "description": desc,
            "severity": severity,
            "threat": threat,
            "confidence": confidence,
            "amplitude": amplitude,
            "frequency_hz": freq_hz,
            "position_km": position_km,
            "lat": lat,
            "lng": lng,
            "governorate": gov,
            "company": company,
            "status": status,
            "status_label": _STATUS_LABELS[status],
            "minutes_ago": minutes_ago,
            "occurred_label": _age_label(minutes_ago),
            "occurred_at": occurred_at,
        }
        # سلسلة الحزمة الكاملة — للتهديدات فقط
        event["workflow"] = _build_workflow(event, rng) if threat else None
        events.append(event)

    events.sort(key=lambda e: e["minutes_ago"])  # الأحدث أولاً
    return events


def _build_workflow(event: Dict, rng: random.Random) -> Dict:
    """يبني سلسلة الاستجابة الحتمية: إنذار ← وكيل ← موقع ← كاميرا ← تذكرة."""
    gov, company = event["governorate"], event["company"]
    sla = {"critical": 4, "major": 8, "warning": 24, "minor": 48}[event["severity"]]

    alarm = {
        "uid": f"ALM-{event['id']}",
        "title": f"{event['type_label']} على {event['route_name']} — {gov}",
        "severity": event["severity"],
        "source_type": "dfos",
    }
    agent = _nearest_agent(gov, company, rng)
    location = {
        "lat": event["lat"], "lng": event["lng"],
        "route": event["route_name"], "governorate": gov,
        "position_km": event["position_km"],
        "landmark": f"مسار {event['route_name']} — كم {event['position_km']} ({gov})",
    }
    camera = _nearest_camera(event["lat"], event["lng"], event["route_id"])

    # تذكرة حادث تلقائية (محتسبة حتمياً — تُصعَّد فعلياً عبر dispatch)
    ticket = {
        "id": f"INC-D{int(event['id'].split('-')[-1]):04d}",
        "type": _TYPE_TO_ISSUE.get(event["type"], "إنذار جهاز (Hardware)"),
        "company": company,
        "governorate": gov,
        "severity": _SEVERITY_TO_ISSUE.get(event["severity"], "متوسط"),
        "sla_hours": sla,
        "status": "auto_open",
        "status_label": "مفتوحة تلقائياً",
        "auto": True,
        "dispatched": False,
    }
    return {"alarm": alarm, "agent": agent, "location": location,
            "camera": camera, "ticket": ticket}


_EVENTS = _build_events()
_EVENT_BY_ID = {e["id"]: e for e in _EVENTS}
# تذاكر مُصعّدة فعلياً خلال الجلسة {event_id: real_ticket_id}
_DISPATCHED: Dict[str, str] = {}


# ---------------------------------------------------------------------------
# التجميعات والواجهة العامة
# ---------------------------------------------------------------------------

def _totals(events: List[Dict]) -> Dict:
    threats = [e for e in events if e["threat"]]
    return {
        "sensors": len(_SENSORS),
        "sensors_online": sum(1 for s in _SENSORS if s["status"] == "online"),
        "cameras": len(_CAMERAS),
        "cameras_online": sum(1 for c in _CAMERAS if c["status"] == "online"),
        "events": len(events),
        "threats": len(threats),
        "threats_active": sum(1 for e in threats if e["status"] == "active"),
        "critical": sum(1 for e in events if e["severity"] == "critical"),
        "monitored_routes": len(_monitored_routes()),
        "monitored_km": round(sum(_route_length_km(r["coordinates"])
                                  for r in _monitored_routes()), 1),
    }


def _by_type(events: List[Dict]) -> List[Dict]:
    counts: Dict[str, int] = {}
    for e in events:
        counts[e["type"]] = counts.get(e["type"], 0) + 1
    out = [{"type": k, "label": _EVENT_META[k][1],
            "severity": _EVENT_META[k][2], "threat": _EVENT_META[k][3],
            "count": v} for k, v in counts.items()]
    out.sort(key=lambda x: x["count"], reverse=True)
    return out


def _public_event(e: Dict) -> Dict:
    """نسخة الحدث للعرض مع دمج حالة التصعيد الفعلي إن وُجد."""
    d = dict(e)
    if e["id"] in _DISPATCHED and e.get("workflow"):
        wf = {**e["workflow"]}
        tk = {**wf["ticket"], "dispatched": True,
              "status": "in_progress", "status_label": "قيد التنفيذ",
              "real_id": _DISPATCHED[e["id"]]}
        wf["ticket"] = tk
        d["workflow"] = wf
    return d


def overview(governorate: Optional[str] = None,
             threats_only: bool = False) -> Dict:
    """صورة DfoS الكاملة: أجهزة، كاميرات، أحداث، وتجميعات."""
    events = _EVENTS
    if governorate:
        events = [e for e in events if e["governorate"] == governorate]
    if threats_only:
        events = [e for e in events if e["threat"]]

    return {
        "scope": {"governorate": governorate, "threats_only": threats_only},
        "totals": _totals(events),
        "sensors": _SENSORS,
        "cameras": _CAMERAS,
        "events": [_public_event(e) for e in events],
        "by_type": _by_type(events),
        "filters": {
            "governorates": sorted({e["governorate"] for e in _EVENTS}),
            "types": [{"type": e[0], "label": e[1]} for e in _EVENT_TYPES],
        },
    }


def event_detail(event_id: str) -> Optional[Dict]:
    e = _EVENT_BY_ID.get(event_id)
    return _public_event(e) if e else None


def map_data(governorate: Optional[str] = None) -> Dict:
    """طبقة GIS: المسارات المراقَبة + أجهزة DfoS + الكاميرات + علامات الأحداث."""
    events = _EVENTS
    if governorate:
        events = [e for e in events if e["governorate"] == governorate]
    routes = [{"id": r["id"], "type": r["type"], "name": r["name"],
               "color": r["color"], "coordinates": r["coordinates"]}
              for r in _monitored_routes()]
    return {
        "scope": {"governorate": governorate},
        "routes": routes,
        "sensors": _SENSORS,
        "cameras": _CAMERAS,
        "events": [
            {"id": e["id"], "type": e["type"], "type_label": e["type_label"],
             "severity": e["severity"], "threat": e["threat"],
             "status": e["status"], "lat": e["lat"], "lng": e["lng"],
             "governorate": e["governorate"], "route_id": e["route_id"],
             "occurred_label": e["occurred_label"]}
            for e in events
        ],
    }


def dispatch(event_id: str) -> Dict:
    """تصعيد حدث تهديد: يُنشئ تذكرة حادث فعلية في سجلّ المشاكل (issues)."""
    e = _EVENT_BY_ID.get(event_id)
    if e is None:
        raise ValueError("حدث غير معروف")
    if not e["threat"]:
        raise ValueError("لا يُصعَّد إلا حدث تهديد.")

    wf = e.get("workflow") or {}
    tk = wf.get("ticket", {})
    desc = (f"[DfoS] {e['type_label']} على {e['route_name']} — "
            f"كم {e['position_km']} ({e['governorate']}). "
            f"ثقة التصنيف {int(e['confidence'] * 100)}%، "
            f"سعة {e['amplitude']}، تردد {e['frequency_hz']}Hz. "
            f"الحدث {e['id']}.")
    issue = issues_svc.create_issue(
        type=tk.get("type", "قطع ألياف (Fiber Cut)"),
        company=e["company"],
        severity=tk.get("severity", "حرج"),
        governorate=e["governorate"],
        description=desc,
    )
    _DISPATCHED[event_id] = issue["id"]
    return {
        "event_id": event_id,
        "ticket": issue,
        "message": f"تم فتح تذكرة الحادث {issue['id']} وإسنادها إلى {e['company']}.",
    }


# ---------------------------------------------------------------------------
# تحليل ذكي (قواعد محلية + Claude إن توفّر المفتاح)
# ---------------------------------------------------------------------------

def _rule_based_analysis(data: Dict) -> str:
    t = data["totals"]
    by_type = data["by_type"]
    lines: List[str] = ["🛰️ تحليل مراقبة الألياف (DfoS):"]
    lines.append(
        f"• {t['sensors']} جهاز استشعار ({t['sensors_online']} متصل) يراقب "
        f"{t['monitored_routes']} مساراً بطول {t['monitored_km']:,} كم.")
    lines.append(
        f"• {t['events']} حدث مرصود، منها {t['threats']} تهديد "
        f"({t['threats_active']} نشط، {t['critical']} حرج).")
    threats = [b for b in by_type if b["threat"] and b["count"] > 0]
    if threats:
        lines.append("⚠️ أبرز التهديدات: "
                     + "، ".join(f"{b['label']} ({b['count']})" for b in threats))
    if t["threats_active"] > 0:
        lines.append("• يُنصح بتصعيد التهديدات النشطة: إنذار الصيانة، إشعار الوكيل، "
                     "تشغيل أقرب كاميرا، وفتح تذكرة حادث.")
    else:
        lines.append("✅ لا تهديدات نشطة حالياً — النظام في وضع المراقبة الطبيعي.")
    lines.append("— (تحليل آلي من قواعد المحرّك؛ فعّل ANTHROPIC_API_KEY لتحليل أعمق.)")
    return "\n".join(lines)


def analyze(governorate: Optional[str] = None) -> Dict:
    """تحليل ذكي لمشهد تهديدات DfoS (Claude إن توفّر المفتاح، وإلا قواعد محلية)."""
    data = overview(governorate)
    try:
        from .ai_assistant import _get_client
        from ..config import settings
        client = _get_client()
        if client is not None:
            t = data["totals"]
            summary = (
                f"بيانات استشعار ليفي موزّع (DfoS) لشبكة ألياف العراق: "
                f"{t['sensors']} جهاز، {t['monitored_routes']} مسار، "
                f"{t['monitored_km']} كم، {t['events']} حدث، {t['threats']} تهديد "
                f"({t['threats_active']} نشط، {t['critical']} حرج). الأنواع: "
                + "، ".join(f"{b['label']}={b['count']}" for b in data["by_type"])
            )
            msg = client.messages.create(
                model=settings.ai_model,
                max_tokens=700,
                system=("أنت خبير أمن بنية تحتية للألياف الضوئية. حلّل مشهد تهديدات "
                        "الاستشعار الليفي الموزّع (حفر/قطع/عبث) بالعربية بإيجاز مهني: "
                        "المخاطر، الأولويات، وإجراءات الاستجابة. استخدم نقاطاً."),
                messages=[{"role": "user", "content": summary}],
            )
            text = "".join(b.text for b in msg.content
                           if getattr(b, "type", "") == "text")
            return {"analysis": text, "source": "claude", "totals": data["totals"]}
    except Exception:
        pass
    return {"analysis": _rule_based_analysis(data), "source": "rules",
            "totals": data["totals"]}
