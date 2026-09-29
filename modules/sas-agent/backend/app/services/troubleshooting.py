"""
محرك التشخيص الذكي — يجمع بيانات ONT تلقائياً، يطبّق القواعد الخبيرة،
ويُرجع تشخيصاً وحلولاً مقترحة. الطبقة الأولى من الذكاء (فوري، بدون إنترنت).
"""
from typing import Dict, List
from ..core.olt_connection import manager
from ..core import command_library as cl
from ..core import parsers
from .monitoring import evaluate_ont, _RULES


def diagnose_ont(device, fsp: str, ont_id: int) -> Dict:
    """
    يشخّص ONT واحد: يجمع display ont info + port state + failed-configuration،
    يطبّق القواعد، ويُرجع تقريراً كاملاً.
    """
    sess = manager.get(device)
    f, s, p = fsp.split("/")

    # 1) جمع البيانات
    detail_out = sess.run(cl.DISPLAY["ont_info"](f, s, p, ont_id))
    detail = parsers.parse_ont_detail(detail_out)
    port_out = sess.run(cl.DISPLAY["port_state"](p))
    port_state = parsers.parse_port_state(port_out)

    ont_data = {
        "fsp": fsp, "ont_id": ont_id,
        "run_state": detail.get("run_state"),
        "config_state": detail.get("config_state"),
        "match_state": detail.get("match_state"),
        "control_flag": detail.get("control_flag"),
        "rx_power": port_state.get("rx_power_dbm"),
    }

    # 2) تطبيق القواعد
    findings = evaluate_ont(device, ont_data, port_state)

    # 3) إن كان config failed — اجلب التفاصيل
    failed_detail = None
    if str(detail.get("config_state", "")).lower() == "failed":
        failed_detail = sess.run(cl.DISPLAY["ont_failed"]())

    # 4) الحرارة
    temp = detail.get("temperature")
    tth = _RULES["temperature_thresholds"]
    if temp is not None:
        if temp > tth["critical_above"]:
            findings.append({"severity": "critical", "source": f"ONT {fsp}/{ont_id}",
                             "message": f"حرارة حرجة {temp}°C.", "action": "افحص التبريد فوراً.",
                             "rule_id": "temp_critical"})
        elif temp > tth["warning_above"]:
            findings.append({"severity": "warning", "source": f"ONT {fsp}/{ont_id}",
                             "message": f"حرارة مرتفعة {temp}°C.", "action": "راقب مكان التركيب.",
                             "rule_id": "temp_warning"})

    # 5) الخلاصة
    if not findings:
        verdict = "✅ الجهاز يعمل بشكل سليم — لا مشاكل مكتشَفة."
        health = "healthy"
    else:
        crit = [x for x in findings if x["severity"] == "critical"]
        health = "critical" if crit else "degraded"
        verdict = f"⚠️ اكتُشفت {len(findings)} مشكلة/مشاكل تحتاج انتباهاً."

    return {
        "fsp": fsp, "ont_id": ont_id,
        "verdict": verdict,
        "health": health,
        "raw_detail": detail,
        "optical": port_state,
        "temperature": temp,
        "findings": findings,
        "failed_config": failed_detail,
    }


def voice_diagnose(device, fsp: str) -> Dict:
    """تشخيص جودة مكالمة صوتية عبر esl online-info (MOS/R-Factor)"""
    sess = manager.get(device)
    out = sess.run(cl.DISPLAY["esl_online"](fsp))
    q = parsers.parse_esl_online(out)
    vth = _RULES["voice_quality_thresholds"]
    findings = []
    if q.get("mos_cq") is not None and q["mos_cq"] < vth["mos"]["poor_below"]:
        findings.append(f"جودة صوت رديئة (MOS={q['mos_cq']}) — تحقق من الشبكة.")
    if q.get("packet_loss") is not None and q["packet_loss"] > vth["packet_loss"]["warning_above"]:
        findings.append(f"فقدان حزم مرتفع {q['packet_loss']}%.")
    if q.get("jitter_ms") is not None and q["jitter_ms"] > vth["jitter"]["warning_above"]:
        findings.append(f"jitter مرتفع {q['jitter_ms']}ms.")
    return {"quality": q, "findings": findings,
            "verdict": "جودة جيدة" if not findings else "توجد مشاكل في جودة الصوت"}
