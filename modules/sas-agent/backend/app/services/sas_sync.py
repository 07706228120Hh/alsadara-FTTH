"""
مزامنة الشركات عبر SAS.

لكل شركة مُفعَّلة:
  1. ملخّص المشتركين  (GET advancedDashboard/subscribers) → لقطة CompanySnapshot.
  2. الوكلاء          (POST index/manager) → upsert جدول Agent (مع users_count).
  3. الجلسات الحالية  (POST index/online) → حساب كشف الدمج → استبدال MergeFinding.

يعمل بجانب snmp_poll_loop في lifespan. مرجع الحقول: backend/knowledge/sas4_api_reference.md

يُوضع في backend/app/services/sas_sync.py
"""
from __future__ import annotations

import asyncio
import logging
from collections import defaultdict
from datetime import timedelta
from typing import Any, Dict, List, Optional

from sqlmodel import Session, delete, select

from ..config import settings
from .otp import normalize_phone as _normalize_phone
from ..database import engine
from ..models import (Company, CompanySnapshot, Agent, MergeFinding,
                      Subscriber, SasAccount, User, utcnow)
from ..core.security import decrypt
from ..integrations.sas_client import SASClient, SASError, is_cert_error

_log = logging.getLogger(__name__)


def _int(v, d: int = 0) -> int:
    try:
        return int(v)
    except (TypeError, ValueError):
        return d


def _nn(v, d: int = 0) -> int:
    """عدد غير سالب — بعض خوادم SAS تُرجع عدّادات سالبة خاطئة (مثل offline=-8)."""
    return max(0, _int(v, d))


def _float(v, d: float = 0.0) -> float:
    try:
        return float(v)
    except (TypeError, ValueError):
        return d


def _rows(res: Any) -> List[dict]:
    """يستخرج مصفوفة السجلّات من مغلّف SAS (data[]) أو من قائمة مباشرة."""
    if isinstance(res, dict):
        d = res.get("data", res)
        return d if isinstance(d, list) else []
    return res if isinstance(res, list) else []


# أسماء المحافظات المعروفة (لتطبيع مدينة SAS الحرّة إلى محافظة)
_GOV_NAMES = [
    "بغداد", "البصرة", "نينوى", "ذي قار", "النجف", "بابل", "كركوك", "الأنبار",
    "ديالى", "كربلاء", "صلاح الدين", "واسط", "القادسية", "ميسان", "المثنى",
    "دهوك", "أربيل", "السليمانية",
]


def _norm_gov(city: str) -> str:
    """يطابق مدينة SAS الحرّة بأقرب اسم محافظة معروف، وإلا 'أخرى'."""
    c = (city or "").strip()
    if not c:
        return "غير محدّد"
    for g in _GOV_NAMES:
        if g in c or c in g:
            return g
    return "أخرى"


