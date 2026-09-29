"""
سحّاب SNMP متدرّج — يعمل بجانب حلقة المراقبة CLI دون استبدالها.

الطبقات الأربع وفتراتها (من settings):
  health   — كل snmp_health_interval  ثانية  (افتراضي 45)
  pon      — كل snmp_pon_interval     ثانية  (افتراضي 180)
  ont_basic — كل snmp_ont_basic_interval ثانية (افتراضي 600)
  ont_detail — كل snmp_ont_detail_interval ثانية (افتراضي 2400)

الجدولة: حلقة تيك ثانية واحدة (tick=1s) مع عدّادات لكل طبقة لكل جهاز.
لا يُكسر الجهاز الواحد بقية الأجهزة — try/except حول كل جهاز.
"""
import asyncio
import logging
from typing import Dict, Optional

from sqlmodel import Session, select

from ..config import settings
from ..database import engine
from ..models import (
    OLTDevice, ONTRecord, Metric, DeviceHealth, PonPortStatus, utcnow
)
from ..core.snmp_collector import (
    collect_health, collect_pon, collect_onts_basic, collect_ont_detail
)
from .monitoring import hub

_log = logging.getLogger(__name__)


# =========================================================================
# مساعدات upsert خاصة بهذا الملف
# =========================================================================

def _upsert_device_health(db: Session, olt_id: int, data: Dict) -> DeviceHealth:
    """upsert صف DeviceHealth — صف واحد لكل olt_id."""
    stmt = select(DeviceHealth).where(DeviceHealth.olt_id == olt_id)
    rec = db.exec(stmt).first()
    if rec is None:
        rec = DeviceHealth(olt_id=olt_id)

    rec.cpu = data.get("cpu")
    rec.memory = data.get("memory")
    rec.temperature = data.get("temperature")
    rec.uptime = data.get("uptime")
    rec.power_status = data.get("power_status") or ""
    rec.fan_status = data.get("fan_status") or ""
    rec.sw_version = data.get("sw_version") or ""
    rec.active_alarms = data.get("active_alarms") or 0
    rec.updated_at = utcnow()

    db.add(rec)
    return rec


def _upsert_pon_port(db: Session, olt_id: int, entry: Dict) -> PonPortStatus:
    """upsert صف PonPortStatus — مفتاح (olt_id, frame, slot, port)."""
    stmt = select(PonPortStatus).where(
        PonPortStatus.olt_id == olt_id,
        PonPortStatus.frame == entry["frame"],
        PonPortStatus.slot == entry["slot"],
        PonPortStatus.port == entry["port"],
    )
    rec = db.exec(stmt).first()
    if rec is None:
        rec = PonPortStatus(
            olt_id=olt_id,
            frame=entry["frame"],
            slot=entry["slot"],
            port=entry["port"],
        )

    rec.status = entry.get("status") or ""
    rec.tech = entry.get("tech") or ""
    rec.onts_registered = entry.get("onts_registered") or 0
    rec.onts_online = entry.get("onts_online") or 0
    rec.onts_offline = entry.get("onts_offline") or 0
    rec.rx_traffic = entry.get("rx_traffic")
    rec.tx_traffic = entry.get("tx_traffic")
    rec.utilization = entry.get("utilization")
    rec.updated_at = utcnow()

    db.add(rec)
    return rec


def _upsert_ont_basic(db: Session, olt_id: int, entry: Dict) -> ONTRecord:
    """upsert الحقول الأساسية لـ ONTRecord — مفتاح (olt_id, fsp, ont_id)."""
    stmt = select(ONTRecord).where(
        ONTRecord.olt_id == olt_id,
        ONTRecord.fsp == entry["fsp"],
        ONTRecord.ont_id == entry["ont_id"],
    )
    rec = db.exec(stmt).first()
    if rec is None:
        rec = ONTRecord(
            olt_id=olt_id,
            fsp=entry["fsp"],
            ont_id=entry["ont_id"],
            sn=entry.get("sn") or "",
        )

    # حقول أساسية فقط — لا تمسّ الحقول التفصيلية إن كانت موجودة
    if entry.get("sn"):
        rec.sn = entry["sn"]
    rec.run_state = entry.get("run_state") or "unknown"
    rec.config_state = entry.get("config_state") or "unknown"
    rec.match_state = entry.get("match_state") or "unknown"
    rec.rx_power = entry.get("rx_power")
    rec.updated_at = utcnow()

    db.add(rec)
    return rec


