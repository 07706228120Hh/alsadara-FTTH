"""
SNMPv3 USM — نقل منخفض المستوى.
واجهة غير متزامنة أساسية (async) + أغلفة متزامنة آمنة لـ worker threads.

يتحمّل غياب pysnmp بأمان (HAS_PYSNMP=False):
- في وضع المحاكاة يوجَّه كل شيء إلى MockSNMP.
- في وضع الإنتاج يرفع ConfigurationError واضحاً.
"""
import asyncio
import logging
from typing import Any, Dict, List, Optional

from ..config import settings
from ..core import security

_log = logging.getLogger(__name__)

# -------------------------------------------------------------------------
# كشف pysnmp
# -------------------------------------------------------------------------
try:
    from pysnmp.hlapi.v3arch.asyncio import (
        SnmpEngine,
        UsmUserData,
        UdpTransportTarget,
        ContextData,
        ObjectType,
        ObjectIdentity,
        get_cmd,
        walk_cmd,
        # بروتوكولات المصادقة
        usmHMACSHAAuthProtocol,       # SHA-1 (SHA96)
        usmHMAC192SHA256AuthProtocol,  # SHA-256
        usmHMAC384SHA512AuthProtocol,  # SHA-512
        usmHMACMD5AuthProtocol,        # MD5
        usmNoAuthProtocol,
        # بروتوكولات التشفير
        usmAesCfb128Protocol,          # AES-128
        usmAesCfb256Protocol,          # AES-256
        usmDESPrivProtocol,            # DES
        usmNoPrivProtocol,
    )
    HAS_PYSNMP = True
except ImportError:
    HAS_PYSNMP = False
    _log.info("pysnmp غير مثبَّت — SNMP يعمل في وضع المحاكاة فقط")

# -------------------------------------------------------------------------
# خرائط بروتوكولات auth/priv
# -------------------------------------------------------------------------
_AUTH_MAP: Dict[str, Any] = {}
_PRIV_MAP: Dict[str, Any] = {}

if HAS_PYSNMP:
    _AUTH_MAP = {
        "SHA":    usmHMACSHAAuthProtocol,
        "SHA96":  usmHMACSHAAuthProtocol,
        "SHA256": usmHMAC192SHA256AuthProtocol,
        "SHA512": usmHMAC384SHA512AuthProtocol,
        "MD5":    usmHMACMD5AuthProtocol,
        "NONE":   usmNoAuthProtocol,
    }
    _PRIV_MAP = {
        "AES":    usmAesCfb128Protocol,
        "AES128": usmAesCfb128Protocol,
        "AES256": usmAesCfb256Protocol,
        "DES":    usmDESPrivProtocol,
        "NONE":   usmNoPrivProtocol,
    }


def _resolve_auth(proto: str):
    return _AUTH_MAP.get((proto or "SHA256").upper(), usmHMAC192SHA256AuthProtocol if HAS_PYSNMP else None)


def _resolve_priv(proto: str):
    return _PRIV_MAP.get((proto or "AES").upper(), usmAesCfb128Protocol if HAS_PYSNMP else None)


# -------------------------------------------------------------------------
# SNMPSession
# -------------------------------------------------------------------------

