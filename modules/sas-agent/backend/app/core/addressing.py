"""محرّك العنونة الوطنية NAS-IQ — تنفيذ أمين لمواصفة دراسة «النظام الوطني
للعنونة الرقمية في العراق» (الملحق أ).

ثلاث طبقات:
  1) NPN  — رقم العقار الوطني (11 خانة): GG + 8 أرقام تسلسل + رقم تحقّق Luhn.
  2) IQ-Pin — رمز شبكي مفتوح (10 رموز) يُشتق من الإحداثيات بدقّة ~1م (مبدأ DIGIPIN).
  3) العنوان الوصفي — يُدار في طبقة السجل (خارج هذا الملف).

كل الدوال نقية (لا حالة، لا I/O) وحتمية — قابلة لإعادة الإنتاج والاختبار.
مُتحقَّقة مقابل أمثلة الدراسة: encode(33.3389,44.4009) == "8L8L865FMT".
"""
from __future__ import annotations

import math
from typing import Tuple

# أبجدية 16 رمزاً خالية من الالتباس (لا 0/O ولا 1/I …)
ALPHABET = "23456789CFJKLMPT"
# الصندوق الجغرافي العراقي (خط الطول/العرض)
LON_MIN, LON_MAX = 38.0, 50.0
LAT_MIN, LAT_MAX = 28.0, 38.0
LEVELS = 10  # عمق التقسيم 4×4 → دقّة الخلية ~1م

# أكواد المحافظات (كتلة تخصيص NPN) — من جدول الدراسة (البادئة البريدية/التعداد).
# مثال الدراسة: بغداد=10 ⇒ NPN 10-0483-9221-0.
GOV_CODES = {
    "بغداد": 10, "الأنبار": 31, "ديالى": 32, "صلاح الدين": 34, "كركوك": 36,
    "نينوى": 41, "دهوك": 42, "أربيل": 44, "السليمانية": 46, "بابل": 51,
    "واسط": 52, "النجف": 54, "كربلاء": 56, "القادسية": 58, "البصرة": 61,
    "ميسان": 62, "ذي قار": 64, "المثنى": 66, "حلبجة": 47,
}


def gov_code_for(name: str) -> int:
    """كود المحافظة من اسمها (يتساهل مع «محافظة …» والفراغات)؛ 99 إن لم تُعرف."""
    n = (name or "").replace("محافظة", "").strip()
    return GOV_CODES.get(n, 99)


def in_iraq_box(lat: float, lon: float) -> bool:
    """هل النقطة داخل صندوق العراق الجغرافي (شرط صلاحية IQ-Pin)."""
    return LAT_MIN <= lat <= LAT_MAX and LON_MIN <= lon <= LON_MAX


# ══════════════════════ IQ-Pin (الطبقة الثانية) ══════════════════════
def iqpin_encode(lat: float, lon: float, levels: int = LEVELS) -> str:
    """يحوّل (lat, lon) إلى رمز IQ-Pin من `levels` رموز (افتراضياً 10)."""
    if not (LAT_MIN <= lat <= LAT_MAX and LON_MIN <= lon <= LON_MAX):
        raise ValueError(
            f"الإحداثيات خارج صندوق العراق: lat={lat}, lon={lon}")
    lat0, lat1, lon0, lon1 = LAT_MIN, LAT_MAX, LON_MIN, LON_MAX
    out = []
    for _ in range(levels):
        dlat = (lat1 - lat0) / 4
        dlon = (lon1 - lon0) / 4
        row = min(3, int((lat1 - lat) / dlat))  # الصف: الشمال=0
        col = min(3, int((lon - lon0) / dlon))  # العمود: الغرب=0
        out.append(ALPHABET[row * 4 + col])
        lat1 -= row * dlat
        lat0 = lat1 - dlat
        lon0 += col * dlon
        lon1 = lon0 + dlon
    return "".join(out)


def iqpin_decode(code: str) -> Tuple[float, float]:
    """يعيد مركز الخلية (lat, lon) لرمز IQ-Pin (يتجاهل الشرطات/حالة الأحرف)."""
    lat0, lat1, lon0, lon1 = LAT_MIN, LAT_MAX, LON_MIN, LON_MAX
    for ch in code.replace("-", "").upper():
        if ch not in ALPHABET:
            raise ValueError(f"رمز IQ-Pin غير صالح: {ch!r}")
        row, col = divmod(ALPHABET.index(ch), 4)
        dlat = (lat1 - lat0) / 4
        dlon = (lon1 - lon0) / 4
        lat1 -= row * dlat
        lat0 = lat1 - dlat
        lon0 += col * dlon
        lon1 = lon0 + dlon
    return ((lat0 + lat1) / 2, (lon0 + lon1) / 2)