# ─────────────────────── كشف الدمج من الجلسات الحالية ───────────────────────
def compute_merge_findings(company_id: int, sessions: List[dict]) -> List[MergeFinding]:
    """
    قواعد حتمية (كلها «مُحتمَل» لا حكم آلي — راجع مبادئ التصميم):
    - نفس المستخدم على أكثر من nasipaddress    → LOAD_BALANCING_SUSPECTED
    - نفس المستخدم بأكثر من framedipaddress     → BONDING_SUSPECTED
    - نفس callingstationid تحت أكثر من مستخدم   → SHARED_LINE_SUSPECTED (إعادة بيع/مشاركة)
    """
    findings: List[MergeFinding] = []

    by_user: Dict[str, List[dict]] = defaultdict(list)
    by_mac: Dict[str, set] = defaultdict(set)
    for s in sessions:
        u = str(s.get("username") or "").strip()
        if u:
            by_user[u].append(s)
        mac = str(s.get("callingstationid") or "").strip()
        if mac and u:
            by_mac[mac].add(u)

    for user, ss in by_user.items():
        nas = {str(s.get("nasipaddress") or "").strip() for s in ss if s.get("nasipaddress")}
        ips = {str(s.get("framedipaddress") or "").strip() for s in ss if s.get("framedipaddress")}
        if len(nas) > 1:
            findings.append(MergeFinding(
                company_id=company_id, username=user,
                kind="LOAD_BALANCING_SUSPECTED", severity="major",
                session_count=len(ss), nas_count=len(nas), ip_count=len(ips),
                detail=f"جلسات متزامنة على {len(nas)} أجهزة NAS: {', '.join(sorted(nas))}",
            ))
        elif len(ips) > 1:
            findings.append(MergeFinding(
                company_id=company_id, username=user,
                kind="BONDING_SUSPECTED", severity="warning",
                session_count=len(ss), nas_count=len(nas), ip_count=len(ips),
                detail=f"{len(ips)} عناوين IP متزامنة لنفس المستخدم: {', '.join(sorted(ips))}",
            ))

    for mac, users in by_mac.items():
        if len(users) > 1:
            findings.append(MergeFinding(
                company_id=company_id, username=", ".join(sorted(users)),
                kind="SHARED_LINE_SUSPECTED", severity="major",
                session_count=len(users), nas_count=0, ip_count=0,
                detail=f"نفس المعرّف (MAC={mac}) تحت {len(users)} مستخدمين — إعادة بيع/مشاركة محتملة",
            ))
    return findings


# ─────────────────────────── مزامنة شركة واحدة ───────────────────────────
async def _fetch_company(company: Company, verify: bool, heavy: bool = True) -> Dict[str, Any]:
    """يسحب الملخّص + الوكلاء (دائماً) + الجلسات/المشتركين (في الجولات الثقيلة فقط). يرمي عند الفشل."""
    password = decrypt(company.sas_password_enc)
    async with SASClient(company.sas_host, company.sas_username, password,
                         https=company.sas_https, verify_tls=verify) as sas:
        sres = await sas.dashboard_subscribers()
        summary = sres.get("data", sres) if isinstance(sres, dict) else {}
        # الوكلاء (أفضل-جهد): حساب وكيل/reseller قد يُمنع من سرد كل الوكلاء (403) —
        # لا نُفشل المزامنة كلّها؛ managers_ok=False يمنع حذف الوكلاء عند فشل السحب.
        managers_ok = True
        try:
            managers = _rows(await sas.managers_full(page=1, count=1000))
        except SASError as e:
            _log.warning("[SAS] تعذّر سحب الوكلاء للشركة %s (صلاحيات؟): %s", company.name, e)
            managers = []
            managers_ok = False
        # الجلسات والمشتركون = سحب ثقيل → في الجولات الثقيلة فقط (تدرّج يقلّل الحمل عند كثرة الشركات)
        sessions: List[dict] = []
        subscribers: List[dict] = []
        sessions_capped = False
        cap = settings.sas_session_cap
        if heavy:
            try:
                async for row in sas.iter_online(count=1000):
                    sessions.append(row)
                    if len(sessions) >= cap:        # سقف أمان
                        sessions_capped = True
                        _log.warning("[SAS] الشركة %s بلغت سقف الجلسات (%s) — كشف الدمج جزئي، لن يُستبدل", company.name, cap)
                        break
            except SASError as e:
                _log.warning("[SAS] تعذّر سحب الجلسات للشركة %s: %s", company.name, e)
            if settings.sas_sync_subscribers:
                try:
                    async for row in sas.iter_users(count=1000):
                        subscribers.append(row)
                        if len(subscribers) >= settings.sas_subscriber_cap:
                            break
                except SASError as e:
                    _log.warning("[SAS] تعذّر سحب المشتركين للشركة %s: %s", company.name, e)
    return {"summary": summary, "managers": managers, "managers_ok": managers_ok,
            "sessions": sessions, "sessions_capped": sessions_capped,
            "subscribers": subscribers, "heavy": heavy}


