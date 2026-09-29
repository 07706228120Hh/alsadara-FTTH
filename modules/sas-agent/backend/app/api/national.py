"""نقاط نهاية اللوحة الوطنية — صورة أسطول العراق + تحليل ذكي + خريطة ONTs + مسارات."""
from typing import Optional, List
from fastapi import APIRouter, Query
from ..services import national

router = APIRouter(prefix="/api/national", tags=["national"])


@router.get("/overview")
def overview(governorate: Optional[str] = None, company: Optional[str] = None,
             access_type: Optional[str] = None):
    """صورة وطنية شاملة مع تصفية اختيارية حسب المحافظة/الشركة/نوع الاتصال."""
    return national.overview(governorate, company, access_type)


@router.get("/governorates")
def governorates():
    """قائمة المحافظات العراقية مع مراكزها الجغرافية."""
    return {"governorates": national.governorate_centers()}


@router.get("/ont-map")
def ont_map(governorate: Optional[str] = None, company: Optional[str] = None):
    """مواقع ONTs الجغرافية مع تفاصيلها، مع إمكانية التصفية حسب المحافظة/الشركة."""
    return national.ont_map(governorate, company)


@router.get("/device-map")
def device_map(governorate: Optional[str] = None, company: Optional[str] = None):
    """مواقع أجهزة OLT للشركات (طبقة الخريطة)، مع تصفية حسب المحافظة/الشركة."""
    return national.device_map(governorate, company)


@router.get("/routes")
def routes(governorate: Optional[str] = None,
           company: Optional[str] = None,
           types: Optional[List[str]] = Query(None)):
    """مسارات العراق: دولية / بين المحافظات / داخل المحافظة / شبكات."""
    return national.routes(governorate, company, types)


@router.get("/networks")
def networks():
    """إحصائيات كل شركة شبكة (عدد الأجهزة والمشتركين والمحافظات)."""
    return {"networks": national.networks()}


@router.post("/analyze")
def analyze(governorate: Optional[str] = None, company: Optional[str] = None):
    """تحليل ذكي للبيانات الوطنية (Claude إن توفّر، وإلا قواعد محلية)."""
    return national.analyze(governorate, company)
