"""
تشخيص الترانزيت والبوابات الدولية — صحّة المسارات الرئيسية وحجم البيانات العابرة.

يبني صورة حتمية (deterministic) للبوابات الدولية (منافذ العبور الحدودية) التي
تربط العراق بدول الجوار، فوق المسارات الدولية المعرّفة في
`national._INTERNATIONAL_ROUTES` (TR1..TR10). لكل بوابة:

- السعة (Gbps)، الحِمل الحالي (صادر/وارد)، نسبة الإشغال %.
- زمن الوصول (ms)، الجيتر، فقد الحزم %.
- الحالة (up/congested/down)، والبوابة الاحتياطية (redundancy) لإعادة التوجيه.

ثم محرّك تشخيص بالقواعد الخبيرة يكشف الازدحام/الأعطال ويقترح إعادة التوجيه،
وتحليل ذكي هجين (قواعد محلية + Claude إن توفّر المفتاح) بنمط بقية اللوحات.

كل الأرقام تُشتق من بذرة ثابتة فتبقى مستقرّة بين الطلبات.
"""
import random
from typing import Dict, List, Optional

from . import national

# ── وصف البوابات الدولية العشر (متوافق مع ترتيب _INTERNATIONAL_ROUTES) ──
# (الدولة، منفذ العبور الحدودي، مدينة الوصول، السعة Gbps، إشغال أساسي،
#  حالة مفروضة اختيارياً لأغراض العرض)
_GATEWAY_META = [
    ("الأردن", "طريبيل", "عمّان", 400, 0.61, None),
    ("سوريا", "القائم", "دمشق", 200, 0.34, "down"),        # بوابة ساقطة (قطع/صيانة)
    ("تركيا", "إبراهيم الخليل", "إسطنبول", 800, 0.72, None),
    ("إيران", "مندلي", "طهران", 300, 0.79, None),
    ("إيران", "الشلامجة", "الأحواز → طهران", 500, 0.88, None),  # وشيك الازدحام
    ("الكويت", "سفوان", "الكويت", 200, 0.57, None),
    ("السعودية", "عرعر", "الرياض", 300, 0.45, None),
    ("تركيا", "أربيل", "الحدود التركية", 400, 0.55, None),
    ("إيران", "السليمانية", "الحدود الإيرانية", 200, 0.71, None),
    ("تركيا", "دهوك", "الحدود التركية", 300, 0.66, None),
]

# زمن الوصول الأساسي (ms) لكل دولة وصول — يُضاف إليه جيتر بسيط
_LATENCY_BASE = {
    "الأردن": 14.0, "سوريا": 16.0, "تركيا": 26.0,
    "إيران": 20.0, "الكويت": 10.0, "السعودية": 22.0,
}

_STATUS_LABELS = {
    "up": "تعمل",
    "congested": "مزدحمة",
    "down": "ساقطة",
}


def _intl_routes() -> List[Dict]:
    """المسارات الدولية المبنية مسبقاً (مع الإحداثيات) بترتيب _INTERNATIONAL_ROUTES."""
    return [r for r in national._ROUTES if r["type"] == "international"]


def _derive_status(util: float, loss: float, forced: Optional[str]) -> str:
    if forced:
        return forced
    if util >= 0.90 or loss >= 1.0:
        return "congested"
    return "up"