def _apply(db: Session, company: Company, data: Dict[str, Any]) -> CompanySnapshot:
    """يكتب اللقطة + يحدّث الوكلاء (upsert) + يستبدل نتائج كشف الدمج. لا يلمس الشبكة."""
    s = data["summary"] or {}
    snap = CompanySnapshot(
        company_id=company.id,
        total=_nn(s.get("total")), active=_nn(s.get("active")),
        expired=_nn(s.get("expired")), online=_nn(s.get("online")),
        offline=_nn(s.get("offline")), expiring_today=_nn(s.get("expiring_today")),
        expiring_soon=_nn(s.get("expiring_soon")), fup=_nn(s.get("fup")),
        managers=_nn(s.get("managers")),
    )
    db.add(snap)

    # --- الوكلاء: upsert على (company_id, manager_id) ---
    existing = {a.manager_id: a for a in db.exec(
        select(Agent).where(Agent.company_id == company.id)).all()}
    seen = set()
    for m in data["managers"]:
        mid = _int(m.get("id"))
        if not mid:
            continue
        seen.add(mid)
        a = existing.get(mid) or Agent(company_id=company.id, manager_id=mid)
        a.username = str(m.get("username") or "")
        a.firstname = str(m.get("firstname") or "")
        a.lastname = str(m.get("lastname") or "")
        a.parent_id = _int(m.get("parent_id")) or None
        pd = m.get("parent_details") or {}
        a.parent_username = str((pd or {}).get("username") or "") if isinstance(pd, dict) else ""
        a.users_count = _int(m.get("users_count"))
        a.balance = _float(m.get("balance"))
        a.reward_points = _float(m.get("reward_points"))
        a.discount_rate = _float(m.get("discount_rate"))
        a.enabled = bool(m.get("enabled", True))
        a.updated_at = utcnow()
        db.add(a)
    # حذف الوكلاء الأيتام — فقط عند نجاح سحب الوكلاء (خطأ 403 عابر يجب ألا يمحو الجدول)
    if data.get("managers_ok", True):
        for mid, a in existing.items():
            if mid not in seen:
                db.delete(a)

    # --- كشف الدمج: استبدال كامل — في الجولات الثقيلة فقط، وما لم تُقطع الجلسات بالسقف ---
    # (استبدال نتائج كاملة بأخرى مبتورة قد يُخفي دمجاً حقيقياً — نُبقي الأخيرة الكاملة)
    heavy = data.get("heavy", True)
    if heavy and not data.get("sessions_capped", False):
        db.exec(delete(MergeFinding).where(MergeFinding.company_id == company.id))
        for f in compute_merge_findings(company.id, data["sessions"]):
            db.add(f)

    # --- المشتركون: upsert على (company_id, sub_id) — في الجولات الثقيلة فقط ---
    subs = data.get("subscribers") or []
    if heavy and settings.sas_sync_subscribers:
        existing_s = {s.sub_id: s for s in db.exec(
            select(Subscriber).where(Subscriber.company_id == company.id)).all()}
        seen_s = set()
        for u in subs:
            uid = _int(u.get("id"))
            if not uid:
                continue
            seen_s.add(uid)
            s = existing_s.get(uid) or Subscriber(company_id=company.id, sub_id=uid)
            s.username = str(u.get("username") or "")
            s.firstname = str(u.get("firstname") or "")
            s.lastname = str(u.get("lastname") or "")
            s.agent_username = str(u.get("parent_username") or "")
            s.profile_id = _int(u.get("profile_id")) or None
            pdet = u.get("profile_details") or {}
            s.profile_name = str((pdet or {}).get("name") or "") if isinstance(pdet, dict) else ""
            # حالة SAS تأتي ككائن {status, traffic, expiration, uptime} — نستخرج العلم الرئيسي
            _st = u.get("status")
            if isinstance(_st, dict):
                s.status = "active" if _st.get("status") else "expired"
            else:
                s.status = "active" if str(_st or "").strip().lower() in ("active", "1", "true") else "expired"
            s.online = str(u.get("online_status") or "").lower() in ("online", "1", "true")
            s.enabled = bool(u.get("enabled", True))
            s.expiration = str(u.get("expiration") or "")
            s.city = str(u.get("city") or "")
            s.governorate = _norm_gov(s.city)
            s.phone = str(u.get("phone") or "")
            s.phone_norm = _normalize_phone(s.phone)
            s.updated_at = utcnow()
            db.add(s)
        # حذف من لم يعد موجوداً (فقط عند سحب فعلي غير مقطوع بالسقف)
        if len(subs) < settings.sas_subscriber_cap:
            for uid, s in existing_s.items():
                if uid not in seen_s:
                    db.delete(s)

    return snap


