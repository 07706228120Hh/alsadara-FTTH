"""نقاط نهاية المصادقة — تسجيل الدخول ومعرفة الهوية الحالية."""
from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select
from ..database import get_session
from ..models import User
from ..schemas import LoginRequest
from ..core import security
from ..core.auth import require_auth
from ..config import settings

router = APIRouter(prefix="/api/auth", tags=["auth"])


@router.post("/login")
def login(req: LoginRequest, db: Session = Depends(get_session)):
    """تسجيل الدخول — يُرجع توكن جلسة عند صحّة البيانات (نقطة عامّة)."""
    u = db.exec(select(User).where(User.username == req.username)).first()
    if not u or not u.enabled or not security.verify_password(req.password, u.password_hash):
        raise HTTPException(401, "اسم المستخدم أو كلمة المرور غير صحيحة")
    token = security.make_user_token(u.username, u.role)
    return {
        "token": token,
        "user": u.username,
        "role": u.role,
        "expires_in": settings.token_ttl_hours * 3600,
    }


@router.get("/me")
def me(identity: dict = Depends(require_auth)):
    """الهوية الحالية (الدور، مصدر المصادقة، ونطاق الشركة/الوكيل)."""
    return {
        "user": identity.get("user"),
        "role": identity.get("role"),
        "via": identity.get("via"),
        "company_id": identity.get("company_id"),
        "agent": identity.get("agent") or None,
        # نوع الحساب للتطبيقات المنفصلة: regulator | company | agent
        "kind": ("agent" if (identity.get("agent") or "").strip()
                 else "company" if identity.get("company_id") is not None
                 else "regulator"),
    }
