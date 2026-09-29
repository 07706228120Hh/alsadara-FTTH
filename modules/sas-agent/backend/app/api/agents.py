"""نقاط نهاية الوكلاء — صورة الوكلاء ومشتركيهم مع تصفية وتفاصيل وتسجيل."""
from typing import List, Optional
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from ..services import agents

router = APIRouter(prefix="/api/agents", tags=["agents"])


class AgentRegister(BaseModel):
    """طلب تسجيل وكيل — الاسم والشركة إلزاميان، والبقية اختيارية."""
    name: str
    company: str
    governorate: Optional[str] = None
    phone: Optional[str] = None
    national_id: Optional[str] = None
    office: Optional[str] = None
    handle: Optional[str] = None
    area: Optional[str] = None
    address: Optional[str] = None
    device_type: Optional[str] = None
    service_types: Optional[List[str]] = None
    status: Optional[str] = None
    lat: Optional[float] = None
    lng: Optional[float] = None
    notes: Optional[str] = None


@router.get("/overview")
def overview(governorate: Optional[str] = None, company: Optional[str] = None,
             service_type: Optional[str] = None):
    """صورة شاملة للوكلاء مع تصفية اختيارية حسب المحافظة/الشركة/نوع الخدمة."""
    return agents.overview(governorate, company, service_type)


@router.get("/map")
def agent_map(governorate: Optional[str] = None, company: Optional[str] = None):
    """مواقع الوكلاء الجغرافية (طبقة الخريطة) — يُعرَّف قبل /{agent_id}."""
    return agents.agent_map(governorate, company)


@router.post("/register")
def register(body: AgentRegister):
    """تسجيل وكيل جديد بكل بياناته (يُعرَّف قبل /{agent_id})."""
    try:
        return agents.register_agent(body.model_dump())
    except ValueError as e:
        raise HTTPException(400, str(e))


@router.get("/{agent_id}")
def detail(agent_id: str, service_type: Optional[str] = None,
           status: Optional[str] = None):
    """تفاصيل وكيل مع قائمة مشتركيه (تصفية اختيارية بنوع الخدمة/الحالة)."""
    data = agents.detail(agent_id, service_type, status)
    if data is None:
        raise HTTPException(404, "الوكيل غير موجود")
    return data
