"""
قارئ SNMP عالي المستوى — يجمع بين Adapter + SNMPClient لإنتاج بيانات موحّدة.
هذا هو العقد العام الذي يستهلكه سحّاب المراقبة والـ API.

الدوال العامة (كلها متزامنة، تُستدعى من asyncio.to_thread):
  collect_health(device) -> dict
  collect_pon(device)    -> list[dict]
  collect_onts_basic(device) -> list[dict]
  collect_ont_detail(device, fsp, ont_id) -> dict
  load_adapter(device)   -> dict
  list_adapters()        -> list[dict]
"""
import json
import logging
import os
from pathlib import Path
from typing import Any, Dict, List, Optional

from .snmp_client import snmp_manager

_log = logging.getLogger(__name__)

# مسار ملفات Adapter — pathlib (متوافق مع ويندوز)
_ADAPTERS_DIR = Path(__file__).resolve().parent.parent / "knowledge" / "adapters"

# ONT base OIDs المُستخدمة في walk (HUAWEI-XPON-MIB)
_ONT_INFO_BASE = "1.3.6.1.4.1.2011.6.128.1.1.2.46.1"
_ONT_DDM_BASE = "1.3.6.1.4.1.2011.6.128.1.1.2.51.1"
_PON_PORT_BASE = "1.3.6.1.4.1.2011.6.128.1.1.2.47.1"


# =========================================================================
# تحميل Adapter
# =========================================================================

def _load_adapter_file(path: Path) -> Dict:
    """يقرأ ملف JSON بترميز UTF-8."""
    with open(str(path), encoding="utf-8") as fh:
        return json.load(fh)


def _find_adapter_path(device) -> Optional[Path]:
    """
    يختار ملف Adapter المناسب للجهاز:
    1. adapter_profile صريح على الجهاز.
    2. مطابقة model مع حقل match.model في كل Adapter.
    3. خيار احتياطي: أول ملف Adapter في المجلد.
    """
    if not _ADAPTERS_DIR.exists():
        return None

    # 1. adapter_profile صريح
    profile = (getattr(device, "adapter_profile", None) or "").strip()
    if profile:
        candidates = [
            _ADAPTERS_DIR / profile,
            _ADAPTERS_DIR / (profile + ".json"),
        ]
        for c in candidates:
            if c.exists():
                return c

    # 2. مطابقة model
    dev_model = (getattr(device, "model", "") or "").upper()
    for f in _ADAPTERS_DIR.glob("*.json"):
        try:
            data = _load_adapter_file(f)
            match_models = [m.upper() for m in data.get("match", {}).get("model", [])]
            if dev_model and any(dev_model in mm or mm in dev_model for mm in match_models):
                return f
        except Exception:
            pass

    # 3. احتياطي
    files = list(_ADAPTERS_DIR.glob("*.json"))
    return files[0] if files else None


def load_adapter(device) -> Dict:
    """
    يُرجع dict كامل لملف Adapter المناسب للجهاز.
    يُرجع dict فارغاً إن لم يُعثر على ملف.
    """
    path = _find_adapter_path(device)
    if not path:
        _log.warning("لم يُعثر على Adapter لـ %s", getattr(device, "model", "?"))
        return {}
    try:
        return _load_adapter_file(path)
    except Exception as exc:
        _log.warning("فشل تحميل Adapter %s: %s", path.name, exc)
        return {}


def list_adapters() -> List[Dict]:
    """
    يُرجع قائمة بكل Adapters المتاحة: [{name, model, vendor, file}].
    """
    result = []
    if not _ADAPTERS_DIR.exists():
        return result
    for f in sorted(_ADAPTERS_DIR.glob("*.json")):
        try:
            data = _load_adapter_file(f)
            result.append({
                "name": f.stem,
                "model": data.get("model", ""),
                "vendor": data.get("vendor", ""),
                "match": data.get("match", {}),
                "file": f.name,
            })
        except Exception:
            pass
    return result


# =========================================================================
# مساعدات تطبيق scale / map
# =========================================================================

