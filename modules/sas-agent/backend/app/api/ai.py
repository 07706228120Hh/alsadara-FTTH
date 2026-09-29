"""نقطة نهاية مساعد الذكاء الاصطناعي"""
from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session
from ..database import get_session
from ..models import OLTDevice
from ..schemas import AIChatRequest
from ..services import ai_assistant

router = APIRouter(prefix="/api/ai", tags=["ai"])


@router.post("/{device_id}/chat")
def chat(device_id: int, req: AIChatRequest, db: Session = Depends(get_session)):
    """محادثة مع الخبير الذكي — يستطيع تنفيذ أوامر عرض تلقائياً"""
    device = db.get(OLTDevice, device_id)
    if not device:
        raise HTTPException(404, "الجهاز غير موجود")
    return ai_assistant.ask(device, req.question, req.history)