class SNMPSession:
    """
    جلسة SNMPv3 لجهاز واحد.
    توفّر أساليب غير متزامنة (aget/awalk) وأغلفة متزامنة (get/walk)
    آمنة للاستدعاء من خيط عامل.
    """

    def __init__(
        self,
        host: str,
        port: int,
        user: str,
        auth_proto: str,
        auth_key: str,
        priv_proto: str,
        priv_key: str,
        context: str = "",
        engine_id: str = "",
        mock: bool = False,
    ) -> None:
        self.host = host
        self.port = port
        self.user = user
        self.auth_proto = auth_proto
        self.auth_key = auth_key
        self.priv_proto = priv_proto
        self.priv_key = priv_key
        self.context = context
        self.engine_id = engine_id
        self._mock = mock

    # ------------------------------------------------------------------
    # مساعدات pysnmp
    # ------------------------------------------------------------------

    def _build_auth(self) -> "UsmUserData":  # type: ignore[name-defined]
        auth_p = _resolve_auth(self.auth_proto)
        priv_p = _resolve_priv(self.priv_proto)
        kwargs: Dict[str, Any] = {
            "authProtocol": auth_p,
            "authKey": self.auth_key,
            "privProtocol": priv_p,
            "privKey": self.priv_key,
        }
        if self.engine_id:
            try:
                from pysnmp.proto.rfc1902 import OctetString
                kwargs["securityEngineId"] = OctetString(hexValue=self.engine_id.replace(":", ""))
            except Exception:
                pass
        return UsmUserData(self.user, **kwargs)

    async def _build_target(self) -> "UdpTransportTarget":  # type: ignore[name-defined]
        return await UdpTransportTarget.create(
            (self.host, self.port),
            timeout=settings.snmp_timeout,
            retries=settings.snmp_retries,
        )

    def _build_context(self) -> "ContextData":  # type: ignore[name-defined]
        if self.context:
            from pysnmp.hlapi.v3arch.asyncio import ContextData as CD
            return CD(contextName=self.context)
        return ContextData()

    # ------------------------------------------------------------------
    # واجهة غير متزامنة
    # ------------------------------------------------------------------

    def _is_mock(self) -> bool:
        """يُحدَّد في وقت التشغيل حتى يعكس تغيير settings."""
        return self._mock or settings.use_mock_olt

    async def aget(self, oids: List[str]) -> Dict[str, object]:
        """GET على قائمة OIDs — يُرجع {oid: value}."""
        if self._is_mock():
            from .mock_snmp import MockSNMP
            return MockSNMP().get(oids)
        if not HAS_PYSNMP:
            raise RuntimeError("pysnmp غير مثبَّت وهذا ليس وضع المحاكاة")

        engine = SnmpEngine()
        auth = self._build_auth()
        target = await self._build_target()
        ctx = self._build_context()
        result: Dict[str, object] = {}
        var_binds = [ObjectType(ObjectIdentity(oid)) for oid in oids]
        try:
            error_indication, error_status, error_index, var_bind_table = await get_cmd(
                engine, auth, target, ctx, *var_binds
            )
            if error_indication:
                _log.warning("SNMP GET خطأ [%s]: %s", self.host, error_indication)
            elif error_status:
                _log.warning("SNMP GET status=%s index=%s [%s]",
                             error_status.prettyPrint(), error_index, self.host)
            else:
                for vb in var_bind_table:
                    oid_str = str(vb[0])
                    val = vb[1]
                    try:
                        result[oid_str] = int(val)
                    except Exception:
                        result[oid_str] = str(val)
        except Exception as exc:
            _log.warning("SNMP GET استثناء [%s]: %s", self.host, exc)
        finally:
            engine.close_dispatcher()
        return result

    async def awalk(self, base_oid: str) -> Dict[str, object]:
        """WALK من base_oid — يُرجع {oid: value}."""
        if self._is_mock():
            from .mock_snmp import MockSNMP
            return MockSNMP().walk(base_oid)
        if not HAS_PYSNMP:
            raise RuntimeError("pysnmp غير مثبَّت وهذا ليس وضع المحاكاة")

        engine = SnmpEngine()
        auth = self._build_auth()
        target = await self._build_target()
        ctx = self._build_context()
        result: Dict[str, object] = {}
        try:
            async for (error_indication, error_status, _idx, var_binds) in walk_cmd(
                engine, auth, target, ctx,
                ObjectType(ObjectIdentity(base_oid)),
                lexicographicMode=False,
            ):
                if error_indication or error_status:
                    break
                for vb in var_binds:
                    oid_str = str(vb[0])
                    val = vb[1]
                    try:
                        result[oid_str] = int(val)
                    except Exception:
                        result[oid_str] = str(val)
        except Exception as exc:
            _log.warning("SNMP WALK استثناء [%s]: %s", self.host, exc)
        finally:
            engine.close_dispatcher()
        return result

    # ------------------------------------------------------------------
    # أغلفة متزامنة (للاستخدام من worker thread)
    # ------------------------------------------------------------------

    def get(self, oids: List[str]) -> Dict[str, object]:
        """غلاف متزامن لـ aget — آمن داخل asyncio.to_thread."""
        if self._is_mock():
            from .mock_snmp import MockSNMP
            return MockSNMP().get(oids)
        try:
            loop = asyncio.get_event_loop()
        except RuntimeError:
            loop = None
        if loop and loop.is_running():
            # داخل حلقة asyncio — نفّذ في خيط فرعي عبر concurrent.futures
            import concurrent.futures
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
                future = pool.submit(asyncio.run, self.aget(oids))
                return future.result()
        return asyncio.run(self.aget(oids))

    def walk(self, base_oid: str) -> Dict[str, object]:
        """غلاف متزامن لـ awalk — آمن داخل asyncio.to_thread."""
        if self._is_mock():
            from .mock_snmp import MockSNMP
            return MockSNMP().walk(base_oid)
        try:
            loop = asyncio.get_event_loop()
        except RuntimeError:
            loop = None
        if loop and loop.is_running():
            import concurrent.futures
            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
                future = pool.submit(asyncio.run, self.awalk(base_oid))
                return future.result()
        return asyncio.run(self.awalk(base_oid))


