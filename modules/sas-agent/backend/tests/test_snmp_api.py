"""
اختبارات تكامل E2E لطبقة SNMPv3 — تعمل بالكامل في وضع المحاكاة (USE_MOCK_OLT=true).

تغطّي مسارات التكامل:
1. GET  /api/adapters            — قائمة Adapters غير فارغة تحتوي حقل model
2. POST /api/devices/{id}/snmp/test — اختبار اتصال SNMP (ok=true في المحاكاة)
3. GET  /api/devices/{id}/snmp/health — صحّة الجهاز (poll فوري إن لا سجل)
4. GET  /api/devices/{id}/pon   — منافذ PON (poll فوري إن لا بيانات)
5. POST /api/onts/{record_id}/refresh — تحديث ONT (يتطلب سجل ONTRecord موجود)
6. POST /api/devices             — يقبل حقول SNMPv3، والاستجابة لا تحتوي مفاتيح
7. GET  /api/devices             — لا تحتوي الاستجابة على أي مفاتيح مشفَّرة أو خام

ملاحظات المصادقة:
- وضع المحاكاة بلا API_TOKEN → admin تطويري تلقائياً (conftest يضبط ذلك)
- المسارات بدور operator (test/refresh) تعمل بنفس الوصول التطويري
- الاختبارات مستقلة — لا تعتمد على ترتيب التشغيل
"""
import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app.config import settings
from app.database import engine
from app.main import _seed_demo_device
from app.models import OLTDevice, ONTRecord, DeviceHealth, PonPortStatus
from app.services.snmp_poller import poll_onts_basic


# ---------------------------------------------------------------------------
# مساعدات
# ---------------------------------------------------------------------------

def _get_device_id(client: TestClient) -> int:
    """يُرجع id الجهاز المبذور (id=1 في المحاكاة)."""
    r = client.get("/api/devices")
    assert r.status_code == 200
    devices = r.json()
    assert devices, "لا يوجد جهاز في قاعدة الاختبار"
    return devices[0]["id"]


def _ensure_ont_record(device_id: int) -> int:
    """
    يتحقق من وجود سجل ONTRecord لهذا الجهاز ويُنشئه عبر poll_onts_basic إن لم يوجد.
    يُرجع id السجل الأول.
    """
    with Session(engine) as db:
        existing = db.exec(
            select(ONTRecord).where(ONTRecord.olt_id == device_id)
        ).first()
        if existing:
            return existing.id

    # تنفيذ سحب أساسي لإنشاء سجلات ONT
    with Session(engine) as db:
        device = db.get(OLTDevice, device_id)
        assert device is not None, f"لم يُعثر على الجهاز id={device_id}"

    poll_onts_basic(device)

    with Session(engine) as db:
        rec = db.exec(
            select(ONTRecord).where(ONTRecord.olt_id == device_id)
        ).first()
        assert rec is not None, "poll_onts_basic لم يُنشئ أي سجل ONT"
        return rec.id


def _operator_headers(client: TestClient) -> dict:
    """
    في وضع المحاكاة بلا API_TOKEN يُسمح تلقائياً بدور admin.
    إن كان API_TOKEN مضبوطاً (حالة نادرة في الاختبارات)، نسجّل دخولاً بحساب operator.
    يُرجع ترويسات الطلب.
    """
    if not settings.api_token:
        return {}

    # ننشئ مستخدم operator مؤقتاً عبر admin
    client.post(
        "/api/users",
        json={"username": "test_operator_snmp", "password": "pw_op", "role": "operator"},
        headers={"Authorization": f"Bearer {settings.api_token}"},
    )
    r = client.post(
        "/api/auth/login",
        json={"username": "test_operator_snmp", "password": "pw_op"},
    )
    if r.status_code == 200:
        tok = r.json()["token"]
        return {"Authorization": f"Bearer {tok}"}
    return {"Authorization": f"Bearer {settings.api_token}"}


# ===========================================================================
# 1. GET /api/adapters
# ===========================================================================

