"""
الوكلاء (Resellers) — وكلاء الشركات ومشتركوهم (بيانات محاكاة واقعية حتمية).

كل وكيل تابع لشركة مزوّدة خدمة، في محافظة، ويدير مجموعة من المشتركين بنوع خدمة
(ألياف FTTH / وايرليس) حسب ما تجهّزه شركته. تُشتق كل الأرقام من بذرة
ثابتة فتبقى مستقرّة بين الطلبات، وتعيد استخدام شركات ومحافظات اللوحة الوطنية.
"""
import json
import os
import random
from typing import Dict, List, Optional

from . import national

# أسماء أولى ذكورية — تُستخدم لأسماء الوكلاء (ذكور فقط)
_MALE_FIRST_NAMES = [
    "محمد", "أحمد", "علي", "حسين", "حسن", "عمر", "مصطفى", "يوسف", "إبراهيم",
    "عبدالله", "كرار", "مرتضى", "حيدر", "زيد", "سيف", "عباس", "مهند", "أمير",
    "عمار", "قاسم", "باسم", "وليد", "نبيل", "غسان", "أنس", "رائد",
]

# أسماء أولى مختلطة (ذكور/إناث) — تُستخدم لأسماء المشتركين
_FIRST_NAMES = _MALE_FIRST_NAMES + [
    "فاطمة", "زينب", "مريم", "نور", "سارة", "رقية", "هدى", "آية", "دعاء", "ريم",
]
_FAMILY_NAMES = [
    "العبيدي", "الجبوري", "الدليمي", "التميمي", "الزيدي", "الساعدي", "الموسوي",
    "الحسيني", "الربيعي", "الخفاجي", "العزاوي", "الشمري", "الكناني", "البدري",
    "العامري", "الطائي", "الجنابي", "المالكي", "الغراوي", "الفتلاوي",
]
_OFFICE_SUFFIX = [
    "للاتصالات", "للإنترنت", "لخدمات الإنترنت", "نت", "لتكنولوجيا المعلومات",
    "للحلول الرقمية", "تليكوم",
]
_AREAS = [
    "المنصور", "الكرادة", "حي الجامعة", "حي النصر", "الحي العسكري", "حي الزهور",
    "المعلمين", "حي الحسين", "حي الصحة", "الشرطة الرابعة", "حي التأميم", "العروبة",
]

# باقات الخدمة حسب النوع: (الوصف، الرسم الشهري بالدينار)
_PLANS = {
    "ftth": [("30 Mbps", 25000), ("50 Mbps", 35000), ("100 Mbps", 50000),
             ("200 Mbps", 75000)],
    "wireless": [("10 Mbps", 20000), ("20 Mbps", 30000), ("40 Mbps", 45000)],
}

# رموز الشركات (لاتينية) لتوليد مُعرّف الوكيل «@» المسجَّل لدى الشركة
_COMPANY_CODES = {
    "الصدارة نت": "sdr",
    "إيرثلنك": "erth",
    "هلا": "hala",
    "الجزيرة": "jzr",
    "سوبر سيل": "sprcl",
}

_SUB_STATUS = ["active", "suspended", "expired"]
_SUB_STATUS_LABELS = {
    "active": "نشط", "suspended": "موقوف", "expired": "منتهٍ",
}
_AGENT_STATUS_LABELS = {"active": "نشط", "suspended": "موقوف"}


def _phone(rng: random.Random) -> str:
    prefix = rng.choice(["0770", "0771", "0780", "0781", "0790", "0750", "0751"])
    return f"{prefix}{rng.randint(100, 999)}{rng.randint(1000, 9999)}"


def _ip(rng: random.Random) -> str:
    """عنوان IP للمشترك (نطاق CGNAT الشائع لدى مزوّدي الخدمة 100.64.0.0/10)."""
    return f"100.{rng.randint(64, 120)}.{rng.randint(0, 255)}.{rng.randint(2, 254)}"


def _mac(rng: random.Random) -> str:
    """عنوان MAC لجهاز المشترك (ONT/راوتر)."""
    return ":".join(f"{rng.randint(0, 255):02X}" for _ in range(6))


def _person(rng: random.Random) -> str:
    return f"{rng.choice(_FIRST_NAMES)} {rng.choice(_FAMILY_NAMES)}"


def _male_person(rng: random.Random) -> str:
    """اسم ذكوري — لأسماء الوكلاء."""
    return f"{rng.choice(_MALE_FIRST_NAMES)} {rng.choice(_FAMILY_NAMES)}"


