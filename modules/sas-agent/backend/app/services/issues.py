"""
مشاكل الشركات ومستوى الخدمة (SLA) — سجلّ أعطال/بلاغات حتمي للأسطول الوطني.

بما أن النظام يدير جهازاً واحداً في وضع التطوير، تُولَّد هنا صورة حتمية
(deterministic) لبلاغات الأعطال عبر كل الشركات والمحافظات، مصنّفة حسب
التزامها بزمن الخدمة المتّفق عليه (SLA):

- «حُلّت ضمن الوقت المحدد»   (on_time)     — أُغلقت قبل انتهاء المهلة.
- «لم تُحلّ ضمن الوقت المحدد» (breached)    — تجاوزت المهلة (حُلّت متأخرة أو ما زالت مفتوحة).
- «قيد التنفيذ»              (in_progress) — مفتوحة وضمن المهلة بعد.

كل الأرقام تُشتق من بذرة ثابتة فتبقى مستقرّة بين الطلبات. يعيد استخدام
أسطول `national._FLEET` (المحافظات/الشركات/الأجهزة) لضمان الاتساق.
"""
import json
import os
import random
from datetime import datetime, timezone
from typing import Dict, List, Optional

from . import national

# حالات البلاغ الثلاث (وِسومها العربية وألوانها الدلالية)
_STATUS_LABELS = {
    "on_time": "حُلّت ضمن الوقت المحدد",
    "breached": "لم تُحلّ ضمن الوقت المحدد",
    "in_progress": "قيد التنفيذ",
}

# أنواع الأعطال الشائعة على شبكات الوصول
_ISSUE_TYPES = [
    "انقطاع خدمة",
    "بطء في السرعة",
    "قدرة ضوئية منخفضة",
    "عطل منفذ PON",
    "إنذار جهاز (Hardware)",
    "انقطاع تيار كهربائي",
    "خطأ في التهيئة",
    "تدهور جودة (Video/VoIP)",
    "مشكلة اشتراك/تفعيل",
    "قطع ألياف (Fiber Cut)",
]

# شدّة العطل ومهلة الخدمة (SLA) بالساعات ووزنها في التوليد
_SEVERITIES = [
    # (label, priority, sla_hours, weight)
    ("حرج", "P1", 4, 0.14),
    ("عالٍ", "P2", 8, 0.28),
    ("متوسط", "P3", 24, 0.38),
    ("منخفض", "P4", 48, 0.20),
]

# مستوى التزام كل شركة بالـ SLA (نسبة تقريبية) — يمنح كل شركة أداءً مميّزاً،
# فتظهر شركات ملتزمة وأخرى متعثّرة (لديها بلاغات لم تُحلّ ضمن الوقت المحدد).
_COMPANY_SLA_TARGET = {
    "الصدارة نت": 0.90,
    "إيرثلنك": 0.87,
    "الجزيرة": 0.82,
    "سوبر سيل": 0.73,
    "هلا": 0.66,
}

# حصّة البلاغات المفتوحة قيد التنفيذ (ضمن المهلة بعد)
_IN_PROGRESS_SHARE = 0.13

# غرامة تأخّر الصيانة على الشركة — بالدينار العراقي لكل **دقيقة** تأخّر بعد انتهاء
# المهلة (SLA)، وتختلف حسب نوع الصيانة/العطل (الأشدّ تأثيراً على الخدمة أغلى غرامة).
_PENALTY_PER_MIN = {
    "قطع ألياف (Fiber Cut)": 500,
    "انقطاع خدمة": 400,
    "عطل منفذ PON": 350,
    "إنذار جهاز (Hardware)": 300,
    "قدرة ضوئية منخفضة": 200,
    "تدهور جودة (Video/VoIP)": 200,
    "خطأ في التهيئة": 150,
    "بطء في السرعة": 150,
    "انقطاع تيار كهربائي": 100,
    "مشكلة اشتراك/تفعيل": 80,
}