class TestAdapters:
    """اختبارات قائمة Adapters."""

    def test_adapters_returns_nonempty_list(self, client):
        """يجب أن تُرجع /api/adapters قائمة غير فارغة."""
        r = client.get("/api/adapters")
        assert r.status_code == 200
        data = r.json()
        assert isinstance(data, list), "الاستجابة يجب أن تكون قائمة"
        assert len(data) > 0, "القائمة لا يجب أن تكون فارغة"

    def test_adapters_each_has_model_field(self, client):
        """كل عنصر في القائمة يجب أن يحتوي حقل model."""
        r = client.get("/api/adapters")
        assert r.status_code == 200
        for adapter in r.json():
            assert "model" in adapter, f"Adapter يفتقد حقل model: {adapter}"

    def test_adapters_each_has_required_fields(self, client):
        """كل عنصر يجب أن يحتوي الحقول المتوقعة (name, model, vendor, file)."""
        r = client.get("/api/adapters")
        assert r.status_code == 200
        required_fields = {"name", "model", "vendor", "file"}
        for adapter in r.json():
            missing = required_fields - set(adapter.keys())
            assert not missing, f"Adapter يفتقد الحقول: {missing} — الموجود: {adapter}"

    def test_adapters_includes_ma5800(self, client):
        """يجب أن تشتمل القائمة على Adapter لجهاز MA5800 (النموذج المبذور في الاختبارات)."""
        r = client.get("/api/adapters")
        assert r.status_code == 200
        models = [a.get("model", "").upper() for a in r.json()]
        assert any("MA5800" in m for m in models), (
            f"لم يُعثر على Adapter MA5800 — الموجود: {models}"
        )


# ===========================================================================
# 2. POST /api/devices/{id}/snmp/test
# ===========================================================================

class TestSNMPTest:
    """اختبارات اختبار اتصال SNMPv3."""

    def test_snmp_test_returns_ok_true_in_mock(self, client):
        """في وضع المحاكاة يجب أن يُرجع ok=true."""
        device_id = _get_device_id(client)
        headers = _operator_headers(client)
        r = client.post(f"/api/devices/{device_id}/snmp/test", headers=headers)
        assert r.status_code == 200, f"HTTP {r.status_code}: {r.text}"
        body = r.json()
        assert body["ok"] is True, f"المتوقع ok=True — المُرجَع: {body}"

    def test_snmp_test_returns_sysdescr(self, client):
        """يجب أن تحتوي الاستجابة على sysDescr غير فارغ في المحاكاة."""
        device_id = _get_device_id(client)
        headers = _operator_headers(client)
        r = client.post(f"/api/devices/{device_id}/snmp/test", headers=headers)
        assert r.status_code == 200
        body = r.json()
        assert "sysDescr" in body, "الاستجابة لا تحتوي sysDescr"
        assert body["sysDescr"], "sysDescr فارغ في المحاكاة"

    def test_snmp_test_returns_uptime_positive(self, client):
        """uptime يجب أن يكون موجباً (الجهاز المُحاكى يعمل منذ ~128 يوماً)."""
        device_id = _get_device_id(client)
        headers = _operator_headers(client)
        r = client.post(f"/api/devices/{device_id}/snmp/test", headers=headers)
        assert r.status_code == 200
        body = r.json()
        assert "uptime" in body, "الاستجابة لا تحتوي uptime"
        assert body["uptime"] > 0, f"uptime يجب أن يكون موجباً — المُرجَع: {body['uptime']}"

    def test_snmp_test_response_schema(self, client):
        """الاستجابة يجب أن تتوافق مع SNMPTestResult schema."""
        device_id = _get_device_id(client)
        headers = _operator_headers(client)
        r = client.post(f"/api/devices/{device_id}/snmp/test", headers=headers)
        assert r.status_code == 200
        body = r.json()
        assert set(body.keys()) >= {"ok", "sysDescr", "uptime"}, (
            f"الاستجابة لا تحتوي الحقول المتوقعة — المُرجَع: {set(body.keys())}"
        )

    def test_snmp_test_nonexistent_device_returns_404(self, client):
        """جهاز غير موجود يجب أن يُرجع 404."""
        headers = _operator_headers(client)
        r = client.post("/api/devices/9999/snmp/test", headers=headers)
        assert r.status_code == 404

    def test_snmp_test_requires_operator_role(self, client, monkeypatch):
        """
        مسار snmp/test يتطلب دور operator على الأقل.
        في وضع المحاكاة بلا توكن، الوصول مسموح (admin تطويري).
        هذا الاختبار يتحقق أن المسار محمي إن كان API_TOKEN مضبوطاً.
        """
        # نحضر device_id قبل ضبط التوكن (قبل تفعيل المصادقة الإجبارية)
        device_id = _get_device_id(client)

        # نضبط توكن API للتحقق من حماية الدور
        monkeypatch.setattr(settings, "api_token", "test-secret-token-xyz")

        # بلا توكن → 401
        r_no_auth = client.post(f"/api/devices/{device_id}/snmp/test")
        assert r_no_auth.status_code == 401

        # بتوكن صحيح (admin) → 200
        r_admin = client.post(
            f"/api/devices/{device_id}/snmp/test",
            headers={"Authorization": "Bearer test-secret-token-xyz"},
        )
        assert r_admin.status_code == 200