def _build_gateways() -> List[Dict]:
    rng = random.Random(20260725)  # بذرة مستقلّة للبوابات
    intl = _intl_routes()
    gateways: List[Dict] = []

    # فهرس الاحتياطي: بوابة أخرى في نفس الدولة تتحمّل إعادة التوجيه
    by_country: Dict[str, List[int]] = {}
    for idx, (country, *_rest) in enumerate(_GATEWAY_META):
        by_country.setdefault(country, []).append(idx)

    for idx, meta in enumerate(_GATEWAY_META):
        country, border, endpoint, capacity, base_util, forced = meta
        route = intl[idx] if idx < len(intl) else None
        route_name = route["name"] if route else f"TR{idx + 1}"
        color = route["color"] if route else "#F87171"
        coords = route["coordinates"] if route else []

        if forced == "down":
            util = 0.0
            egress = 0.0
            ingress = 0.0
            loss = 100.0
            latency = 0.0
            jitter = 0.0
        else:
            util = min(0.98, max(0.05, base_util + rng.uniform(-0.05, 0.05)))
            traffic = round(capacity * util, 1)
            # قسمة الحِمل بين الصادر والوارد (الصادر أعلى قليلاً عادةً)
            egress_share = rng.uniform(0.52, 0.62)
            egress = round(traffic * egress_share, 1)
            ingress = round(traffic - egress, 1)
            # فقد الحزم يرتفع مع الإشغال
            loss = round(max(0.0, (util - 0.75) * 4.0) + rng.uniform(0.0, 0.15), 2)
            base = _LATENCY_BASE.get(country, 18.0)
            latency = round(base * (1 + max(0.0, util - 0.7) * 0.8)
                            + rng.uniform(-1.0, 2.0), 1)
            jitter = round(rng.uniform(0.3, 2.2) * (1 + max(0.0, util - 0.8)), 2)

        status = _derive_status(util, loss, forced)
        traffic_total = round(egress + ingress, 1)

        # البوابة الاحتياطية: أول بوابة أخرى في نفس الدولة (إن وُجدت)
        partners = [i for i in by_country.get(country, []) if i != idx]
        redundancy = f"GW-TR{partners[0] + 1}" if partners else None

        gateways.append({
            "id": f"GW-TR{idx + 1}",
            "code": f"TR{idx + 1}",
            "name": route_name,
            "country": country,
            "border": border,
            "endpoint": endpoint,
            "color": color,
            "capacity_gbps": float(capacity),
            "egress_gbps": egress,
            "ingress_gbps": ingress,
            "traffic_gbps": traffic_total,
            "utilization_pct": round(util * 100, 1),
            "latency_ms": latency,
            "jitter_ms": jitter,
            "loss_pct": loss,
            "status": status,
            "status_label": _STATUS_LABELS[status],
            "redundancy": redundancy,
            "coordinates": coords,
        })
    return gateways


_GATEWAYS = _build_gateways()


def _by_country(gateways: List[Dict]) -> List[Dict]:
    groups: Dict[str, List[Dict]] = {}
    for g in gateways:
        groups.setdefault(g["country"], []).append(g)
    out = []
    for country, items in groups.items():
        cap = sum(i["capacity_gbps"] for i in items)
        traf = round(sum(i["traffic_gbps"] for i in items), 1)
        out.append({
            "country": country,
            "gateways": len(items),
            "capacity_gbps": cap,
            "traffic_gbps": traf,
            "utilization_pct": round(traf / cap * 100, 1) if cap else 0.0,
            "up": sum(1 for i in items if i["status"] == "up"),
            "congested": sum(1 for i in items if i["status"] == "congested"),
            "down": sum(1 for i in items if i["status"] == "down"),
        })
    out.sort(key=lambda x: x["traffic_gbps"], reverse=True)
    return out


def _totals(gateways: List[Dict]) -> Dict:
    cap = sum(g["capacity_gbps"] for g in gateways)
    egress = round(sum(g["egress_gbps"] for g in gateways), 1)
    ingress = round(sum(g["ingress_gbps"] for g in gateways), 1)
    traffic = round(egress + ingress, 1)
    live = [g for g in gateways if g["status"] != "down"]
    avg_latency = round(sum(g["latency_ms"] for g in live) / len(live), 1) if live else 0.0
    avg_loss = round(sum(g["loss_pct"] for g in live) / len(live), 2) if live else 0.0
    return {
        "gateways": len(gateways),
        "up": sum(1 for g in gateways if g["status"] == "up"),
        "congested": sum(1 for g in gateways if g["status"] == "congested"),
        "down": sum(1 for g in gateways if g["status"] == "down"),
        "capacity_gbps": cap,
        "egress_gbps": egress,
        "ingress_gbps": ingress,
        "traffic_gbps": traffic,
        "utilization_pct": round(traffic / cap * 100, 1) if cap else 0.0,
        "avg_latency_ms": avg_latency,
        "avg_loss_pct": avg_loss,
        "countries": len({g["country"] for g in gateways}),
    }


