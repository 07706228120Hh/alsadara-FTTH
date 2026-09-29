"""
مطبِّع إنذارات SNMP Traps — يُحوّل varbinds خام إلى صيغة AlarmRecord الموحّدة.
"""
import re
import threading
from datetime import datetime
from typing import Dict, List, Optional, Tuple

from ..models import utcnow

# -------------------------------------------------------------------------
# عدّاد لتوليد alarm_uid فريد (آمن للخيوط)
# -------------------------------------------------------------------------
_uid_lock = threading.Lock()
_uid_counter = 0


def _next_uid() -> str:
    global _uid_counter
    with _uid_lock:
        _uid_counter += 1
        n = _uid_counter
    now = utcnow()
    date_part = now.strftime("%Y%m%d")
    return f"ALM-{date_part}-{n:04d}"


# -------------------------------------------------------------------------
# قواعد التصنيف الحتمية — مرتّبة من الأكثر تحديداً إلى الأقل
#
# كل قاعدة: dict بمفاتيح:
#   code        — رمز الإنذار المستهدَف
#   exact       — قائمة أنماط regex تُختبر على النص الأصلي (case-insensitive)
#                 مع حدود الكلمة (\b) لمنع التداخل
#
# المبدأ:
#   1. كل كود يملك أنماطه الفريدة التي لا تلتقطها أكواد أخرى.
#   2. الترتيب يُحسم التداخل المحتمل — الأكثر تحديداً أولاً.
#   3. مطابقة حدود الكلمة (\b) تمنع "powerfail" من التقاط "hwPowerFail".
#
# ملاحظة تقنية: \b في regex Python تعمل على الأبجدية اللاتينية وتعامل أرقاماً
# وحروفاً متصلة ككلمة واحدة، مما يكفي لفصل "hw" عن "powerfail" لأن
# "hwpowerfail" كلمة واحدة بلا \b داخلها.
# -------------------------------------------------------------------------