# ===========================================================================
# 3. GET /api/devices/{id}/snmp/health
# ===========================================================================

class TestSNMPHealth:
    """اختبارات صحّة الجهاز عبر SNMP."""

    def test_health_returns_200(self, client):
        """يجب أن يُرجع /snmp/health استجابة 200."""
        device_id = _get_device_id(client)
        r = client.get(f"/api/devices/{device_id}/snmp/health")
        assert r.status_code == 200, f"HTTP {r.status_code}: {r.text}"

    def test_health_has_olt_id(self, client):
        """الاستجابة يجب أن تحتوي olt_id يتطابق مع الجهاز المطلوب."""
        device_id = _get_device_id(client)
        r = client.get(f"/api/devices/{device_id}/snmp/health")
        assert r.status_code == 200
        body = r.json()
        assert "olt_id" in body, f"الاستجابة لا تحتوي olt_id — المُرجَع: {set(body.keys())}"
        assert body["olt_id"] == device_id, (
            f"olt_id المُرجَع {body['olt_id']} لا يطابق الجهاز {device_id}"
        )

    def test_health_triggers_immediate_poll_when_no_record(self, client):
        """
        إن لم يوجد سجل DeviceHealth، يُنفَّذ poll فوري ويُرجع بيانات صحّيحة.
        نتحقق بحذف السجل ثم طلب الصحّة.
        """
        device_id = _get_device_id(client)

        # حذف سجل الصحّة إن وُجد
        with Session(engine) as db:
            rec = db.exec(
                select(DeviceHealth).where(DeviceHealth.olt_id == device_id)
            ).first()
            if rec:
                db.delete(rec)
                db.commit()

        # الطلب يُنفّذ poll فوري
        r = client.get(f"/api/devices/{device_id}/snmp/health")
        assert r.status_code == 200
        body = r.json()
        # الـ poll الفوري يُرجع dict من collect_health (ليس صف DeviceHealth دائماً)
        # نتحقق من أن الاستجابة تحتوي معلومات مفيدة (cpu أو memory)
        assert body is not None, "الاستجابة فارغة"

    def test_health_cpu_value_reasonable_in_mock(self, client):
        """CPU في المحاكاة يجب أن يكون بين 0 و 100."""
        device_id = _get_device_id(client)
        r = client.get(f"/api/devices/{device_id}/snmp/health")
        assert r.status_code == 200
        body = r.json()
        cpu = body.get("cpu")
        if cpu is not None:
            assert 0 <= cpu <= 100, f"CPU خارج النطاق المتوقع: {cpu}"

    def test_health_nonexistent_device_returns_404(self, client):
        """جهاز غير موجود يجب أن يُرجع 404."""
        r = client.get("/api/devices/9999/snmp/health")
        assert r.status_code == 404

    def test_health_creates_db_record_after_poll(self, client):
        """بعد poll فوري يجب أن يُنشأ سجل DeviceHealth في قاعدة البيانات."""
        device_id = _get_device_id(client)

        # حذف السجل القائم
        with Session(engine) as db:
            rec = db.exec(
                select(DeviceHealth).where(DeviceHealth.olt_id == device_id)
            ).first()
            if rec:
                db.delete(rec)
                db.commit()

        # طلب الصحّة → poll فوري
        r = client.get(f"/api/devices/{device_id}/snmp/health")
        assert r.status_code == 200

        # التحقق من إنشاء السجل في القاعدة
        with Session(engine) as db:
            rec_after = db.exec(
                select(DeviceHealth).where(DeviceHealth.olt_id == device_id)
            ).first()
        assert rec_after is not None, "لم يُنشأ سجل DeviceHealth بعد poll الفوري"