def iqpin_display(code: str) -> str:
    """صيغة العرض المجموعة 3-3-4 (مثل 8L8-L86-5FMT)."""
    c = code.replace("-", "")
    return f"{c[:3]}-{c[3:6]}-{c[6:]}" if len(c) >= 7 else c


# ══════════════════════ NPN (الطبقة الأولى) ══════════════════════
def luhn_check_digit(num: str) -> str:
    """رقم تحقّق Luhn لسلسلة أرقام (لاكتشاف أخطاء الكتابة)."""
    total = 0
    for i, d in enumerate(reversed(num)):
        n = int(d)
        if i % 2 == 0:
            n *= 2
            if n > 9:
                n -= 9
        total += n
    return str((10 - total % 10) % 10)


def build_npn(gov_code: int, seq: int) -> str:
    """يبني رقم العقار الوطني (11 خانة): GG + 8 أرقام تسلسل + Luhn.

    gov_code: 1..19 (رمز المحافظة، كتلة تخصيص لا صفة موقع).
    seq: 0..99_999_999 (تسلسل داخل كتلة المحافظة).
    """
    if not (1 <= gov_code <= 99):
        raise ValueError(f"رمز محافظة غير صالح: {gov_code}")
    if not (0 <= seq <= 99_999_999):
        raise ValueError(f"تسلسل NPN خارج المدى: {seq}")
    base = f"{gov_code:02d}{seq:08d}"       # 10 أرقام
    return base + luhn_check_digit(base)     # 11 خانة


def npn_display(npn: str) -> str:
    """صيغة العرض للناس: GG-NNNN-NNNN-C (مثل 10-0483-9221-0)."""
    n = npn.strip()
    if len(n) != 11 or not n.isdigit():
        return n
    return f"{n[:2]}-{n[2:6]}-{n[6:10]}-{n[10]}"


def validate_npn(npn: str) -> bool:
    """يتحقّق أن NPN من 11 رقماً ورقم تحقّق Luhn صحيح."""
    n = npn.strip()
    if len(n) != 11 or not n.isdigit():
        return False
    return luhn_check_digit(n[:10]) == n[10]


# ══════════════════════ مساعدات هندسية ══════════════════════
def polygon_centroid(ring: list) -> Tuple[float, float]:
    """مركز حلقة إحداثيات [[lon,lat],...] — صيغة المضلّع (shoelace)؛
    يرجع (lat, lon). يتراجع إلى المتوسط الحسابي للحلقات المنحلّة."""
    pts = [(float(p[0]), float(p[1])) for p in ring if len(p) >= 2]
    if not pts:
        raise ValueError("حلقة فارغة")
    if len(pts) < 3:
        lon = sum(x for x, _ in pts) / len(pts)
        lat = sum(y for _, y in pts) / len(pts)
        return (lat, lon)
    a = cx = cy = 0.0
    for i in range(len(pts)):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % len(pts)]
        cross = x0 * y1 - x1 * y0
        a += cross
        cx += (x0 + x1) * cross
        cy += (y0 + y1) * cross
    if abs(a) < 1e-12:  # منحلّ → متوسط
        lon = sum(x for x, _ in pts) / len(pts)
        lat = sum(y for _, y in pts) / len(pts)
        return (lat, lon)
    a *= 0.5
    return (cy / (6 * a), cx / (6 * a))  # (lat, lon)


def geometry_point(geom: dict) -> Tuple[float, float]:
    """يستخرج نقطة تمثيلية (lat, lon) من هندسة GeoJSON (Point/Polygon/Line…)."""
    t = geom.get("type")
    c = geom.get("coordinates")
    if t == "Point" and isinstance(c, list) and len(c) >= 2:
        return (float(c[1]), float(c[0]))
    if t == "Polygon" and isinstance(c, list) and c:
        return polygon_centroid(c[0])
    if t == "MultiPolygon" and isinstance(c, list) and c and c[0]:
        return polygon_centroid(c[0][0])
    if t in ("LineString", "MultiPoint") and isinstance(c, list) and c:
        pts = c[0] if t == "MultiPoint" else c
        xs = [p for p in pts if isinstance(p, list) and len(p) >= 2]
        if xs:
            lon = sum(p[0] for p in xs) / len(xs)
            lat = sum(p[1] for p in xs) / len(xs)
            return (lat, lon)
    raise ValueError(f"هندسة غير مدعومة لاستخراج نقطة: {t}")


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """المسافة بالمتر بين نقطتين (haversine)."""
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