def overview(country: Optional[str] = None) -> Dict:
    """صورة الترانزيت الكاملة مع تصفية اختيارية حسب دولة العبور."""
    gateways = _GATEWAYS
    if country:
        gateways = [g for g in gateways if g["country"] == country]

    totals = _totals(gateways)
    series = national._throughput_series(totals["traffic_gbps"] or 1.0,
                                         f"transit|{country}")
    first = series[0]["value"] if series else 0
    last = series[-1]["value"] if series else 0
    change_pct = round((last - first) / first * 100, 2) if first else 0.0

    return {
        "scope": {"country": country},
        "totals": totals,
        "gateways": sorted(gateways, key=lambda g: g["traffic_gbps"], reverse=True),
        "by_country": _by_country(gateways),
        "throughput_series": series,
        "throughput_change_pct": change_pct,
        "throughput_low": min((p["value"] for p in series), default=0),
        "throughput_high": max((p["value"] for p in series), default=0),
        "filters": {"countries": sorted({g["country"] for g in _GATEWAYS})},
    }


# ---------------------------------------------------------------------------
# محرّك التشخيص بالقواعد الخبيرة
# ---------------------------------------------------------------------------

def _gateway_findings(g: Dict) -> List[Dict]:
    """قواعد تشخيص بوابة واحدة → قائمة نتائج (شدّة/مصدر/رسالة/إجراء)."""
    findings: List[Dict] = []
    src = f"{g['code']} · {g['country']}"
    reroute = (f" أعد التوجيه إلى البوابة الاحتياطية {g['redundancy']}."
               if g.get("redundancy") else " لا توجد بوابة احتياطية — خطر انقطاع كامل.")

    if g["status"] == "down":
        findings.append({
            "severity": "critical", "source": src, "gateway": g["code"],
            "message": f"البوابة الدولية {g['code']} ({g['border']} → {g['endpoint']}) ساقطة.",
            "action": "افحص وصلة العبور الحدودية والمزوّد الدولي." + reroute,
        })
        return findings

    util = g["utilization_pct"]
    if util >= 90:
        findings.append({
            "severity": "critical", "source": src, "gateway": g["code"],
            "message": f"ازدحام حرج على {g['code']}: الإشغال {util}% من السعة.",
            "action": "وسّع السعة أو وزّع الحِمل." + reroute,
        })
    elif util >= 80:
        findings.append({
            "severity": "major", "source": src, "gateway": g["code"],
            "message": f"ازدحام وشيك على {g['code']}: الإشغال {util}%.",
            "action": "راقب الذروة وخطّط لزيادة السعة قبل بلوغ 90%.",
        })

    if g["loss_pct"] >= 1.0:
        findings.append({
            "severity": "major", "source": src, "gateway": g["code"],
            "message": f"فقد حزم مرتفع على {g['code']}: {g['loss_pct']}%.",
            "action": "افحص جودة الوصلة الضوئية والازدحام على المسار الدولي.",
        })

    base = _LATENCY_BASE.get(g["country"], 18.0)
    if g["latency_ms"] >= base * 1.6:
        findings.append({
            "severity": "warning", "source": src, "gateway": g["code"],
            "message": f"زمن وصول مرتفع على {g['code']}: {g['latency_ms']} ms "
                       f"(الأساس ~{base} ms).",
            "action": "راجع مسار التوجيه وأولويات الحركة (QoS) نحو الوجهة الدولية.",
        })

    return findings


def _health(findings: List[Dict]) -> str:
    if any(f["severity"] == "critical" for f in findings):
        return "critical"
    if findings:
        return "degraded"
    return "healthy"


def diagnose(country: Optional[str] = None,
             gateway_id: Optional[str] = None) -> Dict:
    """تشخيص الترانزيت: يفحص كل البوابات (أو بوابة/دولة محدّدة) ويُخرج النتائج."""
    gateways = _GATEWAYS
    if gateway_id:
        gateways = [g for g in gateways if g["id"] == gateway_id]
    elif country:
        gateways = [g for g in gateways if g["country"] == country]

    findings: List[Dict] = []
    enriched: List[Dict] = []
    for g in gateways:
        gf = _gateway_findings(g)
        findings.extend(gf)
        d = dict(g)
        d["health"] = _health(gf)
        d["finding_count"] = len(gf)
        enriched.append(d)

    # ترتيب النتائج حسب الشدّة
    order = {"critical": 0, "major": 1, "warning": 2, "minor": 3}
    findings.sort(key=lambda f: order.get(f["severity"], 9))

    health = _health(findings)
    totals = _totals(gateways)
    if health == "critical":
        verdict = "خلل حرج في الترانزيت الدولي — تدخّل فوري مطلوب."
    elif health == "degraded":
        verdict = "الترانزيت الدولي يعمل مع ملاحظات تتطلّب المتابعة."
    else:
        verdict = "الترانزيت الدولي سليم — لا مشاكل مرصودة."

    return {
        "scope": {"country": country, "gateway_id": gateway_id},
        "health": health,
        "verdict": verdict,
        "findings": findings,
        "totals": totals,
        "gateways": sorted(enriched, key=lambda g: g["utilization_pct"], reverse=True),
    }


