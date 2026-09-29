"""
محاكاة SNMP — يُرجع قيَم OID وهمية متوافقة مع mock_olt.py.
يُستخدَم عوضاً عن الشبكة الحقيقية عند use_mock_olt=True.

ONTs المُحاكاة (تتطابق مع MockOLT):
  0/5/0/1 — 48575443D8EAC605  online   rx=-15.x dBm
  0/5/0/2 — 48575443D8F92405  online   rx=-17.x dBm
  0/5/0/3 — 48575443E1F0A409  online   rx=-20.x dBm
  0/5/1/1 — 4857544329518907  online   rx=-12.x dBm
  0/5/1/2 — 48575443F444CB04  OFFLINE  rx=-30.5 dBm  ← معطوب
"""
import random
import time
from typing import Any, Dict, List, Tuple

# =========================================================================
# بيانات ONTs الثابتة (تتّسق مع MockOLT.onts)
# =========================================================================
_ONTS: List[Dict] = [
    {"frame": 0, "slot": 5, "port": 0, "ont_id": 1, "sn": "48575443D8EAC605",
     "run_state": 1, "rx_power_raw": -1543, "tx_power_raw": 250,
     "olt_rx_raw": -1601, "temp": 55, "voltage_raw": 3310,
     "bias_raw": 16000, "distance": 1200, "last_down_cause": 2,
     "model": "EG8145V5", "hw_ver": "VER.A", "sw_ver": "V3R017C10",
     "auth_type": 1},
    {"frame": 0, "slot": 5, "port": 0, "ont_id": 2, "sn": "48575443D8F92405",
     "run_state": 1, "rx_power_raw": -1722, "tx_power_raw": 240,
     "olt_rx_raw": -1780, "temp": 58, "voltage_raw": 3305,
     "bias_raw": 14500, "distance": 2350, "last_down_cause": 11,
     "model": "EG8145V5", "hw_ver": "VER.A", "sw_ver": "V3R017C10",
     "auth_type": 1},
    {"frame": 0, "slot": 5, "port": 0, "ont_id": 3, "sn": "48575443E1F0A409",
     "run_state": 1, "rx_power_raw": -2005, "tx_power_raw": 235,
     "olt_rx_raw": -2066, "temp": 60, "voltage_raw": 3298,
     "bias_raw": 13800, "distance": 3780, "last_down_cause": 2,
     "model": "EG8145V5", "hw_ver": "VER.B", "sw_ver": "V3R017C10",
     "auth_type": 1},
    {"frame": 0, "slot": 5, "port": 1, "ont_id": 1, "sn": "4857544329518907",
     "run_state": 1, "rx_power_raw": -1250, "tx_power_raw": 280,
     "olt_rx_raw": -1310, "temp": 48, "voltage_raw": 3320,
     "bias_raw": 18000, "distance": 850, "last_down_cause": 2,
     "model": "EG8145X6", "hw_ver": "VER.A", "sw_ver": "V5R019C10",
     "auth_type": 1},
    # ONT معطوب — offline، قدرة منخفضة
    {"frame": 0, "slot": 5, "port": 1, "ont_id": 2, "sn": "48575443F444CB04",
     "run_state": 2, "rx_power_raw": -3050, "tx_power_raw": 0,
     "olt_rx_raw": -3100, "temp": 0, "voltage_raw": 0,
     "bias_raw": 0, "distance": 4200, "last_down_cause": 2,
     "model": "EG8145V5", "hw_ver": "VER.A", "sw_ver": "V3R017C10",
     "auth_type": 1},
]

# سحب uptime ثابت نسبياً (جلسة التشغيل)
_BOOT_TIME = time.time() - 128 * 86400 - 6 * 3600  # 128 يوماً و6 ساعات

# أساس OID لـ HUAWEI-XPON-MIB ONT info
_ONT_INFO_BASE = "1.3.6.1.4.1.2011.6.128.1.1.2.46.1"
_ONT_DDM_BASE = "1.3.6.1.4.1.2011.6.128.1.1.2.51.1"
_PON_PORT_BASE = "1.3.6.1.4.1.2011.6.128.1.1.2.47.1"