async def sync_one(company_id: int, heavy: bool = True) -> Optional[CompanySnapshot]:
    """مزامنة شركة (ملخّص + وكلاء دائماً؛ جلسات/مشتركون عند heavy). يحفظ ويحدّث الحالة."""
    with Session(engine) as db:
        company = db.get(Company, company_id)
        if not company:
            return None
    timeout = settings.sas_company_timeout          # ميزانية زمنية لكل شركة (لا تعلق الجولة)
    healed = False
    try:
        try:
            data = await asyncio.wait_for(
                _fetch_company(company, company.sas_verify_tls, heavy), timeout)
        except Exception as e:                         # noqa: BLE001
            if company.sas_verify_tls and is_cert_error(e):   # شهادة ذاتية → أعِد بلا تحقّق
                _log.warning("[SAS] شهادة ذاتية للشركة %s — إعادة المحاولة بلا تحقّق TLS", company.name)
                data = await asyncio.wait_for(
                    _fetch_company(company, False, heavy), timeout)
                healed = True
            else:
                raise
    except Exception as e:                             # noqa: BLE001
        with Session(engine) as db:
            c = db.get(Company, company_id)
            if c:                                      # قد تُحذف الشركة أثناء نافذة المزامنة
                c.last_sync_ok = False
                c.last_sync_error = str(e)[:500]
                c.last_sync_at = utcnow()
                db.add(c)
                db.commit()
        _log.warning("[SAS] فشلت مزامنة الشركة %s: %s", company.name, e)
        return None

    with Session(engine) as db:
        c = db.get(Company, company_id)
        if not c:                          # حُذفت الشركة أثناء المزامنة
            return None
        if healed:                         # لا نُثبّت الإطفاء (نحترم إعداد المستخدم) — تسجيل فقط
            _log.info("[SAS] الشركة %s: نجحت بتجاوز تحقّق الشهادة مؤقتاً (الإعداد المحفوظ دون تغيير)", company.name)
        snap = _apply(db, c, data)
        c.last_sync_ok = True
        c.last_sync_error = ""
        c.last_sync_at = utcnow()
        db.add(c)
        db.commit()
        db.refresh(snap)
        return snap


async def sync_all_once(heavy: bool = True) -> dict:
    """جولة مزامنة على كل الشركات المُفعَّلة — بالتوازي (semaphore) لتصمد لعشرات الشركات."""
    with Session(engine) as db:
        # الشركات المُفعَّلة التي ضبطت اتصال SAS فقط — نتخطّى غير المُهيّأة (sas_host فارغ)
        # كي لا تُغرِق السجلّ بأخطاء «URL بلا بروتوكول».
        ids = [c.id for c in db.exec(
            select(Company).where(Company.enabled == True)              # noqa: E712
            .where(Company.sas_host != "")).all()]
    sem = asyncio.Semaphore(max(1, settings.sas_sync_concurrency))

    async def _one(cid: int):
        async with sem:
            return await sync_one(cid, heavy)

    results = await asyncio.gather(*[_one(cid) for cid in ids], return_exceptions=True)
    ok = sum(1 for r in results if r and not isinstance(r, Exception))
    return {"companies": len(ids), "ok": ok, "failed": len(ids) - ok, "heavy": heavy}