# الأولوية الصريحة: الأكثر تحديداً أولاً
_CLASSIFICATION_RULES: List[Dict] = [
    # ------------------------------------------------------------------
    # ONT_LOS — فقدان الإشارة الضوئية (LOS / Signal Lost)
    # نستخدم حدود الكلمة لـ "los" لمنع تلقاطه في كلمات مثل "close"
    # ------------------------------------------------------------------
    {
        "code": "ONT_LOS",
        "patterns": [
            r"\bontlos\b",
            r"\bont[-_]?los\b",
            r"\bgponontlos\b",
            r"\bhwgponontlos\b",
            r"\bsignal\s+lost\b",
            r"2011\.6\.128\.1\.1\.3\.1",  # OID prefix
            r"\blos\b",                   # مع حد الكلمة لتجنّب "close/elos"
        ],
    },
    # ------------------------------------------------------------------
    # DYING_GASP — انقطاع كهرباء ONT مع إشعار dying gasp
    # كلمات مفتاحية فريدة لا تتداخل مع POWER_FAILURE (OLT-side)
    # "dgi" هو اختصار dying gasp indication
    # ------------------------------------------------------------------
    {
        "code": "DYING_GASP",
        "patterns": [
            r"\bdyinggasp\b",
            r"\bdying[-_]?gasp\b",
            r"\bhwgpondyinggasp\b",
            r"\bdgi\b",
            r"\bpowerfailureont\b",       # "power failure ont" — خاص بـ ONT
        ],
    },
    # ------------------------------------------------------------------
    # POWER_FAILURE — انقطاع طاقة جانب OLT (PSU / AC / DC)
    # hwPowerFail هنا OLT-side — حدّ الكلمة يفصله عن dyinggasp
    # ------------------------------------------------------------------
    {
        "code": "POWER_FAILURE",
        "patterns": [
            r"\bhwpowerfail\b",
            r"\bpowerfailure\b",
            r"\bpsu\s*(?:alarm|event|fail)\b",
            r"\bac\s+fail\b",
            r"\bdc\s+fail\b",
            r"\bpower\s+supply\b",
        ],
    },
    # ------------------------------------------------------------------
    # PON_DOWN — منفذ PON ساقط
    # ------------------------------------------------------------------
    {
        "code": "PON_DOWN",
        "patterns": [
            r"\bpondown\b",
            r"\bpon[-_]?down\b",
            r"\bponlinkdown\b",
            r"\bpon\s+link\s+down\b",
            r"\bgponportdown\b",
            r"\bhwgponportdown\b",
        ],
    },
    # ------------------------------------------------------------------
    # BOARD_FAILURE — عطل في كرت
    # ------------------------------------------------------------------
    {
        "code": "BOARD_FAILURE",
        "patterns": [
            r"\bboardfail\b",
            r"\bboard[-_]?fail\b",
            r"\bslotfail\b",
            r"\bhwboardfail\b",
            r"\bhwslotfail\b",
            r"\bboard\s+abnormal\b",
            r"\bslot\s+failure\b",
        ],
    },
    # ------------------------------------------------------------------
    # HIGH_TEMPERATURE — حرارة مرتفعة
    # أضفنا: hwHighTemperatureAlarm (الصيغة الرسمية في Huawei XPON MIB)
    #        high\s*temperature (مع مسافة اختيارية: "hightemperature"/"high temperature")
    #        overtemperature (صيغة مدمجة في بعض traps)
    # هذه الأنماط لا تتداخل مع أكواد أخرى لأنها محاطة بحدود الكلمة \b.
    # ------------------------------------------------------------------
    {
        "code": "HIGH_TEMPERATURE",
        "patterns": [
            r"\bhightemp\b",
            r"\bhigh\s+temperature\b",
            r"\bhigh\s*temperature\b",      # "hightemperature" بلا مسافة
            r"\btemperature\s+alarm\b",
            r"\bhwtemperaturealarm\b",
            r"\bhwhightemperaturealarm\b",  # الصيغة الرسمية hwHighTemperatureAlarm
            r"\bovertemp\b",
            r"\bovertemperature\b",         # صيغة مدمجة بدون "hw"
            r"\bhwovertemperature\b",
        ],
    },
    # ------------------------------------------------------------------
    # UPLINK_DOWN — انقطاع الرابط الصاعد
    # "linkdown" مع حد كلمة لتجنّب تداخل مع "ponlinkdown"
    # ------------------------------------------------------------------
    {
        "code": "UPLINK_DOWN",
        "patterns": [
            r"\buplinkdown\b",
            r"\buplink[-_]?down\b",
            r"\buplink[-_]?fail\b",
            r"\bhwuplinkfail\b",
            r"\blinkdown\b",
            r"\blink\s+down\b",
        ],
    },
    # ------------------------------------------------------------------
    # OPTICAL_POWER_ABNORMAL — قدرة ضوئية غير طبيعية
    # ------------------------------------------------------------------
    {
        "code": "OPTICAL_POWER_ABNORMAL",
        "patterns": [
            r"\bopticalpowerabnormal\b",
            r"\bhwopticalpower\b",
            r"\boptical\s+power\b",
            r"\brx\s+power\s+alarm\b",
            r"\bddm\s+alarm\b",
            r"\breceivepower\b",
        ],
    },
    # ------------------------------------------------------------------
    # ROGUE_ONT — ONT مارق
    # ------------------------------------------------------------------
    {
        "code": "ROGUE_ONT",
        "patterns": [
            r"\brogueont\b",
            r"\brogue[-_]?ont\b",
            r"\bhwrogueont\b",
            r"\brogue\s+detection\b",
            r"\bspurious\s+signal\b",
            r"\brogue\b",
        ],
    },
    # ------------------------------------------------------------------
    # ONT_AUTH_FAILURE — فشل مصادقة ONT
    # ------------------------------------------------------------------
    {
        "code": "ONT_AUTH_FAILURE",
        "patterns": [
            r"\bautherror\b",
            r"\bhwontauthfail\b",
            r"\bauth[-_]?fail\b",
            r"\bauth[-_]?error\b",
            r"\bsn\s+mismatch\b",
            r"\bpassword\s+error\b",
            r"\bregistration\s+fail\b",
        ],
    },
    # ------------------------------------------------------------------
    # ONT_CONFIG_FAILURE — فشل تهيئة ONT
    # ------------------------------------------------------------------
    {
        "code": "ONT_CONFIG_FAILURE",
        "patterns": [
            r"\bconfigfail\b",
            r"\bhwontconfigfail\b",
            r"\bconfig[-_]?fail\b",
            r"\bprovisioning\s+fail\b",
            r"\bomci[-_]?error\b",
            r"\bomci\s+error\b",
            r"\bservice\s+port\s+fail\b",
        ],
    },
    # ------------------------------------------------------------------
    # ONT_OFFLINE — ONT منفصل (يُفحص أخيراً — أقل تحديداً)
    # ------------------------------------------------------------------
    {
        "code": "ONT_OFFLINE",
        "patterns": [
            r"\bontoffline\b",
            r"\bont[-_]?offline\b",
            r"\bontdown\b",
            r"\bont\s+offline\b",
            r"\bhwgponontdeact\b",
        ],
    },
]