def _ont_index(o: Dict) -> str:
    """يبني index SNMP لـ ONT: frame.slot.port.ont_id"""
    return f"{o['frame']}.{o['slot']}.{o['port']}.{o['ont_id']}"


def _build_tree() -> Dict[str, Any]:
    """يبني شجرة OID كاملة للمحاكاة."""
    tree: Dict[str, Any] = {}

    # --- System OIDs ---
    uptime_ticks = int((time.time() - _BOOT_TIME) * 100)
    tree["1.3.6.1.2.1.1.1.0"] = "Huawei MA5800-X17 VRP V100R017C10 (Mock)"
    tree["1.3.6.1.2.1.1.2.0"] = "1.3.6.1.4.1.2011.2.218"
    tree["1.3.6.1.2.1.1.3.0"] = uptime_ticks
    tree["1.3.6.1.2.1.1.5.0"] = "OLT-Mock-Baghdad"
    tree["1.3.6.1.2.1.1.6.0"] = "Baghdad-NOC"

    # --- CPU / Memory (صف واحد لبطاقة المعالج) ---
    cpu_val = random.randint(3, 18)
    mem_val = random.randint(20, 40)
    tree["1.3.6.1.4.1.2011.6.3.3.1.1.10.0"] = cpu_val    # hwCpuDevDuty
    tree["1.3.6.1.4.1.2011.6.3.3.1.1.12.0"] = mem_val    # hwMemoryDevUsage

    # --- كرت المعالج slot 9 ---
    tree["1.3.6.1.4.1.2011.6.3.3.2.1.13.0.9"] = random.randint(45, 72)   # hwSlotTemprature
    tree["1.3.6.1.4.1.2011.6.3.3.2.1.8.0.9"] = 2   # hwSlotOperStatus = normal
    tree["1.3.6.1.4.1.2011.6.3.3.5.1.3.1"] = 1     # hwFanStatus = normal
    tree["1.3.6.1.4.1.2011.6.3.3.5.1.3.2"] = 1

    # --- PON ports: منافذ 0 و1 على slot 5 ---
    for port_idx in (0, 1):
        # index: frame.slot.port = 0.5.port_idx
        idx = f"0.5.{port_idx}"
        onts_on_port = [o for o in _ONTS if o["port"] == port_idx]
        online_cnt = sum(1 for o in onts_on_port if o["run_state"] == 1)
        offline_cnt = len(onts_on_port) - online_cnt
        tree[f"{_PON_PORT_BASE}.9.{idx}"] = online_cnt    # hwGponDevicePortActiveOntNum
        tree[f"{_PON_PORT_BASE}.10.{idx}"] = offline_cnt  # hwGponDevicePortDeactOntNum
        tree[f"{_PON_PORT_BASE}.19.{idx}"] = len(onts_on_port)  # hwGponDevicePortMaxOntNum
        tree[f"{_PON_PORT_BASE}.25.{idx}"] = random.randint(10, 65)  # BandWidthUsageRatio %
        tree[f"1.3.6.1.4.1.2011.6.128.1.1.2.12.1.3.{idx}"] = 1   # hwGponDevicePortPonType = GPON
        tree[f"1.3.6.1.2.1.2.2.1.8.{100 + port_idx}"] = 1    # ifOperStatus = up
        tree[f"1.3.6.1.2.1.2.2.1.10.{100 + port_idx}"] = random.randint(10_000_000, 100_000_000)
        tree[f"1.3.6.1.2.1.2.2.1.16.{100 + port_idx}"] = random.randint(5_000_000, 80_000_000)

    # --- ONT info + DDM ---
    for o in _ONTS:
        idx = _ont_index(o)
        # ONT Info table (hwGponOntInfoTable — .46.1.x)
        tree[f"{_ONT_INFO_BASE}.3.{idx}"] = o["sn"]            # SerialNumber
        tree[f"{_ONT_INFO_BASE}.4.{idx}"] = o["auth_type"]     # AuthType
        tree[f"{_ONT_INFO_BASE}.9.{idx}"] = o["model"]         # EquipmentId
        tree[f"{_ONT_INFO_BASE}.10.{idx}"] = o["sw_ver"]       # SoftwareVersion
        tree[f"{_ONT_INFO_BASE}.11.{idx}"] = o["hw_ver"]       # HardwareVersion
        tree[f"{_ONT_INFO_BASE}.15.{idx}"] = o["run_state"]    # RunState (1=online,2=offline)
        tree[f"{_ONT_INFO_BASE}.23.{idx}"] = o["distance"]     # Distance (m)
        tree[f"{_ONT_INFO_BASE}.25.{idx}"] = o["last_down_cause"]  # LastDownCause

        # ONT DDM table (hwGponOntOpticalDdmTable — .51.1.x)
        # قيَم DDM صفرية للـ ONT المنفصل (offline)
        tree[f"{_ONT_DDM_BASE}.1.{idx}"] = o["temp"]           # Temperature (°C)
        tree[f"{_ONT_DDM_BASE}.2.{idx}"] = o["voltage_raw"]    # Voltage ×0.001 V
        tree[f"{_ONT_DDM_BASE}.3.{idx}"] = o["tx_power_raw"]   # TxPower ×0.01 dBm
        tree[f"{_ONT_DDM_BASE}.4.{idx}"] = o["rx_power_raw"]   # RxPower ×0.01 dBm
        tree[f"{_ONT_DDM_BASE}.5.{idx}"] = o["bias_raw"]       # BiasCurrent ×0.002 mA
        tree[f"{_ONT_DDM_BASE}.6.{idx}"] = o["olt_rx_raw"]     # OltRxOntPower ×0.01 dBm

    return tree


