"""إدارة المستخدمين — متاحة لدور admin فقط.

عزل النطاق (H2 — منع التصعيد الأفقي):
إدارة المستخدمين محجوزة للجهة الرقابية فقط (admin بلا نطاق).
مستخدم ذو نطاق (شركة أو وكيل) لا يستطيع إنشاء/تعديل/حذف مستخدمين
— يمنع صناعة جهة رقابية أو تصعيد الصلاحيات.
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select
from ..database import get_session
from ..models import User, Company, Agent
from ..schemas import UserCreate, UserUpdate, UserOut
from ..core import security
from ..core.auth import require_role, current_identity, scope_of

router = APIRouter(prefix="/api/users", tags=["users"],
                   dependencies=[Depends(require_role("admin"))])

_ROLES = {"viewer", "operator", "admin"}


def _out(u: User) -> UserOut:
    return UserOut(id=u.id, username=u.username, role=u.role, enabled=u.enabled,
                   scope_company_id=u.scope_company_id, scope_agent=u.scope_agent or "")


def _deny_scoped_user(identity: dict) -> None:
    """يرفض أي مستخدم ذو نطاق من إدارة المستخدمين — للجهة الرقابية فقط."""
    cid, agent = scope_of(identity)
    if cid is not None or agent:
        raise HTTPException(403, "إدارة المستخدمين للجهة الرقابية فقط")


def _validate_scope(db: Session, cid, scope_agent, role: str):
    """يتحقّق من اتساق النطاق ويعيد (cid, scope_agent) المُطبَّعين.

    القواعد (مشتركة بين الإنشاء والتعديل):
      كلاهما فارغ → جهة رقابية · شركة فقط → مدير شركة · الاثنان → وكيل.
      وكيل بلا شركة → 400 · شركة غير موجودة → 404 ·
      وكيل غير موجود بالشركة → 404 · دور admin لحساب وكيل → 400.
    لا يشمل فحص التكرار (409) لأنه يختلف بين الإنشاء والتعديل.
    """
    agent_scope = (scope_agent or "").strip()
    if agent_scope and cid is None:
        raise HTTPException(400, "حساب الوكيل يتطلّب تحديد الشركة")
    if cid is not None and not db.get(Company, cid):
        raise HTTPException(404, "الشركة غير موجودة")
    if agent_scope:
        if role == "admin":
            raise HTTPException(400, "لا يُسمح بدور admin لحساب وكيل")
        if not db.exec(select(Agent).where(
                Agent.company_id == cid, Agent.username == agent_scope)).first():
            raise HTTPException(404, "الوكيل غير موجود في هذه الشركة")
    return cid, agent_scope


@router.get("", response_model=list[UserOut])
def list_users(db: Session = Depends(get_session)):
    return [_out(u) for u in db.exec(select(User)).all()]


@router.post("", response_model=UserOut)
def create_user(req: UserCreate, db: Session = Depends(get_session),
                identity: dict = Depends(current_identity)):
    # منع التصعيد الأفقي H2: مستخدم ذو نطاق لا ينشئ مستخدمين
    _deny_scoped_user(identity)
    if req.role not in _ROLES:
        raise HTTPException(400, f"دور غير صالح: {req.role}")
    username = req.username.strip()
    if not username or not req.password:
        raise HTTPException(400, "اسم المستخدم وكلمة المرور مطلوبان")

    # ── تحديد النطاق والتحقّق منه ──────────────────────────────────
    #   كلاهما فارغ → جهة رقابية · شركة فقط → مدير شركة · الاثنان → وكيل
    cid, agent_scope = _validate_scope(
        db, req.scope_company_id, req.scope_agent, req.role)
    # سياسة كلمة المرور: حساب ذو نطاق (شركة/وكيل) حساب تشغيلي حقيقي —
    # يتطلّب 8 محارف على الأقل، اتساقاً مع تزويد حساب الوكيل في مسار الشركة.
    if cid is not None and len(req.password) < 8:
        raise HTTPException(400, "كلمة المرور قصيرة — 8 محارف على الأقل")
    if agent_scope and db.exec(select(User).where(
            User.scope_company_id == cid,
            User.scope_agent == agent_scope)).first():
        raise HTTPException(409, "للوكيل حساب دخول مسبقاً")

    if db.exec(select(User).where(User.username == username)).first():
        raise HTTPException(400, "اسم المستخدم موجود مسبقاً")
    u = User(username=username, role=req.role,
             password_hash=security.hash_password(req.password),
             scope_company_id=cid, scope_agent=agent_scope, enabled=True)
    db.add(u)
    db.commit()
    db.refresh(u)
    return _out(u)


@router.patch("/{user_id}", response_model=UserOut)
def update_user(user_id: int, req: UserUpdate, db: Session = Depends(get_session),
                identity: dict = Depends(current_identity)):
    # منع التصعيد الأفقي H2
    _deny_scoped_user(identity)
    u = db.get(User, user_id)
    if not u:
        raise HTTPException(404, "المستخدم غير موجود")
    # تغيير اسم المستخدم (يُبطل توكنات هذا الحساب ⇒ يتطلّب إعادة دخوله)
    if req.username is not None:
        new_username = req.username.strip()
        if not new_username:
            raise HTTPException(400, "اسم المستخدم لا يمكن أن يكون فارغاً")
        if new_username != u.username and db.exec(select(User).where(
                User.username == new_username, User.id != user_id)).first():
            raise HTTPException(400, "اسم المستخدم موجود مسبقاً")
        u.username = new_username

    # حرّاس آخر مدير رقابي: الحساب الحاسم لإدارة المستخدمين هو المدير الرقابي
    # (admin بلا نطاق) — لأن المقيّد بشركة لا يمكنه إدارة المستخدمين أصلاً.
    # لذا نحمي «آخر مدير رقابي» عبر كل الأبعاد (دور/تفعيل/نطاق/حذف).
    is_reg_admin = u.scope_company_id is None and u.role == "admin"
    if req.role is not None:
        if req.role not in _ROLES:
            raise HTTPException(400, f"دور غير صالح: {req.role}")
        if (is_reg_admin and req.role != "admin"
                and _regulator_admin_count(db) <= 1):
            raise HTTPException(400, "لا يمكن إزالة آخر مدير رقابي")
        u.role = req.role
    if req.enabled is not None:
        if (is_reg_admin and not req.enabled
                and _regulator_admin_count(db) <= 1):
            raise HTTPException(400, "لا يمكن تعطيل آخر مدير رقابي")
        u.enabled = req.enabled
    if req.password:
        u.password_hash = security.hash_password(req.password)

    # ── تعديل النطاق (يُطبَّق فقط إن وُرِد أيّ من حقلَي النطاق صراحةً) ──
    fields = req.model_fields_set
    if "scope_company_id" in fields or "scope_agent" in fields:
        cid, agent_scope = _validate_scope(
            db, req.scope_company_id, req.scope_agent, u.role)
        # سياسة كلمة المرور: التحويل لنطاق مع كلمة مرور جديدة قصيرة → 400
        if cid is not None and req.password and len(req.password) < 8:
            raise HTTPException(400, "كلمة المرور قصيرة — 8 محارف على الأقل")
        # منع تقييد آخر مدير رقابي (وإلا انغلقت إدارة المستخدمين للأبد)
        if (is_reg_admin and cid is not None
                and _regulator_admin_count(db) <= 1):
            raise HTTPException(400, "لا يمكن تقييد آخر مدير رقابي بنطاق")
        # فريدة حساب الوكيل على النطاق (باستثناء الحساب نفسه)
        if agent_scope and db.exec(select(User).where(
                User.scope_company_id == cid,
                User.scope_agent == agent_scope,
                User.id != user_id)).first():
            raise HTTPException(409, "للوكيل حساب دخول مسبقاً")
        u.scope_company_id = cid
        u.scope_agent = agent_scope

    # ثابت لا يُنتهك: حساب الوكيل لا يكون admin (يحمي من تغيير الدور وحده)
    if u.scope_agent and u.role == "admin":
        raise HTTPException(400, "لا يُسمح بدور admin لحساب وكيل")

    db.add(u)
    db.commit()
    db.refresh(u)
    return _out(u)


@router.delete("/{user_id}")
def delete_user(user_id: int, db: Session = Depends(get_session),
                identity: dict = Depends(current_identity)):
    # منع التصعيد الأفقي H2
    _deny_scoped_user(identity)
    u = db.get(User, user_id)
    if not u:
        raise HTTPException(404, "المستخدم غير موجود")
    # منع حذف آخر مدير رقابي (يمنع قفل إدارة المستخدمين)
    if (u.scope_company_id is None and u.role == "admin"
            and _regulator_admin_count(db) <= 1):
        raise HTTPException(400, "لا يمكن حذف آخر مدير رقابي")
    db.delete(u)
    db.commit()
    return {"deleted": user_id}


def _regulator_admin_count(db: Session) -> int:
    """عدد المدراء الرقابيين المفعّلين (admin بلا نطاق) — حرّاس قفل الإدارة."""
    return len(db.exec(select(User).where(
        User.role == "admin", User.enabled == True,  # noqa: E712
        User.scope_company_id.is_(None))).all())