# ---------------------------------------------------------------------------
# تحليل ذكي (قواعد محلية + Claude إن توفّر المفتاح)
# ---------------------------------------------------------------------------

def _rule_based_analysis(data: Dict) -> str:
    t = data["totals"]
    lines: List[str] = ["🌐 تحليل الترانزيت الدولي:"]
    lines.append(
        f"• {t['gateways']} بوابة دولية بسعة إجمالية {t['capacity_gbps']:,} Gbps، "
        f"حركة عابرة {t['traffic_gbps']:,} Gbps (إشغال {t['utilization_pct']}%).")
    lines.append(
        f"• الحالة: {t['up']} تعمل، {t['congested']} مزدحمة، {t['down']} ساقطة "
        f"(متوسط زمن الوصول {t['avg_latency_ms']} ms، فقد {t['avg_loss_pct']}%).")
    cong = [g for g in data["gateways"] if g["status"] == "congested"]
    down = [g for g in data["gateways"] if g["status"] == "down"]
    if down:
        lines.append("⚠️ بوابات ساقطة: "
                     + "، ".join(f"{g['code']} ({g['country']})" for g in down)
                     + " — أعد التوجيه للبوابات الاحتياطية.")
    if cong:
        lines.append("⚠️ بوابات مزدحمة: "
                     + "، ".join(f"{g['code']} {g['utilization_pct']}%" for g in cong)
                     + " — خطّط لزيادة السعة.")
    if not down and not cong:
        lines.append("✅ لا ازدحام أو أعطال حرجة على البوابات الدولية.")
    lines.append("— (تحليل آلي من قواعد المحرّك؛ فعّل ANTHROPIC_API_KEY لتحليل أعمق.)")
    return "\n".join(lines)


def analyze(country: Optional[str] = None) -> Dict:
    """تحليل ذكي للترانزيت (Claude إن توفّر المفتاح، وإلا قواعد محلية)."""
    data = diagnose(country)
    try:
        from .ai_assistant import _get_client
        from ..config import settings
        client = _get_client()
        if client is not None:
            t = data["totals"]
            summary = (
                f"بيانات ترانزيت دولي (العراق): {t['gateways']} بوابة، سعة "
                f"{t['capacity_gbps']} Gbps، حركة {t['traffic_gbps']} Gbps، إشغال "
                f"{t['utilization_pct']}%، {t['down']} ساقطة، {t['congested']} مزدحمة، "
                f"متوسط زمن الوصول {t['avg_latency_ms']} ms، فقد {t['avg_loss_pct']}%. "
                "البوابات: "
                + "، ".join(
                    f"{g['code']}({g['country']})={g['utilization_pct']}%/{g['status']}"
                    for g in data["gateways"])
            )
            msg = client.messages.create(
                model=settings.ai_model,
                max_tokens=700,
                system=("أنت مهندس شبكة نقل (Transport/Backbone) خبير. حلّل صحّة "
                        "الترانزيت الدولي وحجم البيانات العابرة عبر البوابات بالعربية "
                        "بإيجاز مهني: الازدحام، الأعطال، وإعادة التوجيه، وتوصيات السعة. "
                        "استخدم نقاطاً."),
                messages=[{"role": "user", "content": summary}],
            )
            text = "".join(b.text for b in msg.content
                           if getattr(b, "type", "") == "text")
            return {"analysis": text, "source": "claude", "totals": data["totals"]}
    except Exception:
        pass
    return {"analysis": _rule_based_analysis(data), "source": "rules",
            "totals": data["totals"]}
