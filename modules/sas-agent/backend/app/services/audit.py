"""
التدقيق (Audit) — مطابقة أعداد المشتركين المُبلَّغة من الوكيل مقابل الشركة المجهِّزة.

لكل وكيل مُعرّف «@» مسجَّل لدى شركته. يقارن هذا التدقيق:
- ما يذكره الوكيل   (agent_reported)   = عدد مشتركيه الفعليّين.
- ما تذكره الشركة  (company_reported) = العدد المسجَّل لدى الشركة تحت «@» الوكيل.

القاعدة (كشف التلاعب):
- الوكيل يذكر **أقل** مما تذكره الشركة  → **الشركة مشبوهة** (دمج/تهريب بيانات).
- الوكيل يذكر **أكثر** مما تذكره الشركة → **الوكيل مشبوه** (عملية دمج).
- تساوٍ → **مطابق**.

والمجاميع الكلّية لكل شركة (مجموع ما يذكره وكلاؤها مقابل مجموع ما تذكره) تُعطي
حكماً على مستوى الشركة بالمنطق نفسه. البيانات حتمية (بذرة ثابتة).
"""
import random
from typing import Dict, List, Optional

from . import agents as agents_svc
from . import national

# ميل كل شركة في التدقيق (يمنح المجاميع أحكاماً واضحة على مستوى الشركة):
# clean=مطابقة غالباً · company_over=الشركة تُبالغ · agent_over=الوكلاء يبالغون
_COMPANY_PROFILE = {
    "الصدارة نت": "clean",
    "إيرثلنك": "company_over",
    "هلا": "agent_over",
    "الجزيرة": "clean",
    "سوبر سيل": "company_over",
}

_STATUS_LABELS = {
    "matched": "مطابق",
    "company_suspicious": "الشركة مشبوهة",
    "agent_suspicious": "الوكيل مشبوه",
}


def _classify(diff: int) -> str:
    """diff = agent_reported - company_reported."""
    if diff == 0:
        return "matched"
    return "agent_suspicious" if diff > 0 else "company_suspicious"


def _classify_f(diff: float, tol: float = 0.05) -> str:
    """تصنيف فرق عائم (لحجم البيانات) بهامش تسامح صغير."""
    if abs(diff) < tol:
        return "matched"
    return "agent_suspicious" if diff > 0 else "company_suspicious"


def _plan_mbps(plan: str) -> float:
    """استخراج السرعة (Mbps) من وصف الباقة مثل '100 Mbps'."""
    try:
        return float(plan.split()[0])
    except (ValueError, IndexError):
        return 0.0


def _build_audit() -> List[Dict]:
    rng = random.Random(20260724)  # بذرة ثابتة
    out: List[Dict] = []
    for a in agents_svc._AGENTS:
        agent_reported = a["subscriber_count"]
        profile = _COMPANY_PROFILE.get(a["company"], "clean")
        # احتمالات النتيجة حسب ميل الشركة: (حدّ المطابقة، حدّ «الشركة تذكر أكثر»)
        if profile == "clean":
            p_match, p_company_over = 0.80, 0.90
        elif profile == "company_over":
            p_match, p_company_over = 0.45, 0.85
        else:  # agent_over
            p_match, p_company_over = 0.45, 0.55

        r = rng.random()
        if r < p_match:
            company_reported = agent_reported
        elif r < p_company_over:
            # الشركة تذكر أكثر → الوكيل أقل → الشركة مشبوهة
            company_reported = agent_reported + rng.randint(6, 70)
        else:
            # الشركة تذكر أقل → الوكيل أكثر → الوكيل مشبوه
            hi = min(60, max(6, agent_reported - 3))
            company_reported = agent_reported - rng.randint(6, hi)

        diff = agent_reported - company_reported
        status = _classify(diff)

        # ===== حجم البيانات (Gbps) — بُعد تدقيق مستقلّ =====
        # ما يذكره الوكيل = استهلاك مشتركيه النشطين (نسبة تزامن من سعة الباقات)
        active_mbps = sum(_plan_mbps(s["plan"]) for s in a["subscribers"]
                          if s["status"] == "active")
        util = rng.uniform(0.16, 0.30)
        agent_traffic = round(active_mbps * util / 1000.0, 1)
        # ما تذكره الشركة — قرار مستقلّ بميل الشركة نفسه
        r2 = rng.random()
        if r2 < p_match:
            company_traffic = agent_traffic
        elif r2 < p_company_over:
            company_traffic = round(agent_traffic * (1 + rng.uniform(0.05, 0.35)), 1)
        else:
            company_traffic = round(agent_traffic * (1 - rng.uniform(0.05, 0.30)), 1)
        traffic_diff = round(agent_traffic - company_traffic, 1)
        traffic_status = _classify_f(traffic_diff)

        out.append({
            "agent_id": a["id"],
            "name": a["name"],
            "office": a["office"],
            "handle": a["handle"],
            "company": a["company"],
            "governorate": a["governorate"],
            "agent_reported": agent_reported,
            "company_reported": company_reported,
            "diff": diff,
            "abs_diff": abs(diff),
            "status": status,
            "status_label": _STATUS_LABELS[status],
            "agent_traffic": agent_traffic,
            "company_traffic": company_traffic,
            "traffic_diff": traffic_diff,
            "traffic_abs_diff": abs(traffic_diff),
            "traffic_status": traffic_status,
            "traffic_status_label": _STATUS_LABELS[traffic_status],
        })
    return out