def _upsert_ont_detail(db: Session, olt_id: int, fsp: str, ont_id: int,
                       data: Dict) -> ONTRecord:
    """upsert الحقول التفصيلية لـ ONTRecord — يكمّل _upsert_ont_basic دون تدمير بياناته."""
    stmt = select(ONTRecord).where(
        ONTRecord.olt_id == olt_id,
        ONTRecord.fsp == fsp,
        ONTRecord.ont_id == ont_id,
    )
    rec = db.exec(stmt).first()
    if rec is None:
        rec = ONTRecord(olt_id=olt_id, fsp=fsp, ont_id=ont_id, sn="")

    # الحقول الضوئية والتفصيلية
    if data.get("rx_power") is not None:
        rec.rx_power = data["rx_power"]
    rec.tx_power = data.get("tx_power")
    rec.olt_rx_power = data.get("olt_rx_power")
    rec.temperature = data.get("temperature")
    rec.voltage = data.get("voltage")
    rec.bias_current = data.get("bias_current")
    if data.get("distance_m") is not None:
        rec.distance_m = data["distance_m"]
    rec.last_up = data.get("last_up")
    rec.last_down = data.get("last_down")
    rec.last_down_cause = data.get("last_down_cause") or ""
    rec.ont_model = data.get("ont_model") or ""
    rec.hw_version = data.get("hw_version") or ""
    rec.sw_version = data.get("sw_version") or ""
    rec.reg_method = data.get("reg_method") or ""
    rec.updated_at = utcnow()

    db.add(rec)
    return rec


# =========================================================================
# الدوال العامة (متزامنة — تُستدعى من asyncio.to_thread)
# =========================================================================

def poll_health(device: OLTDevice) -> Dict:
    """
    يسحب بيانات صحّة OLT عبر SNMP ثم يكتب/يحدّث صف DeviceHealth،
    ويضيف قياسات Metric لكل من cpu/memory/temperature عند توفّرها.
    يُرجع dict الصحّة.
    """
    data = collect_health(device)

    with Session(engine) as db:
        _upsert_device_health(db, device.id, data)

        # قياسات زمنية اختيارية
        ts = utcnow()
        for metric_name in ("cpu", "memory", "temperature"):
            val = data.get(metric_name)
            if val is not None:
                db.add(Metric(
                    olt_id=device.id,
                    target=f"OLT {device.name}",
                    metric=metric_name,
                    value=float(val),
                    ts=ts,
                ))

        db.commit()

    return data


def poll_pon(device: OLTDevice) -> list:
    """
    يسحب ملخّص منافذ PON عبر SNMP ثم يكتب/يحدّث صفوف PonPortStatus.
    يُرجع القائمة كما أعادها collect_pon.
    """
    entries = collect_pon(device)

    with Session(engine) as db:
        for entry in entries:
            _upsert_pon_port(db, device.id, entry)
        db.commit()

    return entries


def poll_onts_basic(device: OLTDevice) -> list:
    """
    يسحب حالة ONTs الأساسية عبر SNMP ثم يكتب/يحدّث الحقول الأساسية في ONTRecord.
    يضيف قياس Metric لـ rx_power عند توفّره.
    يُرجع القائمة كما أعادها collect_onts_basic.
    """
    entries = collect_onts_basic(device)

    with Session(engine) as db:
        ts = utcnow()
        for entry in entries:
            _upsert_ont_basic(db, device.id, entry)

            rx = entry.get("rx_power")
            if rx is not None:
                db.add(Metric(
                    olt_id=device.id,
                    target=f"ONT {entry['fsp']}/{entry['ont_id']}",
                    metric="rx_power",
                    value=float(rx),
                    ts=ts,
                ))
        db.commit()

    return entries


def refresh_ont_detail(device: OLTDevice, fsp: str, ont_id: int) -> Dict:
    """
    يسحب بيانات ONT التفصيلية فوراً (DDM كامل + مسافة + إصدارات + سبب الانقطاع).
    يُحدّث الحقول التفصيلية في ONTRecord ويُرجع dict السجل المحدَّث.
    تخدم «القراءة الفورية عند فتح صفحة المشترك».
    """
    data = collect_ont_detail(device, fsp, ont_id)

    with Session(engine) as db:
        rec = _upsert_ont_detail(db, device.id, fsp, ont_id, data)
        db.commit()
        db.refresh(rec)
        # بناء dict الإرجاع من السجل المحدَّث
        return {
            "fsp": rec.fsp,
            "ont_id": rec.ont_id,
            "sn": rec.sn,
            "run_state": rec.run_state,
            "rx_power": rec.rx_power,
            "tx_power": rec.tx_power,
            "olt_rx_power": rec.olt_rx_power,
            "temperature": rec.temperature,
            "voltage": rec.voltage,
            "bias_current": rec.bias_current,
            "distance_m": rec.distance_m,
            "last_up": rec.last_up,
            "last_down": rec.last_down,
            "last_down_cause": rec.last_down_cause,
            "ont_model": rec.ont_model,
            "hw_version": rec.hw_version,
            "sw_version": rec.sw_version,
            "reg_method": rec.reg_method,
            "updated_at": rec.updated_at,
        }


# =========================================================================
# حلقة السحب المتدرّجة (async)
# =========================================================================

# آخر وقت تشغيل فعلي لكل طبقة لكل جهاز {device_id: {layer: float timestamp}}
_last_run: Dict[int, Dict[str, float]] = {}


