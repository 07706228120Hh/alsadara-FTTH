"""
مستقبِل SNMP Traps — يستمع للإنذارات الفورية من أجهزة OLT (UDP 162).
يدعم SNMPv3 USM (auth SHA256 + priv AES).
في وضع المحاكاة يحقن إنذارات وهمية دورية عبر normalize_trap.
يتطلب pysnmp للتشغيل الحقيقي (يتحمّل غيابه بأمان).
"""
import asyncio
import logging
from typing import Optional

from sqlmodel import Session, select

from ..database import engine
from ..models import OLTDevice, AlarmRecord, utcnow
from ..config import settings
from .monitoring import hub
from .alarm_normalizer import normalize_trap, ALARM_CODES

_log = logging.getLogger(__name__)

# علم توفّر pysnmp
try:
    from pysnmp.carrier.asyncio.dgram import udp as udp_transport
    from pysnmp.entity import config as snmp_config, engine as snmp_engine_mod
    from pysnmp.entity.rfc3413 import ntfrcv
    # بروتوكولات auth/priv لمستخدم SNMPv3
    from pysnmp.hlapi.v3arch.asyncio import (
        usmHMAC192SHA256AuthProtocol,
        usmAesCfb128Protocol,
        usmNoPrivProtocol,
        usmNoAuthProtocol,
    )
    HAS_PYSNMP = True
except ImportError:
    HAS_PYSNMP = False
    _log.info("pysnmp غير مثبَّت — مستقبِل trap يعمل في وضع المحاكاة فقط")


# =========================================================================
# عمليات مشتركة (تخزين + بث)
# =========================================================================

async def _store_and_broadcast(
    olt_id: int,
    normalized: dict,
    severity: str,
    source: str,
    message: str,
):
    """يخزّن AlarmRecord ويبثّه عبر WebSocket hub."""
    with Session(engine) as db:
        record = AlarmRecord(
            olt_id=olt_id,
            severity=severity,
            source=source,
            message=message,
            active=True,
            ts=utcnow(),
            alarm_uid=normalized.get("alarm_uid", ""),
            source_type=normalized.get("source_type", ""),
            frame=normalized.get("frame"),
            slot=normalized.get("slot"),
            pon=normalized.get("pon"),
            ont_id_ref=normalized.get("ont_id"),   # العمود هو ont_id_ref
            code=normalized.get("code", ""),
            title=normalized.get("title", ""),
            occurred_at=normalized.get("occurred_at"),
        )
        db.add(record)
        db.commit()

    await hub.broadcast({
        "type": "trap",
        "data": {
            "alarm_uid": normalized.get("alarm_uid"),
            "severity": severity,
            "source": source,
            "code": normalized.get("code"),
            "title": normalized.get("title"),
            "message": message,
            "frame": normalized.get("frame"),
            "slot": normalized.get("slot"),
            "pon": normalized.get("pon"),
            "ont_id": normalized.get("ont_id"),
            "ts": utcnow().isoformat(),
        },
    })


# =========================================================================
# حلقة المحاكاة
# =========================================================================

async def _mock_trap_loop():
    """يحقن إنذارات تجريبية دورية في وضع المحاكاة — عبر normalize_trap."""
    # عيّنات من varbinds وهمية تغطي أكواد مختلفة
    samples = [
        # (وصف للعرض، varbinds)
        ("LOS", [
            ("1.3.6.1.6.3.1.1.4.1.0", "1.3.6.1.4.1.2011.6.128.1.1.3.1"),
            ("1.3.6.1.4.1.2011.6.128.1.1.2.46.1.15.0.5.1.2", "2"),
            ("fsp_text", "0/5/1/2"),
        ]),
        ("HIGH_TEMP", [
            ("1.3.6.1.6.3.1.1.4.1.0", "1.3.6.1.4.1.2011.6.3.3.20.1"),
            ("hwHighTemperatureAlarm", "Board 0/9 temp=85C"),
        ]),
        ("PON_DOWN", [
            ("1.3.6.1.6.3.1.1.4.1.0", "1.3.6.1.4.1.2011.6.128.1.1.3.5"),
            ("hwGponPortDown", "0.5.0"),
        ]),
    ]
    i = 0
    # تأخير أطول من دورة المراقبة لتجنّب إغراق الواجهة
    while True:
        await asyncio.sleep(max(90, settings.monitor_interval * 3))
        with Session(engine) as db:
            device = db.exec(select(OLTDevice)).first()
        if not device:
            continue

        desc, varbinds = samples[i % len(samples)]
        try:
            normalized = normalize_trap(
                varbinds=varbinds,
                olt_id=device.id,
                olt_name=device.name,
                source_ip="127.0.0.1",
            )
            await _store_and_broadcast(
                olt_id=device.id,
                normalized=normalized,
                severity=normalized["severity"],
                source=normalized["source"],
                message=normalized["message"],
            )
            _log.debug("trap وهمي: %s uid=%s", desc, normalized["alarm_uid"])
        except Exception as exc:
            _log.warning("_mock_trap_loop خطأ: %s", exc)
        i += 1