def _build_issues() -> List[Dict]:
    """توليد سجلّ بلاغات حتمي مبني على أسطول OLT الوطني.

    لكل شركة نسبة التزام مستهدفة بالـ SLA، وتُولَّد الحالات لتقاربها؛ مع ضبط
    حقول العمر وزمن الحل لتبقى متّسقة مع الحالة (محلول في الوقت/متأخر/قيد التنفيذ).
    """
    rng = random.Random(20260722)  # بذرة ثابتة → بيانات مستقرّة
    fleet = national._FLEET
    issues: List[Dict] = []
    iid = 0
    max_age = 14 * 24  # 14 يوماً بالساعات

    sev_labels = [s[0] for s in _SEVERITIES]
    sev_weights = [s[3] for s in _SEVERITIES]
    sev_meta = {s[0]: {"priority": s[1], "sla_hours": s[2]} for s in _SEVERITIES}

    for dev in fleet:
        # عدد البلاغات لهذا الجهاز يتناسب مع عدد مشاكله الحالية + خلفية عشوائية
        base = dev["problems"] * rng.randint(2, 4)
        n = base + rng.choices([0, 1, 2], [0.55, 0.30, 0.15])[0]
        if dev["status"] == "offline":
            n += rng.randint(1, 3)
        compliance = _COMPANY_SLA_TARGET.get(dev["company"], 0.80)
        for _ in range(n):
            iid += 1
            sev = rng.choices(sev_labels, sev_weights)[0]
            meta = sev_meta[sev]
            sla = meta["sla_hours"]
            itype = rng.choice(_ISSUE_TYPES)

            r = rng.random()
            if r < _IN_PROGRESS_SHARE:
                # قيد التنفيذ: مفتوح وضمن المهلة بعد (حديث)
                status = "in_progress"
                opened_hours_ago = round(rng.uniform(0.2, max(sla * 0.85, 1)), 1)
                resolution_hours = None
            elif rng.random() < compliance:
                # حُلّ ضمن الوقت المحدد
                status = "on_time"
                resolution_hours = round(rng.uniform(0.3, sla * 0.9), 1)
                opened_hours_ago = round(
                    resolution_hours + rng.uniform(0, min(max_age - resolution_hours, 120)), 1)
            else:
                # لم يُحلّ ضمن الوقت المحدد (متأخر): إمّا حُلّ متأخراً أو ما زال مفتوحاً
                status = "breached"
                if rng.random() < 0.55:
                    resolution_hours = round(rng.uniform(sla * 1.15, min(sla * 3.0, 300)), 1)
                    opened_hours_ago = round(
                        resolution_hours + rng.uniform(0, min(max_age - resolution_hours, 80)), 1)
                else:
                    resolution_hours = None
                    opened_hours_ago = round(rng.uniform(sla * 1.2, max_age), 1)

            # غرامة التأخّر: تُحتسب فقط على البلاغات التي تجاوزت المهلة (breached)،
            # بالدينار = دقائق التأخّر بعد المهلة × غرامة الدقيقة لنوع الصيانة.
            rate = _PENALTY_PER_MIN.get(itype, 100)
            if status == "breached":
                ref = resolution_hours if resolution_hours is not None else opened_hours_ago
                overdue_minutes = max(0, round((ref - sla) * 60))
            else:
                overdue_minutes = 0
            penalty = overdue_minutes * rate

            issues.append({
                "id": f"INC-{iid:05d}",
                "company": dev["company"],
                "governorate": dev["governorate"],
                "device": dev["name"],
                "device_id": dev["id"],
                "type": itype,
                "severity": sev,
                "priority": meta["priority"],
                "status": status,
                "status_label": _STATUS_LABELS[status],
                "sla_hours": sla,
                "opened_hours_ago": opened_hours_ago,
                "opened_label": _age_label(opened_hours_ago),
                "resolution_hours": resolution_hours,
                "overdue_by": (round(opened_hours_ago - sla, 1)
                               if status == "breached" and resolution_hours is None
                               else None),
                "penalty_per_min": rate,
                "overdue_minutes": overdue_minutes,
                "penalty": penalty,
            })
    return issues