# ─────────────────── مزامنة وكيل مستقل (خادم SAS الخاص به) ───────────────────
# الوكيل يُدخل خادمه واسم مستخدمه وكلمة مروره، فتُخزَّن على صفّ User (لا Company).
# حلقة sync_all_once تزامن الشركات فقط، لذا نحتاج مساراً منفصلاً يستخدم اعتماد الوكيل.
# الخادم مُنطاق بدخول الوكيل (يُرجع مشتركي هذا المدير فقط)، فنثبّت agent_username=scope_agent
# كي تُطابق فلترة list_subscribers ولا نعتمد على parent_username (قد يكون فارغاً/محجوباً).

async def _fetch_agent_users(host: str, username: str, password: str,
                             https: bool, verify: bool) -> List[dict]:
    """يسحب مشتركي الوكيل من خادمه الخاص (اعتماده هو). يرمي عند الفشل."""
    rows: List[dict] = []
    async with SASClient(host, username, password, https=https, verify_tls=verify) as sas:
        async for row in sas.iter_users(count=1000):
            rows.append(row)
            if len(rows) >= settings.sas_subscriber_cap:
                break
    return rows


def ensure_agent_accounts(db: Session, user: User) -> List[SasAccount]:
    """يُرجع حسابات SAS التابعة للوكيل — مع **ترحيل تلقائي** للحساب المفرد القديم.

    إن لم يكن للوكيل أي صفّ SasAccount لكن لديه اعتماد قديم على User.sas_* → يُنشأ
    منه حساب أساسي، وتُتبنّى مشتركوه القدامى (sas_account_id فارغ) لهذا الحساب كي يبقى
    مفتاح المزامنة (sas_account_id, sub_id) نظيفاً. idempotent — يُستدعى بأمان مراراً."""
    accounts = list(db.exec(
        select(SasAccount).where(SasAccount.owner_user_id == user.id)).all())
    if accounts:
        return accounts
    if user.sas_host and user.sas_username and user.sas_password_enc:
        acc = SasAccount(
            owner_user_id=user.id,
            company_id=user.scope_company_id,
            label="الحساب الأساسي",
            sas_host=user.sas_host, sas_https=user.sas_https,
            sas_verify_tls=user.sas_verify_tls,
            sas_username=user.sas_username,
            sas_password_enc=user.sas_password_enc,
            enabled=True,
        )
        db.add(acc)
        db.commit()
        db.refresh(acc)
        # تبنّي مشتركي الوكيل القدامى (بلا حساب) لهذا الحساب الأساسي
        orphans = db.exec(select(Subscriber).where(
            Subscriber.company_id == user.scope_company_id,
            Subscriber.agent_username == user.scope_agent,
            Subscriber.sas_account_id.is_(None))).all()
        for s in orphans:
            s.sas_account_id = acc.id
            db.add(s)
        if orphans:
            db.commit()
        return [acc]
    return []


