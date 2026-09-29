"""
اختبارات وحدة — قرّاء SNMP (collectors) وسحّاب (poller) في وضع المحاكاة.

يتحقّق من:
1. collect_health يُرجع المفاتيح الإلزامية بقيَم رقمية.
2. collect_onts_basic يُرجع 5 عناصر بينها ONT معطوب (offline).
3. collect_ont_detail(dev, "0/5/1", 2) يُرجع rx_power ≈ -30.5 و last_down_cause غير فارغ.
4. poll_health يكتب صف DeviceHealth واحداً (upsert لا يكرّر عند الاستدعاء مرتين).
5. refresh_ont_detail يُحدِّث ONTRecord.
6. snmp_manager.test(dev) يُرجع ok=True في المحاكاة.
"""
import pytest
from types import SimpleNamespace

from sqlmodel import Session, select

from app.core.snmp_collector import collect_health, collect_onts_basic, collect_ont_detail
from app.core.snmp_client import snmp_manager
from app.services.snmp_poller import poll_health, refresh_ont_detail
from app.models import OLTDevice, DeviceHealth, ONTRecord
from app.database import engine


# ===========================================================================
# جهاز وهمي — يستخدم المحاكاة (use_mock_olt=True مضبوط في conftest)
# ===========================================================================

@pytest.fixture
def mock_device(tmp_path):
    """ينشئ جهاز OLT وهمي في قاعدة الاختبار ويُرجعه، ثم يمسحه بعد الاختبار."""
    with Session(engine) as db:
        dev = OLTDevice(
            name="SNMP-Test-OLT",
            host="127.0.0.1",
            model="MA5800",
            snmp_enabled=True,
        )
        db.add(dev)
        db.commit()
        db.refresh(dev)
        dev_id = dev.id

    yield dev

    # تنظيف — حذف الصفوف المرتبطة بهذا الجهاز
    with Session(engine) as db:
        from app.models import DeviceHealth, ONTRecord, Metric
        for Model in (DeviceHealth, ONTRecord, Metric):
            rows = db.exec(
                select(Model).where(Model.olt_id == dev_id)
            ).all()
            for r in rows:
                db.delete(r)
        device = db.get(OLTDevice, dev_id)
        if device:
            db.delete(device)
        db.commit()

    # حذف الجلسة المخزَّنة في SNMPManager
    snmp_manager.drop(dev_id)


# ===========================================================================
# 1. collect_health
# ===========================================================================

class TestCollectHealth:
    _REQUIRED_KEYS = {"cpu", "memory", "temperature", "uptime",
                      "power_status", "fan_status", "sw_version", "active_alarms"}

    def test_returns_required_keys(self, mock_device):
        result = collect_health(mock_device)
        missing = self._REQUIRED_KEYS - set(result.keys())
        assert not missing, f"مفاتيح مفقودة في collect_health: {missing}"

    def test_cpu_is_numeric(self, mock_device):
        result = collect_health(mock_device)
        assert isinstance(result["cpu"], (int, float)), (
            f"cpu يجب أن يكون رقماً، حصلت {type(result['cpu'])}"
        )
        assert 0 <= result["cpu"] <= 100

    def test_memory_is_numeric(self, mock_device):
        result = collect_health(mock_device)
        assert isinstance(result["memory"], (int, float))
        assert 0 <= result["memory"] <= 100

    def test_sw_version_nonempty(self, mock_device):
        result = collect_health(mock_device)
        assert result["sw_version"], "sw_version يجب ألّا يكون فارغاً في المحاكاة"

    def test_uptime_positive(self, mock_device):
        result = collect_health(mock_device)
        if result["uptime"] is not None:
            assert result["uptime"] > 0

    def test_temperature_reasonable(self, mock_device):
        result = collect_health(mock_device)
        if result["temperature"] is not None:
            assert 0 < result["temperature"] < 100, (
                f"درجة الحرارة خارج النطاق المعقول: {result['temperature']}"
            )


# ===========================================================================
# 2. collect_onts_basic
# ===========================================================================

