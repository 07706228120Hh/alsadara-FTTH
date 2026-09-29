"""
محرك المراقبة — يسحب حالة الأجهزة والـ ONTs دورياً، يخزّن القياسات،
ويولّد التنبيهات. يبثّ التحديثات الحية عبر WebSocket.
"""
import asyncio
import json
import os
from datetime import datetime, timedelta
from typing import Dict, List
from sqlmodel import Session, select, delete
from ..config import settings
from ..database import engine
from ..models import OLTDevice, ONTRecord, Metric, AlarmRecord, utcnow
from ..core.olt_connection import manager
from ..core import command_library as cl
from ..core import parsers

# قواعد التشخيص — مسار متوافق مع ويندوز/لينكس (os.path بدل تقسيم "/")
_RULES_PATH = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "knowledge", "diagnosis_rules.json")
)
with open(_RULES_PATH, encoding="utf-8") as _fp:
    _RULES = json.load(_fp)


class MonitorHub:
    """يدير المشتركين في التحديثات الحية (WebSocket)"""
    def __init__(self):
        self._subscribers: List = []

    def subscribe(self, ws):
        self._subscribers.append(ws)

    def unsubscribe(self, ws):
        if ws in self._subscribers:
            self._subscribers.remove(ws)

    async def broadcast(self, event: Dict):
        dead = []
        for ws in self._subscribers:
            try:
                await ws.send_json(event)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.unsubscribe(ws)


hub = MonitorHub()


def poll_device(device: OLTDevice) -> Dict:
    """سحب حالة جهاز واحد وكل ONTs عليه — يُرجع ملخصاً"""
    sess = manager.get(device)
    summary = {"device": device.name, "onts": [], "alarms": []}

    # حالة البوردات
    boards_out = sess.run(cl.DISPLAY["board"]())
    summary["boards"] = parsers.parse_board_list(boards_out)

    # ONTs على كل بورد GPON (نبسّط: البورد 5، المنفذان 0 و1)
    all_onts = []
    for port in (0, 1):
        out = sess.run(cl.DISPLAY["ont_info_all"](port))
        all_onts.extend(parsers.parse_ont_info_all(out))

    with Session(engine) as db:
        for ont in all_onts:
            # قدرة ضوئية (مبسّطة — منفذ واحد)
            ps = parsers.parse_port_state(sess.run(cl.DISPLAY["port_state"](0)))
            ont["rx_power"] = ps.get("rx_power_dbm")

            # تقييم القواعد وتوليد التنبيهات
            alarms = evaluate_ont(device, ont, ps)
            summary["alarms"].extend(alarms)

            # حفظ/تحديث السجل
            _upsert_ont(db, device.id, ont)
            # قياس القدرة الضوئية
            if ont.get("rx_power") is not None:
                db.add(Metric(olt_id=device.id, target=f"ONT {ont['fsp']}/{ont['ont_id']}",
                              metric="rx_power", value=ont["rx_power"]))
            summary["onts"].append(ont)

        # حفظ التنبيهات
        for a in summary["alarms"]:
            db.add(AlarmRecord(olt_id=device.id, severity=a["severity"],
                               source=a["source"], message=a["message"]))
        # تحديث حالة الجهاز داخل جلسة هذه الدالة (merge لتفادي تعارض الجلسات)
        fresh = db.get(OLTDevice, device.id)
        if fresh:
            fresh.reachable = True
            fresh.last_seen = utcnow()
            db.add(fresh)
        db.commit()

    return summary