def _apply_field(raw_val: Any, field_def: Dict) -> Any:
    """يُحوّل القيمة الخام إلى وحدة موحّدة بتطبيق scale و map."""
    if raw_val is None:
        return None
    kind = field_def.get("kind", "gauge")
    mapping = field_def.get("map")
    scale = field_def.get("scale", 1)

    if mapping:
        return mapping.get(str(raw_val), raw_val)

    if kind in ("int", "gauge", "counter", "timeticks"):
        try:
            val = float(raw_val)
            if scale != 1:
                val = round(val * scale, 4)
            return val
        except (TypeError, ValueError):
            return raw_val

    return raw_val  # string


def _get_oid_for_field(field_name: str, adapter: Dict, mib_hint: bool = True) -> Optional[str]:
    """يُرجع OID رقمي لحقل معيّن من Adapter (مع محاولة حل MIB رمزي إن توفّر)."""
    fields = adapter.get("fields", {})
    field_def = fields.get(field_name, {})
    if not field_def:
        return None

    # محاولة حل MIB رمزي أولاً
    if mib_hint:
        symbol = field_def.get("symbol")
        if symbol:
            try:
                from .mib_registry import registry
                resolved = registry.resolve(symbol)
                if resolved:
                    return resolved
            except Exception:
                pass

    return field_def.get("oid")


def _extract_indexed_values(walk_data: Dict[str, Any], base_oid: str) -> Dict[str, Any]:
    """
    من نتيجة walk يستخرج {suffix: value}
    حيث suffix = ما بعد base_oid.
    """
    result: Dict[str, Any] = {}
    prefix = base_oid.rstrip(".") + "."
    for full_oid, val in walk_data.items():
        if full_oid.startswith(prefix):
            suffix = full_oid[len(prefix):]
            result[suffix] = val
    return result


# =========================================================================
# collect_health
# =========================================================================

def collect_health(device) -> Dict:
    """
    يجمع بيانات صحّة OLT (CPU / ذاكرة / حرارة / uptime / مروحة / طاقة / إصدار).
    يُرجع dict بمفاتيح موحّدة.
    """
    result: Dict = {
        "cpu": None, "memory": None, "temperature": None, "uptime": None,
        "power_status": "", "fan_status": "", "sw_version": "",
        "active_alarms": 0,
    }
    try:
        adapter = load_adapter(device)
        sess = snmp_manager.get(device)
        fields = adapter.get("fields", {})

        # حقول scalar (oid ثابت بدون index)
        scalar_map = {
            "cpu":         "olt.cpu",
            "memory":      "olt.memory",
            "sw_version":  "olt.sw_version",
            "uptime":      "olt.uptime",
        }
        oids_to_fetch = []
        oid_field_map: Dict[str, tuple] = {}
        for result_key, field_name in scalar_map.items():
            fd = fields.get(field_name)
            if fd:
                oid = _get_oid_for_field(field_name, adapter)
                if oid:
                    oids_to_fetch.append(oid)
                    oid_field_map[oid] = (result_key, fd)

        if oids_to_fetch:
            data = sess.get(oids_to_fetch)
            for oid, (res_key, fd) in oid_field_map.items():
                # حاول OID مباشراً أو مع suffix .0
                raw = data.get(oid) or data.get(oid + ".0")
                if raw is not None:
                    val = _apply_field(raw, fd)
                    # uptime يُخزَّن كـ int (ثوانٍ صحيحة) في DeviceHealth.uptime
                    if res_key == "uptime" and val is not None:
                        try:
                            val = int(val)
                        except (TypeError, ValueError):
                            val = None
                    result[res_key] = val

        # درجة الحرارة — walk per_slot وأخذ أعلى قيمة (أسوأ حالة)
        temp_oid = _get_oid_for_field("olt.temperature", adapter)
        if temp_oid:
            temp_data = sess.walk(temp_oid)
            temps = []
            for val in temp_data.values():
                try:
                    tv = int(val)
                    if tv != 0x7FFFFFFF:  # قيمة "غير متاح" عند Huawei
                        temps.append(tv)
                except Exception:
                    pass
            if temps:
                result["temperature"] = max(temps)

        # حالة الطاقة — walk per_slot وأبلغ عن أسوأ حالة
        power_oid = _get_oid_for_field("olt.power_status", adapter)
        if power_oid:
            pw_data = sess.walk(power_oid)
            fd = fields.get("olt.power_status", {})
            statuses = [_apply_field(v, fd) for v in pw_data.values()]
            # ابحث عن failure/powered-off أولاً
            for bad in ("failure", "out-of-service", "powered-off", "disabled"):
                if bad in statuses:
                    result["power_status"] = bad
                    break
            else:
                result["power_status"] = statuses[0] if statuses else ""

        # حالة المراوح — walk
        fan_oid = _get_oid_for_field("olt.fan_status", adapter)
        if fan_oid:
            fan_data = sess.walk(fan_oid)
            fd = fields.get("olt.fan_status", {})
            fan_statuses = [_apply_field(v, fd) for v in fan_data.values()]
            result["fan_status"] = "abnormal" if "abnormal" in fan_statuses else "normal"

    except Exception as exc:
        _log.error("collect_health فشل [%s]: %s", getattr(device, "name", "?"), exc)

    return result