# ══════════════════════ ترقيم الشوارع (فردي/زوجي) ══════════════════════
_R = 6371000.0


def _to_xy(lat: float, lon: float, lat0: float) -> Tuple[float, float]:
    """إسقاط مستوٍ محلي (equirectangular) بالمتر حول خط عرض مرجعي."""
    x = math.radians(lon) * _R * math.cos(math.radians(lat0))
    y = math.radians(lat) * _R
    return (x, y)


def _project_point_segment(px, py, ax, ay, bx, by):
    """يعيد (t∈[0,1], المسافة العمودية بالمتر، إشارة الجهة). الجهة>0 = يسار A→B."""
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / l2))
    cx, cy = ax + t * dx, ay + t * dy
    dist = math.hypot(px - cx, py - cy)
    cross = dx * (py - ay) - dy * (px - ax)
    return t, dist, cross


def number_along_streets(buildings: list, streets: list,
                         start: int = 1, max_dist_m: float = 200.0) -> dict:
    """يخصّص رقم دار تسلسلياً لكل مبنى على طول أقرب شارع (فردي جهة، زوجي أخرى).

    buildings: [{"id": any, "lat": float, "lon": float}]
    streets:   [{"id": any, "name": str, "coords": [[lon,lat], ...]}]
    يعيد: {building_id: {street_id, street_name, hno, side, along_m, offset_m}}
    المباني الأبعد من max_dist_m عن أي شارع لا تُرقَّم (لا مفتاح لها).
    """
    if not buildings:
        return {}
    lat0 = sum(b["lat"] for b in buildings) / len(buildings)

    # تحضير مقاطع الشوارع في الإحداثيات المستوية + المسافة التراكمية
    prepared = []
    for st in streets:
        pts = [(float(c[0]), float(c[1])) for c in st.get("coords", [])
               if isinstance(c, list) and len(c) >= 2]
        if len(pts) < 2:
            continue
        xy = [_to_xy(lat, lon, lat0) for lon, lat in pts]
        cum = [0.0]
        for i in range(1, len(xy)):
            cum.append(cum[-1] + math.hypot(xy[i][0] - xy[i - 1][0],
                                            xy[i][1] - xy[i - 1][1]))
        prepared.append({"id": st.get("id"), "name": st.get("name", ""),
                         "xy": xy, "cum": cum})

    # لكل مبنى: أقرب شارع + المسافة على طوله + الجهة
    assign = {}
    per_street = {}  # street_id → [(building_id, along, side)]
    for b in buildings:
        px, py = _to_xy(b["lat"], b["lon"], lat0)
        best = None
        for st in prepared:
            xy, cum = st["xy"], st["cum"]
            for i in range(len(xy) - 1):
                ax, ay = xy[i]
                bx, by = xy[i + 1]
                t, dist, cross = _project_point_segment(px, py, ax, ay, bx, by)
                if best is None or dist < best[0]:
                    seglen = cum[i + 1] - cum[i]
                    along = cum[i] + t * seglen
                    best = (dist, st, along, "left" if cross > 0 else "right")
        if best is None or best[0] > max_dist_m:
            continue
        dist, st, along, side = best
        assign[b["id"]] = {"street_id": st["id"], "street_name": st["name"],
                           "side": side, "along_m": round(along, 2),
                           "offset_m": round(dist, 2)}
        per_street.setdefault(st["id"], []).append((b["id"], along, side))

    # ترقيم تسلسلي لكل شارع: فردي=يسار، زوجي=يمين (بترتيب المسافة على الطول)
    for sid, items in per_street.items():
        for side, parity in (("left", 1), ("right", 0)):
            ordered = sorted((it for it in items if it[2] == side),
                             key=lambda x: x[1])
            n = start if parity else start + 1
            for bid, _along, _side in ordered:
                assign[bid]["hno"] = n
                n += 2
    return assign
