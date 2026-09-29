"""نقاط نهاية SNMP — اختبار الاتصال، صحّة الجهاز، منافذ PON، تحديث ONT، قائمة Adapters"""
from fastapi import APIRouter, Depends, HTTPException
from fastapi.concurrency import run_in_threadpool
from sqlmodel import Session, select

from ..database import get_session
from ..models import OLTDevice, ONTRecord, DeviceHealth, PonPortStatus
from ..schemas import SNMPTestResult
from ..core.snmp_client import snmp_manager
from ..core.snmp_collector import list_adapters
from ..core.auth import require_role
from ..services.snmp_poller import poll_health, poll_pon, refresh_ont_detail

router = APIRouter(prefix="/api", tags=["snmp"])

_operator = [Depends(require_role("operator"))]


# ---------------------------------------------------------------------------
# POST /api/devices/{device_id}/snmp/test
# ---------------------------------------------------------------------------

@router.post(
    "/devices/{device_id}/snmp/test",
    response_model=SNMPTestResult,
    dependencies=_operator,
    summary="اختبار اتصال SNMPv3 بجهاز",
)
async def test_snmp(device_id: int, db: Session = Depends(get_session)):
    """
    يتحقّق من إمكانية الوصول SNMP للجهاز:
    يقرأ sysDescr + sysUpTime ويُرجع ok/error.
    """
    device = db.get(OLTDevice, device_id)
    if not device:
        raise HTTPException(404, "الجهاز غير موجود")
    result = await run_in_threadpool(snmp_manager.test, device)
    return result


# ---------------------------------------------------------------------------
# GET /api/devices/{device_id}/snmp/health
# ---------------------------------------------------------------------------

@router.get(
    "/devices/{device_id}/snmp/health",
    summary="أحدث صحّة الجهاز (CPU/ذاكرة/حرارة/uptime)",
)
async def get_health(device_id: int, db: Session = Depends(get_session)):
    """
    يُرجع أحدث صف DeviceHealth للجهاز من قاعدة البيانات.
    إن لم يوجد سجل يستدعي poll_health فوراً ويُرجع النتيجة.
    """
    device = db.get(OLTDevice, device_id)
    if not device:
        raise HTTPException(404, "الجهاز غير موجود")

    health = db.exec(
        select(DeviceHealth).where(DeviceHealth.olt_id == device_id)
    ).first()

    if health:
        return health

    # لا يوجد سجل — سحب فوري
    data = await run_in_threadpool(poll_health, device)
    return data


# ---------------------------------------------------------------------------
# GET /api/devices/{device_id}/pon
# ---------------------------------------------------------------------------

@router.get(
    "/devices/{device_id}/pon",
    summary="قائمة منافذ PON وملخّص حالتها",
)
async def get_pon_ports(device_id: int, db: Session = Depends(get_session)):
    """
    يُرجع قائمة صفوف PonPortStatus للجهاز من قاعدة البيانات.
    إن كانت القائمة فارغة يستدعي poll_pon فوراً ويُرجع النتيجة.
    """
    device = db.get(OLTDevice, device_id)
    if not device:
        raise HTTPException(404, "الجهاز غير موجود")

    rows = db.exec(
        select(PonPortStatus).where(PonPortStatus.olt_id == device_id)
    ).all()

    if rows:
        return rows

    # لا يوجد بيانات — سحب فوري
    data = await run_in_threadpool(poll_pon, device)
    return data


# ---------------------------------------------------------------------------
# POST /api/onts/{record_id}/refresh
# ---------------------------------------------------------------------------

@router.post(
    "/onts/{record_id}/refresh",
    dependencies=_operator,
    summary="تحديث بيانات ONT التفصيلية فوراً (DDM + إصدارات)",
)
async def refresh_ont(record_id: int, db: Session = Depends(get_session)):
    """
    يجلب ONTRecord بمفتاحه الأساسي (id) — يتجنب مشكلة الشرطات في fsp داخل المسار.
    ثم يستدعي refresh_ont_detail لقراءة بيانات DDM المحدَّثة.
    يُرجع السجل المحدَّث بعد الحفظ.
    """
    rec = db.get(ONTRecord, record_id)
    if not rec:
        raise HTTPException(404, "سجل ONT غير موجود")

    device = db.get(OLTDevice, rec.olt_id)
    if not device:
        raise HTTPException(404, "الجهاز المرتبط بهذا ONT غير موجود")

    updated = await run_in_threadpool(refresh_ont_detail, device, rec.fsp, rec.ont_id)

    # تحديث حقول ONTRecord من النتيجة
    updatable = (
        "rx_power", "tx_power", "olt_rx_power", "temperature",
        "voltage", "bias_current", "distance_m",
        "last_down_cause", "ont_model", "hw_version", "sw_version", "reg_method",
    )
    for field in updatable:
        val = updated.get(field)
        if val is not None:
            setattr(rec, field, val)

    db.add(rec)
    db.commit()
    db.refresh(rec)
    return rec


# ---------------------------------------------------------------------------
# GET /api/adapters
# ---------------------------------------------------------------------------

@router.get(
    "/adapters",
    summary="قائمة ملفات Adapter المتاحة لأجهزة Huawei",
)
def get_adapters():
    """
    يُرجع قائمة ملفات Adapter (JSON) الموجودة في knowledge/adapters/.
    كل عنصر: {name, model, vendor, match, file}.
    """
    return list_adapters()