# -------------------------------------------------------------------------
# ترجمة القواعد إلى regex مجمَّعة (compiled) للأداء
# -------------------------------------------------------------------------
_COMPILED_RULES: List[Dict] = [
    {
        "code": rule["code"],
        "regex": re.compile(
            "|".join(rule["patterns"]),
            re.IGNORECASE,
        ),
    }
    for rule in _CLASSIFICATION_RULES
]

# -------------------------------------------------------------------------
# خريطة أكواد الإنذارات — metadata فقط (لا تؤثر في التصنيف)
# -------------------------------------------------------------------------
ALARM_CODES: Dict[str, Dict] = {
    "ONT_LOS": {
        "severity": "critical",
        "source_type": "ONT",
        "title": "فقدان إشارة ONT (LOS)",
        "keywords": ["ontlos", "ont-los", "gponontlos", "los", "signal lost",
                     "hwgponontlos", "2011.6.128.1.1.3.1"],
    },
    "ONT_OFFLINE": {
        "severity": "major",
        "source_type": "ONT",
        "title": "ONT منفصل",
        "keywords": ["ontoffline", "ont-offline", "ontdown", "ont offline",
                     "hwgponontdeact"],
    },
    "DYING_GASP": {
        "severity": "critical",
        "source_type": "ONT",
        "title": "Dying Gasp — انقطاع كهرباء ONT",
        "keywords": ["dyinggasp", "dying-gasp", "dying gasp",
                     "hwgpondyinggasp", "dgi", "power failure ont"],
    },
    "PON_DOWN": {
        "severity": "critical",
        "source_type": "PON",
        "title": "منفذ PON ساقط",
        "keywords": ["pondown", "pon-down", "pon link down", "gponportdown",
                     "hwgponportdown", "ponlinkdown"],
    },
    "BOARD_FAILURE": {
        "severity": "critical",
        "source_type": "BOARD",
        "title": "عطل في كرت",
        "keywords": ["boardfail", "board fail", "slotfail", "hwboardfail",
                     "hwslotfail", "board abnormal", "slot failure"],
    },
    "HIGH_TEMPERATURE": {
        "severity": "warning",
        "source_type": "BOARD",
        "title": "حرارة مرتفعة",
        "keywords": ["hightemp", "high temperature", "temperature alarm",
                     "hwtemperaturealarm", "overtemp", "hwovertemperature"],
    },
    "POWER_FAILURE": {
        "severity": "critical",
        "source_type": "OLT",
        "title": "انقطاع مصدر الطاقة",
        "keywords": ["hwpowerfail", "powerfailure", "power failure", "ac fail",
                     "dc fail", "psu alarm", "power supply"],
    },
    "UPLINK_DOWN": {
        "severity": "critical",
        "source_type": "OLT",
        "title": "انقطاع الرابط الصاعد",
        "keywords": ["uplinkdown", "uplink down", "uplink fail",
                     "hwuplinkfail", "linkdown", "link down"],
    },
    "OPTICAL_POWER_ABNORMAL": {
        "severity": "major",
        "source_type": "ONT",
        "title": "قدرة ضوئية غير طبيعية",
        "keywords": ["opticalpowerabnormal", "optical power", "rx power alarm",
                     "hwopticalpower", "ddm alarm", "receivepower"],
    },
    "ROGUE_ONT": {
        "severity": "major",
        "source_type": "ONT",
        "title": "ONT مارق (Rogue)",
        "keywords": ["rogue", "rogueont", "rogue ont", "hwrogueont",
                     "rogue detection", "spurious signal"],
    },
    "ONT_AUTH_FAILURE": {
        "severity": "major",
        "source_type": "ONT",
        "title": "فشل مصادقة ONT",
        "keywords": ["autherror", "auth fail", "sn mismatch", "password error",
                     "hwontauthfail", "registration fail", "auth-error"],
    },
    "ONT_CONFIG_FAILURE": {
        "severity": "major",
        "source_type": "ONT",
        "title": "فشل تهيئة ONT",
        "keywords": ["configfail", "config fail", "provisioning fail",
                     "hwontconfigfail", "omci error", "omci-error",
                     "service port fail"],
    },
}