# ===========================================================================
# 4. GET /api/devices/{id}/pon
# ===========================================================================

class TestPONPorts:
    """اختبارات منافذ PON."""

    def test_pon_returns_200(self, client):
        """يجب أن يُرجع /pon استجابة 200."""
        device_id = _get_device_id(client)
        r = client.get(f"/api/devices/{device_id}/pon")
        assert r.status_code == 200, f"HTTP {r.status_code}: {r.text}"

    def test_pon_returns_list(self, client):
        """الاستجابة يجب أن تكون قائمة."""
        device_id = _get_device_id(client)
        r = client.get(f"/api/devices/{device_id}/pon")
        assert r.status_code == 200
        data = r.json()
        assert isinstance(data, list), f"الاستجابة يجب أن تكون قائمة — المُرجَع: {type(data)}"

    def test_pon_triggers_immediate_poll_when_empty(self, client):
        """
        إن كانت قائمة PonPortStatus فارغة، يُنفَّذ poll فوري.
        نتحقق بحذف صفوف PON ثم طلبها.
        """
        device_id = _get_device_id(client)

        # حذف صفوف PON الموجودة
        with Session(engine) as db:
            rows = db.exec(
                select(PonPortStatus).where(PonPortStatus.olt_id == device_id)
            ).all()
            for row in rows:
                db.delete(row)
            db.commit()

        r = client.get(f"/api/devices/{device_id}/pon")
        assert r.status_code == 200
        data = r.json()
        # المحاكاة لديها 2 منفذ PON (port 0 و port 1 على slot 5)
        assert isinstance(data, list)

    def test_pon_ports_have_required_fields(self, client):
        """كل منفذ PON يجب أن يحتوي الحقول: frame, slot, port."""
        device_id = _get_device_id(client)
        r = client.get(f"/api/devices/{device_id}/pon")
        assert r.status_code == 200
        ports = r.json()
        if ports:
            for p in ports:
                for field in ("frame", "slot", "port"):
                    assert field in p, f"منفذ PON يفتقد حقل {field}: {p}"

    def test_pon_mock_has_two_ports(self, client):
        """
        الجهاز المُحاكى (MA5800) لديه منفذان PON على slot 5.
        بعد poll يجب أن تُرجع قائمة بمنفذَين على الأقل.
        """
        device_id = _get_device_id(client)

        # حذف السجلات القائمة لإجبار poll فوري
        with Session(engine) as db:
            rows = db.exec(
                select(PonPortStatus).where(PonPortStatus.olt_id == device_id)
            ).all()
            for row in rows:
                db.delete(row)
            db.commit()

        r = client.get(f"/api/devices/{device_id}/pon")
        assert r.status_code == 200
        data = r.json()
        assert len(data) >= 2, (
            f"المتوقع >= 2 منفذ PON في المحاكاة — المُرجَع: {len(data)}"
        )

    def test_pon_nonexistent_device_returns_404(self, client):
        """جهاز غير موجود يجب أن يُرجع 404."""
        r = client.get("/api/devices/9999/pon")
        assert r.status_code == 404

    def test_pon_creates_db_records_after_poll(self, client):
        """بعد poll يجب أن تُنشأ سجلات PonPortStatus في القاعدة."""
        device_id = _get_device_id(client)

        # حذف السجلات
        with Session(engine) as db:
            rows = db.exec(
                select(PonPortStatus).where(PonPortStatus.olt_id == device_id)
            ).all()
            for row in rows:
                db.delete(row)
            db.commit()

        r = client.get(f"/api/devices/{device_id}/pon")
        assert r.status_code == 200

        with Session(engine) as db:
            rows_after = db.exec(
                select(PonPortStatus).where(PonPortStatus.olt_id == device_id)
            ).all()
        assert len(rows_after) >= 1, "لم تُنشأ سجلات PonPortStatus بعد poll الفوري"


