"""نقاط نهاية التدقيق — مطابقة أعداد مشتركي الوكلاء مقابل الشركات المجهِّزة."""
from typing import Optional
from fastapi import APIRouter
from ..services import audit

router = APIRouter(prefix="/api/audit", tags=["audit"])


@router.get("/overview")
def overview(company: Optional[str] = None):
    """صورة التدقيق: تفصيلي لكل وكيل (حسب @) + مجاميع كل شركة + الأحكام."""
    return audit.overview(company)
