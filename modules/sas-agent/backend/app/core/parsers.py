"""
محلّلات مخرجات CLI — تحوّل النص غير المنظّم إلى بيانات JSON.
أهم تحدٍّ في التطبيق: مخرجات Huawei نصية، فنحوّلها إلى كائنات قابلة للاستخدام.
"""
import re
from typing import List, Dict, Optional


def parse_board_list(output: str) -> List[Dict]:
    boards = []
    for line in output.splitlines():
        m = re.match(r"\s*(\d+)\s+(H\w+)\s+(\S+)", line)
        if m:
            boards.append({
                "slot": int(m.group(1)),
                "name": m.group(2),
                "status": m.group(3),
            })
    return boards


def parse_ont_info_all(output: str) -> List[Dict]:
    """تحليل: display ont info <port> all"""
    onts = []
    for line in output.splitlines():
        # 0 /5 /0     1        48575443D8EAC605  active      online   normal   match
        m = re.match(
            r"\s*(\d+)\s*/\s*(\d+)\s*/\s*(\d+)\s+(\d+)\s+([0-9A-Fa-f]{12,16})\s+"
            r"(\w+)\s+(\w+)\s+(\w+)\s+(\w+)", line)
        if m:
            onts.append({
                "fsp": f"{m.group(1)}/{m.group(2)}/{m.group(3)}",
                "ont_id": int(m.group(4)),
                "sn": m.group(5),
                "control_flag": m.group(6),
                "run_state": m.group(7),
                "config_state": m.group(8),
                "match_state": m.group(9),
            })
    return onts


def _kv(output: str, key: str) -> Optional[str]:
    for line in output.splitlines():
        if key.lower() in line.lower() and ":" in line:
            return line.split(":", 1)[1].strip()
    return None


def parse_ont_detail(output: str) -> Dict:
    """تحليل تفاصيل ONT واحد"""
    def num(v):
        try:
            return float(re.sub(r"[^0-9.\-]", "", v))
        except Exception:
            return None
    d = {
        "run_state": _kv(output, "Run state"),
        "config_state": _kv(output, "Config state"),
        "match_state": _kv(output, "Match state"),
        "control_flag": _kv(output, "Control flag"),
        "sn": _kv(output, "SN"),
        "mgmt_mode": _kv(output, "Management mode"),
        "description": _kv(output, "Description"),
    }
    dist = _kv(output, "ONT distance(m)")
    temp = _kv(output, "Temperature(C)")
    cpu = _kv(output, "CPU occupation")
    mem = _kv(output, "Memory occupation")
    d["distance_m"] = int(num(dist)) if dist else None
    d["temperature"] = num(temp) if temp else None
    d["cpu"] = num(cpu) if cpu else None
    d["memory"] = num(mem) if mem else None
    return d


def parse_port_state(output: str) -> Dict:
    """تحليل القدرة الضوئية والليزر — display port state"""
    def num(key):
        v = _kv(output, key)
        if v is None:
            return None
        try:
            return float(re.sub(r"[^0-9.\-]", "", v))
        except Exception:
            return None
    return {
        "optical_module": _kv(output, "Optical Module status"),
        "port_state": _kv(output, "Port state"),
        "laser_state": _kv(output, "Laser state"),
        "temperature": num("Temperature(C)"),
        "tx_bias_ma": num("TX Bias current"),
        "voltage": num("Supply Voltage"),
        "tx_power_dbm": num("TX power(dBm)"),
        "rx_power_dbm": num("RX power(dBm)"),
        "last_down_cause": _kv(output, "Last down cause"),
    }


def parse_autofind(output: str) -> List[Dict]:
    """تحليل ONTs المكتشَفة — display ont autofind"""
    found = []
    blocks = re.split(r"Number\s*:", output)
    for block in blocks[1:]:
        sn = re.search(r"Ont SN\s*:\s*([0-9A-Fa-f]{12,16})", block)
        fsp = re.search(r"F/S/P\s*:\s*([\d/]+)", block)
        eq = re.search(r"EquipmentID\s*:\s*(\S+)", block)
        if sn:
            found.append({
                "sn": sn.group(1),
                "fsp": fsp.group(1) if fsp else "",
                "equipment": eq.group(1) if eq else "",
            })
    return found


def parse_esl_online(output: str) -> Dict:
    """تحليل جودة المكالمة الصوتية — MOS / R-Factor / jitter"""
    def num(key):
        v = _kv(output, key)
        if v is None:
            return None
        try:
            return float(re.sub(r"[^0-9.\-]", "", v))
        except Exception:
            return None
    return {
        "codec": _kv(output, "Codec"),
        "mos_lq": num("Estimated MOSLQ"),
        "mos_cq": num("Estimated MOSCQ"),
        "r_factor": num("R Factor"),
        "jitter_ms": num("Local Jitter"),
        "packet_loss": num("Local Packet loss"),
        "rtt_ms": num("RTCP RTT"),
    }


def parse_security_config(output: str) -> Dict:
    """تحليل حالة الأمان"""
    result = {}
    for line in output.splitlines():
        if ":" in line and "function" in line.lower():
            k, v = line.split(":", 1)
            result[k.strip()] = v.strip()
    return result


def parse_ping(output: str) -> Dict:
    loss = re.search(r"([\d.]+)%\s*packet loss", output)
    return {
        "success": "0.00% packet loss" in output or "0% packet loss" in output,
        "loss_percent": float(loss.group(1)) if loss else 100.0,
        "raw": output,
    }