def _apply_account_subs(db: Session, account: SasAccount, subs: List[dict]) -> int:
    """upsert مشتركي **حساب SAS واحد** محلياً — معزول على sas_account_id.
    المفتاح (sas_account_id, sub_id)؛ الحذف مقيّد بهذا الحساب فقط (لا يلمس حسابات أخرى
    للوكيل نفسه). agent_username يبقى نطاق الوكيل كي يعمل العرض المدموج عبر كل حساباته."""
    owner = db.get(User, account.owner_user_id)
    cid = account.company_id if account.company_id is not None else (owner.scope_company_id if owner else None)
    agent_uname = owner.scope_agent if owner else ""
    existing_s = {s.sub_id: s for s in db.exec(
        select(Subscriber).where(Subscriber.sas_account_id == account.id)).all()}
    seen_s: set = set()
    for u in subs:
        uid = _int(u.get("id"))
        if not uid:
            continue
        seen_s.add(uid)
        s = existing_s.get(uid) or Subscriber(company_id=cid, sub_id=uid, sas_account_id=account.id)
        s.company_id = cid
        s.sas_account_id = account.id
        s.username = str(u.get("username") or "")
        s.firstname = str(u.get("firstname") or "")
        s.lastname = str(u.get("lastname") or "")
        s.agent_username = agent_uname          # نطاق الوكيل (يشترك فيه كل حساباته → عرض مدموج)
        s.profile_id = _int(u.get("profile_id")) or None
        pdet = u.get("profile_details") or {}
        s.profile_name = str((pdet or {}).get("name") or "") if isinstance(pdet, dict) else ""
        _st = u.get("status")
        if isinstance(_st, dict):
            s.status = "active" if _st.get("status") else "expired"
        else:
            s.status = "active" if str(_st or "").strip().lower() in ("active", "1", "true") else "expired"
        s.online = str(u.get("online_status") or "").lower() in ("online", "1", "true")
        s.enabled = bool(u.get("enabled", True))
        s.expiration = str(u.get("expiration") or "")
        s.city = str(u.get("city") or "")
        s.governorate = _norm_gov(s.city)
        s.phone = str(u.get("phone") or "")
        s.phone_norm = _normalize_phone(s.phone)
        s.updated_at = utcnow()
        db.add(s)
    if len(subs) < settings.sas_subscriber_cap:     # سحب كامل غير مقطوع بالسقف → آمن للحذف
        for uid, s in existing_s.items():
            if uid not in seen_s:
                db.delete(s)
    return len(seen_s)


async def sync_account(account_id: int) -> dict:
    """مزامنة مشتركي **حساب SAS واحد** من خادمه إلى القاعدة المحلية (وسمهم بـ sas_account_id).
    يحدّث حالة المزامنة على صفّ الحساب. أفضل-جهد: يُرجع {ok,error/count} ولا يرمي."""
    with Session(engine) as db:
        acc = db.get(SasAccount, account_id)
        if not acc or not acc.enabled:
            return {"ok": False, "error": "الحساب غير موجود أو معطّل"}
        if not (acc.sas_host and acc.sas_username and acc.sas_password_enc):
            return {"ok": False, "error": "الحساب لم يُضبط بالكامل (الخادم + المستخدم + كلمة المرور)"}
        host, uname = acc.sas_host, acc.sas_username
        password = decrypt(acc.sas_password_enc)
        https, verify = acc.sas_https, acc.sas_verify_tls
    timeout = settings.sas_company_timeout
    try:
        try:
            rows = await asyncio.wait_for(_fetch_agent_users(host, uname, password, https, verify), timeout)
        except Exception as e:                          # noqa: BLE001
            if verify and is_cert_error(e):             # شهادة ذاتية → أعِد بلا تحقّق
                rows = await asyncio.wait_for(_fetch_agent_users(host, uname, password, https, False), timeout)
            else:
                raise
    except Exception as e:                              # noqa: BLE001
        with Session(engine) as db:
            acc = db.get(SasAccount, account_id)
            if acc:
                acc.last_sync_ok = False
                acc.last_sync_error = str(e)[:300]
                acc.last_sync_at = utcnow()
                db.add(acc)
                db.commit()
        _log.warning("[SAS] فشلت مزامنة حساب SAS %s: %s", uname, e)
        return {"ok": False, "error": str(e)[:300]}
    with Session(engine) as db:
        acc = db.get(SasAccount, account_id)
        if not acc:
            return {"ok": False, "error": "حُذف الحساب أثناء المزامنة"}
        count = _apply_account_subs(db, acc, rows)
        acc.last_sync_ok = True
        acc.last_sync_error = ""
        acc.last_sync_at = utcnow()
        db.add(acc)
        db.commit()
    return {"ok": True, "count": count}


