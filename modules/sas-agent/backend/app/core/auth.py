"""
المصادقة والصلاحيات.

يُقبل أيٌّ من:
1. توكن جلسة مستخدم (Bearer) صادر عن /api/auth/login — يحمل الدور (viewer/operator/admin).
2. API_TOKEN الرئيسي (Bearer) — يُعامَل كصلاحية admin كاملة.
3. وضع المحاكاة بلا API_TOKEN — وصول تطوير محلي (admin) دون مصادقة.
4. توكن جلسة مشترك (Bearer) صادر عن /api/subscriber/otp/verify — دور subscriber،
   مقبول فقط في مسارات /api/subscriber/* (require_subscriber) ومرفوض في مسارات الموظّفين.

الأدوار: viewer < operator < admin.
- viewer: القراءة والعرض فقط.
- operator: + تنفيذ الأوامر والتزويد والتهيئة.
- admin: + إدارة المستخدمين والأجهزة.
"""
import hmac
from typing import Optional
from fastapi import Header, HTTPException, status, Depends
from sqlmodel import Session, select
from ..config import settings
from ..database import engine
from ..core import security

_ROLE_RANK = {"viewer": 1, "operator": 2, "admin": 3}


def _identity_from_user_token(token: str) -> Optional[dict]:
    """يُحاول قراءة توكن جلسة مستخدم والتحقّق من وجوده وتفعيله."""
    data = security.read_user_token(token, settings.token_ttl_hours * 3600)
    if not data:
        return None
    from ..models import User
    with Session(engine) as db:
        u = db.exec(select(User).where(User.username == data.get("u"))).first()
        if u and u.enabled:
            return {"user": u.username, "role": u.role, "via": "user",
                    "company_id": u.scope_company_id, "agent": u.scope_agent}
    return None


def _identity_from_subscriber_token(token: str) -> Optional[dict]:
    """يُحاول قراءة توكن مشترك (رقم هاتف مطبَّع). لا نطاق شركة/وكيل هنا —
    تُحلّ حسابات المشترك من جدول Subscriber عند كل طلب (قد يملك أكثر من حساب)."""
    phone = security.read_subscriber_token(token, settings.subscriber_token_ttl_hours * 3600)
    if not phone:
        return None
    return {"user": phone, "role": "subscriber", "via": "subscriber",
            "company_id": None, "agent": "", "phone": phone, "kind": "subscriber"}


def _bearer(authorization: str) -> str:
    return authorization[7:] if authorization.startswith("Bearer ") else ""


def current_identity(authorization: str = Header(default="")) -> dict:
    """اعتمادية تُرجع هوية الطالب أو ترفع 401."""
    provided = _bearer(authorization)

    ident = _identity_from_user_token(provided)
    if ident:
        ident.setdefault("kind", "staff")
        return ident

    ident = _identity_from_subscriber_token(provided)
    if ident:
        return ident

    if settings.api_token and hmac.compare_digest(provided or "", settings.api_token):
        return {"user": None, "role": "admin", "via": "api_token",
                "company_id": None, "agent": "", "kind": "staff"}

    if not settings.api_token and settings.use_mock_olt:
        return {"user": None, "role": "admin", "via": "dev",
                "company_id": None, "agent": "", "kind": "staff"}

    raise HTTPException(
        status.HTTP_401_UNAUTHORIZED,
        "مصادقة مطلوبة أو توكن غير صالح",
        headers={"WWW-Authenticate": "Bearer"},
    )


def require_auth(identity: dict = Depends(current_identity)) -> dict:
    """حماية عامة لمسارات الموظّفين — أي هوية مُصادَقة (viewer فأعلى).
    توكن المشترك مرفوض هنا (403) كي لا يصل إلى بيانات الشركات/الوكلاء."""
    if identity.get("kind") == "subscriber":
        raise HTTPException(status.HTTP_403_FORBIDDEN,
                            "هذا المسار لحسابات الموظّفين — استخدم مسارات /api/subscriber")
    return identity


def require_subscriber(identity: dict = Depends(current_identity)) -> dict:
    """حماية مسارات تطبيق المشتركين — توكن مشترك حصراً."""
    if identity.get("kind") != "subscriber":
        raise HTTPException(status.HTTP_403_FORBIDDEN,
                            "هذا المسار لحسابات المشتركين (OTP)")
    return identity


def require_role(min_role: str):
    """مصنع اعتمادية تفرض حداً أدنى من الدور."""
    def checker(identity: dict = Depends(current_identity)) -> dict:
        rank = _ROLE_RANK.get(identity.get("role", "viewer"), 0)
        if rank < _ROLE_RANK[min_role]:
            raise HTTPException(
                status.HTTP_403_FORBIDDEN,
                f"صلاحية غير كافية — يتطلب دور {min_role} أو أعلى",
            )
        return identity
    return checker


def scope_of(identity: dict) -> tuple:
    """نطاق الطالب (company_id, agent) — (None, "") = جهة رقابية ترى كل الشركات.
    تستخدمه نقاط النهاية لتقييد الصفوف: شركة → صفوفها فقط، وكيل → نطاقه فقط."""
    return identity.get("company_id"), (identity.get("agent") or "")


def ws_authorized(token: str) -> bool:
    """تحقّق توكن الـ WebSocket (query param)."""
    if _identity_from_user_token(token):
        return True
    if settings.api_token and hmac.compare_digest(token or "", settings.api_token):
        return True
    if not settings.api_token and settings.use_mock_olt:
        return True
    return False