def _build_agents() -> List[Dict]:
    rng = random.Random(20260723)  # بذرة ثابتة → بيانات مستقرّة
    gov_names = [g for g, _, _, _ in national._GOVERNORATES]
    gov_weights = [w for _, w, _, _ in national._GOVERNORATES]
    agents: List[Dict] = []
    sub_seq = 0

    aid = 0
    for company in national._COMPANIES:
        access = national._COMPANY_ACCESS[company]  # أنواع الخدمة المتاحة للشركة
        n_agents = rng.randint(9, 16)               # عدد وكلاء الشركة
        for _ in range(n_agents):
            aid += 1
            gov = rng.choices(gov_names, gov_weights)[0]
            person = _male_person(rng)  # أسماء الوكلاء ذكور فقط
            office = f"مكتب {person.split()[1]} {rng.choice(_OFFICE_SUFFIX)}"
            # أنواع الخدمة التي يجهّزها الوكيل (كل ما تتيحه شركته أو جزء منه)
            if len(access) > 1 and rng.random() < 0.35:
                svc_types = [rng.choice(access)]
            else:
                svc_types = list(access)
            status = "active" if rng.random() > 0.10 else "suspended"
            n_subs = rng.randint(18, 240)

            subscribers: List[Dict] = []
            for _ in range(n_subs):
                sub_seq += 1
                stype = rng.choice(svc_types)
                plan, fee = rng.choice(_PLANS[stype])
                r = rng.random()
                sstatus = "active" if r > 0.16 else ("suspended" if r > 0.07 else "expired")
                subscribers.append({
                    "id": f"SUB-{sub_seq:06d}",
                    "name": _person(rng),
                    "phone": _phone(rng),
                    "ip": _ip(rng),
                    "mac": _mac(rng),
                    "governorate": gov,
                    "address": f"{gov} - {rng.choice(_AREAS)}",
                    "service_type": stype,
                    "service_label": national._ACCESS_LABELS[stype],
                    "plan": plan,
                    "monthly_fee": fee,
                    "status": sstatus,
                    "status_label": _SUB_STATUS_LABELS[sstatus],
                    "since": f"{rng.randint(2019, 2026)}-{rng.randint(1, 12):02d}",
                    "agent_id": f"AG-{aid:04d}",
                    "company": company,
                })

            active_subs = sum(1 for s in subscribers if s["status"] == "active")
            revenue = sum(s["monthly_fee"] for s in subscribers if s["status"] == "active")
            agents.append({
                "id": f"AG-{aid:04d}",
                "name": person,
                "office": office,
                # «@» = اسم الوكيل المسجَّل لدى الشركة المجهِّزة له
                "handle": f"@{_COMPANY_CODES.get(company, 'ag')}{aid:04d}",
                "company": company,
                "governorate": gov,
                "phone": _phone(rng),
                "since": rng.randint(2016, 2024),
                "status": status,
                "status_label": _AGENT_STATUS_LABELS[status],
                "service_types": svc_types,
                "service_labels": [national._ACCESS_LABELS[t] for t in svc_types],
                "subscriber_count": len(subscribers),
                "active_subscribers": active_subs,
                "revenue_monthly": revenue,
                "subscribers": subscribers,
            })
    return agents


# ---------------------------------------------------------------------------
# الوكلاء المُسجَّلون يدوياً (يُحفظون في ملف JSON فيبقون بعد إعادة التشغيل)
# ---------------------------------------------------------------------------
_MANUAL_FILE = os.path.join(
    os.path.dirname(__file__), "..", "..", "manual_agents.json")


def _load_manual_agents() -> List[Dict]:
    try:
        if os.path.exists(_MANUAL_FILE):
            with open(_MANUAL_FILE, encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, list):
                    return data
    except Exception:
        pass
    return []


def _save_manual_agents() -> None:
    try:
        with open(_MANUAL_FILE, "w", encoding="utf-8") as f:
            json.dump(_MANUAL_AGENTS, f, ensure_ascii=False, indent=2)
    except Exception:
        pass


_AGENTS = _build_agents()
_MANUAL_AGENTS: List[Dict] = _load_manual_agents()
_AGENTS.extend(_MANUAL_AGENTS)  # الوكلاء اليدويون يظهرون في كل التجميعات
_BY_ID = {a["id"]: a for a in _AGENTS}