async def sync_agent(user_id: int) -> dict:
    """مزامنة **كل حسابات SAS** التابعة للوكيل (مع ترحيل الحساب المفرد القديم تلقائياً).
    تُستدعى عند حفظ حساب (حفظ محلي فوري) ودورياً. أفضل-جهد: تُرجع {ok,count,accounts}."""
    with Session(engine) as db:
        user = db.get(User, user_id)
        if not user:
            return {"ok": False, "error": "الحساب غير موجود"}
        if not user.scope_company_id:
            return {"ok": False, "error": "حساب الوكيل بلا شركة/مزوّد"}
        accounts = ensure_agent_accounts(db, user)
        account_ids = [a.id for a in accounts
                       if a.enabled and a.sas_host and a.sas_username and a.sas_password_enc]
    if not account_ids:
        return {"ok": False, "error": "الوكيل لم يضبط أي حساب SAS بالكامل"}
    results: List[dict] = []
    total = 0
    for aid in account_ids:                 # تسلسلي لكل حسابات الوكيل (عددها صغير عادةً)
        r = await sync_account(aid)
        results.append({"account_id": aid, **r})
        if r.get("ok"):
            total += int(r.get("count", 0))
    return {"ok": any(r.get("ok") for r in results), "count": total, "accounts": results}


async def sync_all_agents_once() -> dict:
    """جولة مزامنة لكل الوكلاء الذين يملكون حساب SAS مضبوطاً — بالتوازي.
    يشمل ملّاك حسابات SasAccount المفعّلة + وكلاء الحساب المفرد القديم (لترحيلهم)."""
    with Session(engine) as db:
        owner_ids = {a.owner_user_id for a in db.exec(
            select(SasAccount).where(SasAccount.enabled == True)         # noqa: E712
            .where(SasAccount.sas_host != "").where(SasAccount.sas_username != "")
            .where(SasAccount.sas_password_enc != "")).all()}
        legacy_ids = {u.id for u in db.exec(
            select(User).where(User.enabled == True)                     # noqa: E712
            .where(User.scope_agent != "")
            .where(User.sas_host != "").where(User.sas_username != "")
            .where(User.sas_password_enc != "")).all()}
        ids = list(owner_ids | legacy_ids)
    if not ids:
        return {"agents": 0, "ok": 0, "failed": 0}
    sem = asyncio.Semaphore(max(1, settings.sas_sync_concurrency))

    async def _one(uid: int):
        async with sem:
            return await sync_agent(uid)

    results = await asyncio.gather(*[_one(uid) for uid in ids], return_exceptions=True)
    ok = sum(1 for r in results if isinstance(r, dict) and r.get("ok"))
    return {"agents": len(ids), "ok": ok, "failed": len(ids) - ok}


def purge_old_snapshots() -> int:
    """حذف لقطات الشركات الأقدم من company_snapshot_retention_days (كي لا تنمو بلا حدّ)."""
    days = settings.company_snapshot_retention_days
    if days <= 0:
        return 0
    cutoff = utcnow() - timedelta(days=days)
    with Session(engine) as db:
        res = db.exec(delete(CompanySnapshot).where(CompanySnapshot.ts < cutoff))
        db.commit()
        return getattr(res, "rowcount", 0) or 0


async def sas_sync_loop():
    interval = settings.sas_sync_interval
    heavy_every = max(1, settings.sas_heavy_every)
    _log.info("[SAS] بدء حلقة المزامنة كل %ss (جولة ثقيلة كل %s)", interval, heavy_every)
    round_no = 0
    while True:
        try:
            heavy = (round_no % heavy_every == 0)     # أول جولة ثقيلة، ثم كل heavy_every
            _log.info("[SAS] جولة مزامنة (heavy=%s): %s", heavy, await sync_all_once(heavy))
            if heavy:
                _log.info("[SAS] جولة مزامنة الوكلاء المستقلين: %s", await sync_all_agents_once())
                purged = purge_old_snapshots()
                if purged:
                    _log.info("[SAS] حُذفت %s لقطة قديمة", purged)
        except asyncio.CancelledError:
            raise
        except Exception as e:   # noqa: BLE001
            _log.error("[SAS] خطأ في حلقة المزامنة: %s", e)
        round_no += 1
        await asyncio.sleep(interval)
