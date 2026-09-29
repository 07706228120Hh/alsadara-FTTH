"""نقاط نهاية DfoS — الاستشعار الليفي الموزّع: أحداث، خريطة GIS، وتصعيد الحوادث."""
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from ..services import dfos
from ..core.auth import require_role

router = APIRouter(prefix="/api/dfos", tags=["dfos"])


@router.get("/overview")
def overview(governorate: Optional[str] = None, threats_only: bool = False):
    """صورة DfoS: أجهزة الاستشعار، الكاميرات، الأحداث المصنّفة، والتجميعات."""
    return dfos.overview(governorate, threats_only)


@router.get("/map")
def map_data(governorate: Optional[str] = None):
    """طبقة GIS: المسارات المراقَبة + أجهزة DfoS + الكاميرات + علامات الأحداث."""
    return dfos.map_data(governorate)


@router.get("/events/{event_id}")
def event_detail(event_id: str):
    """تفاصيل حدث واحد مع سلسلة الحزمة الكاملة (إنذار/وكيل/موقع/كاميرا/تذكرة)."""
    e = dfos.event_detail(event_id)
    if e is None:
        raise HTTPException(404, "حدث غير معروف")
    return e


@router.post("/{event_id}/dispatch",
             dependencies=[Depends(require_role("operator"))])
def dispatch(event_id: str):
    """تصعيد حدث تهديد: فتح تذكرة حادث فعلية في سجلّ المشاكل (operator)."""
    try:
        return dfos.dispatch(event_id)
    except ValueError as e:
        raise HTTPException(400, str(e))


@router.post("/analyze")
def analyze(governorate: Optional[str] = None):
    """تحليل ذكي لمشهد تهديدات DfoS (Claude إن توفّر المفتاح، وإلا قواعد محلية)."""
    return dfos.analyze(governorate)