class TestCollectOntsBasic:

    def test_returns_five_onts(self, mock_device):
        results = collect_onts_basic(mock_device)
        assert len(results) == 5, f"المتوقع 5 ONTs، حصلت {len(results)}"

    def test_has_offline_ont(self, mock_device):
        results = collect_onts_basic(mock_device)
        offline = [r for r in results if r["run_state"] == "offline"]
        assert len(offline) >= 1, "يجب أن يكون هناك ONT واحد على الأقل offline"

    def test_offline_ont_is_0_5_1_2(self, mock_device):
        results = collect_onts_basic(mock_device)
        broken = next(
            (r for r in results if r["fsp"] == "0/5/1" and r["ont_id"] == 2),
            None
        )
        assert broken is not None, "ONT 0/5/1/2 غير موجود في النتائج"
        assert broken["run_state"] == "offline", (
            f"ONT 0/5/1/2 يجب أن يكون offline، حصلت {broken['run_state']}"
        )

    def test_online_onts_count(self, mock_device):
        results = collect_onts_basic(mock_device)
        online = [r for r in results if r["run_state"] == "online"]
        assert len(online) == 4

    def test_ont_record_structure(self, mock_device):
        results = collect_onts_basic(mock_device)
        for ont in results:
            for key in ("fsp", "ont_id", "sn", "run_state", "rx_power"):
                assert key in ont, f"المفتاح '{key}' مفقود في سجل ONT"

    def test_offline_ont_rx_power_low(self, mock_device):
        results = collect_onts_basic(mock_device)
        broken = next(
            (r for r in results if r["fsp"] == "0/5/1" and r["ont_id"] == 2),
            None
        )
        assert broken is not None
        rx = broken.get("rx_power")
        if rx is not None:
            # ONT المعطوب عنده rx_power_raw = -3050 × 0.01 = -30.5
            assert rx < -25, f"rx_power للـ ONT المعطوب يجب أن يكون أقل من -25 dBm، حصلت {rx}"


# ===========================================================================
# 3. collect_ont_detail
# ===========================================================================

class TestCollectOntDetail:

    def test_broken_ont_rx_power_approx(self, mock_device):
        """ONT 0/5/1/2 معطوب: rx_power ≈ -30.5 dBm."""
        result = collect_ont_detail(mock_device, "0/5/1", 2)
        rx = result.get("rx_power")
        assert rx is not None, "rx_power يجب ألّا يكون None لـ ONT 0/5/1/2"
        assert abs(rx - (-30.5)) < 1.0, (
            f"rx_power لـ ONT 0/5/1/2 يجب أن يكون ≈ -30.5، حصلت {rx}"
        )

    def test_broken_ont_last_down_cause_nonempty(self, mock_device):
        """last_down_cause يجب ألّا يكون فارغاً للـ ONT المعطوب."""
        result = collect_ont_detail(mock_device, "0/5/1", 2)
        cause = result.get("last_down_cause")
        assert cause, f"last_down_cause يجب ألّا يكون فارغاً، حصلت {cause!r}"

    def test_detail_structure(self, mock_device):
        """التحقّق من وجود المفاتيح الأساسية."""
        result = collect_ont_detail(mock_device, "0/5/1", 2)
        for key in ("fsp", "ont_id", "rx_power", "last_down_cause"):
            assert key in result, f"المفتاح '{key}' مفقود في collect_ont_detail"

    def test_online_ont_detail(self, mock_device):
        """ONT سليم (0/5/0/1) له rx_power معقول."""
        result = collect_ont_detail(mock_device, "0/5/0", 1)
        rx = result.get("rx_power")
        if rx is not None:
            assert -30 < rx < 0, f"rx_power للـ ONT السليم خارج النطاق: {rx}"

    def test_fsp_and_ont_id_in_result(self, mock_device):
        result = collect_ont_detail(mock_device, "0/5/1", 2)
        assert result["fsp"] == "0/5/1"
        assert result["ont_id"] == 2


# ===========================================================================
# 4. poll_health — upsert لا يكرّر عند الاستدعاء مرتين
# ===========================================================================

