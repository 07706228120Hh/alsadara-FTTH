"""نقاط نهاية الشبكة الحكومية (Intranet) — الوزارات ومؤسساتها عبر VLAN حكومي."""
from fastapi import APIRouter, HTTPException
from ..services import gov_network

router = APIRouter(prefix="/api/gov", tags=["gov-network"])


@router.get("/overview")
def overview():
    """صورة الشبكة الحكومية: الـ VLAN الحكومي، الإجماليات، وقائمة الوزارات."""
    return gov_network.overview()


@router.get("/ministry")
def ministry(id: str):
    """تفاصيل وزارة واحدة مع كل مؤسساتها المرتبطة بالشبكة الداخلية."""
    try:
        return gov_network.ministry(id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