def _classify_varbinds(text: str) -> str:
    """
    يُعيد كود الإنذار الأنسب من نص varbinds.

    يستخدم قواعد regex مرتّبة بأولوية صريحة مع حدود الكلمة (\b) لضمان
    عدم التداخل بين الأكواد. مثال: "hwPowerFail" يُطابق POWER_FAILURE فقط
    لأن النمط r"\bhwpowerfail\b" كلمة مستقلة، بينما لا يُطابق DYING_GASP
    الذي لا يملك "hwpowerfail" في أنماطه.
    """
    for rule in _COMPILED_RULES:
        if rule["regex"].search(text):
            return rule["code"]
    return "ONT_OFFLINE"   # افتراضي


# -------------------------------------------------------------------------
# استخراج frame/slot/pon/ont_id من OID index أو نص F/S/P/O
# -------------------------------------------------------------------------

# نمط OID index: x.frame.slot.port.ont_id (HUAWEI-XPON-MIB convention)
_ONT_IDX_RE = re.compile(
    r"\.(?P<frame>\d+)\.(?P<slot>\d+)\.(?P<pon>\d+)\.(?P<ont_id>\d+)"
)
# نمط من النص: "0/5/1/2" أو "F/S/P/O" (4 أجزاء = موقع ONT الكامل)
_FSP_TEXT_RE = re.compile(
    r"(?P<frame>\d+)/(?P<slot>\d+)/(?P<pon>\d+)/(?P<ont_id>\d+)"
)
# نمط ثلاثي: "0/5/1" = frame/slot/pon بلا ont_id (يُستخدم لإنذارات PON/BOARD)
_FSP_3_RE = re.compile(
    r"(?P<frame>\d+)/(?P<slot>\d+)/(?P<pon>\d+)(?!/)"   # تأكّد ألا يتبعها "/"
)


# الـ source_types التي تعتمد على ont_id
_ONT_LEVEL_TYPES = {"ONT"}
# الـ source_types التي تعتمد على frame/slot فقط (بلا pon/ont_id)
_BOARD_LEVEL_TYPES = {"BOARD"}
# الـ source_types التي تعتمد على frame/slot/pon (بلا ont_id)
_PON_LEVEL_TYPES = {"PON"}


def _extract_location(varbinds_text: str, source_type: str = "ONT") -> Dict[str, Optional[int]]:
    """
    يستخرج frame/slot/pon/ont_id من نص varbinds حسب مستوى الإنذار.

    قواعد:
    - إنذار ONT (source_type="ONT"): يملأ frame/slot/pon/ont_id من نمط F/S/P/O أو OID index.
    - إنذار PON (source_type="PON"): يملأ frame/slot/pon ولا يلحق ont_id (قد يكون 4 أرقام
      في OID لكنها تشير للمنفذ لا للـ ONT).
    - إنذار BOARD (source_type="BOARD"): يملأ frame/slot فقط.
    - إنذارات OLT/أخرى: لا تستخرج موقعاً محدداً (كلها None).

    ملاحظة: أنماط OID index ذات 4 أرقام قد تظهر في إنذارات غير-ONT؛ نتجاهل
    الرقم الرابع (ont_id) إلا عندما يكون source_type="ONT" صراحةً.
    """
    loc: Dict[str, Optional[int]] = {
        "frame": None, "slot": None, "pon": None, "ont_id": None
    }

    if source_type in _ONT_LEVEL_TYPES:
        # --- مستوى ONT: نريد F/S/P/O الكامل ---
        # أولاً: نمط نصي صريح "F/S/P/O"
        m = _FSP_TEXT_RE.search(varbinds_text)
        if m:
            loc["frame"] = int(m.group("frame"))
            loc["slot"] = int(m.group("slot"))
            loc["pon"] = int(m.group("pon"))
            loc["ont_id"] = int(m.group("ont_id"))
            return loc
        # ثانياً: من OID index (\.frame.slot.port.ont_id)
        m = _ONT_IDX_RE.search(varbinds_text)
        if m:
            loc["frame"] = int(m.group("frame"))
            loc["slot"] = int(m.group("slot"))
            loc["pon"] = int(m.group("pon"))
            loc["ont_id"] = int(m.group("ont_id"))
        return loc

    if source_type in _PON_LEVEL_TYPES:
        # --- مستوى PON: F/S/P بلا ont_id ---
        # نبحث عن نمط نصي ثلاثي أولاً، وإلا نمط رباعي ونتجاهل الرقع الرابع
        m = _FSP_TEXT_RE.search(varbinds_text)
        if m:
            loc["frame"] = int(m.group("frame"))
            loc["slot"] = int(m.group("slot"))
            loc["pon"] = int(m.group("pon"))
            # ont_id يبقى None عمداً
            return loc
        m = _FSP_3_RE.search(varbinds_text)
        if m:
            loc["frame"] = int(m.group("frame"))
            loc["slot"] = int(m.group("slot"))
            loc["pon"] = int(m.group("pon"))
        return loc

    if source_type in _BOARD_LEVEL_TYPES:
        # --- مستوى BOARD: frame/slot فقط ---
        # نحاول استخراج أول رقمين من نمط "F/S" أو "F/S/..." ونتجاهل الباقي
        m = _FSP_TEXT_RE.search(varbinds_text) or _FSP_3_RE.search(varbinds_text)
        if m:
            loc["frame"] = int(m.group("frame"))
            loc["slot"] = int(m.group("slot"))
            # pon و ont_id يبقيان None عمداً
        return loc

    # --- مستوى OLT أو غير محدد: لا موقع تفصيلي ---
    return loc