class TestPollHealth:

    def test_poll_health_writes_device_health(self, mock_device):
        poll_health(mock_device)
        with Session(engine) as db:
            rec = db.exec(
                select(DeviceHealth).where(DeviceHealth.olt_id == mock_device.id)
            ).first()
        assert rec is not None, "poll_health يجب أن يكتب صف DeviceHealth"

    def test_poll_health_upsert_no_duplicate(self, mock_device):
        """استدعاء مرتين لا ينتج إلا صف واحد."""
        poll_health(mock_device)
        poll_health(mock_device)
        with Session(engine) as db:
            rows = db.exec(
                select(DeviceHealth).where(DeviceHealth.olt_id == mock_device.id)
            ).all()
        assert len(rows) == 1, (
            f"upsert يجب أن يُنتج صفاً واحداً فقط، حصلت {len(rows)}"
        )

    def test_poll_health_returns_dict(self, mock_device):
        data = poll_health(mock_device)
        assert isinstance(data, dict)
        assert "cpu" in data

    def test_poll_health_values_in_db(self, mock_device):
        data = poll_health(mock_device)
        with Session(engine) as db:
            rec = db.exec(
                select(DeviceHealth).where(DeviceHealth.olt_id == mock_device.id)
            ).first()
        if data.get("cpu") is not None:
            assert rec.cpu == data["cpu"]


# ===========================================================================
# 5. refresh_ont_detail — يُحدِّث ONTRecord
# ===========================================================================

class TestRefreshOntDetail:

    def test_refresh_creates_ont_record(self, mock_device):
        refresh_ont_detail(mock_device, "0/5/1", 2)
        with Session(engine) as db:
            rec = db.exec(
                select(ONTRecord).where(
                    ONTRecord.olt_id == mock_device.id,
                    ONTRecord.fsp == "0/5/1",
                    ONTRecord.ont_id == 2,
                )
            ).first()
        assert rec is not None, "refresh_ont_detail يجب أن يُنشئ ONTRecord"

    def test_refresh_updates_rx_power(self, mock_device):
        result = refresh_ont_detail(mock_device, "0/5/1", 2)
        assert result.get("rx_power") is not None
        # القيمة المعادة تتوافق مع ما في القاعدة
        with Session(engine) as db:
            rec = db.exec(
                select(ONTRecord).where(
                    ONTRecord.olt_id == mock_device.id,
                    ONTRecord.fsp == "0/5/1",
                    ONTRecord.ont_id == 2,
                )
            ).first()
        assert rec.rx_power is not None
        assert abs(rec.rx_power - (-30.5)) < 1.0

    def test_refresh_returns_dict_with_keys(self, mock_device):
        result = refresh_ont_detail(mock_device, "0/5/1", 2)
        for key in ("fsp", "ont_id", "rx_power", "last_down_cause", "updated_at"):
            assert key in result, f"المفتاح '{key}' مفقود في نتيجة refresh_ont_detail"

    def test_refresh_idempotent(self, mock_device):
        """استدعاء مرتين لا ينتج إلا سجل ONTRecord واحد."""
        refresh_ont_detail(mock_device, "0/5/0", 1)
        refresh_ont_detail(mock_device, "0/5/0", 1)
        with Session(engine) as db:
            rows = db.exec(
                select(ONTRecord).where(
                    ONTRecord.olt_id == mock_device.id,
                    ONTRecord.fsp == "0/5/0",
                    ONTRecord.ont_id == 1,
                )
            ).all()
        assert len(rows) == 1


# ===========================================================================
# 6. snmp_manager.test — يُرجع ok=True في المحاكاة
# ===========================================================================

class TestSnmpManagerTest:

    def test_returns_ok_true_in_mock(self, mock_device):
        result = snmp_manager.test(mock_device)
        assert result["ok"] is True, (
            f"snmp_manager.test يجب أن يُرجع ok=True في المحاكاة، حصلت: {result}"
        )

    def test_returns_sysdescr_nonempty(self, mock_device):
        result = snmp_manager.test(mock_device)
        assert result.get("sysDescr"), "sysDescr يجب ألّا يكون فارغاً"

    def test_returns_no_error(self, mock_device):
        result = snmp_manager.test(mock_device)
        assert result.get("error") is None, (
            f"error يجب أن يكون None في المحاكاة، حصلت: {result.get('error')}"
        )

    def test_returns_uptime_positive(self, mock_device):
        result = snmp_manager.test(mock_device)
        assert isinstance(result.get("uptime"), int)
        assert result["uptime"] > 0