def _agent_latlng(a: Dict, centers: Dict) -> Optional[tuple]:
    """إحداثيات الوكيل: المحفوظة إن وُجدت، وإلا مشتقّة من مركز محافظته."""
    if a.get("lat") is not None and a.get("lng") is not None:
        return (a["lat"], a["lng"])
    c = centers.get(a["governorate"])
    if not c:
        return None
    try:
        seed = int(a["id"].split("-")[1])
    except (ValueError, IndexError):
        seed = abs(hash(a["id"])) % 100000
    r = random.Random(seed * 7919)
    return (round(c[0] + r.uniform(-0.11, 0.11), 6),
            round(c[1] + r.uniform(-0.15, 0.15), 6))


def agent_map(governorate: Optional[str] = None,
              company: Optional[str] = None) -> Dict:
    """مواقع الوكلاء الجغرافية — مشتقّة من مركز المحافظة أو المحفوظة (طبقة خريطة)."""
    centers = {g: (lat, lng) for g, _w, lat, lng in national._GOVERNORATES}
    out = []
    for a in _AGENTS:
        if governorate and a["governorate"] != governorate:
            continue
        if company and a["company"] != company:
            continue
        loc = _agent_latlng(a, centers)
        if loc is None:
            continue
        out.append({
            "id": a["id"],
            "name": a["name"],
            "office": a["office"],
            "handle": a["handle"],
            "company": a["company"],
            "governorate": a["governorate"],
            "lat": loc[0],
            "lng": loc[1],
            "status": a["status"],
            "subscriber_count": a["subscriber_count"],
            "active_subscribers": a["active_subscribers"],
            "color": national._COMPANY_COLORS.get(a["company"], "#22D3EE"),
        })
    return {"count": len(out), "agents": out}


def register_agent(payload: Dict) -> Dict:
    """تسجيل وكيل جديد يدوياً — يُحفظ ويظهر في القائمة والخريطة والتجميعات."""
    name = (payload.get("name") or "").strip()
    company = (payload.get("company") or "").strip()
    if not name:
        raise ValueError("اسم الوكيل مطلوب")
    if company not in national._COMPANIES:
        raise ValueError("شركة غير معروفة — اختر شركة من القائمة")

    govs = [g for g, _w, _la, _ln in national._GOVERNORATES]
    gov = (payload.get("governorate") or "").strip()
    if gov not in govs:
        gov = govs[0]

    svc = payload.get("service_types") or national._COMPANY_ACCESS.get(
        company, ["ftth"])
    if isinstance(svc, str):
        svc = [svc]
    svc = [s for s in svc if s in national._ACCESS_LABELS] or ["ftth"]

    status = payload.get("status")
    if status not in ("active", "suspended"):
        status = "active"

    seq = len(_MANUAL_AGENTS) + 1
    aid = f"AG-M{seq:04d}"

    lat = payload.get("lat")
    lng = payload.get("lng")
    if lat is None or lng is None:
        centers = {g: (la, ln) for g, _w, la, ln in national._GOVERNORATES}
        c = centers.get(gov)
        if c:
            r = random.Random(seq * 7919)
            lat = round(c[0] + r.uniform(-0.08, 0.08), 6)
            lng = round(c[1] + r.uniform(-0.10, 0.10), 6)

    agent = {
        "id": aid,
        "name": name,
        "office": (payload.get("office") or f"مكتب {name.split()[0]}").strip(),
        "handle": (payload.get("handle") or
                   f"@{_COMPANY_CODES.get(company, 'ag')}{seq:04d}").strip(),
        "company": company,
        "governorate": gov,
        "phone": (payload.get("phone") or "").strip(),
        "national_id": (payload.get("national_id") or "").strip(),
        "area": (payload.get("area") or "").strip(),
        "address": (payload.get("address") or "").strip(),
        "device_type": (payload.get("device_type") or "").strip(),
        "since": 2026,
        "status": status,
        "status_label": _AGENT_STATUS_LABELS[status],
        "service_types": svc,
        "service_labels": [national._ACCESS_LABELS[t] for t in svc],
        "subscriber_count": 0,
        "active_subscribers": 0,
        "revenue_monthly": 0,
        "lat": lat,
        "lng": lng,
        "manual": True,
        "notes": (payload.get("notes") or "").strip(),
        "subscribers": [],
    }
    _MANUAL_AGENTS.append(agent)
    _save_manual_agents()
    _AGENTS.append(agent)
    _BY_ID[aid] = agent
    return _public(agent)