def _age_label(hours: float) -> str:
    """وصف عربي مختصر لعمر البلاغ."""
    if hours < 1:
        return f"منذ {int(hours * 60)} دقيقة"
    if hours < 24:
        return f"منذ {int(hours)} ساعة"
    days = int(hours // 24)
    return f"منذ {days} يوم"


_ISSUES = _build_issues()


# ---------------------------------------------------------------------------
# المشاكل المُضافة يدوياً (تُحفظ في ملف JSON فتبقى بعد إعادة التشغيل)
# ---------------------------------------------------------------------------
# ملف تخزين المشاكل اليدوية بجانب مجلد backend (مسار متوافق مع ويندوز).
_MANUAL_FILE = os.path.join(
    os.path.dirname(__file__), "..", "..", "manual_issues.json")


def _load_manual() -> List[Dict]:
    """تحميل المشاكل المُضافة يدوياً من ملف JSON (قائمة فارغة إن غاب/تعذّر)."""
    try:
        if os.path.exists(_MANUAL_FILE):
            with open(_MANUAL_FILE, encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, list):
                    return data
    except Exception:
        pass
    return []


def _save_manual() -> None:
    """حفظ المشاكل اليدوية إلى ملف JSON (عربي مقروء)."""
    try:
        with open(_MANUAL_FILE, "w", encoding="utf-8") as f:
            json.dump(_MANUAL, f, ensure_ascii=False, indent=2)
    except Exception:
        pass


_MANUAL: List[Dict] = _load_manual()


def _all_issues() -> List[Dict]:
    """كل البلاغات: المولّدة حتمياً + المُضافة يدوياً."""
    return _ISSUES + _MANUAL


def _sev_meta(label: str) -> tuple:
    """(الأولوية، مهلة SLA بالساعات) لشدّة معيّنة — الافتراضي «متوسط»."""
    for l, pri, sla, _w in _SEVERITIES:
        if l == label:
            return pri, sla
    return "P3", 24


def _govs_for_company(company: str) -> List[str]:
    """المحافظات التي تعمل بها الشركة (من أسطول OLT الوطني)."""
    return sorted({d["governorate"] for d in national._FLEET
                   if d["company"] == company})


def create_issue(type: str, company: str,
                 severity: Optional[str] = None,
                 governorate: Optional[str] = None,
                 description: Optional[str] = None) -> Dict:
    """إنشاء بلاغ عطل يدوي بحالة «قيد التنفيذ» (مهمة مفتوحة) لشركة محدّدة.

    يُضاف إلى مخزن المشاكل اليدوية ويُحفظ فوراً، فيظهر في تجميعات الشركة
    وقائمة البلاغات. النوع/الشركة إلزاميان؛ الشدّة/المحافظة/الوصف اختيارية.
    """
    itype = (type or "").strip() or _ISSUE_TYPES[0]
    comp = (company or "").strip()
    if comp not in national._COMPANIES:
        raise ValueError("شركة غير معروفة — اختر شركة من القائمة.")

    sev = severity if severity in [s[0] for s in _SEVERITIES] else "متوسط"
    pri, sla = _sev_meta(sev)

    gov = (governorate or "").strip()
    if not gov:
        govs = _govs_for_company(comp)
        gov = govs[0] if govs else national._GOVERNORATES[0][0]

    seq = len(_MANUAL) + 1
    now = datetime.now(timezone.utc)
    issue = {
        "id": f"INC-M{seq:04d}",
        "company": comp,
        "governorate": gov,
        "device": "—",
        "device_id": None,
        "type": itype,
        "severity": sev,
        "priority": pri,
        "status": "in_progress",  # مهمة مفتوحة (ضمن المهلة بعد)
        "status_label": _STATUS_LABELS["in_progress"],
        "sla_hours": sla,
        "opened_hours_ago": 0.0,
        "opened_label": "الآن",
        "resolution_hours": None,
        "overdue_by": None,
        "penalty_per_min": _PENALTY_PER_MIN.get(itype, 100),
        "overdue_minutes": 0,
        "penalty": 0,
        "manual": True,
        "description": (description or "").strip(),
        "created_at": now.isoformat(timespec="seconds"),
    }
    _MANUAL.append(issue)
    _save_manual()
    return issue


# ---------------------------------------------------------------------------
# تجميعات
# ---------------------------------------------------------------------------

def _counts(items: List[Dict]) -> Dict[str, int]:
    c = {"on_time": 0, "breached": 0, "in_progress": 0}
    for it in items:
        c[it["status"]] += 1
    return c


def _sla_pct(c: Dict[str, int]) -> float:
    """نسبة الالتزام: المحلولة في الوقت ÷ (المحلولة في الوقت + المُخِلّة)."""
    decided = c["on_time"] + c["breached"]
    return round(c["on_time"] / decided * 100, 1) if decided else 100.0


def _avg_resolution(items: List[Dict]) -> float:
    vals = [it["resolution_hours"] for it in items if it["resolution_hours"] is not None]
    return round(sum(vals) / len(vals), 1) if vals else 0.0


def _agg(items: List[Dict]) -> Dict:
    c = _counts(items)
    return {
        "total": len(items),
        "on_time": c["on_time"],
        "breached": c["breached"],
        "in_progress": c["in_progress"],
        "resolved": sum(1 for it in items if it["resolution_hours"] is not None),
        "sla_compliance_pct": _sla_pct(c),
        "avg_resolution_hours": _avg_resolution(items),
        "critical_open": sum(1 for it in items
                             if it["severity"] == "حرج" and it["status"] != "on_time"),
        # غرامات التأخّر
        "total_penalty": sum(it["penalty"] for it in items),
        "penalized_count": sum(1 for it in items if it["penalty"] > 0),
        "total_overdue_minutes": sum(it["overdue_minutes"] for it in items),
    }


def _group_by(items: List[Dict], key: str) -> List[Dict]:
    groups: Dict[str, List[Dict]] = {}
    for it in items:
        groups.setdefault(it[key], []).append(it)
    out = []
    for name, sub in groups.items():
        a = _agg(sub)
        a["name"] = name
        if key == "company":
            a["color"] = national._COMPANY_COLORS.get(name, "#22D3EE")
        out.append(a)
    # ترتيب: الأكثر إخلالاً بالـ SLA أولاً ثم الأكثر بلاغات
    out.sort(key=lambda x: (-x["breached"], -x["total"]))
    return out


def _distribution(items: List[Dict], key: str) -> List[Dict]:
    counts: Dict[str, int] = {}
    for it in items:
        counts[it[key]] = counts.get(it[key], 0) + 1
    out = [{"name": k, "count": v} for k, v in counts.items()]
    out.sort(key=lambda x: x["count"], reverse=True)
    return out


def _by_maintenance_type(items: List[Dict]) -> List[Dict]:
    """قائمة أنواع الصيانة مع غرامة الدقيقة والغرامة المتراكمة على الشركات عن التأخّر.

    تعرض كل الأنواع (حتى ما لم يتأخّر منها) لتكون كتالوج غرامات مرجعياً.
    """
    agg: Dict[str, Dict] = {}
    for it in items:
        g = agg.setdefault(it["type"], {"count": 0, "breached": 0,
                                        "overdue_minutes": 0, "penalty": 0})
        g["count"] += 1
        if it["penalty"] > 0:
            g["breached"] += 1
            g["overdue_minutes"] += it["overdue_minutes"]
            g["penalty"] += it["penalty"]
    out = []
    for ty in _ISSUE_TYPES:
        g = agg.get(ty, {"count": 0, "breached": 0,
                         "overdue_minutes": 0, "penalty": 0})
        out.append({
            "type": ty,
            "penalty_per_min": _PENALTY_PER_MIN.get(ty, 100),
            "count": g["count"],
            "breached": g["breached"],
            "overdue_minutes": g["overdue_minutes"],
            "penalty": g["penalty"],
        })
    out.sort(key=lambda x: (-x["penalty"], -x["penalty_per_min"]))
    return out


def _trend(items: List[Dict], days: int = 14) -> List[Dict]:
    """اتجاه يومي: عدد البلاغات المفتوحة مقابل المحلولة لكل يوم (آخر 14 يوماً)."""
    opened = [0] * days
    resolved = [0] * days
    for it in items:
        # يوم الفتح: 0 = قبل 14 يوماً ... days-1 = اليوم
        d_open = days - 1 - int(it["opened_hours_ago"] // 24)
        if 0 <= d_open < days:
            opened[d_open] += 1
        if it["resolution_hours"] is not None:
            closed_hours_ago = it["opened_hours_ago"] - it["resolution_hours"]
            d_close = days - 1 - int(closed_hours_ago // 24)
            if 0 <= d_close < days:
                resolved[d_close] += 1
    out = []
    for i in range(days):
        ago = days - 1 - i
        label = "اليوم" if ago == 0 else f"-{ago}ي"
        out.append({"day": label, "opened": opened[i], "resolved": resolved[i]})
    return out


def overview(governorate: Optional[str] = None,
             company: Optional[str] = None) -> Dict:
    """صورة شاملة لبلاغات الأعطال مع تصفية اختيارية حسب المحافظة/الشركة."""
    items = _all_issues()
    if governorate:
        items = [i for i in items if i["governorate"] == governorate]
    if company:
        items = [i for i in items if i["company"] == company]

    totals = _agg(items)
    totals["governorates"] = len({i["governorate"] for i in items})
    totals["companies"] = len({i["company"] for i in items})

    # أحدث البلاغات المفتوحة/المتأخرة أولاً للعرض في جدول
    def _rank(it: Dict) -> tuple:
        sev_order = {"حرج": 0, "عالٍ": 1, "متوسط": 2, "منخفض": 3}
        status_order = {"breached": 0, "in_progress": 1, "on_time": 2}
        return (status_order[it["status"]], sev_order.get(it["severity"], 9),
                -it["opened_hours_ago"])

    # المشاكل المُضافة يدوياً تتصدّر القائمة (الأحدث أولاً) لتظهر فور إضافتها،
    # يتبعها بقية البلاغات مرتّبة بالأولوية.
    manual_items = [it for it in items if it.get("manual")]
    manual_items.sort(key=lambda it: it.get("created_at", ""), reverse=True)
    gen_items = [it for it in items if not it.get("manual")]
    recent = (manual_items + sorted(gen_items, key=_rank))[:24]

    return {
        "scope": {"governorate": governorate, "company": company},
        "totals": totals,
        "by_company": _group_by(items, "company"),
        "by_governorate": _group_by(items, "governorate"),
        "by_type": _distribution(items, "type"),
        "by_severity": _distribution(items, "severity"),
        "by_maintenance_type": _by_maintenance_type(items),
        "status_labels": _STATUS_LABELS,
        "trend": _trend(items),
        "recent": recent,
        "filters": {
            "governorates": [g for g, _, _, _ in national._GOVERNORATES],
            "companies": national._COMPANIES,
            "types": _ISSUE_TYPES,
            "severities": [s[0] for s in _SEVERITIES],
        },
    }


# ---------------------------------------------------------------------------
# التقارير
# ---------------------------------------------------------------------------

def report(governorate: Optional[str] = None,
           company: Optional[str] = None) -> Dict:
    """تقرير نصّي (Markdown عربي) قابل للعرض والنسخ حول حالة الأعطال والـ SLA."""
    data = overview(governorate, company)
    t = data["totals"]
    scope = "العراق (كل الشركات والمحافظات)"
    if governorate:
        scope = f"محافظة {governorate}"
    elif company:
        scope = f"شركة {company}"

    lines: List[str] = []
    lines.append(f"# تقرير مشاكل الشبكة ومستوى الخدمة (SLA)")
    lines.append(f"**النطاق:** {scope}")
    lines.append("")
    lines.append("## ملخّص تنفيذي")
    lines.append(f"- إجمالي البلاغات: **{t['total']}**")
    lines.append(f"- حُلّت ضمن الوقت المحدد: **{t['on_time']}**")
    lines.append(f"- لم تُحلّ ضمن الوقت المحدد: **{t['breached']}**")
    lines.append(f"- قيد التنفيذ: **{t['in_progress']}**")
    lines.append(f"- نسبة الالتزام بالـ SLA: **{t['sla_compliance_pct']}%**")
    lines.append(f"- متوسط زمن الحل: **{t['avg_resolution_hours']} ساعة**")
    lines.append(f"- بلاغات حرجة مفتوحة: **{t['critical_open']}**")
    lines.append(
        f"- إجمالي غرامات التأخّر: **{t['total_penalty']:,} د.ع** "
        f"({t['penalized_count']} بلاغ متأخر · {t['total_overdue_minutes']:,} دقيقة).")
    lines.append("")

    lines.append("## أداء الشركات (SLA)")
    lines.append("| الشركة | إجمالي | في الوقت | متأخرة | قيد التنفيذ | الالتزام % |")
    lines.append("|---|---|---|---|---|---|")
    for c in data["by_company"]:
        lines.append(
            f"| {c['name']} | {c['total']} | {c['on_time']} | {c['breached']} "
            f"| {c['in_progress']} | {c['sla_compliance_pct']}% |")
    lines.append("")

    lines.append("## غرامات تأخّر الصيانة (بالدقيقة)")
    lines.append(
        f"إجمالي الغرامات: **{t['total_penalty']:,} د.ع** على "
        f"**{t['penalized_count']}** بلاغ متأخر "
        f"(**{t['total_overdue_minutes']:,}** دقيقة تأخير إجمالاً).")
    lines.append("")
    lines.append(
        "| نوع الصيانة | غرامة/دقيقة (د.ع) | بلاغات متأخرة | دقائق التأخير | إجمالي الغرامة (د.ع) |")
    lines.append("|---|---|---|---|---|")
    for m in data["by_maintenance_type"]:
        if m["penalty"] > 0:
            lines.append(
                f"| {m['type']} | {m['penalty_per_min']:,} | {m['breached']} "
                f"| {m['overdue_minutes']:,} | {m['penalty']:,} |")
    lines.append("")

    lines.append("## أعلى المحافظات بالبلاغات المتأخرة")
    for g in data["by_governorate"][:8]:
        lines.append(
            f"- {g['name']}: {g['breached']} متأخرة من أصل {g['total']} "
            f"(التزام {g['sla_compliance_pct']}%)")
    lines.append("")

    lines.append("## توزيع أنواع الأعطال")
    for ty in data["by_type"][:8]:
        lines.append(f"- {ty['name']}: {ty['count']}")
    lines.append("")

    # توصيات مبنية على القواعد
    lines.append("## التوصيات")
    if t["sla_compliance_pct"] < 80:
        lines.append("- ⚠️ نسبة الالتزام دون 80% — راجع تخصيص فرق الصيانة وأولويات البلاغات الحرجة.")
    worst = data["by_company"][0] if data["by_company"] else None
    if worst and worst["breached"] > 0:
        lines.append(
            f"- الشركة الأكثر إخلالاً: **{worst['name']}** ({worst['breached']} بلاغ متأخر) "
            "— تحتاج خطة تحسين SLA.")
    if t["critical_open"] > 0:
        lines.append(f"- توجد **{t['critical_open']}** بلاغات حرجة مفتوحة تتطلّب تدخّلاً فورياً.")
    if t["breached"] == 0:
        lines.append("- ✅ لا توجد بلاغات مُخِلّة بالـ SLA في هذا النطاق.")
    lines.append("")
    lines.append("_تقرير آلي من منصّة العراق الرقمية._")

    return {
        "scope": data["scope"],
        "title": f"تقرير SLA — {scope}",
        "markdown": "\n".join(lines),
        "totals": t,
    }


# ---------------------------------------------------------------------------
# تحليل ذكي (قواعد محلية + Claude إن توفّر المفتاح)
# ---------------------------------------------------------------------------

def _grade(sla: float) -> tuple:
    """تقييم أداء الالتزام: (وسم عربي، مفتاح دلالي للّون)."""
    if sla >= 90:
        return ("ممتاز", "excellent")
    if sla >= 75:
        return ("جيد", "good")
    return ("متعثّر", "poor")


def _company_note(c: Dict) -> str:
    """قراءة تلقائية موجزة لأداء شركة واحدة (سبب التقييم + أبرز المخاطر)."""
    sla = c["sla_compliance_pct"]
    if sla >= 90:
        base = "أداء ممتاز في الالتزام بزمن الخدمة"
    elif sla >= 75:
        base = "أداء مقبول مع مجال لتقليص زمن الاستجابة"
    else:
        base = "أداء متعثّر يتطلّب خطة تحسين SLA عاجلة"
    extra: List[str] = []
    if c["breached"] > 0:
        extra.append(f"{c['breached']} بلاغ متأخر")
    if c["critical_open"] > 0:
        extra.append(f"{c['critical_open']} حرج مفتوح")
    if c.get("total_penalty", 0) > 0:
        extra.append(f"غرامة {c['total_penalty']:,} د.ع")
    return f"{base} (" + " · ".join(extra) + ")." if extra else f"{base}."


def _company_detail(comps: List[Dict]) -> List[Dict]:
    """إثراء تجميعات الشركات بترتيب وتقييم وقراءة تلقائية لكل شركة."""
    out: List[Dict] = []
    for i, c in enumerate(comps):
        label, key = _grade(c["sla_compliance_pct"])
        d = dict(c)
        d["rank"] = i + 1
        d["grade"] = label
        d["grade_key"] = key
        d["note"] = _company_note(c)
        out.append(d)
    return out


def _highlights(data: Dict) -> Dict:
    """أبرز النقاط عند لمحة واحدة: أسوأ/أفضل شركة، أكثر محافظة تأخّراً، أبرز عطل."""
    comps = data["by_company"]
    govs = data["by_governorate"]
    types = data["by_type"]
    h: Dict = {"worst_company": None, "best_company": None,
               "worst_governorate": None, "top_type": None}
    if comps:
        worst = comps[0]  # مرتّبة: الأكثر إخلالاً أولاً
        if worst["breached"] > 0:
            h["worst_company"] = {"name": worst["name"],
                                  "breached": worst["breached"],
                                  "sla": worst["sla_compliance_pct"]}
        best = max(comps, key=lambda c: c["sla_compliance_pct"])
        h["best_company"] = {"name": best["name"], "sla": best["sla_compliance_pct"]}
    if govs:
        gw = max(govs, key=lambda g: g["breached"])
        if gw["breached"] > 0:
            h["worst_governorate"] = {"name": gw["name"], "breached": gw["breached"],
                                      "sla": gw["sla_compliance_pct"]}
    if types:
        tt = types[0]
        h["top_type"] = {"name": tt["name"], "count": tt["count"]}
    return h


def _rule_based_parts(data: Dict) -> Dict:
    """القراءة القائمة على القواعد مُهيكلة: عنوان + ملاحظات + توصيات (بلا رموز/بادئات)."""
    t = data["totals"]
    comps = data["by_company"]
    govs = data["by_governorate"]
    scope = data["scope"]
    where = ""
    if scope.get("governorate"):
        where = f" (محافظة {scope['governorate']})"
    elif scope.get("company"):
        where = f" (شركة {scope['company']})"
    headline = f"تحليل مشاكل الشبكة ومستوى الخدمة{where}"

    insights: List[str] = []
    insights.append(
        f"الإجمالي {t['total']} بلاغ — {t['on_time']} حُلّت في الوقت، "
        f"{t['breached']} تجاوزت المهلة، {t['in_progress']} قيد التنفيذ.")
    insights.append(
        f"الالتزام بالـ SLA {t['sla_compliance_pct']}% بمتوسط زمن حل "
        f"{t['avg_resolution_hours']} ساعة.")
    if t["critical_open"] > 0:
        insights.append(f"{t['critical_open']} بلاغ حرج مفتوح يتطلّب أولوية قصوى.")
    if comps and comps[0]["breached"] > 0:
        w = comps[0]
        insights.append(
            f"أكثر شركة إخلالاً: {w['name']} ({w['breached']} متأخر، "
            f"التزام {w['sla_compliance_pct']}%).")
    if comps:
        b = max(comps, key=lambda c: c["sla_compliance_pct"])
        insights.append(f"أفضل التزاماً: {b['name']} ({b['sla_compliance_pct']}%).")
    if govs:
        gw = max(govs, key=lambda g: g["breached"])
        if gw["breached"] > 0:
            insights.append(
                f"أكثر محافظة تأخيراً: {gw['name']} ({gw['breached']} بلاغ متأخر).")
    if data["by_type"]:
        tp = data["by_type"][0]
        insights.append(f"أبرز نوع عطل: {tp['name']} ({tp['count']} بلاغ).")
    if t.get("total_penalty", 0) > 0:
        insights.append(
            f"غرامات التأخّر بلغت {t['total_penalty']:,} د.ع على "
            f"{t['penalized_count']} بلاغ متأخر.")

    recs: List[str] = []
    if t["sla_compliance_pct"] >= 90:
        recs.append("الأداء ممتاز — حافظ على مستوى الاستجابة الحالي والصيانة الوقائية.")
    elif t["sla_compliance_pct"] >= 75:
        recs.append("راجع أولوية البلاغات الحرجة لتقليص زمن الاستجابة ورفع الالتزام فوق 90%.")
    else:
        recs.append("الالتزام منخفض — أعد توزيع فرق الصيانة وخطّط لصيانة استباقية.")
    if comps and comps[0]["breached"] > 0:
        recs.append(
            f"ضع خطة تحسين SLA لـ {comps[0]['name']} "
            f"({comps[0]['breached']} بلاغ متأخر).")
    if t["critical_open"] > 0:
        recs.append(f"عالج فوراً {t['critical_open']} بلاغ حرج مفتوح (أولوية قصوى).")
    if t.get("total_penalty", 0) > 0:
        recs.append(
            f"عالج البلاغات المتأخرة لوقف تراكم الغرامات "
            f"({t['total_penalty']:,} د.ع حتى الآن).")
    if t["breached"] == 0:
        recs.append("لا بلاغات مُخِلّة بالـ SLA في هذا النطاق — وضع ممتاز.")

    return {"headline": headline, "insights": insights, "recommendations": recs}


def _rule_based_analysis(data: Dict) -> str:
    """النص المسطّح للقراءة القائمة على القواعد (يُبنى من الأجزاء المُهيكلة)."""
    p = _rule_based_parts(data)
    lines: List[str] = [f"🛠️ {p['headline']}:"]
    lines += [f"• {i}" for i in p["insights"]]
    lines += [f"• {r}" for r in p["recommendations"]]
    lines.append("— (تحليل آلي من قواعد المحرّك؛ فعّل ANTHROPIC_API_KEY لتحليل أعمق.)")
    return "\n".join(lines)


def _split_bullets(text: str) -> List[str]:
    """تفكيك نص Claude إلى نقاط نظيفة (إزالة رموز التعداد والمسافات)."""
    out: List[str] = []
    for raw in text.splitlines():
        s = raw.strip().lstrip("•-*—▪◦●∙·").strip()
        if s:
            out.append(s)
    return out


def analyze(governorate: Optional[str] = None,
            company: Optional[str] = None) -> Dict:
    """تحليل ذكي لبلاغات الأعطال — بنية غنية (ملخّص + تفصيل لكل شركة + قراءة).

    يُرجع دائماً الحقول المُهيكلة الحتمية (`totals`/`companies`/`highlights`)
    ليعرضها العميل باحترافية، مع قراءة نصّية (`insights`/`recommendations`
    و`analysis`) من Claude إن توفّر المفتاح وإلا من قواعد المحرّك.
    """
    data = overview(governorate, company)
    companies = _company_detail(data["by_company"])
    highlights = _highlights(data)
    parts = _rule_based_parts(data)
    structured = {
        "scope": data["scope"],
        "totals": data["totals"],
        "companies": companies,
        "highlights": highlights,
        "headline": parts["headline"],
    }
    try:
        from .ai_assistant import _get_client
        from ..config import settings
        client = _get_client()
        if client is not None:
            t = data["totals"]
            summary = (
                f"بيانات بلاغات أعطال شبكة OLT (العراق): {t['total']} بلاغ، "
                f"{t['on_time']} حُلّت ضمن SLA، {t['breached']} تجاوزت المهلة، "
                f"{t['in_progress']} قيد التنفيذ، نسبة الالتزام {t['sla_compliance_pct']}%، "
                f"متوسط زمن الحل {t['avg_resolution_hours']} ساعة، "
                f"{t['critical_open']} بلاغ حرج مفتوح. أداء الشركات: "
                + ", ".join(
                    f"{c['name']}={c['sla_compliance_pct']}%({c['breached']}متأخر)"
                    for c in data["by_company"])
                + ". أبرز الأعطال: "
                + ", ".join(f"{ty['name']}={ty['count']}" for ty in data["by_type"][:5])
            )
            msg = client.messages.create(
                model=settings.ai_model,
                max_tokens=700,
                system=("أنت مدير عمليات شبكات وصول خبير. حلّل بلاغات الأعطال ومستوى "
                        "الخدمة (SLA) بالعربية بإيجاز مهني: أبرز المخاطر، الشركات "
                        "المتعثّرة، وتوصيات عملية لتحسين زمن الاستجابة. استخدم نقاطاً."),
                messages=[{"role": "user", "content": summary}],
            )
            text = "".join(b.text for b in msg.content
                           if getattr(b, "type", "") == "text")
            return {
                **structured,
                "source": "claude",
                "analysis": text,
                "insights": _split_bullets(text) or parts["insights"],
                # التوصيات الحتمية المبنية على البيانات تبقى ملموسة حتى مع Claude
                # (أرقام/شركات محددة) فيُثري المفتاح المحتوى ولا يُنقِصه.
                "recommendations": parts["recommendations"],
            }
    except Exception:
        pass
    return {
        **structured,
        "source": "rules",
        "analysis": _rule_based_analysis(data),
        "insights": parts["insights"],
        "recommendations": parts["recommendations"],
    }
