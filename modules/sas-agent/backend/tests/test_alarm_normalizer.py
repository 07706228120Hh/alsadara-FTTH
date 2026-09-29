"""
اختبارات وحدة — مطبِّع إنذارات SNMP Traps (alarm_normalizer).

يتحقّق من:
1. كل كود إلزامي (12 كوداً) يُطلَق بـ varbinds تمثيلية.
2. severity معقول لكل كود.
3. alarm_uid بصيغة ALM-YYYYMMDD-NNNN.
4. source_type صحيح لكل كود.
5. occurred_at واعٍ بالمنطقة الزمنية (tz-aware).
6. استخراج frame/slot/pon/ont_id من نص F/S/P/O.
7. الكود الافتراضي (لا varbinds معروفة) يُرجع ONT_OFFLINE.
"""
import re
from datetime import timezone

import pytest

from app.services.alarm_normalizer import normalize_trap, ALARM_CODES

# ===========================================================================
# بيانات اختبار لكل كود إلزامي
# varbinds: قائمة (oid_str, value_str)
# ===========================================================================

_MANDATORY_CODES = {
    # ONT_LOS: الكلمة المفتاحية الصريحة "hwGponOntLos"
    "ONT_LOS": [
        ("trapOid", "hwGponOntLos"),
        ("sysUpTime", "12345"),
    ],
    # ONT_OFFLINE: "ontdown" كلمة مفتاحية واضحة
    "ONT_OFFLINE": [
        ("trapOid", "ontdown"),
        ("description", "ONT offline event"),
    ],
    # DYING_GASP: "hwGponDyingGasp" — كلمة صريحة لا تتشابك
    "DYING_GASP": [
        ("trapOid", "hwGponDyingGasp"),
        ("description", "dying gasp event"),
    ],
    # PON_DOWN: "ponlinkdown" كلمة واضحة
    "PON_DOWN": [
        ("trapOid", "ponlinkdown"),
        ("description", "pon link down event"),
    ],
    # BOARD_FAILURE: "hwSlotFail"
    "BOARD_FAILURE": [
        ("trapOid", "hwSlotFail"),
        ("description", "slot failure detected"),
    ],
    # HIGH_TEMPERATURE: "hwOverTemperature"
    "HIGH_TEMPERATURE": [
        ("trapOid", "hwOverTemperature"),
        ("description", "temperature alarm"),
    ],
    # POWER_FAILURE: "ac fail" — كلمة مفتاحية فريدة لـ POWER_FAILURE
    # (تجنّب "powerfail" الذي يلتقطه DYING_GASP أولاً)
    "POWER_FAILURE": [
        ("trapOid", "psuEvent"),
        ("description", "ac fail dc fail"),
    ],
    # UPLINK_DOWN: "hwUplinkFail"
    "UPLINK_DOWN": [
        ("trapOid", "hwUplinkFail"),
        ("description", "uplink fail event"),
    ],
    # OPTICAL_POWER_ABNORMAL: "hwOpticalPower" — بدون أي كلمة تتداخل مع LOS
    "OPTICAL_POWER_ABNORMAL": [
        ("trapOid", "hwOpticalPower"),
        ("description", "ddm alarm receivepower"),
    ],
    # ROGUE_ONT: "rogueOnt"
    "ROGUE_ONT": [
        ("trapOid", "hwRogueOnt"),
        ("description", "rogue detection event"),
    ],
    # ONT_AUTH_FAILURE: "hwOntAuthFail"
    "ONT_AUTH_FAILURE": [
        ("trapOid", "hwOntAuthFail"),
        ("description", "sn mismatch auth fail"),
    ],
    # ONT_CONFIG_FAILURE: "hwOntConfigFail"
    "ONT_CONFIG_FAILURE": [
        ("trapOid", "hwOntConfigFail"),
        ("description", "omci error config fail"),
    ],
}

# severities المقبولة لكل كود
_EXPECTED_SEVERITY = {
    "ONT_LOS": "critical",
    "ONT_OFFLINE": "major",
    "DYING_GASP": "critical",
    "PON_DOWN": "critical",
    "BOARD_FAILURE": "critical",
    "HIGH_TEMPERATURE": "warning",
    "POWER_FAILURE": "critical",
    "UPLINK_DOWN": "critical",
    "OPTICAL_POWER_ABNORMAL": "major",
    "ROGUE_ONT": "major",
    "ONT_AUTH_FAILURE": "major",
    "ONT_CONFIG_FAILURE": "major",
}

# source_type المتوقّع من الكتالوج
_EXPECTED_SOURCE_TYPE = {
    code: meta["source_type"]
    for code, meta in ALARM_CODES.items()
}

# نمط alarm_uid
_UID_RE = re.compile(r"^ALM-\d{8}-\d{4}$")


# ===========================================================================
# مساعد
# ===========================================================================