# =========================================================================
# collect_pon
# =========================================================================

def collect_pon(device) -> List[Dict]:
    """
    يجمع ملخّص منافذ PON.
    يُرجع list[dict] بمفاتيح: frame,slot,port,status,tech,onts_registered,
    onts_online,onts_offline,rx_traffic,tx_traffic,utilization.
    """
    results: List[Dict] = []
    try:
        adapter = load_adapter(device)
        sess = snmp_manager.get(device)
        fields = adapter.get("fields", {})

        # Walk على onts_online (hwGponDevicePortActiveOntNum) لاكتشاف المنافذ
        online_oid = _get_oid_for_field("pon.onts_online", adapter)
        if not online_oid:
            return results

        online_data = _extract_indexed_values(sess.walk(online_oid), online_oid)

        # جمع باقي الحقول بـ walk
        def _walk_field(fname: str) -> Dict[str, Any]:
            oid = _get_oid_for_field(fname, adapter)
            if not oid:
                return {}
            return _extract_indexed_values(sess.walk(oid), oid)

        offline_data = _walk_field("pon.onts_offline")
        reg_data = _walk_field("pon.onts_registered")
        util_data = _walk_field("pon.utilization")
        tech_data = _walk_field("pon.tech")
        status_data = _walk_field("pon.status")
        rx_data = _walk_field("pon.rx_traffic")
        tx_data = _walk_field("pon.tx_traffic")

        for idx, online_raw in online_data.items():
            # idx مثل "0.5.0" (frame.slot.port)
            parts = idx.split(".")
            try:
                frame, slot, port = int(parts[0]), int(parts[1]), int(parts[2])
            except (IndexError, ValueError):
                continue

            fd_online = fields.get("pon.onts_online", {})
            fd_offline = fields.get("pon.onts_offline", {})
            fd_reg = fields.get("pon.onts_registered", {})
            fd_util = fields.get("pon.utilization", {})
            fd_tech = fields.get("pon.tech", {})
            fd_status = fields.get("pon.status", {})
            fd_rx = fields.get("pon.rx_traffic", {})
            fd_tx = fields.get("pon.tx_traffic", {})

            results.append({
                "frame": frame,
                "slot": slot,
                "port": port,
                "status": _apply_field(status_data.get(idx), fd_status) or "up",
                "tech": _apply_field(tech_data.get(idx), fd_tech) or "GPON",
                "onts_registered": _apply_field(reg_data.get(idx), fd_reg) or 0,
                "onts_online": _apply_field(online_raw, fd_online) or 0,
                "onts_offline": _apply_field(offline_data.get(idx), fd_offline) or 0,
                "rx_traffic": _apply_field(rx_data.get(idx), fd_rx),
                "tx_traffic": _apply_field(tx_data.get(idx), fd_tx),
                "utilization": _apply_field(util_data.get(idx), fd_util),
            })

    except Exception as exc:
        _log.error("collect_pon فشل [%s]: %s", getattr(device, "name", "?"), exc)

    return results


# =========================================================================
# collect_onts_basic
# =========================================================================

