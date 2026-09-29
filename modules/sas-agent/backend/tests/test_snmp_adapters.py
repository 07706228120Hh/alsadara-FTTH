"""
اختبارات وحدة — محوّلات SNMP (Adapters).

يتحقّق من:
1. list_adapters() تُرجع ≥3 محوّلات (MA5800 / MA5680T / EA5800).
2. load_adapter() يختار الملف الصحيح لجهاز MA5800.
3. صحّة JSON لكل ملف في knowledge/adapters/.
4. كل محوّل يحوي حقول إلزامية (model, vendor, match, fields).
5. الحقول الأساسية (olt.cpu, ont.status, ont.optical_rx_dbm) موجودة في MA5800.
"""
import json
from pathlib import Path
from types import SimpleNamespace

import pytest


# نستورد بعد إعداد conftest (الذي يضبط env قبل أي import من app)
from app.core.snmp_collector import list_adapters, load_adapter

# مسار مجلد المحوّلات
_ADAPTERS_DIR = (
    Path(__file__).resolve().parent.parent / "app" / "knowledge" / "adapters"
)

# جهاز وهمي بسيط
_MA5800_DEV = SimpleNamespace(
    id=99, name="test-olt", host="127.0.0.1", model="MA5800",
    snmp_enabled=True, adapter_profile="",
)
_MA5680T_DEV = SimpleNamespace(
    id=98, name="test-olt-680", host="127.0.0.1", model="MA5680T",
    snmp_enabled=True, adapter_profile="",
)
_EA5800_DEV = SimpleNamespace(
    id=97, name="test-olt-ea", host="127.0.0.1", model="EA5800",
    snmp_enabled=True, adapter_profile="",
)


# ===========================================================================
# 1. قائمة المحوّلات
# ===========================================================================

def test_list_adapters_returns_at_least_three():
    adapters = list_adapters()
    assert len(adapters) >= 3, f"المتوقع ≥3 محوّلات، وجد {len(adapters)}"


def test_list_adapters_contains_expected_models():
    adapters = list_adapters()
    models = [a["model"].upper() for a in adapters]
    for expected in ("MA5800", "MA5680T", "EA5800"):
        assert any(expected in m for m in models), (
            f"لم يُعثر على محوّل {expected} في القائمة: {models}"
        )


def test_list_adapters_structure():
    """كل عنصر يحوي المفاتيح المطلوبة."""
    for adapter in list_adapters():
        for key in ("name", "model", "vendor", "file"):
            assert key in adapter, f"المفتاح '{key}' مفقود في المحوّل {adapter.get('name')}"


# ===========================================================================
# 2. اختيار المحوّل الصحيح
# ===========================================================================

def test_load_adapter_ma5800():
    adapter = load_adapter(_MA5800_DEV)
    assert adapter, "load_adapter أعاد dict فارغاً لجهاز MA5800"
    assert "MA5800" in adapter.get("model", "").upper()


def test_load_adapter_ma5680t():
    adapter = load_adapter(_MA5680T_DEV)
    assert adapter, "load_adapter أعاد dict فارغاً لجهاز MA5680T"
    assert "MA5680T" in adapter.get("model", "").upper() or adapter.get("vendor") == "Huawei"


def test_load_adapter_ea5800():
    adapter = load_adapter(_EA5800_DEV)
    assert adapter, "load_adapter أعاد dict فارغاً لجهاز EA5800"
    assert adapter.get("vendor") == "Huawei"


def test_load_adapter_explicit_profile():
    """adapter_profile صريح يُعيّن ملف بعينه."""
    dev = SimpleNamespace(
        id=96, name="explicit", host="127.0.0.1", model="MA5800",
        snmp_enabled=True, adapter_profile="huawei_ma5800.json",
    )
    adapter = load_adapter(dev)
    assert "MA5800" in adapter.get("model", "").upper()


# ===========================================================================
# 3. صحّة JSON لكل ملف
# ===========================================================================

@pytest.mark.parametrize("json_file", list(_ADAPTERS_DIR.glob("*.json")))
def test_adapter_json_valid(json_file):
    """كل ملف JSON قابل للتحليل بترميز UTF-8."""
    with open(str(json_file), encoding="utf-8") as fh:
        data = json.load(fh)
    assert isinstance(data, dict), f"{json_file.name} لا يُرجع dict"


# ===========================================================================
# 4. الحقول الإلزامية في كل محوّل
# ===========================================================================

@pytest.mark.parametrize("json_file", list(_ADAPTERS_DIR.glob("*.json")))
def test_adapter_mandatory_keys(json_file):
    """كل محوّل يحوي model, vendor, match, fields."""
    with open(str(json_file), encoding="utf-8") as fh:
        data = json.load(fh)
    for key in ("model", "vendor", "match", "fields"):
        assert key in data, f"المفتاح '{key}' مفقود في {json_file.name}"
    assert isinstance(data["fields"], dict)
    assert len(data["fields"]) > 0, f"قسم fields فارغ في {json_file.name}"


# ===========================================================================
# 5. الحقول الأساسية للـ MA5800
# ===========================================================================

_REQUIRED_FIELDS = [
    "olt.cpu", "olt.memory", "olt.uptime",
    "ont.status", "ont.optical_rx_dbm", "ont.serial",
]


def test_ma5800_adapter_has_required_fields():
    adapter = load_adapter(_MA5800_DEV)
    fields = adapter.get("fields", {})
    for field_name in _REQUIRED_FIELDS:
        assert field_name in fields, (
            f"الحقل '{field_name}' مفقود من محوّل MA5800"
        )


def test_ma5800_fields_have_oid():
    """كل حقل في محوّل MA5800 يحوي إما oid أو symbol."""
    adapter = load_adapter(_MA5800_DEV)
    fields = adapter.get("fields", {})
    for name, fd in fields.items():
        assert fd.get("oid") or fd.get("symbol"), (
            f"الحقل '{name}' لا يحوي oid ولا symbol في محوّل MA5800"
        )
