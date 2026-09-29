"""
OTP واتساب لتطبيق المشتركين — تطبيع أرقام الهواتف العراقية، إصدار الرموز والتحقّق منها،
وإرسالها عبر بوابة واتساب (wa-gateway) المضبوطة في الإعدادات.

الرمز لا يُخزَّن نصّاً: نحفظ HMAC-SHA256(secret_key, phone + code) فقط.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import logging
import re
import secrets
from datetime import timedelta
from typing import Optional

import httpx
from sqlmodel import Session, select

from ..config import settings
from ..models import OtpCode, Subscriber, utcnow

_log = logging.getLogger(__name__)

# الأرقام العربية-الهندية → لاتينية (المستخدم قد يكتب ٠٧٧٠…)
_ARABIC_DIGITS = str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹", "01234567890123456789")


def normalize_phone(raw: str) -> str:
    """يُطبِّع رقم هاتف عراقي إلى الصيغة الدولية بلا «+»: 9647XXXXXXXXX.

    يقبل: 07701234567 · 7701234567 · +9647701234567 · 009647701234567 · 964 770 123 4567.
    يُرجع "" إن لم يكن الرقم عراقياً صالحاً (شبكة 7 + 9 أرقام).
    """
    if not raw:
        return ""
    s = raw.translate(_ARABIC_DIGITS)
    s = re.sub(r"\D", "", s)
    if s.startswith("00"):
        s = s[2:]
    if s.startswith("964"):
        s = s[3:]
    s = s.lstrip("0")
    # الجوال العراقي: يبدأ بـ 7 وطوله 10 أرقام (7XXXXXXXXX)
    if len(s) == 10 and s.startswith("7"):
        return "964" + s
    return ""


def phone_matches(stored: str, normalized: str) -> bool:
    """مطابقة رقم مخزَّن (بأي صيغة كتبته الشركة في SAS) مع رقم مطبَّع."""
    if not normalized:
        return False
    n = normalize_phone(stored)
    return n == normalized


def find_subscriber_accounts(db: Session, normalized: str) -> list[Subscriber]:
    """كل حسابات المشترك (قد يملك أكثر من اشتراك لدى أكثر من شركة) بحسب رقم الهاتف.

    المطابقة على العمود المطبَّع phone_norm (يُملأ عند مزامنة SAS) — استعلام مفهرس مباشر."""
    if not normalized:
        return []
    return list(db.exec(select(Subscriber).where(Subscriber.phone_norm == normalized)).all())


# ─────────────────────────────── الرموز ───────────────────────────────

def _hash(phone: str, code: str) -> str:
    return hmac.new(settings.secret_key.encode(), f"{phone}:{code}".encode(),
                    hashlib.sha256).hexdigest()


def _gen_code() -> str:
    n = max(4, min(settings.otp_length, 8))
    return "".join(secrets.choice("0123456789") for _ in range(n))


class OtpRateLimited(Exception):
    """تجاوز حدّ الإرسال داخل النافذة الزمنية."""


def issue_code(db: Session, phone: str) -> str:
    """يُصدر رمزاً جديداً للرقم (يُبطل السابق) ويُرجعه نصّاً كي يُرسَل.
    يرفع OtpRateLimited عند تجاوز الحدّ."""
    now = utcnow()
    window_start = now - timedelta(seconds=settings.otp_window_seconds)
    recent = db.exec(select(OtpCode).where(OtpCode.phone == phone,
                                           OtpCode.created_at >= window_start)).all()
    if len(recent) >= settings.otp_max_per_window:
        raise OtpRateLimited()
    # إبطال الرموز السابقة غير المستهلكة
    for old in db.exec(select(OtpCode).where(OtpCode.phone == phone,
                                             OtpCode.consumed == False)).all():  # noqa: E712
        old.consumed = True
        db.add(old)
    code = _gen_code()
    db.add(OtpCode(phone=phone, code_hash=_hash(phone, code),
                   expires_at=now + timedelta(seconds=settings.otp_ttl_seconds)))
    db.commit()
    return code


def verify_code(db: Session, phone: str, code: str) -> bool:
    """يتحقّق من الرمز؛ يستهلكه عند النجاح ويزيد عدّاد المحاولات عند الفشل."""
    row: Optional[OtpCode] = db.exec(
        select(OtpCode).where(OtpCode.phone == phone, OtpCode.consumed == False)  # noqa: E712
        .order_by(OtpCode.created_at.desc())  # type: ignore[attr-defined]
    ).first()
    if not row:
        return False
    now = utcnow()
    exp = row.expires_at if row.expires_at.tzinfo else row.expires_at.replace(tzinfo=now.tzinfo)
    if exp < now or row.attempts >= settings.otp_max_attempts:
        row.consumed = True
        db.add(row); db.commit()
        return False
    if hmac.compare_digest(row.code_hash, _hash(phone, code.strip())):
        row.consumed = True
        db.add(row); db.commit()
        return True
    row.attempts += 1
    if row.attempts >= settings.otp_max_attempts:
        row.consumed = True
    db.add(row); db.commit()
    return False


# ─────────────────────────────── الإرسال ───────────────────────────────

def otp_message(code: str) -> str:
    return (f"رمز الدخول إلى منصة العراق الرقمية: {code}\n"
            f"صالح لمدة {settings.otp_ttl_seconds // 60} دقائق. لا تشاركه مع أحد.")


def send_whatsapp(phone: str, message: str) -> bool:
    """يرسل رسالة عبر بوابة واتساب المضبوطة. يُرجع False (بلا استثناء) عند الفشل أو غياب الضبط."""
    url = settings.whatsapp_api_url.strip()
    if not url:
        _log.warning("[OTP] لا بوابة واتساب مضبوطة — لم يُرسَل الرمز إلى %s", phone[-4:])
        return False
    try:
        payload = json.loads(settings.whatsapp_payload_template
                             .replace("{phone}", phone)
                             .replace("{message}", json.dumps(message, ensure_ascii=False)[1:-1]))
    except json.JSONDecodeError:
        _log.error("[OTP] WHATSAPP_PAYLOAD_TEMPLATE ليس JSON صالحاً")
        return False
    headers = {"Content-Type": "application/json"}
    if settings.whatsapp_api_token:
        headers["Authorization"] = f"Bearer {settings.whatsapp_api_token}"
    try:
        r = httpx.post(url, json=payload, headers=headers, timeout=settings.whatsapp_timeout)
        if 200 <= r.status_code < 300:
            return True
        _log.warning("[OTP] بوابة واتساب أعادت %s", r.status_code)
    except httpx.HTTPError as e:
        _log.warning("[OTP] تعذّر الاتصال ببوابة واتساب: %s", e)
    return False