def collect_onts_basic(device) -> List[Dict]:
    """
    يجمع حالة ONTs الأساسية (online/offline + SN + rx_power).
    يُرجع list[dict]: fsp, ont_id, sn, run_state, config_state, match_state, rx_power.
    """
    results: List[Dict] = []
    try:
        adapter = load_adapter(device)
        sess = snmp_manager.get(device)
        fields = adapter.get("fields", {})

        # Walk على run_state لاكتشاف ONTs
        state_oid = _get_oid_for_field("ont.status", adapter)
        if not state_oid:
            return results

        state_data = _extract_indexed_values(sess.walk(state_oid), state_oid)

        def _walk_ont_field(fname: str) -> Dict[str, Any]:
            oid = _get_oid_for_field(fname, adapter)
            if not oid:
                return {}
            return _extract_indexed_values(sess.walk(oid), oid)

        sn_data = _walk_ont_field("ont.serial")
        rx_data = _walk_ont_field("ont.optical_rx_dbm")

        fd_state = fields.get("ont.status", {})
        fd_rx = fields.get("ont.optical_rx_dbm", {})

        for idx, state_raw in state_data.items():
            # idx مثل "0.5.0.1" (frame.slot.port.ont_id)
            parts = idx.split(".")
            try:
                frame, slot, port, ont_id = (
                    int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3])
                )
            except (IndexError, ValueError):
                continue

            fsp = f"{frame}/{slot}/{port}"
            run_state = _apply_field(state_raw, fd_state) or "unknown"
            rx_raw = rx_data.get(idx)
            rx_power = _apply_field(rx_raw, fd_rx)

            results.append({
                "fsp": fsp,
                "ont_id": ont_id,
                "sn": sn_data.get(idx, ""),
                "run_state": run_state,
                "config_state": "normal",   # متاح فقط عبر CLI في هذا التطبيق
                "match_state": "match",
                "rx_power": rx_power,
            })

    except Exception as exc:
        _log.error("collect_onts_basic فشل [%s]: %s", getattr(device, "name", "?"), exc)

    return results


# =========================================================================
# collect_ont_detail
# =========================================================================

def collect_ont_detail(device, fsp: str, ont_id: int) -> Dict:
    """
    يجمع بيانات ONT التفصيلية: DDM كامل + مسافة + إصدارات + سبب الانقطاع.
    fsp: مثل "0/5/1"، ont_id: رقم صحيح.
    يُرجع dict بمفاتيح موحّدة.
    """
    result: Dict = {
        "fsp": fsp, "ont_id": ont_id,
        "rx_power": None, "tx_power": None, "olt_rx_power": None,
        "temperature": None, "voltage": None, "bias_current": None,
        "distance_m": None,
        "last_up": None, "last_down": None, "last_down_cause": "",
        "ont_model": "", "hw_version": "", "sw_version": "", "reg_method": "",
    }
    try:
        adapter = load_adapter(device)
        sess = snmp_manager.get(device)
        fields = adapter.get("fields", {})

        # بناء SNMP index من fsp + ont_id
        parts = fsp.split("/")
        if len(parts) == 3:
            snmp_idx = f"{parts[0]}.{parts[1]}.{parts[2]}.{ont_id}"
        else:
            snmp_idx = f"0.5.{fsp.replace('/', '.')}.{ont_id}"

        # OIDs التفصيلية للـ ONT
        detail_fields = {
            "rx_power":        "ont.optical_rx_dbm",
            "tx_power":        "ont.optical_tx_dbm",
            "olt_rx_power":    "ont.olt_rx_dbm",
            "temperature":     "ont.temperature",
            "voltage":         "ont.voltage",
            "bias_current":    "ont.bias_current",
            "distance_m":      "ont.distance_meters",
            "last_down_cause": "ont.last_down_cause",
            "ont_model":       "ont.model",
            "hw_version":      "ont.hw_version",
            "sw_version":      "ont.sw_version",
            "reg_method":      "ont.reg_method",
        }

        oids_to_get = []
        oid_map: Dict[str, tuple] = {}
        for res_key, field_name in detail_fields.items():
            fd = fields.get(field_name)
            if fd:
                base_oid = _get_oid_for_field(field_name, adapter)
                if base_oid:
                    full_oid = f"{base_oid}.{snmp_idx}"
                    oids_to_get.append(full_oid)
                    oid_map[full_oid] = (res_key, fd)

        if oids_to_get:
            data = sess.get(oids_to_get)
            for full_oid, (res_key, fd) in oid_map.items():
                raw = data.get(full_oid)
                if raw is not None:
                    result[res_key] = _apply_field(raw, fd)

    except Exception as exc:
        _log.error("collect_ont_detail فشل [%s %s/%d]: %s",
                   getattr(device, "name", "?"), fsp, ont_id, exc)

    return result