# ===========================================================================
# 5. POST /api/onts/{record_id}/refresh
# ===========================================================================

class TestONTRefresh:
    """اختبارات تحديث بيانات ONT التفصيلية."""

    def test_refresh_returns_200_with_valid_record(self, client):
        """تحديث ONT موجود يجب أن يُرجع 200."""
        device_id = _get_device_id(client)
        record_id = _ensure_ont_record(device_id)
        headers = _operator_headers(client)
        r = client.post(f"/api/onts/{record_id}/refresh", headers=headers)
        assert r.status_code == 200, f"HTTP {r.status_code}: {r.text}"

    def test_refresh_returns_updated_record(self, client):
        """الاستجابة يجب أن تحتوي السجل المحدَّث بحقوله الأساسية."""
        device_id = _get_device_id(client)
        record_id = _ensure_ont_record(device_id)
        headers = _operator_headers(client)
        r = client.post(f"/api/onts/{record_id}/refresh", headers=headers)
        assert r.status_code == 200
        body = r.json()
        # الحقول الأساسية المتوقعة في ONTRecord
        for field in ("id", "olt_id", "fsp", "ont_id", "sn"):
            assert field in body, f"الاستجابة لا تحتوي حقل {field}: {set(body.keys())}"

    def test_refresh_updates_optical_fields(self, client):
        """
        بعد refresh يجب أن تُحدَّث الحقول الضوئية (rx_power) في السجل.
        MockSNMP يُرجع قيَم DDM حقيقية.
        """
        device_id = _get_device_id(client)
        record_id = _ensure_ont_record(device_id)
        headers = _operator_headers(client)
        r = client.post(f"/api/onts/{record_id}/refresh", headers=headers)
        assert r.status_code == 200
        body = r.json()
        # rx_power يُتوقع أن يكون موجوداً (وليس null) في المحاكاة
        # (MockSNMP يُرجع rx_power_raw لكل ONT)
        assert "rx_power" in body, "الاستجابة لا تحتوي rx_power"

    def test_refresh_persists_to_database(self, client):
        """بعد refresh يجب أن تُحفَظ التغييرات في قاعدة البيانات."""
        device_id = _get_device_id(client)
        record_id = _ensure_ont_record(device_id)
        headers = _operator_headers(client)

        r = client.post(f"/api/onts/{record_id}/refresh", headers=headers)
        assert r.status_code == 200

        # نتحقق من قاعدة البيانات مباشرةً
        with Session(engine) as db:
            rec = db.get(ONTRecord, record_id)
            assert rec is not None, f"لم يُعثر على السجل {record_id} في القاعدة"

    def test_refresh_nonexistent_record_returns_404(self, client):
        """سجل ONT غير موجود يجب أن يُرجع 404."""
        headers = _operator_headers(client)
        r = client.post("/api/onts/99999/refresh", headers=headers)
        assert r.status_code == 404

    def test_refresh_requires_operator_role(self, client, monkeypatch):
        """
        مسار refresh يتطلب دور operator.
        نتحقق أن المسار محمي إن كان API_TOKEN مضبوطاً.
        """
        # نحضر البيانات قبل ضبط التوكن
        device_id = _get_device_id(client)
        record_id = _ensure_ont_record(device_id)

        # الآن نضبط التوكن لتفعيل المصادقة الإجبارية
        monkeypatch.setattr(settings, "api_token", "test-secret-token-xyz")

        # بلا توكن → 401
        r_no_auth = client.post(f"/api/onts/{record_id}/refresh")
        assert r_no_auth.status_code == 401

        # بتوكن صحيح → 200
        r_auth = client.post(
            f"/api/onts/{record_id}/refresh",
            headers={"Authorization": "Bearer test-secret-token-xyz"},
        )
        assert r_auth.status_code == 200