async def snmp_poll_loop() -> None:
    """
    الحلقة الخلفية للسحب المتدرّج عبر SNMP.

    الجدولة بنمط tick/counter:
      - الحلقة تستيقظ كل ثانية واحدة (tick=1s).
      - تتحقق لكل جهاز من الوقت المنقضي منذ آخر تشغيل لكل طبقة.
      - تُنفّذ الطبقة فقط إن بلغ الفارق الزمني الفترة المُعدّة.
      - هذا يضمن تشغيل الطبقات حسب أولويتها بدون انتظار بعضها.

    عزل الأخطاء: try/except حول كل جهاز — فشل جهاز لا يُسقط الحلقة.
    """
    if not settings.snmp_poll_enabled:
        _log.info("سحّاب SNMP معطَّل (SNMP_POLL_ENABLED=false) — الحلقة لا تعمل.")
        return

    _log.info(
        "بدء سحّاب SNMP المتدرّج — health=%ds, pon=%ds, ont_basic=%ds, ont_detail=%ds",
        settings.snmp_health_interval,
        settings.snmp_pon_interval,
        settings.snmp_ont_basic_interval,
        settings.snmp_ont_detail_interval,
    )

    while True:
        try:
            # جلب الأجهزة المفعَّلة والمُمكَّن عليها SNMP
            with Session(engine) as db:
                devices = db.exec(
                    select(OLTDevice).where(
                        OLTDevice.enabled == True,   # noqa: E712
                        OLTDevice.snmp_enabled == True,  # noqa: E712
                    )
                ).all()

            import time
            now = time.monotonic()

            for device in devices:
                dev_id: int = device.id
                if dev_id not in _last_run:
                    # أول مرة — ابدأ بالصفر ليُشغَّل فوراً
                    _last_run[dev_id] = {
                        "health": 0.0,
                        "pon": 0.0,
                        "ont_basic": 0.0,
                        "ont_detail": 0.0,
                    }

                timers = _last_run[dev_id]

                try:
                    # --- طبقة health ---
                    if now - timers["health"] >= settings.snmp_health_interval:
                        health_data = await asyncio.to_thread(poll_health, device)
                        timers["health"] = now
                        await hub.broadcast({
                            "type": "snmp",
                            "layer": "health",
                            "device": device.name,
                            "data": health_data,
                        })

                    # --- طبقة pon ---
                    if now - timers["pon"] >= settings.snmp_pon_interval:
                        pon_data = await asyncio.to_thread(poll_pon, device)
                        timers["pon"] = now
                        await hub.broadcast({
                            "type": "snmp",
                            "layer": "pon",
                            "device": device.name,
                            "data": pon_data,
                        })

                    # --- طبقة ont_basic ---
                    if now - timers["ont_basic"] >= settings.snmp_ont_basic_interval:
                        onts_data = await asyncio.to_thread(poll_onts_basic, device)
                        timers["ont_basic"] = now
                        await hub.broadcast({
                            "type": "snmp",
                            "layer": "ont_basic",
                            "device": device.name,
                            "data": onts_data,
                        })

                    # --- طبقة ont_detail (كل ONT دفعة واحدة بدورة منفصلة) ---
                    if now - timers["ont_detail"] >= settings.snmp_ont_detail_interval:
                        await _run_ont_detail_sweep(device)
                        timers["ont_detail"] = now

                except Exception as dev_err:
                    _log.error(
                        "خطأ في سحب SNMP للجهاز %s: %s",
                        device.name, dev_err, exc_info=True
                    )
                    await hub.broadcast({
                        "type": "error",
                        "source": "snmp_poller",
                        "device": device.name,
                        "message": str(dev_err),
                    })

        except Exception as loop_err:
            # خطأ في جلب قائمة الأجهزة — لا يُسقط الحلقة
            _log.error("خطأ عام في snmp_poll_loop: %s", loop_err, exc_info=True)
            await hub.broadcast({
                "type": "error",
                "source": "snmp_poller",
                "message": str(loop_err),
            })

        await asyncio.sleep(1)


async def _run_ont_detail_sweep(device: OLTDevice) -> None:
    """
    يجمع البيانات التفصيلية لكل ONT مسجَّل على هذا الجهاز.
    يستخدم collect_onts_basic أولاً للحصول على قائمة (fsp, ont_id) ثم
    يُشغّل refresh_ont_detail على كل واحد.
    يُبثّ حدث ont_detail_sweep واحد بعد الانتهاء.
    """
    # اقرأ قائمة ONTs من القاعدة (أسرع من إعادة سحب SNMP كامل)
    with Session(engine) as db:
        onts = db.exec(
            select(ONTRecord).where(ONTRecord.olt_id == device.id)
        ).all()

    updated = []
    for ont in onts:
        try:
            detail = await asyncio.to_thread(
                refresh_ont_detail, device, ont.fsp, ont.ont_id
            )
            updated.append(detail)
        except Exception as exc:
            _log.warning(
                "تعذّر سحب تفاصيل ONT %s/%d من %s: %s",
                ont.fsp, ont.ont_id, device.name, exc
            )

    await hub.broadcast({
        "type": "snmp",
        "layer": "ont_detail",
        "device": device.name,
        "data": updated,
    })
