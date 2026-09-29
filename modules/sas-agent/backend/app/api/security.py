"""
نقاط نهاية الأمن السيبراني الدفاعي — تشغيل وكلاء الحماية على المنصة.

يُوضع في backend/app/api/security.py، ويُربط في main.py:
    from .api import ... , security as security_api
    app.include_router(security_api.router, dependencies=_auth)
"""
from fastapi import APIRouter, Depends
from sqlmodel import Session

from ..database import get_session
from ..core.auth import require_role
from ..services import security_agents as sec

router = APIRouter(prefix="/api/security", tags=["security"])

# التدقيق الأمني حسّاس — admin فقط
_admin = [Depends(require_role("admin"))]


@router.get("/scan", dependencies=_admin)
def full_scan(code: bool = True, db: Session = Depends(get_session)):
    """يشغّل كل وكلاء الدفاع ويُرجع درجة الأمان + النتائج مصنّفة بالشدّة."""
    return sec.run_all(db, include_code=code)


@router.get("/hardening", dependencies=_admin)
def hardening():
    return {"findings": [x.dict() for x in sec.audit_hardening()]}


@router.get("/code", dependencies=_admin)
def code_scan():
    return {"findings": [x.dict() for x in sec.scan_code(sec._project_root())]}


@router.get("/crypto", dependencies=_admin)
def crypto():
    return {"findings": [x.dict() for x in sec.audit_crypto()]}


@router.get("/access", dependencies=_admin)
def access(db: Session = Depends(get_session)):
    return {"findings": [x.dict() for x in sec.audit_access(db)]}


@router.get("/anomalies", dependencies=_admin)
def anomalies(db: Session = Depends(get_session)):
    return {"findings": [x.dict() for x in sec.detect_anomalies(db)]}
