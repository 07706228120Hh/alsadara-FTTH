"""نقاط نهاية تشخيص الترانزيت والبوابات الدولية — صحّة المسارات وحجم البيانات العابرة."""
from typing import Optional
from fastapi import APIRouter
from ..services import transit

router = APIRouter(prefix="/api/transit", tags=["transit"])


@router.get("/overview")
def overview(country: Optional[str] = None):
    """صورة الترانزيت: البوابات الدولية، الحِمل، الإشغال، والسلسلة الزمنية."""
    return transit.overview(country)


@router.post("/diagnose")
def diagnose(country: Optional[str] = None, gateway_id: Optional[str] = None):
    """تشخيص بالقواعد الخبيرة للبوابات (كلّها أو دولة/بوابة محدّدة)."""
    return transit.diagnose(country, gateway_id)


@router.post("/analyze")
def analyze(country: Optional[str] = None):
    """تحليل ذكي للترانزيت (Claude إن توفّر المفتاح، وإلا قواعد محلية)."""
    return transit.analyze(country)