class MockSNMP:
    """
    محاكاة SNMP لجهاز OLT وهمي واحد.
    يوفّر get(oids) وwalk(base_oid) تُرجع قيَماً معقولة.
    يُعاد بناء الشجرة عند كل استدعاء لعكس التغيّر الزمني (CPU / uptime).
    """

    def get(self, oids: List[str]) -> Dict[str, Any]:
        """
        يُرجع dict {oid: value} للـ OIDs المطلوبة.
        يجرّب OID مباشراً أولاً، ثم OID.0 (scalar convention)،
        ثم أول مدخل يبدأ بـ OID (للحقول المُفهرَسة).
        """
        tree = _build_tree()
        result: Dict[str, Any] = {}
        for oid in oids:
            oid = oid.rstrip(".")
            # 1. مطابقة تامة
            val = tree.get(oid)
            if val is not None:
                result[oid] = val
                continue
            # 2. scalar .0
            val = tree.get(oid + ".0")
            if val is not None:
                result[oid + ".0"] = val
                result[oid] = val   # أيضاً بالمفتاح الأصلي للتسهيل
                continue
            # 3. أول مدخل مُفهرَس (يبدأ بـ oid.)
            prefix = oid + "."
            for full_oid, v in tree.items():
                if full_oid.startswith(prefix):
                    result[full_oid] = v
                    result[oid] = v   # مفتاح قصير للتسهيل
                    break
        return result

    def walk(self, base_oid: str) -> Dict[str, Any]:
        """
        يُرجع dict {oid: value} لكل OIDs تبدأ بـ base_oid.
        يُحاكي GETNEXT/GETBULK.
        """
        tree = _build_tree()
        base = base_oid.rstrip(".")
        result: Dict[str, Any] = {}
        for oid, val in tree.items():
            if oid.startswith(base + ".") or oid == base:
                result[oid] = val
        return result

    # دوال مساعدة مباشرة للاختبار
    def get_ont_list(self) -> List[Dict]:
        """يُرجع قائمة بكل ONTs المُحاكاة (للاختبار السريع)."""
        return list(_ONTS)
