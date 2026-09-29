"""نقاط نهاية مشاكل الشركات ومستوى الخدمة (SLA) — صورة + تقرير + تحليل ذكي + إضافة."""
from typing import Optional
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from ..services import issues

router = APIRouter(prefix="/api/issues", tags=["issues"])


class IssueCreate(BaseModel):
    """طلب إضافة مشكلة يدوياً — النوع والشركة إلزاميان."""
    type: str
    company: str
    severity: Optional[str] = None
    governorate: Optional[str] = None
    description: Optional[str] = None


@router.get("/overview")
def overview(governorate: Optional[str] = None, company: Optional[str] = None):
    """صورة شاملة لبلاغات الأعطال مع تصفية اختيارية حسب المحافظة/الشركة."""
    return issues.overview(governorate, company)


@router.get("/report")
def report(governorate: Optional[str] = None, company: Optional[str] = None):
    """تقرير نصّي (Markdown عربي) عن حالة الأعطال والالتزام بالـ SLA."""
    return issues.report(governorate, company)


@router.post("/analyze")
def analyze(governorate: Optional[str] = None, company: Optional[str] = None):
    """تحليل ذكي لبلاغات الأعطال (Claude إن توفّر، وإلا قواعد محلية)."""
    return issues.analyze(governorate, company)


@router.post("/create")
def create(body: IssueCreate):
    """إضافة مشكلة يدوياً كمهمة مفتوحة (قيد التنفيذ) لشركة محدّدة."""
    try:
        return issues.create_issue(
            type=body.type,
            company=body.company,
            severity=body.severity,
            governorate=body.governorate,
            description=body.description,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