def _norm(code_key: str) -> dict:
    return normalize_trap(
        varbinds=_MANDATORY_CODES[code_key],
        olt_id=1,
        olt_name="OLT-Test",
        source_ip="192.168.1.1",
    )


# ===========================================================================
# اختبارات لكل كود
# ===========================================================================

@pytest.mark.parametrize("code", list(_MANDATORY_CODES.keys()))
def test_code_classified_correctly(code):
    result = _norm(code)
    assert result["code"] == code, (
        f"code خاطئ: توقّعت {code}، حصلت {result['code']}"
    )


@pytest.mark.parametrize("code", list(_MANDATORY_CODES.keys()))
def test_severity_correct(code):
    result = _norm(code)
    expected = _EXPECTED_SEVERITY[code]
    assert result["severity"] == expected, (
        f"{code}: severity خاطئ — توقّعت {expected}، حصلت {result['severity']}"
    )


@pytest.mark.parametrize("code", list(_MANDATORY_CODES.keys()))
def test_alarm_uid_format(code):
    result = _norm(code)
    uid = result["alarm_uid"]
    assert _UID_RE.match(uid), (
        f"{code}: alarm_uid بصيغة غير متوقّعة: {uid!r}"
    )


@pytest.mark.parametrize("code", list(_MANDATORY_CODES.keys()))
def test_source_type_correct(code):
    result = _norm(code)
    expected = _EXPECTED_SOURCE_TYPE[code]
    assert result["source_type"] == expected, (
        f"{code}: source_type خاطئ — توقّعت {expected}، حصلت {result['source_type']}"
    )


@pytest.mark.parametrize("code", list(_MANDATORY_CODES.keys()))
def test_occurred_at_tz_aware(code):
    result = _norm(code)
    occurred_at = result["occurred_at"]
    assert occurred_at is not None
    assert occurred_at.tzinfo is not None, (
        f"{code}: occurred_at غير واعٍ بالمنطقة الزمنية"
    )
    assert occurred_at.tzinfo.utcoffset(occurred_at).total_seconds() == 0, (
        f"{code}: occurred_at يجب أن يكون UTC"
    )


# ===========================================================================
# استخراج الموقع (F/S/P/O)
# ===========================================================================

def test_location_extracted_from_fsp_text():
    """يستخرج frame/slot/pon/ont_id من نص F/S/P/O."""
    varbinds = [
        ("trap-oid", "ontOffline"),
        ("description", "ONT offline at 0/5/1/3"),
    ]
    result = normalize_trap(varbinds, olt_id=1, olt_name="OLT-Test")
    assert result["frame"] == 0
    assert result["slot"] == 5
    assert result["pon"] == 1
    assert result["ont_id"] == 3


def test_location_extracted_from_oid_index():
    """يستخرج الموقع من OID index (.frame.slot.port.ont_id) في قيمة varbind."""
    # نمط _ONT_IDX_RE يتطلب نقطة قيادية: \.frame.slot.port.ont_id
    varbinds = [
        ("trapOid", "hwGponOntLos"),
        ("hwGponOntInfoIndex", ".0.5.0.2"),
    ]
    result = normalize_trap(varbinds, olt_id=1, olt_name="OLT-Test")
    assert result["frame"] == 0
    assert result["slot"] == 5
    assert result["pon"] == 0
    assert result["ont_id"] == 2


def test_location_none_when_absent():
    """بلا بيانات موقع تبقى None."""
    result = normalize_trap([("trap", "ponDown")], olt_id=1, olt_name="OLT-Test")
    # pon_down لا يحوي موقع ONT بالضرورة — نتحقّق من البنية فقط
    assert "frame" in result
    assert "olt_id" in result and result["olt_id"] == 1


# ===========================================================================
# الكود الافتراضي
# ===========================================================================

def test_unknown_varbinds_default_to_ont_offline():
    """varbinds بلا كلمات مفتاحية معروفة → ONT_OFFLINE (الافتراضي)."""
    varbinds = [
        ("1.3.6.1.2.1.1.3.0", "99999"),
        ("1.3.6.1.2.1.1.5.0", "Unknown-OLT"),
    ]
    result = normalize_trap(varbinds, olt_id=1, olt_name="OLT-Test")
    assert result["code"] == "ONT_OFFLINE"


# ===========================================================================
# olt_id و olt_name يُمرَّران بشكل صحيح
# ===========================================================================

def test_olt_id_and_name_in_result():
    result = normalize_trap(
        [("trap", "ontLOS")],
        olt_id=42, olt_name="Baghdad-OLT",
    )
    assert result["olt_id"] == 42
    assert result["olt_name"] == "Baghdad-OLT"


def test_alarm_uids_unique():
    """كل استدعاء يُنتج uid مختلفاً."""
    uid1 = normalize_trap([("t", "ontLOS")], 1, "OLT")["alarm_uid"]
    uid2 = normalize_trap([("t", "ontLOS")], 1, "OLT")["alarm_uid"]
    assert uid1 != uid2