_AUDIT = _build_audit()


def _by_company(rows: List[Dict]) -> List[Dict]:
    groups: Dict[str, List[Dict]] = {}
    for r in rows:
        groups.setdefault(r["company"], []).append(r)
    out = []
    for name, sub in groups.items():
        ar = sum(r["agent_reported"] for r in sub)
        cr = sum(r["company_reported"] for r in sub)
        diff = ar - cr
        verdict = _classify(diff)
        atr = round(sum(r["agent_traffic"] for r in sub), 1)
        ctr = round(sum(r["company_traffic"] for r in sub), 1)
        tdiff = round(atr - ctr, 1)
        tverdict = _classify_f(tdiff, tol=0.1)
        out.append({
            "name": name,
            "agents": len(sub),
            "agent_reported": ar,
            "company_reported": cr,
            "diff": diff,
            "verdict": verdict,
            "verdict_label": _STATUS_LABELS[verdict],
            "matched": sum(1 for r in sub if r["status"] == "matched"),
            "company_suspicious": sum(1 for r in sub if r["status"] == "company_suspicious"),
            "agent_suspicious": sum(1 for r in sub if r["status"] == "agent_suspicious"),
            "agent_traffic": atr,
            "company_traffic": ctr,
            "traffic_diff": tdiff,
            "traffic_verdict": tverdict,
            "traffic_verdict_label": _STATUS_LABELS[tverdict],
            "traffic_matched": sum(1 for r in sub if r["traffic_status"] == "matched"),
            "traffic_company_suspicious": sum(1 for r in sub if r["traffic_status"] == "company_suspicious"),
            "traffic_agent_suspicious": sum(1 for r in sub if r["traffic_status"] == "agent_suspicious"),
            "color": national._COMPANY_COLORS.get(name, "#22D3EE"),
        })
    out.sort(key=lambda x: abs(x["diff"]), reverse=True)
    return out


def overview(company: Optional[str] = None) -> Dict:
    """صورة التدقيق: مطابقة أعداد المشتركين للوكلاء مقابل الشركات."""
    rows = _AUDIT
    if company:
        rows = [r for r in rows if r["company"] == company]

    total_agent = sum(r["agent_reported"] for r in rows)
    total_company = sum(r["company_reported"] for r in rows)
    total_agent_tr = round(sum(r["agent_traffic"] for r in rows), 1)
    total_company_tr = round(sum(r["company_traffic"] for r in rows), 1)
    totals = {
        "agents": len(rows),
        "agent_reported": total_agent,
        "company_reported": total_company,
        "diff": total_agent - total_company,
        "matched": sum(1 for r in rows if r["status"] == "matched"),
        "company_suspicious": sum(1 for r in rows if r["status"] == "company_suspicious"),
        "agent_suspicious": sum(1 for r in rows if r["status"] == "agent_suspicious"),
        "agent_traffic": total_agent_tr,
        "company_traffic": total_company_tr,
        "traffic_diff": round(total_agent_tr - total_company_tr, 1),
        "traffic_matched": sum(1 for r in rows if r["traffic_status"] == "matched"),
        "traffic_company_suspicious": sum(1 for r in rows if r["traffic_status"] == "company_suspicious"),
        "traffic_agent_suspicious": sum(1 for r in rows if r["traffic_status"] == "agent_suspicious"),
        "companies": len({r["company"] for r in rows}),
    }
    return {
        "scope": {"company": company},
        "totals": totals,
        "by_company": _by_company(rows),
        "agents": sorted(rows, key=lambda r: (r["abs_diff"], r["company"]),
                         reverse=True),
        "status_labels": _STATUS_LABELS,
        "filters": {"companies": national._COMPANIES},
    }