# -------------------------------------------------------------------------
# SNMPManager
# -------------------------------------------------------------------------

class SNMPManager:
    """
    مدير جلسات SNMP — جلسة مُخزَّنة لكل device.id.
    يفكّ تشفير مفاتيح auth/priv عبر security.decrypt.
    """

    def __init__(self) -> None:
        self._sessions: Dict[int, SNMPSession] = {}

    def get(self, device) -> SNMPSession:
        """
        يُرجع SNMPSession للجهاز (يُنشئها عند الحاجة).
        يفكّ تشفير snmp_auth_key_enc و snmp_priv_key_enc من Fernet.
        وضع المحاكاة يُحدَّد في وقت التشغيل عبر _is_mock() في SNMPSession.
        """
        dev_id = device.id if hasattr(device, "id") else id(device)
        if dev_id not in self._sessions:
            auth_key = security.decrypt(getattr(device, "snmp_auth_key_enc", "") or "")
            priv_key = security.decrypt(getattr(device, "snmp_priv_key_enc", "") or "")
            # use_mock يُفحص ديناميكياً في SNMPSession._is_mock() عبر settings.use_mock_olt
            use_mock = not getattr(device, "snmp_enabled", True)
            self._sessions[dev_id] = SNMPSession(
                host=getattr(device, "host", "127.0.0.1"),
                port=getattr(device, "snmp_port", 161),
                user=getattr(device, "snmp_user", "platform-monitor"),
                auth_proto=getattr(device, "snmp_auth_proto", "SHA256"),
                auth_key=auth_key,
                priv_proto=getattr(device, "snmp_priv_proto", "AES"),
                priv_key=priv_key,
                context=getattr(device, "snmp_context", ""),
                engine_id=getattr(device, "snmp_engine_id", ""),
                mock=use_mock,
            )
        return self._sessions[dev_id]

    def drop(self, device_id: int) -> None:
        """يحذف الجلسة المخزَّنة لجهاز معيّن (عند تعديل بيانات الجهاز)."""
        self._sessions.pop(device_id, None)

    def test(self, device) -> Dict[str, object]:
        """
        يقرأ sysDescr و sysUpTime للتحقّق من الاتصال.
        يُرجع {"ok": bool, "sysDescr": str, "uptime": int, "error": str|None}.
        """
        sys_descr_oid = "1.3.6.1.2.1.1.1.0"
        sys_uptime_oid = "1.3.6.1.2.1.1.3.0"
        try:
            sess = self.get(device)
            data = sess.get([sys_descr_oid, sys_uptime_oid])
            descr = str(data.get(sys_descr_oid, ""))
            uptime_raw = data.get(sys_uptime_oid, 0)
            try:
                uptime_sec = int(uptime_raw) // 100  # timeticks → ثوانٍ
            except Exception:
                uptime_sec = 0
            if not descr and not uptime_sec:
                return {"ok": False, "sysDescr": "", "uptime": 0,
                        "error": "لا استجابة SNMP — تحقّق من إعدادات SNMPv3 للجهاز"}
            return {"ok": True, "sysDescr": descr, "uptime": uptime_sec, "error": None}
        except Exception as exc:
            return {"ok": False, "sysDescr": "", "uptime": 0, "error": str(exc)}


# مثيل عام
snmp_manager = SNMPManager()