# -------------------------------------------------------------------------
# الدالة الرئيسية
# -------------------------------------------------------------------------

def normalize_trap(
    varbinds: List[Tuple[str, str]],
    olt_id: int,
    olt_name: str,
    source_ip: Optional[str] = None,
) -> Dict:
    """
    يُحوّل varbinds خام إلى dict إنذار موحّد.

    المعاملات:
        varbinds   : قائمة (oid_str, value_str) من حدث SNMP trap
        olt_id     : معرّف الجهاز في قاعدة البيانات
        olt_name   : اسم الجهاز (للعرض)
        source_ip  : عنوان IP المُرسِل (اختياري)

    يُرجع dict يحوي:
        alarm_uid, source_type, olt_id, olt_name,
        frame, slot, pon, ont_id,
        severity, code, title, message, occurred_at
    """
    # دمج كل النص للتصنيف
    full_text = "; ".join(f"{k}={v}" for k, v in varbinds)

    # تصنيف الكود
    code = _classify_varbinds(full_text)
    meta = ALARM_CODES.get(code, ALARM_CODES["ONT_OFFLINE"])

    # استخراج الموقع مع مراعاة مستوى الإنذار:
    # - إنذارات ONT: تملأ frame/slot/pon/ont_id
    # - إنذارات PON: تملأ frame/slot/pon فقط (ont_id = None)
    # - إنذارات BOARD/HIGH_TEMPERATURE: تملأ frame/slot فقط
    # - إنذارات OLT-level (POWER_FAILURE/UPLINK_DOWN/...): كلها None
    loc = _extract_location(full_text, source_type=meta["source_type"])

    # بناء الرسالة
    source_parts = [olt_name]
    if source_ip:
        source_parts.append(f"({source_ip})")
    if loc["frame"] is not None:
        fsp = f"{loc['frame']}/{loc['slot']}/{loc['pon']}"
        source_parts.append(f"PON {fsp}")
    if loc["ont_id"] is not None:
        source_parts.append(f"ONT {loc['ont_id']}")
    source_label = " ".join(source_parts)

    message = f"[{meta['title']}] {full_text[:360]}" if len(full_text) > 5 else meta["title"]

    return {
        "alarm_uid": _next_uid(),
        "source_type": meta["source_type"],
        "olt_id": olt_id,
        "olt_name": olt_name,
        "frame": loc["frame"],
        "slot": loc["slot"],
        "pon": loc["pon"],
        "ont_id": loc["ont_id"],
        "severity": meta["severity"],
        "code": code,
        "title": meta["title"],
        "message": message,
        "source": source_label,
        "occurred_at": utcnow(),
    }