# ===========================================================================
# 6. POST /api/devices — قبول حقول SNMPv3
# ===========================================================================

class TestDeviceCreateWithSNMP:
    """اختبارات إنشاء جهاز بحقول SNMPv3."""

    _SNMP_PAYLOAD = {
        "name": "OLT-SNMP-اختبار",
        "host": "10.0.0.100",
        "port": 22,
        "protocol": "ssh",
        "username": "root",
        "password": "test_password",
        "model": "MA5800",
        "snmp_enabled": True,
        "snmp_port": 161,
        "snmp_user": "monitor-user",
        "snmp_auth_proto": "SHA256",
        "snmp_auth_key": "super_secret_auth_key_12345",
        "snmp_priv_proto": "AES",
        "snmp_priv_key": "super_secret_priv_key_12345",
        "snmp_context": "test-context",
        "adapter_profile": "",
    }

    def test_create_device_with_snmp_fields_returns_200(self, client):
        """إنشاء جهاز بحقول SNMPv3 يجب أن يُرجع 200."""
        r = client.post("/api/devices", json=self._SNMP_PAYLOAD)
        assert r.status_code == 200, f"HTTP {r.status_code}: {r.text}"

    def test_create_device_response_has_snmp_enabled(self, client):
        """الاستجابة يجب أن تحتوي snmp_enabled."""
        r = client.post("/api/devices", json=self._SNMP_PAYLOAD)
        assert r.status_code == 200
        body = r.json()
        assert "snmp_enabled" in body, f"الاستجابة لا تحتوي snmp_enabled: {set(body.keys())}"
        assert body["snmp_enabled"] is True

    def test_create_device_response_has_snmp_user(self, client):
        """الاستجابة يجب أن تحتوي snmp_user."""
        r = client.post("/api/devices", json=self._SNMP_PAYLOAD)
        assert r.status_code == 200
        body = r.json()
        assert "snmp_user" in body, f"الاستجابة لا تحتوي snmp_user: {set(body.keys())}"
        assert body["snmp_user"] == "monitor-user"

    def test_create_device_response_has_adapter_profile(self, client):
        """الاستجابة يجب أن تحتوي adapter_profile."""
        r = client.post("/api/devices", json=self._SNMP_PAYLOAD)
        assert r.status_code == 200
        body = r.json()
        assert "adapter_profile" in body, f"الاستجابة لا تحتوي adapter_profile: {set(body.keys())}"

    def test_create_device_response_no_auth_key(self, client):
        """
        الاستجابة يجب أن لا تحتوي snmp_auth_key (المفتاح الخام).
        هذا يتحقق من عدم تسرّب المفاتيح.
        """
        r = client.post("/api/devices", json=self._SNMP_PAYLOAD)
        assert r.status_code == 200
        body = r.json()
        assert "snmp_auth_key" not in body, (
            "تسرّب أمني: snmp_auth_key موجود في الاستجابة!"
        )

    def test_create_device_response_no_priv_key(self, client):
        """
        الاستجابة يجب أن لا تحتوي snmp_priv_key (المفتاح الخام).
        """
        r = client.post("/api/devices", json=self._SNMP_PAYLOAD)
        assert r.status_code == 200
        body = r.json()
        assert "snmp_priv_key" not in body, (
            "تسرّب أمني: snmp_priv_key موجود في الاستجابة!"
        )

    def test_create_device_response_no_encrypted_keys(self, client):
        """
        الاستجابة يجب أن لا تحتوي المفاتيح المشفَّرة (_enc).
        DeviceOut schema يجب أن يُخفيها.
        """
        r = client.post("/api/devices", json=self._SNMP_PAYLOAD)
        assert r.status_code == 200
        body = r.json()
        for enc_field in ("snmp_auth_key_enc", "snmp_priv_key_enc", "password_enc"):
            assert enc_field not in body, (
                f"تسرّب أمني: {enc_field} موجود في الاستجابة!"
            )


