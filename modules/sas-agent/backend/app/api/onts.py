"""نقاط نهاية ONTs والمراقبة"""
from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select
from ..database import get_session
from ..models import OLTDevice, ONTRecord, AlarmRecord, Metric
from ..core.olt_connection import manager
from ..core import command_library as cl
from ..core import parsers
from ..services import monitoring

router = APIRouter(prefix="/api", tags=["onts"])


@router.get("/devices/{device_id}/onts")
def list_onts(device_id: int, db: Session = Depends(get_session)):
    """قائمة ONTs المخزّنة + سحب حي"""
    device = db.get(OLTDevice, device_id)
    if not device:
        raise HTTPException(404, "الجهاز غير موجود")
    summary = monitoring.poll_device(device)
    return summary


@router.get("/devices/{device_id}/autofind")
def autofind(device_id: int, port: int = 0, db: Session = Depends(get_session)):
    """اكتشاف ONTs الجديدة على منفذ"""
    device = db.get(OLTDevice, device_id)
    if not device:
        raise HTTPException(404, "الجهاز غير موجود")
    out = manager.get(device).run(cl.DISPLAY["ont_autofind"](port))
    return {"found": parsers.parse_autofind(out), "raw": out}


@router.get("/devices/{device_id}/alarms")
def list_alarms(device_id: int, active_only: bool = True, db: Session = Depends(get_session)):
    stmt = select(AlarmRecord).where(AlarmRecord.olt_id == device_id)
    if active_only:
        stmt = stmt.where(AlarmRecord.active == True)  # noqa: E712
    stmt = stmt.order_by(AlarmRecord.ts.desc()).limit(200)
    return db.exec(stmt).all()


@router.get("/devices/{device_id}/metrics")
def get_metrics(device_id: int, metric: str = "rx_power", limit: int = 200,
                db: Session = Depends(get_session)):
    stmt = select(Metric).where(Metric.olt_id == device_id, Metric.metric == metric).order_by(
        Metric.ts.desc()).limit(limit)
    return list(reversed(db.exec(stmt).all()))


# ---------------------------------------------------------------------------
# مستكشف الجهاز الشامل (CLI) — كاردات · بورتات · برمجة · ONTs
# ---------------------------------------------------------------------------

@router.get("/devices/{device_id}/inventory")
def device_inventory(device_id: int, db: Session = Depends(get_session)):
    """جرد الجهاز: قائمة الكاردات + معلومات النظام (display board 0 + display version)."""
    device = db.get(OLTDevice, device_id)
    if not device:
        raise HTTPException(404, "الجهاز غير موجود")
    sess = manager.get(device)
    board_out = sess.run(cl.DISPLAY["board"]())
    try:
        version_out = sess.run(cl.DISPLAY["version"]())
    except Exception as e:  # pragma: no cover
        version_out = f"تعذّر جلب الإصدار: {e}"
    return {
        "boards": parsers.parse_board_list(board_out),
        "board_raw": board_out,
        "version_raw": version_out,
    }


@router.get("/devices/{device_id}/board/{slot}")
def board_detail(device_id: int, slot: int, db: Session = Depends(get_session)):
    """تفاصيل كارت وبورتاته (display board 0/slot)."""
    device = db.get(OLTDevice, device_id)
    if not device:
        raise HTTPException(404, "الجهاز غير موجود")
    sess = manager.get(device)
    out = sess.run(cl.DISPLAY["board_detail"](f"0/{slot}"))
    return {"slot": slot, "raw": out}


@router.get("/devices/{device_id}/running-config")
def running_config(device_id: int, db: Session = Depends(get_session)):
    """البرمجة الكاملة للجهاز (display current-configuration)."""
    device = db.get(OLTDevice, device_id)
    if not device:
        raise HTTPException(404, "الجهاز غير موجود")
    sess = manager.get(device)
    out = sess.run(cl.DISPLAY["current_config"]())
    return {"config": out}


@router.get("/devices/{device_id}/port/{slot}/{port}/onts")
def port_onts(device_id: int, slot: int, port: int, db: Session = Depends(get_session)):
    """ONTs على بورت GPON معيّن (display ont info 0/slot/port all)."""
    device = db.get(OLTDevice, device_id)
    if not device:
        raise HTTPException(404, "الجهاز غير موجود")
    sess = manager.get(device)
    out = sess.run(cl.DISPLAY["ont_info_all"](f"0/{slot}/{port}"))
    return {"onts": parsers.parse_ont_info_all(out), "raw": out}