def _public(agent: Dict) -> Dict:
    """نسخة الوكيل للعرض في القائمة (دون قائمة المشتركين الكاملة)."""
    return {k: v for k, v in agent.items() if k != "subscribers"}


def _agent_service_types(agents: List[Dict]) -> List[str]:
    s = set()
    for a in agents:
        s.update(a["service_types"])
    return sorted(s)


def overview(governorate: Optional[str] = None,
             company: Optional[str] = None,
             service_type: Optional[str] = None) -> Dict:
    """صورة شاملة للوكلاء مع تصفية اختيارية حسب المحافظة/الشركة/نوع الخدمة."""
    agents = _AGENTS
    if governorate:
        agents = [a for a in agents if a["governorate"] == governorate]
    if company:
        agents = [a for a in agents if a["company"] == company]
    if service_type:
        agents = [a for a in agents if service_type in a["service_types"]]

    total_subs = sum(a["subscriber_count"] for a in agents)
    active_subs = sum(a["active_subscribers"] for a in agents)
    revenue = sum(a["revenue_monthly"] for a in agents)

    # توزيع المشتركين حسب نوع الخدمة (يتطلّب المرور على المشتركين)
    subs_by_type: Dict[str, int] = {}
    for a in agents:
        for s in a["subscribers"]:
            if service_type and s["service_type"] != service_type:
                continue
            subs_by_type[s["service_type"]] = subs_by_type.get(s["service_type"], 0) + 1

    by_type = [
        {"type": t, "label": national._ACCESS_LABELS.get(t, t),
         "subscribers": c,
         "agents": sum(1 for a in agents if t in a["service_types"])}
        for t, c in sorted(subs_by_type.items(), key=lambda x: -x[1])
    ]

    totals = {
        "agents": len(agents),
        "subscribers": total_subs,
        "active_subscribers": active_subs,
        "suspended_subscribers": total_subs - active_subs,
        "avg_per_agent": round(total_subs / len(agents), 1) if agents else 0,
        "revenue_monthly": revenue,
        "companies": len({a["company"] for a in agents}),
        "governorates": len({a["governorate"] for a in agents}),
    }

    return {
        "scope": {"governorate": governorate, "company": company,
                  "service_type": service_type},
        "totals": totals,
        "by_company": _group_by(agents, "company"),
        "by_governorate": _group_by(agents, "governorate"),
        "by_service_type": by_type,
        "agents": sorted((_public(a) for a in agents),
                         key=lambda x: x["subscriber_count"], reverse=True),
        "filters": {
            "governorates": [g for g, _, _, _ in national._GOVERNORATES],
            "companies": national._COMPANIES,
            "service_types": [{"type": k, "label": v}
                              for k, v in national._ACCESS_LABELS.items()],
        },
    }


def _group_by(agents: List[Dict], key: str) -> List[Dict]:
    groups: Dict[str, List[Dict]] = {}
    for a in agents:
        groups.setdefault(a[key], []).append(a)
    out = []
    for name, sub in groups.items():
        out.append({
            "name": name,
            "agents": len(sub),
            "subscribers": sum(a["subscriber_count"] for a in sub),
            "active_subscribers": sum(a["active_subscribers"] for a in sub),
            "revenue_monthly": sum(a["revenue_monthly"] for a in sub),
            "color": national._COMPANY_COLORS.get(name, "#22D3EE") if key == "company" else None,
        })
    out.sort(key=lambda x: x["subscribers"], reverse=True)
    return out


def detail(agent_id: str, service_type: Optional[str] = None,
           status: Optional[str] = None) -> Optional[Dict]:
    """تفاصيل وكيل مع قائمة مشتركيه (مع تصفية اختيارية بنوع الخدمة/الحالة)."""
    agent = _BY_ID.get(agent_id)
    if not agent:
        return None
    subs = agent["subscribers"]
    if service_type:
        subs = [s for s in subs if s["service_type"] == service_type]
    if status:
        subs = [s for s in subs if s["status"] == status]
    # توزيع مشتركي الوكيل حسب نوع الخدمة
    by_type: Dict[str, int] = {}
    for s in agent["subscribers"]:
        by_type[s["service_type"]] = by_type.get(s["service_type"], 0) + 1
    result = _public(agent)
    result["by_service_type"] = [
        {"type": t, "label": national._ACCESS_LABELS.get(t, t), "subscribers": c}
        for t, c in sorted(by_type.items(), key=lambda x: -x[1])
    ]
    result["subscribers"] = sorted(subs, key=lambda x: x["name"])
    return result
