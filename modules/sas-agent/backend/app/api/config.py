"""نقاط نهاية كتالوج التهيئة — واجهة عامة لبرمجة الجهاز حسب أدلة HCIA/HCIP."""
from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session
from ..database import get_session
from ..models import OLTDevice, AuditLog
from ..schemas import ConfigBuildRequest
from ..services import config_catalog, provisioning
from ..core.auth import require_role

router = APIRouter(prefix="/api/config", tags=["config"])


@router.get("/catalog")
def get_catalog():
    """يُرجع كتالوج كل الإجراءات (فئات + حقول + شرح الربط) لبناء الواجهة."""
    return {"catalog": config_catalog.CATALOG}


def _build_steps(procedure: str, params: dict):
    try:
        return config_catalog.build(procedure, params or {})
    except KeyError:
        raise HTTPException(400, f"إجراء غير معروف: {procedure}")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(400, f"تعذّر بناء الأوامر: {e}")


@router.post("/{device_id}/build")
def build_config(device_id: int, req: ConfigBuildRequest,
                 db: Session = Depends(get_session)):
    """معاينة (dry-run): يُرجع الأوامر التي ستُنفَّذ دون تنفيذها."""
    device = db.get(OLTDevice, device_id)
    if not device:
        raise HTTPException(404, "الجهاز غير موجود")
    steps = _build_steps(req.procedure, req.params)
    return {
        "dry_run": True,
        "procedure": req.procedure,
        "steps": steps,
        "note": "راجع الأوامر ثم أرسل الطلب إلى /apply للتنفيذ.",
    }


@router.post("/{device_id}/apply", dependencies=[Depends(require_role("operator"))])
def apply_config(device_id: int, req: ConfigBuildRequest,
                 db: Session = Depends(get_session)):
    """تنفيذ الإجراء على الجهاز مع تسجيل كل أمر في Audit log."""
    device = db.get(OLTDevice, device_id)
    if not device:
        raise HTTPException(404, "الجهاز غير موجود")
    steps = _build_steps(req.procedure, req.params)

    plan = provisioning.ProvisionPlan()
    for s in steps:
        plan.add(s["title"], s["commands"], s.get("kind", "write"))

    def log_fn(olt_id, command, kind, success, output):
        db.add(AuditLog(olt_id=olt_id, command=command, kind=kind,
                        success=success, result=output[:1000]))

    result = provisioning.execute_plan(device, plan, log_fn=log_fn)
    db.commit()
    result["procedure"] = req.procedure
    return result
