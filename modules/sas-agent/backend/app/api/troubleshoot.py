"""نقاط نهاية التشخيص"""
from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session
from ..database import get_session
from ..models import OLTDevice
from ..schemas import DiagnoseRequest
from ..services import troubleshooting

router = APIRouter(prefix="/api/troubleshoot", tags=["troubleshoot"])


@router.post("/{device_id}/ont")
def diagnose(device_id: int, req: DiagnoseRequest, db: Session = Depends(get_session)):
    """تشخيص شامل لـ ONT — يجمع البيانات ويطبّق القواعد الخبيرة"""
    device = db.get(OLTDevice, device_id)
    if not device:
        raise HTTPException(404, "الجهاز غير موجود")
    return troubleshooting.diagnose_ont(device, req.fsp, req.ont_id)


@router.post("/{device_id}/voice")
def diagnose_voice(device_id: int, fsp: str, db: Session = Depends(get_session)):
    """تشخيص جودة مكالمة صوتية (MOS/R-Factor)"""
    device = db.get(OLTDevice, device_id)
    if not device:
        raise HTTPException(404, "الجهاز غير موجود")
    return troubleshooting.voice_diagnose(device, fsp)
