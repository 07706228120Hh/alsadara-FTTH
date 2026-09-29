"""
اللوحة الوطنية — صورة شاملة لأسطول OLT في العراق (بيانات محاكاة واقعية).

بما أن النظام يدير جهازاً واحداً في وضع التطوير، تُولَّد هنا صورة وطنية
حتمية (deterministic) لكل المحافظات والشركات والأجهزة، لعرض:
- عدد المحافظات والأجهزة والمشتركين وحجم البيانات لكل مستوى.
- التصفية حسب المحافظة/الشركة/الجهاز.
- تحليل ذكي (قواعد محلية + Claude إن توفّر المفتاح).
- خريطة ONTs: إحداثيات جغرافية للـ ONTs المرتبطة بكل جهاز OLT.

كل الأرقام تُشتق من بذرة ثابتة، فتبقى مستقرّة بين الطلبات.
"""
import math
import random
from typing import Dict, List, Optional, Tuple


# محافظات عراقية مع وزن تقريبي (عدد الأجهزة) ومركز جغرافي
_GOVERNORATES: List[Tuple[str, int, float, float]] = [
    ("بغداد", 40, 33.3152, 44.3661),
    ("البصرة", 18, 30.5156, 47.7804),
    ("نينوى", 16, 36.3356, 43.1358),
    ("ذي قار", 9, 31.2559, 46.7234),
    ("النجف", 9, 31.9924, 44.3140),
    ("بابل", 8, 32.4817, 44.4357),
    ("كركوك", 8, 35.4669, 44.3923),
    ("الأنبار", 8, 33.4256, 43.3006),
    ("ديالى", 7, 33.7735, 45.1494),
    ("كربلاء", 8, 32.6160, 44.0245),
    ("صلاح الدين", 6, 34.5979, 43.6839),
    ("واسط", 6, 32.5129, 45.8187),
    ("القادسية", 6, 31.9796, 44.9299),
    ("ميسان", 5, 31.8364, 47.1489),
    ("المثنى", 4, 30.1984, 46.2687),
]

# شركات مزوّدة خدمة الإنترنت (ISP/FTTH)
_COMPANIES = [
    "الصدارة نت", "إيرثلنك", "هلا", "الجزيرة", "سوبر سيل",
]

# أنواع الاتصال ووسومها العربية
_ACCESS_LABELS = {
    "ftth": "ألياف (FTTH)",
    "wireless": "وايرليس",
}

# أنواع الخدمة التي تجهّزها كل شركة (بعضها FTTH فقط، بعضها وايرليس فقط).
_COMPANY_ACCESS = {
    "الصدارة نت": ["ftth", "wireless"],
    "إيرثلنك": ["ftth"],
    "هلا": ["wireless"],
    "الجزيرة": ["ftth", "wireless"],
    "سوبر سيل": ["wireless"],
}

# ألوان مميزة لكل شركة (تستخدم في مسارات الشبكة وإحصائياتها)
_COMPANY_COLORS = {
    "الصدارة نت": "#22D3EE",  # cyan
    "إيرثلنك": "#34D399",     # green
    "هلا": "#FBBF24",         # amber
    "الجزيرة": "#E879F9",     # fuchsia
    "سوبر سيل": "#60A5FA",    # blue
}


_MODELS = ["MA5800-X17", "MA5800-X7", "MA5680T", "EA5800-X15"]


def _build_fleet() -> List[Dict]:
    rng = random.Random(20260719)  # بذرة ثابتة → بيانات مستقرّة
    fleet: List[Dict] = []
    did = 0
    for gov, count, lat, lng in _GOVERNORATES:
        for _ in range(count):
            did += 1
            company = rng.choice(_COMPANIES)
            access_type = rng.choice(_COMPANY_ACCESS[company])  # نوع الاتصال
            subs = rng.randint(180, 4200)                 # عدد المشتركين (ONT)
            per_sub = rng.uniform(3.5, 12.0)              # متوسط استهلاك Mbps
            thr = round(subs * per_sub / 1000.0, 2)       # حجم البيانات Gbps
            problems = rng.choices([0, 1, 2, 3, 5], [0.55, 0.22, 0.13, 0.07, 0.03])[0]
            r = rng.random()
            status = "online" if r > 0.09 else ("degraded" if r > 0.03 else "offline")
            # موقع الجهاز يحيد قليلاً عن مركز المحافظة
            olt_lat = lat + rng.uniform(-0.08, 0.08)
            olt_lng = lng + rng.uniform(-0.12, 0.12)
            fleet.append({
                "id": did,
                "name": f"OLT-{gov}-{did:03d}",
                "governorate": gov,
                "company": company,
                "access_type": access_type,
                "model": rng.choice(_MODELS),
                "subscribers": subs,
                "throughput_gbps": thr,
                "problems": problems,
                "status": status,
                "lat": round(olt_lat, 6),
                "lng": round(olt_lng, 6),
            })
    return fleet