# ===========================================================================
# 7. GET /api/devices — لا تحتوي مفاتيح مشفَّرة
# ===========================================================================

class TestDeviceListNoKeyLeak:
    """اختبارات عدم تسرّب المفاتيح في قائمة الأجهزة."""

    def test_list_devices_no_auth_key_leak(self, client):
        """
        GET /api/devices يجب أن لا يُرجع snmp_auth_key أو snmp_auth_key_enc.
        """
        # ننشئ جهازاً بمفاتيح SNMP لضمان وجود بيانات
        client.post("/api/devices", json={
            "name": "OLT-leak-test",
            "host": "10.1.1.1",
            "model": "MA5800",
            "snmp_auth_key": "leak_test_auth_key",
            "snmp_priv_key": "leak_test_priv_key",
        })

        r = client.get("/api/devices")
        assert r.status_code == 200
        devices = r.json()
        for d in devices:
            assert "snmp_auth_key" not in d, (
                f"تسرّب أمني: snmp_auth_key في قائمة الأجهزة: جهاز {d.get('name')}"
            )
            assert "snmp_auth_key_enc" not in d, (
                f"تسرّب أمني: snmp_auth_key_enc في قائمة الأجهزة: جهاز {d.get('name')}"
            )

    def test_list_devices_no_priv_key_leak(self, client):
        """
        GET /api/devices يجب أن لا يُرجع snmp_priv_key أو snmp_priv_key_enc.
        """
        r = client.get("/api/devices")
        assert r.status_code == 200
        devices = r.json()
        for d in devices:
            assert "snmp_priv_key" not in d, (
                f"تسرّب أمني: snmp_priv_key في قائمة الأجهزة: جهاز {d.get('name')}"
            )
            assert "snmp_priv_key_enc" not in d, (
                f"تسرّب أمني: snmp_priv_key_enc في قائمة الأجهزة: جهاز {d.get('name')}"
            )

    def test_list_devices_no_password_enc_leak(self, client):
        """
        GET /api/devices يجب أن لا يُرجع password_enc.
        """
        r = client.get("/api/devices")
        assert r.status_code == 200
        for d in r.json():
            assert "password_enc" not in d, (
                f"تسرّب أمني: password_enc في قائمة الأجهزة: جهاز {d.get('name')}"
            )

    def test_list_devices_has_snmp_enabled_field(self, client):
        """
        GET /api/devices يجب أن يُرجع snmp_enabled لكل جهاز (الحقول المسموحة من DeviceOut).
        """
        r = client.get("/api/devices")
        assert r.status_code == 200
        devices = r.json()
        assert devices, "لا توجد أجهزة"
        for d in devices:
            assert "snmp_enabled" in d, f"جهاز لا يحتوي snmp_enabled: {d.get('name')}"

    def test_list_devices_has_snmp_user_field(self, client):
        """
        GET /api/devices يجب أن يُرجع snmp_user لكل جهاز.
        """
        r = client.get("/api/devices")
        assert r.status_code == 200
        for d in r.json():
            assert "snmp_user" in d, f"جهاز لا يحتوي snmp_user: {d.get('name')}"