def evaluate_ont(device, ont: Dict, port_state: Dict) -> List[Dict]:
    """يطبّق القواعد الخبيرة على ONT ويُرجع التنبيهات"""
    alarms = []
    src = f"{device.name} ONT {ont.get('fsp')}/{ont.get('ont_id')}"

    for rule in _RULES["ont_state_rules"]:
        cond = rule["condition"]
        if all(str(ont.get(k, "")).lower() == str(v).lower() for k, v in cond.items()):
            alarms.append({
                "severity": rule["severity"],
                "source": src,
                "message": rule["diagnosis_ar"],
                "action": rule["action_ar"],
                "rule_id": rule["id"],
            })

    # عتبات القدرة الضوئية
    rx = ont.get("rx_power")
    th = _RULES["optical_power_thresholds"]["rx_power"]
    if rx is not None:
        if rx < th["critical_below"]:
            alarms.append({"severity": "critical", "source": src,
                           "message": f"قدرة ضوئية حرجة {rx}dBm — قرب الانقطاع.",
                           "action": "افحص الفايبر والوصلات فوراً.", "rule_id": "rx_critical"})
        elif rx < th["warning_below"]:
            alarms.append({"severity": "warning", "source": src,
                           "message": f"قدرة ضوئية منخفضة {rx}dBm — تدهور محتمل.",
                           "action": "راقب الفايبر ونظّف الوصلات.", "rule_id": "rx_warning"})
    return alarms


def _upsert_ont(db: Session, olt_id: int, ont: Dict):
    stmt = select(ONTRecord).where(
        ONTRecord.olt_id == olt_id,
        ONTRecord.fsp == ont["fsp"],
        ONTRecord.ont_id == ont["ont_id"],
    )
    rec = db.exec(stmt).first()
    if rec is None:
        rec = ONTRecord(olt_id=olt_id, fsp=ont["fsp"], ont_id=ont["ont_id"], sn=ont.get("sn", ""))
    rec.run_state = ont.get("run_state", "unknown")
    rec.config_state = ont.get("config_state", "unknown")
    rec.match_state = ont.get("match_state", "unknown")
    rec.rx_power = ont.get("rx_power")
    rec.updated_at = utcnow()
    db.add(rec)


def purge_old_records(db: Session) -> Dict[str, int]:
    """يحذف القياسات/الإنذارات القديمة حسب سياسة الاحتفاظ. يُرجع عدد المحذوف."""
    now = utcnow()
    metric_cutoff = now - timedelta(days=settings.metric_retention_days)
    alarm_cutoff = now - timedelta(days=settings.alarm_retention_days)

    m_res = db.exec(delete(Metric).where(Metric.ts < metric_cutoff))
    # الإنذارات غير النشطة فقط (نُبقي النشطة مهما كان عمرها)
    a_res = db.exec(
        delete(AlarmRecord).where(
            AlarmRecord.active == False,  # noqa: E712
            AlarmRecord.ts < alarm_cutoff,
        )
    )
    db.commit()
    return {"metrics": m_res.rowcount or 0, "alarms": a_res.rowcount or 0}


async def _retention_sweep():
    """تنظيف دوري للجداول الزمنية (يعمل ضمن حلقة المراقبة)."""
    try:
        with Session(engine) as db:
            deleted = await asyncio.to_thread(purge_old_records, db)
        if deleted["metrics"] or deleted["alarms"]:
            await hub.broadcast({"type": "retention", "data": deleted})
    except Exception as e:  # التنظيف لا يجب أن يُسقط حلقة المراقبة
        await hub.broadcast({"type": "error", "message": f"retention: {e}"})


async def monitor_loop(interval: int):
    """حلقة المراقبة الخلفية"""
    sweep_every = max(1, int(settings.retention_sweep_hours * 3600 / max(interval, 1)))
    tick = 0
    await _retention_sweep()   # تنظيف أولي عند الإقلاع
    while True:
        try:
            with Session(engine) as db:
                devices = db.exec(select(OLTDevice).where(OLTDevice.enabled == True)).all()  # noqa: E712
            for device in devices:
                summary = await asyncio.to_thread(poll_device, device)
                await hub.broadcast({"type": "poll", "data": summary})
        except Exception as e:
            await hub.broadcast({"type": "error", "message": str(e)})
        tick += 1
        if tick % sweep_every == 0:
            await _retention_sweep()
        await asyncio.sleep(interval)