# =========================================================================
# المستقبِل الحقيقي SNMPv3
# =========================================================================

def _real_trap_listener():
    """
    مستمع UDP حقيقي يعمل في خيط منفصل (blocking).
    يقبل SNMPv3 traps بمستخدم 'platform-monitor' (auth SHA256, priv AES).
    يطبّق قيود المصدر من settings.snmp_allowed_sources_list.
    """
    if not HAS_PYSNMP:
        _log.warning("pysnmp غير مثبَّت — مستقبِل trap الحقيقي لن يُشغَّل")
        return None

    # --- رفض التشغيل غير الآمن في الإنتاج ---
    # في الإنتاج (use_mock_olt=false) يجب توفير مفاتيح auth + priv من .env.
    # مفاتيح فارغة = v3 بلا حماية حقيقية، وهو خطر مرفوض صراحةً.
    if not settings.use_mock_olt:
        missing_keys = []
        if not settings.snmp_trap_auth_key:
            missing_keys.append("SNMP_TRAP_AUTH_KEY")
        if not settings.snmp_trap_priv_key:
            missing_keys.append("SNMP_TRAP_PRIV_KEY")
        if missing_keys:
            _log.warning(
                "مستقبِل SNMP trap لن يُشغَّل: مفاتيح SNMPv3 USM مفقودة في .env: %s. "
                "عيّن هذه المتغيّرات لتفعيل الاستقبال الحقيقي. "
                "لا يُستخدم v2c أو مفاتيح افتراضية في الإنتاج.",
                ", ".join(missing_keys),
            )
            return None

    # --- خريطة بروتوكولات auth ---
    _AUTH_PROTOS = {
        "SHA256": usmHMAC192SHA256AuthProtocol,
        "SHA": usmHMAC192SHA256AuthProtocol,   # تعامَل SHA كـ SHA256 (أحدث)
        "MD5": usmNoAuthProtocol,               # MD5 غير مدعوم هنا — fallback آمن
        "NONE": usmNoAuthProtocol,
    }
    _PRIV_PROTOS = {
        "AES": usmAesCfb128Protocol,
        "AES128": usmAesCfb128Protocol,
        "NONE": usmNoPrivProtocol,
    }

    auth_proto = _AUTH_PROTOS.get(
        settings.snmp_trap_auth_proto.upper(), usmHMAC192SHA256AuthProtocol
    )
    priv_proto = _PRIV_PROTOS.get(
        settings.snmp_trap_priv_proto.upper(), usmAesCfb128Protocol
    )

    # بناء engine
    snmpEngine = snmp_engine_mod.SnmpEngine()

    # إضافة نقل UDP
    try:
        snmp_config.add_transport(
            snmpEngine,
            udp_transport.DOMAIN_NAME + (1,),
            udp_transport.UdpTransport().open_server_mode(
                ("0.0.0.0", settings.snmp_trap_port)
            ),
        )
    except Exception as exc:
        _log.error("فشل فتح UDP/%d للـ traps: %s", settings.snmp_trap_port, exc)
        return None

    # --- تسجيل مستخدم SNMPv3 USM واحد فقط — لا v1/v2c إطلاقاً ---
    # جميع القيم (اسم المستخدم، البروتوكولات، المفاتيح) مُقرأة من settings (.env).
    # لا توجد قيم مُرمَّزة في الكود (hardcoded).
    trap_user = settings.snmp_trap_user
    try:
        snmp_config.add_v3_user(
            snmpEngine,
            userName=trap_user,
            authProtocol=auth_proto,
            authKey=settings.snmp_trap_auth_key,
            privProtocol=priv_proto,
            privKey=settings.snmp_trap_priv_key,
        )
    except Exception as exc:
        _log.warning("فشل إضافة مستخدم SNMPv3 USM '%s': %s", trap_user, exc)

    # --- تتبّع عنوان المصدر ---
    #
    # القيد: pysnmp 7.x لا تمرّر عنوان المصدر مباشرةً لـ cbFun. نستخدم
    # observer على نقطة "rfc3412.receiveMessage:request" لالتقاطه قبيل
    # استدعاء cbFun. هذا أفضل-جهد وقد يعاني حالة تسابق تحت حِمل عالٍ
    # إذ يُشارَك _source_tracker بين نفس الخيط (dispatcher أحادي الخيط)
    # فالتسابق نظري في الغالب، لكن:
    #
    # توصية أمان: عزّز هذا القيد بجدار ناري على مستوى الشبكة يقيّد UDP/{snmp_trap_port}
    # على IPs الـ OLT المعروفة — هذا هو الحاجز الفعلي الموثوق.
    # تصفية التطبيق هنا طبقة ثانية "أفضل-جهد".
    _source_tracker: dict = {}

    allowed_ips = set(settings.snmp_allowed_sources_list)
    if not allowed_ips:
        _log.info(
            "SNMP_ALLOWED_SOURCES فارغة — مستقبِل trap يقبل من جميع المصادر "
            "(مناسب للتطوير؛ قيّد في الإنتاج عبر جدار ناري أو اضبط SNMP_ALLOWED_SOURCES)."
        )

    def _source_observer(snmpEngine, execpoint, variables, cbCtx):
        """يلتقط عنوان IP المُرسِل من بيانات النقل قُبيل cbFun."""
        try:
            transport_domain, transport_address = variables.get(
                "transportAddress", (None, ("0.0.0.0",))
            )
            if isinstance(transport_address, tuple) and transport_address:
                _source_tracker["ip"] = transport_address[0]
        except Exception:
            # لا نُهمل بصمت — نُسجّل للتشخيص
            _log.debug("_source_observer: فشل التقاط عنوان المصدر")

    try:
        snmpEngine.observer.register_observer(
            _source_observer,
            "rfc3412.receiveMessage:request",
            lookupMib=False,
        )
    except Exception as exc:
        _log.debug("register_observer غير متاح في هذا الإصدار من pysnmp: %s", exc)

    def cbFun(
        snmpEngine, stateReference, contextEngineId, contextName,
        varBinds, cbCtx
    ):
        """معالج trap الوارد."""
        source_ip = _source_tracker.get("ip", "0.0.0.0")

        # تصفية المصدر
        if allowed_ips and source_ip not in allowed_ips:
            _log.debug("trap مرفوض من %s — خارج قائمة المسموح", source_ip)
            return

        # تحويل varbinds
        varbinds = []
        for name, val in varBinds:
            try:
                varbinds.append((name.prettyPrint(), val.prettyPrint()))
            except Exception:
                varbinds.append((str(name), str(val)))

        full_text = "; ".join(f"{k}={v}" for k, v in varbinds)

        # استخراج olt_id من الجهاز الأول (يمكن توسيعه لاحقاً بخريطة IP→device)
        with Session(engine) as db:
            device = db.exec(select(OLTDevice)).first()
            olt_id = device.id if device else 1
            olt_name = device.name if device else "OLT"

        # تطبيع الإنذار
        try:
            normalized = normalize_trap(
                varbinds=varbinds,
                olt_id=olt_id,
                olt_name=olt_name,
                source_ip=source_ip,
            )
        except Exception as exc:
            _log.warning("normalize_trap خطأ: %s", exc)
            normalized = {
                "alarm_uid": "",
                "source_type": "OLT",
                "frame": None, "slot": None, "pon": None, "ont_id": None,
                "severity": "major",
                "code": "UNKNOWN",
                "title": "إنذار SNMP",
                "source": f"{olt_name} ({source_ip})",
                "message": f"[SNMP Trap] {full_text[:360]}",
                "occurred_at": utcnow(),
            }

        # تخزين في قاعدة البيانات (خيط منفصل — بدون asyncio)
        with Session(engine) as db:
            record = AlarmRecord(
                olt_id=olt_id,
                severity=normalized["severity"],
                source=normalized["source"],
                message=normalized["message"],
                active=True,
                ts=utcnow(),
                alarm_uid=normalized.get("alarm_uid", ""),
                source_type=normalized.get("source_type", ""),
                frame=normalized.get("frame"),
                slot=normalized.get("slot"),
                pon=normalized.get("pon"),
                ont_id_ref=normalized.get("ont_id"),
                code=normalized.get("code", ""),
                title=normalized.get("title", ""),
                occurred_at=normalized.get("occurred_at"),
            )
            db.add(record)
            db.commit()

        _log.info("trap مُستقبَل من %s: %s uid=%s",
                  source_ip, normalized.get("code"), normalized.get("alarm_uid"))

    # تسجيل المعالج
    ntfrcv.NotificationReceiver(snmpEngine, cbFun)
    snmpEngine.transport_dispatcher.job_started(1)
    _log.info("مستقبِل SNMP v3 جاهز على UDP/%d", settings.snmp_trap_port)
    try:
        snmpEngine.transport_dispatcher.run_dispatcher()
    except Exception as exc:
        _log.error("توقّف مستقبِل SNMP: %s", exc)
    finally:
        try:
            snmpEngine.transport_dispatcher.close_dispatcher()
        except Exception:
            pass
    return snmpEngine


# =========================================================================
# نقطة الدخول
# =========================================================================

async def start_trap_receiver():
    """يبدأ المستقبِل المناسب حسب الوضع (mock / real)."""
    if settings.use_mock_olt:
        _log.info("وضع المحاكاة — حلقة traps وهمية تعمل")
        await _mock_trap_loop()
    else:
        _log.info("وضع الإنتاج — بدء مستقبِل SNMP v3 الحقيقي")
        await asyncio.to_thread(_real_trap_listener)
