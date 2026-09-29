"""
الشبكة الحكومية (Government Intranet) — الوزارات ومؤسساتها المترابطة داخلياً.

شبكة داخلية معزولة **لا تخرج إلى الإنترنت**، تربط مؤسسات الدولة فيما بينها
عبر **VLAN حكومي واحد** (`_GOV_VLAN`) يُضاف إلى **كل أجهزة OLT**. لكل وزارة عدّة
مؤسسات، وكل مؤسسة موصولة بجهاز OLT حقيقي من أسطول `national._FLEET` بمنفذ/ONT
وعنوان IP داخلي وسرعة وحالة.

كل البيانات حتمية (بذرة ثابتة) فتبقى مستقرّة بين الطلبات.
"""
import random
from typing import Dict, List, Optional

from . import national

# ── هوية الشبكة الحكومية ───────────────────────────────────────────────
_GOV_VLAN = 4001            # الـ VLAN الحكومي المُضاف على كل الأجهزة
_VLAN_NAME = "GOV-INTRANET"  # اسم الشبكة الداخلية المعزولة

# ── الوزارات: (المعرّف، الاسم، مفتاح الأيقونة، اللون، أنواع مؤسساتها) ──
_MINISTRIES = [
    ("min-01", "وزارة الاتصالات", "comms", "#22D3EE",
     ["سنترال", "مركز بيانات", "مديرية اتصالات", "مقسّم رئيسي"]),
    ("min-02", "وزارة الكهرباء", "power", "#F59E0B",
     ["محطة تحويل", "مديرية توزيع", "مركز تحكّم", "محطة توليد"]),
    ("min-03", "وزارة الصحة", "health", "#34D399",
     ["مستشفى", "مركز صحي", "دائرة صحة", "بنك دم"]),
    ("min-04", "وزارة التربية", "education", "#818CF8",
     ["مديرية تربية", "مجمع مدارس", "معهد إعداد"]),
    ("min-05", "وزارة التعليم العالي", "university", "#A78BFA",
     ["جامعة", "كلية", "مركز بحوث"]),
    ("min-06", "وزارة الداخلية", "interior", "#60A5FA",
     ["مديرية", "مركز شرطة", "دائرة أحوال مدنية", "منفذ حدودي"]),
    ("min-07", "وزارة المالية", "finance", "#4ADE80",
     ["مصرف حكومي", "دائرة ضريبة", "خزينة", "دائرة كمارك"]),
    ("min-08", "وزارة النفط", "oil", "#F472B6",
     ["مصفى", "مستودع", "شركة توزيع", "مركز مراقبة"]),
    ("min-09", "وزارة العدل", "justice", "#FBBF24",
     ["محكمة", "دائرة تنفيذ", "كاتب عدل", "سجل عقاري"]),
    ("min-10", "وزارة الموارد المائية", "water", "#38BDF8",
     ["سد", "مديرية ري", "محطة ضخ", "مركز رصد"]),
]

# سرعات الربط الداخلي الممكنة (Mbps) وأوزانها
_BANDWIDTHS = [50, 100, 155, 200, 300, 500, 1000]
_BW_WEIGHTS = [0.10, 0.22, 0.16, 0.24, 0.14, 0.10, 0.04]

# أولوية المؤسسة (حساسيتها) — تؤثّر على سياسة الخدمة
_PRIORITIES = [("حرج", 0.18), ("عالٍ", 0.34), ("متوسط", 0.48)]


def _fleet_by_gov() -> Dict[str, List[Dict]]:
    idx: Dict[str, List[Dict]] = {}
    for d in national._FLEET:
        idx.setdefault(d["governorate"], []).append(d)
    return idx


def _sn(seed: int) -> str:
    """رقم تسلسلي بصيغة هواوي (HWTC + 8 خانات هيكس)."""
    tail = (0xA0000000 + seed * 0x9E37) & 0xFFFFFFFF
    return f"HWTC{tail:08X}"