_FLEET = _build_fleet()


def _build_onts() -> Dict[int, List[Dict]]:
    """تولّد ONTs لكل جهاز OLT مع إحداثيات حتمية حول موقع الجهاز."""
    rng = random.Random(20260720)  # بذرة منفصلة للـ ONTs
    onts: Dict[int, List[Dict]] = {}
    for olt in _FLEET:
        olt_onts: List[Dict] = []
        # عدد ONTs واقعي ولا يثقل الواجهة (5-25 لكل OLT)
        n = min(max(olt["subscribers"] // 120, 5), 25)
        for i in range(1, n + 1):
            port = rng.randint(0, 15)
            ont_id = i
            fsp = f"0/5/{port}"
            sn = f"48575443{rng.randint(0x10000000, 0xFFFFFFFF):08X}"
            desc = rng.choice([
                "منزل", "محل تجاري", "مقهى", "مدرسة", "عيادة", "شركة", "برج سكني",
            ])
            rx = round(rng.uniform(-30.0, -8.0), 2)
            temp = rng.randint(42, 78)
            run_state = "online" if rng.random() > 0.12 else ("offline" if rng.random() > 0.35 else "degraded")
            config_state = "normal" if rng.random() > 0.08 else "failed"
            match_state = "match" if rng.random() > 0.06 else "mismatch"
            # تحديد نوع التغطية بناءً على الحالة والقدرة الضوئية
            if run_state == "offline" or rx < -28:
                coverage = "none"
            elif run_state == "degraded" or rx < -25 or temp > 70:
                coverage = "degraded"
            else:
                coverage = "good"
            subs = rng.randint(1, 4)
            # توزيع دائري حول موقع OLT
            angle = rng.uniform(0, 2 * 3.141592653589793)
            distance = rng.uniform(0.005, 0.06)
            lat = round(olt["lat"] + distance * math.cos(angle), 6)
            lng = round(olt["lng"] + distance * math.sin(angle), 6)
            olt_onts.append({
                "id": f"{olt['id']}-{i}",
                "olt_id": olt["id"],
                "olt_name": olt["name"],
                "governorate": olt["governorate"],
                "company": olt["company"],
                "fsp": fsp,
                "ont_id": ont_id,
                "sn": sn,
                "description": f"{desc}-{i:02d}",
                "run_state": run_state,
                "config_state": config_state,
                "match_state": match_state,
                "rx_power": rx,
                "temperature": temp,
                "coverage": coverage,
                "subscribers": subs,
                "lat": lat,
                "lng": lng,
            })
        onts[olt["id"]] = olt_onts
    return onts


_ONTS = _build_onts()


def _agg(devices: List[Dict]) -> Dict:
    subs_by_type: Dict[str, int] = {}
    for d in devices:
        tp = d.get("access_type", "ftth")
        subs_by_type[tp] = subs_by_type.get(tp, 0) + d["subscribers"]
    return {
        "devices": len(devices),
        "subscribers": sum(d["subscribers"] for d in devices),
        "throughput_gbps": round(sum(d["throughput_gbps"] for d in devices), 1),
        "problems": sum(d["problems"] for d in devices),
        "online": sum(1 for d in devices if d["status"] == "online"),
        "degraded": sum(1 for d in devices if d["status"] == "degraded"),
        "offline": sum(1 for d in devices if d["status"] == "offline"),
        "access_types": sorted({d.get("access_type", "ftth") for d in devices}),
        "subscribers_by_type": subs_by_type,
    }


def _by_access_type(devices: List[Dict]) -> List[Dict]:
    """تجميع حسب نوع الاتصال (FTTH / وايرليس)."""
    groups: Dict[str, List[Dict]] = {}
    for d in devices:
        groups.setdefault(d.get("access_type", "ftth"), []).append(d)
    out = []
    for tp, items in groups.items():
        a = _agg(items)
        a["type"] = tp
        a["label"] = _ACCESS_LABELS.get(tp, tp)
        a["companies"] = sorted({i["company"] for i in items})
        out.append(a)
    out.sort(key=lambda x: x["subscribers"], reverse=True)
    return out


def _group_by(devices: List[Dict], key: str) -> List[Dict]:
    groups: Dict[str, List[Dict]] = {}
    for d in devices:
        groups.setdefault(d[key], []).append(d)
    out = []
    for name, items in groups.items():
        a = _agg(items)
        a["name"] = name
        a["company_count"] = len({i["company"] for i in items})
        a["governorate_count"] = len({i["governorate"] for i in items})
        out.append(a)
    out.sort(key=lambda x: x["throughput_gbps"], reverse=True)
    return out


def _throughput_series(total_gbps: float, seed_key: str,
                       points: int = 64) -> List[Dict]:
    """سلسلة زمنية لحجم البيانات على مدى 24 ساعة بأسلوب مؤشّر بورصة
    (مسير عشوائي مُرتدّ نحو منحنى الحِمل اليومي). حتمية حسب المفتاح."""
    rng = random.Random((hash(seed_key) & 0x7FFFFFFF) or 1)
    v = total_gbps * rng.uniform(0.70, 0.85)
    series: List[Dict] = []
    for i in range(points):
        hour = i * 24.0 / points
        # منحنى يومي: قاع نحو ~05:00، ذروة نحو ~21:00
        diurnal = 0.55 + 0.45 * (0.5 - 0.5 * math.cos((hour - 5) / 24 * 2 * math.pi))
        target = total_gbps * diurnal
        v += (target - v) * 0.18 + rng.uniform(-0.028, 0.028) * total_gbps
        v = max(total_gbps * 0.30, v)
        hh = int(hour)
        mm = int((hour - hh) * 60)
        series.append({"t": f"{hh:02d}:{mm:02d}", "value": round(v, 1)})
    # اجعل آخر نقطة = الحمل الحالي (الإجمالي) بالضبط
    if series:
        series[-1]["value"] = round(total_gbps, 1)
    return series


def overview(governorate: Optional[str] = None,
             company: Optional[str] = None,
             access_type: Optional[str] = None) -> Dict:
    """صورة وطنية كاملة مع تصفية اختيارية حسب المحافظة/الشركة/نوع الاتصال."""
    devices = _FLEET
    if governorate:
        devices = [d for d in devices if d["governorate"] == governorate]
    if company:
        devices = [d for d in devices if d["company"] == company]
    if access_type:
        devices = [d for d in devices if d.get("access_type") == access_type]

    totals = _agg(devices)
    totals["governorates"] = len({d["governorate"] for d in devices})
    totals["companies"] = len({d["company"] for d in devices})

    series = _throughput_series(totals["throughput_gbps"],
                                f"{governorate}|{company}|{access_type}")
    first = series[0]["value"] if series else 0
    last = series[-1]["value"] if series else 0
    change_pct = round((last - first) / first * 100, 2) if first else 0.0

    # أنواع الاتصال المتاحة لكل شركة (للعرض في جدول الشركات)
    company_access = {c: [_ACCESS_LABELS[a] for a in _COMPANY_ACCESS.get(c, [])]
                      for c in _COMPANIES}

    return {
        "scope": {"governorate": governorate, "company": company,
                  "access_type": access_type},
        "totals": totals,
        "throughput_series": series,
        "throughput_change_pct": change_pct,
        "throughput_low": min((p["value"] for p in series), default=0),
        "throughput_high": max((p["value"] for p in series), default=0),
        "by_governorate": _group_by(devices, "governorate"),
        "by_company": _group_by(devices, "company"),
        "by_access_type": _by_access_type(devices),
        "company_access": company_access,
        "devices": sorted(devices, key=lambda x: x["throughput_gbps"], reverse=True),
        "filters": {
            "governorates": [g for g, _, _, _ in _GOVERNORATES],
            "companies": _COMPANIES,
            "access_types": [{"type": k, "label": v}
                             for k, v in _ACCESS_LABELS.items()],
        },
    }


# ---------------------------------------------------------------------------
# خريطة ONTs
# ---------------------------------------------------------------------------

def governorate_centers() -> List[Dict]:
    """قائمة المحافظات مع مراكزها الجغرافية."""
    return [{"name": g, "lat": lat, "lng": lng} for g, _, lat, lng in _GOVERNORATES]


def device_map(governorate: Optional[str] = None,
               company: Optional[str] = None) -> Dict:
    """مواقع أجهزة OLT للشركات (إحداثيات + حالة) — لطبقة «مواقع أجهزة الشركات»."""
    devs = _FLEET
    if governorate:
        devs = [d for d in devs if d["governorate"] == governorate]
    if company:
        devs = [d for d in devs if d["company"] == company]
    return {
        "count": len(devs),
        "devices": [
            {
                "id": d["id"],
                "name": d["name"],
                "company": d["company"],
                "governorate": d["governorate"],
                "lat": d["lat"],
                "lng": d["lng"],
                "status": d["status"],
                "subscribers": d["subscribers"],
                "model": d["model"],
                "access_type": d.get("access_type", "ftth"),
                "color": _COMPANY_COLORS.get(d["company"], "#22D3EE"),
            }
            for d in devs
        ],
    }


def ont_map(governorate: Optional[str] = None, company: Optional[str] = None) -> Dict:
    """جميع ONTs مع إحداثياتها، مع إمكانية التصفية حسب المحافظة/الشركة."""
    olt_ids = [
        d["id"] for d in _FLEET
        if (governorate is None or d["governorate"] == governorate)
        and (company is None or d["company"] == company)
    ]
    markers = []
    for oid in olt_ids:
        markers.extend(_ONTS.get(oid, []))
    return {
        "governorate": governorate,
        "company": company,
        "count": len(markers),
        "markers": markers,
    }


# ---------------------------------------------------------------------------
# مسارات الخريطة (دولية / بين المحافظات / داخل المحافظة / شبكات)
# ---------------------------------------------------------------------------

def _interpolate_route(a: Tuple[float, float], b: Tuple[float, float],
                       rng: random.Random, points: int = 10) -> List[Tuple[float, float]]:
    """خطّ منحنٍ انسيابي بين نقطتين (منحنى بيزييه لطيف — بلا اهتزاز عشوائي)."""
    return _arc(a, b, points=max(points, 10), bend=0.05)


def _arc(a: Tuple[float, float], b: Tuple[float, float],
         points: int = 14, bend: float = 0.06) -> List[Tuple[float, float]]:
    """منحنى بيزييه تربيعي أنيق بين نقطتين (نقطة تحكّم عمودية على منتصف الخط)."""
    (lat1, lng1), (lat2, lng2) = a, b
    mlat, mlng = (lat1 + lat2) / 2.0, (lng1 + lng2) / 2.0
    dlat, dlng = lat2 - lat1, lng2 - lng1
    clat, clng = mlat - dlng * bend, mlng + dlat * bend
    out = []
    for i in range(points + 1):
        t = i / points
        u = 1 - t
        lat = u * u * lat1 + 2 * u * t * clat + t * t * lat2
        lng = u * u * lng1 + 2 * u * t * clng + t * t * lng2
        out.append((round(lat, 6), round(lng, 6)))
    return out


# مسارات دولية رئيسية (تقريبية) تربط العراق بدول الجوار
_INTERNATIONAL_ROUTES = [
    {
        "name": "TR1: بغداد → الرطبة → الحدود الأردنية → عمّان",
        "color": "#F87171",
        "waypoints": [(33.3152, 44.3661), (33.1, 42.7), (32.7, 41.2), (32.2, 39.5), (31.9, 38.0)],
    },
    {
        "name": "TR2: بغداد → الرمادي → الحدود السورية → دمشق",
        "color": "#FB923C",
        "waypoints": [(33.3152, 44.3661), (33.4, 43.3), (33.7, 41.0), (34.5, 37.0)],
    },
    {
        "name": "TR3: بغداد → الموصل → الحدود التركية → إسطنبول",
        "color": "#FBBF24",
        "waypoints": [(33.3152, 44.3661), (34.9, 43.5), (36.3356, 43.1358), (37.1, 42.6), (38.5, 41.0), (41.0, 29.0)],
    },
    {
        "name": "TR4: بغداد → بعقوبة → مندلي → الحدود الإيرانية → طهران",
        "color": "#34D399",
        "waypoints": [(33.3152, 44.3661), (33.8, 45.2), (34.1, 46.3), (35.7, 51.3)],
    },
    {
        "name": "TR5: بغداد → البصرة → الشلامجة → الأحواز → طهران",
        "color": "#22D3EE",
        "waypoints": [(33.3152, 44.3661), (31.5, 47.0), (30.5156, 47.7804), (30.4, 48.2), (31.8, 51.5)],
    },
    {
        "name": "TR6: بغداد → الناصرية → سفوان → الكويت",
        "color": "#60A5FA",
        "waypoints": [(33.3152, 44.3661), (31.0, 46.3), (30.0, 47.1), (29.3, 47.0)],
    },
    {
        "name": "TR7: بغداد → الناصرية → سميسمة → الرياض",
        "color": "#A78BFA",
        "waypoints": [(33.3152, 44.3661), (31.0, 46.3), (28.5, 46.5), (26.0, 47.0), (24.7, 46.7)],
    },
    {
        "name": "TR8: بغداد → كركوك → أربيل → الحدود التركية",
        "color": "#F472B6",
        "waypoints": [(33.3152, 44.3661), (35.4669, 44.3923), (36.1911, 44.0092), (37.3, 43.0)],
    },
    {
        "name": "TR9: بغداد → السليمانية → الحدود الإيرانية",
        "color": "#2DD4BF",
        "waypoints": [(33.3152, 44.3661), (34.5, 45.5), (35.5575, 45.4350), (36.0, 46.5)],
    },
    {
        "name": "TR10: بغداد → دهوك → الحدود التركية",
        "color": "#A3E635",
        "waypoints": [(33.3152, 44.3661), (35.0, 43.0), (36.8679, 42.9484), (37.5, 42.8)],
    },
]


# مسارات بين المحافظات (العاصمة مركزاً + بعض الوصلات المباشرة)
_INTER_GOVERNORATE_LINKS = [
    ("بغداد", "الأنبار"), ("بغداد", "بابل"), ("بغداد", "كربلاء"),
    ("بغداد", "النجف"), ("بغداد", "واسط"), ("بغداد", "ديالى"),
    ("بغداد", "صلاح الدين"), ("بغداد", "كركوك"), ("بغداد", "نينوى"),
    ("بغداد", "البصرة"), ("البصرة", "ميسان"), ("البصرة", "ذي قار"),
    ("ذي قار", "ميسان"), ("البصرة", "واسط"), ("واسط", "القادسية"),
    ("القادسية", "ذي قار"), ("القادسية", "المثنى"), ("بابل", "كربلاء"),
    ("بابل", "النجف"), ("النجف", "كربلاء"), ("الأنبار", "بابل"),
    ("صلاح الدين", "كركوك"), ("كركوك", "نينوى"), ("كركوك", "أربيل"),
    ("نينوى", "أربيل"), ("أربيل", "السليمانية"), ("السليمانية", "دهوك"),
]


_ROUTE_COLORS = {
    "international": "#F87171",  # red
    "inter_governorate": "#22D3EE",  # cyan accent
    "intra_governorate": "#94A3B8",  # muted
    "network": "#E879F9",  # fuchsia
}


def _build_routes() -> List[Dict]:
    """توليد كل مسارات الخريطة."""
    rng = random.Random(20260721)  # بذرة مستقلة للمسارات
    routes: List[Dict] = []
    gov_centers = {g: (lat, lng) for g, _, lat, lng in _GOVERNORATES}

    # 1) مسارات دولية
    for ir in _INTERNATIONAL_ROUTES:
        waypoints = ir["waypoints"]
        coords = []
        for i in range(len(waypoints) - 1):
            coords.extend(_interpolate_route(waypoints[i], waypoints[i + 1], rng, points=12))
        routes.append({
            "id": f"intl-{len(routes)}",
            "type": "international",
            "name": ir["name"],
            "color": ir["color"],
            "coordinates": coords,
        })

    # 2) مسارات بين المحافظات
    for a_name, b_name in _INTER_GOVERNORATE_LINKS:
        a = gov_centers.get(a_name)
        b = gov_centers.get(b_name)
        if a and b:
            coords = _interpolate_route(a, b, rng, points=14)
            routes.append({
                "id": f"intergov-{len(routes)}",
                "type": "inter_governorate",
                "name": f"{a_name} ↔ {b_name}",
                "color": _ROUTE_COLORS["inter_governorate"],
                "coordinates": coords,
            })

    # 3) مسارات داخل كل محافظة (OLT ↔ OLT و OLT ↔ مركز المحافظة)
    for gov in {d["governorate"] for d in _FLEET}:
        olt_locs = [(d["lat"], d["lng"]) for d in _FLEET if d["governorate"] == gov]
        center = gov_centers.get(gov)
        if center and olt_locs:
            # وصل كل OLT بأقرب OLT آخر + بالمركز
            for i, loc in enumerate(olt_locs):
                routes.append({
                    "id": f"intra-{len(routes)}",
                    "type": "intra_governorate",
                    "name": f"{gov}: OLT-{i+1}",
                    "color": _ROUTE_COLORS["intra_governorate"],
                    "coordinates": _interpolate_route(center, loc, rng, points=6),
                })

    # 4) العمود الفقري لكل شركة — خط انسيابي واحد يربط محاورها عبر المحافظات
    #    (بدل مئات خطوط OLT→ONT المتشابكة). محور = أكبر OLT للشركة في المحافظة.
    for company in _COMPANIES:
        hubs_by_gov: Dict[str, Dict] = {}
        for d in _FLEET:
            if d["company"] != company:
                continue
            g = d["governorate"]
            if g not in hubs_by_gov or d["subscribers"] > hubs_by_gov[g]["subscribers"]:
                hubs_by_gov[g] = d
        hubs = sorted(hubs_by_gov.values(), key=lambda d: d["lat"], reverse=True)  # شمال→جنوب
        if len(hubs) < 2:
            continue
        color = _COMPANY_COLORS.get(company, _ROUTE_COLORS["network"])
        coords: List[Tuple[float, float]] = []
        for i in range(len(hubs) - 1):
            seg = _arc((hubs[i]["lat"], hubs[i]["lng"]),
                       (hubs[i + 1]["lat"], hubs[i + 1]["lng"]), points=16, bend=0.05)
            coords.extend(seg if i == 0 else seg[1:])
        routes.append({
            "id": f"net-{company}",
            "type": "network",
            "name": f"شبكة {company}",
            "company": company,
            "color": color,
            "coordinates": coords,
        })

    return routes


_ROUTES = _build_routes()


def routes(governorate: Optional[str] = None,
           company: Optional[str] = None,
           types: Optional[List[str]] = None) -> Dict:
    """كل المسارات مع تصفية اختيارية حسب المحافظة/الشركة/النوع."""
    out = []
    for r in _ROUTES:
        if types and r["type"] not in types:
            continue
        if r["type"] == "network":
            # الشبكات (العمود الفقري للشركة) تظهر في وضع الشبكة فقط
            if not company or r.get("company") != company:
                continue
        if r["type"] == "intra_governorate":
            # الوصلات المحلية تظهر في وضع المحافظة فقط، وللمحافظة المختارة
            if company:
                continue
            if governorate and not r["name"].startswith(governorate):
                continue
        out.append(r)
    return {
        "governorate": governorate,
        "company": company,
        "types": types,
        "count": len(out),
        "routes": out,
    }


def networks() -> List[Dict]:
    """إحصائيات كل شبكة (شركة) مع عدد المستخدمين."""
    stats: Dict[str, Dict] = {}
    for olt in _FLEET:
        c = olt["company"]
        stats.setdefault(c, {"name": c, "devices": 0, "subscribers": 0, "throughput_gbps": 0.0, "governorates": set()})
        stats[c]["devices"] += 1
        stats[c]["subscribers"] += olt["subscribers"]
        stats[c]["throughput_gbps"] += olt["throughput_gbps"]
        stats[c]["governorates"].add(olt["governorate"])
    out = []
    for c, s in stats.items():
        out.append({
            "name": c,
            "color": _COMPANY_COLORS.get(c, "#22D3EE"),
            "devices": s["devices"],
            "subscribers": s["subscribers"],
            "throughput_gbps": round(s["throughput_gbps"], 1),
            "governorates": len(s["governorates"]),
        })
    out.sort(key=lambda x: x["subscribers"], reverse=True)
    return out


# ---------------------------------------------------------------------------
# تحليل ذكي (قواعد محلية + Claude إن توفّر المفتاح)
# ---------------------------------------------------------------------------

def _rule_based_analysis(data: Dict) -> str:
    t = data["totals"]
    govs = data["by_governorate"]
    comps = data["by_company"]
    scope = data["scope"]
    where = ""
    if scope.get("governorate"):
        where = f" (محافظة {scope['governorate']})"
    elif scope.get("company"):
        where = f" (شركة {scope['company']})"

    lines: List[str] = []
    lines.append(f"📊 تحليل الشبكة الوطنية{where}:")
    lines.append(
        f"• الإجمالي: {t['governorates']} محافظة، {t['companies']} شركة، "
        f"{t['devices']} جهاز OLT، {t['subscribers']:,} مشترك، "
        f"{t['throughput_gbps']:,} Gbps حركة بيانات.")
    avail = (t["online"] / t["devices"] * 100) if t["devices"] else 0
    lines.append(f"• التوافر: {avail:.1f}% من الأجهزة تعمل ({t['offline']} متوقّف، {t['degraded']} متدهور).")

    if govs:
        top = govs[0]
        lines.append(
            f"• أعلى محافظة حِملاً: {top['name']} بـ {top['throughput_gbps']:,} Gbps "
            f"و{top['subscribers']:,} مشترك على {top['devices']} جهاز.")
        worst = max(govs, key=lambda g: g["problems"])
        if worst["problems"] > 0:
            lines.append(
                f"• أكثر محافظة مشاكل: {worst['name']} ({worst['problems']} مشكلة نشطة) — "
                f"يُنصح بأولوية صيانة.")
    if comps:
        topc = max(comps, key=lambda c: c["subscribers"])
        lines.append(
            f"• أكبر شركة بالمشتركين: {topc['name']} ({topc['subscribers']:,} مشترك، "
            f"{topc['devices']} جهاز، {topc['throughput_gbps']:,} Gbps).")

    if t["subscribers"]:
        per = t["throughput_gbps"] * 1000 / t["subscribers"]
        lines.append(f"• متوسط الاستهلاك لكل مشترك: {per:.1f} Mbps.")
    if t["problems"] > 20:
        lines.append("⚠️ عدد المشاكل مرتفع وطنياً — راجع لوحة التنبيهات وخطّط لصيانة استباقية.")
    else:
        lines.append("✅ الوضع العام مستقر؛ لا تركّز مشاكل حرج.")
    lines.append("— (تحليل آلي من قواعد المحرّك؛ فعّل ANTHROPIC_API_KEY لتحليل أعمق بالذكاء الاصطناعي.)")
    return "\n".join(lines)


def analyze(governorate: Optional[str] = None,
            company: Optional[str] = None) -> Dict:
    """يُرجع تحليلاً نصياً للبيانات الوطنية (Claude إن توفّر، وإلا قواعد محلية)."""
    data = overview(governorate, company)
    # محاولة استخدام Claude إن توفّر المفتاح
    try:
        from .ai_assistant import _get_client
        from ..config import settings
        client = _get_client()
        if client is not None:
            t = data["totals"]
            summary = (
                f"بيانات شبكة OLT وطنية (العراق): {t['governorates']} محافظة، "
                f"{t['companies']} شركة، {t['devices']} جهاز، {t['subscribers']} مشترك، "
                f"{t['throughput_gbps']} Gbps، {t['problems']} مشكلة نشطة، "
                f"{t['offline']} جهاز متوقّف. أعلى المحافظات: "
                + ", ".join(f"{g['name']}={g['throughput_gbps']}Gbps" for g in data['by_governorate'][:5])
                + ". الشركات: "
                + ", ".join(f"{c['name']}={c['subscribers']}مشترك" for c in data['by_company'])
            )
            msg = client.messages.create(
                model=settings.ai_model,
                max_tokens=700,
                system="أنت محلّل شبكات وصول خبير. حلّل بيانات الشبكة الوطنية بالعربية بإيجاز مهني: أبرز المخاطر، التوصيات، وفرص التحسين. استخدم نقاطاً.",
                messages=[{"role": "user", "content": summary}],
            )
            text = "".join(b.text for b in msg.content if getattr(b, "type", "") == "text")
            return {"analysis": text, "source": "claude", "totals": data["totals"]}
    except Exception:
        pass
    return {"analysis": _rule_based_analysis(data), "source": "rules",
            "totals": data["totals"]}