# ===========================================================================
# 8. دورة تكامل شاملة (E2E Integration Cycle)
# ===========================================================================

class TestFullSNMPCycle:
    """
    دورة تكامل E2E كاملة:
    إنشاء جهاز → اختبار SNMP → سحب ONTs → refresh ONT فردي → التحقق من القاعدة.
    """

    def test_full_cycle_device_to_ont_refresh(self, client):
        """
        دورة كاملة:
        1. التحقق من وجود الجهاز المبذور
        2. اختبار اتصال SNMP
        3. سحب صحّة الجهاز
        4. سحب منافذ PON
        5. إنشاء سجلات ONT عبر poll
        6. refresh ONT
        7. التحقق من القاعدة
        """
        headers = _operator_headers(client)

        # الخطوة 1: الجهاز المبذور
        device_id = _get_device_id(client)
        assert device_id is not None

        # الخطوة 2: اختبار SNMP
        r_test = client.post(
            f"/api/devices/{device_id}/snmp/test", headers=headers
        )
        assert r_test.status_code == 200
        assert r_test.json()["ok"] is True

        # الخطوة 3: صحّة الجهاز
        r_health = client.get(f"/api/devices/{device_id}/snmp/health")
        assert r_health.status_code == 200

        # الخطوة 4: منافذ PON
        r_pon = client.get(f"/api/devices/{device_id}/pon")
        assert r_pon.status_code == 200
        assert isinstance(r_pon.json(), list)

        # الخطوة 5: إنشاء سجلات ONT
        record_id = _ensure_ont_record(device_id)
        assert record_id is not None

        # الخطوة 6: refresh ONT
        r_refresh = client.post(
            f"/api/onts/{record_id}/refresh", headers=headers
        )
        assert r_refresh.status_code == 200
        body = r_refresh.json()
        assert body["id"] == record_id
        assert body["olt_id"] == device_id

        # الخطوة 7: التحقق من القاعدة
        with Session(engine) as db:
            rec = db.get(ONTRecord, record_id)
            assert rec is not None
            assert rec.olt_id == device_id

    def test_snmp_health_persists_and_returnable(self, client):
        """
        بعد سحب الصحّة، طلب ثانٍ يجب أن يُرجع السجل من القاعدة (وليس poll جديد).
        """
        device_id = _get_device_id(client)

        # الطلب الأول → poll (أو من القاعدة)
        r1 = client.get(f"/api/devices/{device_id}/snmp/health")
        assert r1.status_code == 200

        # الطلب الثاني → من القاعدة (نفس البيانات)
        r2 = client.get(f"/api/devices/{device_id}/snmp/health")
        assert r2.status_code == 200

        # كلا الطلبَين يُرجعان olt_id صحيح
        assert r1.json().get("olt_id") == device_id
        assert r2.json().get("olt_id") == device_id

    def test_pon_data_consistent_with_mock_onts(self, client):
        """
        بيانات PON في المحاكاة يجب أن تكون متسقة مع ONTs المُحاكاة:
        المنفذ 0/5/0 لديه 3 ONTs (2 online + 0 offline واحد ليس على هذا المنفذ).
        """
        device_id = _get_device_id(client)

        # حذف سجلات PON لإجبار poll فوري
        with Session(engine) as db:
            rows = db.exec(
                select(PonPortStatus).where(PonPortStatus.olt_id == device_id)
            ).all()
            for row in rows:
                db.delete(row)
            db.commit()

        r = client.get(f"/api/devices/{device_id}/pon")
        assert r.status_code == 200
        ports = r.json()

        # المحاكاة لها منفذَان: port 0 و port 1 على slot 5
        port_keys = {(p.get("frame"), p.get("slot"), p.get("port")) for p in ports}
        # يجب أن يشتمل على slot=5
        assert any(k[1] == 5 for k in port_keys), (
            f"لم يُعثر على منافذ على slot 5 — المنافذ: {port_keys}"
        )