def _build() -> Dict:
    """توليد الوزارات ومؤسساتها حتمياً وربطها بأجهزة OLT من الأسطول الوطني."""
    rng = random.Random(20260724)
    fleet_by_gov = _fleet_by_gov()
    govs = [g for g, _c, _la, _ln in national._GOVERNORATES]
    # ترجيح المحافظات بعدد أجهزتها (المدن الكبرى تستضيف مؤسسات أكثر)
    gov_weights = [max(1, len(fleet_by_gov.get(g, []))) for g in govs]

    ministries: List[Dict] = []
    institutions: List[Dict] = []
    inst_seq = 0

    for m_idx, (mid, mname, icon, color, types) in enumerate(_MINISTRIES, start=1):
        n = rng.randint(4, 11)  # عدد مؤسسات الوزارة
        m_insts: List[Dict] = []
        for _ in range(n):
            inst_seq += 1
            gov = rng.choices(govs, gov_weights)[0]
            candidates = fleet_by_gov.get(gov) or national._FLEET
            olt = rng.choice(candidates)
            itype = rng.choice(types)

            # منفذ F/S/P على الجهاز + معرّف ONT
            frame, slot = 0, rng.randint(0, 15)
            port = rng.randint(0, 15)
            ont_id = rng.randint(1, 63)

            bw = rng.choices(_BANDWIDTHS, _BW_WEIGHTS)[0]
            prio = rng.choices([p for p, _w in _PRIORITIES],
                               [w for _p, w in _PRIORITIES])[0]

            # حالة المؤسسة متّسقة مع حالة جهازها: جهاز مُطفأ → مؤسسة غير متصلة
            if olt["status"] == "offline":
                status = "offline"
            else:
                r = rng.random()
                status = "online" if r > 0.10 else (
                    "degraded" if r > 0.035 else "offline")

            up_days = 0 if status == "offline" else rng.randint(3, 640)

            inst = {
                "id": f"inst-{inst_seq:04d}",
                "ministry_id": mid,
                "ministry": mname,
                "name": f"{itype} - {gov}",
                "type": itype,
                "governorate": gov,
                "olt_id": olt["id"],
                "olt_name": olt["name"],
                "olt_model": olt["model"],
                "fsp": f"{frame}/{slot}/{port}",
                "ont_id": ont_id,
                "sn": _sn(inst_seq),
                "vlan": _GOV_VLAN,
                # عنوان IP داخلي معزول: 10.<الوزارة>.<المؤسسة>.1
                "ip": f"10.{m_idx}.{(inst_seq % 250) + 1}.1",
                "bandwidth_mbps": bw,
                "priority": prio,
                "status": status,
                "uptime_days": up_days,
            }
            institutions.append(inst)
            m_insts.append(inst)

        online = sum(1 for i in m_insts if i["status"] == "online")
        degraded = sum(1 for i in m_insts if i["status"] == "degraded")
        offline = sum(1 for i in m_insts if i["status"] == "offline")
        m_status = ("offline" if online == 0 else
                    ("degraded" if (degraded + offline) > 0 else "online"))
        ministries.append({
            "id": mid,
            "name": mname,
            "icon": icon,
            "color": color,
            "institutions": len(m_insts),
            "online": online,
            "degraded": degraded,
            "offline": offline,
            "governorates": sorted({i["governorate"] for i in m_insts}),
            "bandwidth_mbps": sum(i["bandwidth_mbps"] for i in m_insts),
            "status": m_status,
        })

    return {"ministries": ministries, "institutions": institutions}


_DATA = _build()


def overview() -> Dict:
    """صورة الشبكة الحكومية: هوية الـ VLAN، إجماليات، وقائمة الوزارات."""
    insts = _DATA["institutions"]
    ministries = _DATA["ministries"]
    return {
        "gov_vlan": _GOV_VLAN,
        "vlan_name": _VLAN_NAME,
        "isolated": True,  # معزولة عن الإنترنت
        "olts_count": len(national._FLEET),  # الـ VLAN مُضاف على كل الأجهزة
        "totals": {
            "ministries": len(ministries),
            "institutions": len(insts),
            "online": sum(1 for i in insts if i["status"] == "online"),
            "degraded": sum(1 for i in insts if i["status"] == "degraded"),
            "offline": sum(1 for i in insts if i["status"] == "offline"),
            "governorates": len({i["governorate"] for i in insts}),
            "bandwidth_mbps": sum(i["bandwidth_mbps"] for i in insts),
        },
        "ministries": ministries,
    }


def ministry(ministry_id: str) -> Dict:
    """تفاصيل وزارة واحدة مع كل مؤسساتها المرتبطة."""
    m = next((x for x in _DATA["ministries"] if x["id"] == ministry_id), None)
    if m is None:
        raise ValueError("وزارة غير معروفة")
    insts = [i for i in _DATA["institutions"] if i["ministry_id"] == ministry_id]
    # ترتيب: غير المتصلة أولاً ثم الأعلى أولوية ثم الأعلى سرعة
    prio_order = {"حرج": 0, "عالٍ": 1, "متوسط": 2}
    status_order = {"offline": 0, "degraded": 1, "online": 2}
    insts = sorted(insts, key=lambda i: (
        status_order.get(i["status"], 9),
        prio_order.get(i["priority"], 9),
        -i["bandwidth_mbps"]))
    return {
        "ministry": m,
        "gov_vlan": _GOV_VLAN,
        "vlan_name": _VLAN_NAME,
        "institutions": insts,
    }
