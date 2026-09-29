"""تشفير كلمات مرور الأجهزة + تجزئة كلمات مرور المستخدمين + توكنات الجلسة"""
import base64
import hashlib
import hmac
import json
import os
from typing import Optional
from cryptography.fernet import Fernet
from ..config import settings


def _key() -> bytes:
    # اشتقاق مفتاح Fernet ثابت من SECRET_KEY
    digest = hashlib.sha256(settings.secret_key.encode()).digest()
    return base64.urlsafe_b64encode(digest)


_fernet = Fernet(_key())


def encrypt(plain: str) -> str:
    if not plain:
        return ""
    return _fernet.encrypt(plain.encode()).decode()


def decrypt(token: str) -> str:
    if not token:
        return ""
    try:
        return _fernet.decrypt(token.encode()).decode()
    except Exception:
        return ""


# ---------------------------------------------------------------------------
# تجزئة كلمات مرور المستخدمين (PBKDF2-SHA256 من المكتبة القياسية — دون اعتمادات إضافية)
# ---------------------------------------------------------------------------
_PBKDF2_ROUNDS = 200_000


def hash_password(password: str) -> str:
    """يُنتج تجزئة مُملّحة قابلة للتخزين: pbkdf2_sha256$rounds$salt$hash."""
    salt = os.urandom(16)
    dk = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, _PBKDF2_ROUNDS)
    return (f"pbkdf2_sha256${_PBKDF2_ROUNDS}$"
            f"{base64.b64encode(salt).decode()}${base64.b64encode(dk).decode()}")


def verify_password(password: str, stored: str) -> bool:
    """تحقّق كلمة مرور مقابل تجزئة مخزّنة (مقارنة زمن ثابت)."""
    try:
        _algo, rounds, salt_b64, hash_b64 = stored.split("$")
        salt = base64.b64decode(salt_b64)
        expected = base64.b64decode(hash_b64)
        dk = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, int(rounds))
        return hmac.compare_digest(dk, expected)
    except Exception:
        return False


# ---------------------------------------------------------------------------
# توكنات جلسة المستخدم (Fernet — يحمل الطابع الزمني، فتُفرض الصلاحية عبر ttl)
# ---------------------------------------------------------------------------

def make_user_token(username: str, role: str) -> str:
    """يُنتج توكن جلسة مشفّراً للمستخدم."""
    payload = json.dumps({"u": username, "r": role}).encode()
    return _fernet.encrypt(payload).decode()


def read_user_token(token: str, ttl_seconds: int) -> Optional[dict]:
    """يفكّ توكن الجلسة ويتحقّق من عدم انتهائه؛ يُرجع {u, r} أو None."""
    if not token:
        return None
    try:
        raw = _fernet.decrypt(token.encode(), ttl=ttl_seconds)
        data = json.loads(raw.decode())
        if isinstance(data, dict) and "u" in data and "r" in data:
            return data
    except Exception:
        pass
    return None


# ---------------------------------------------------------------------------
# توكنات جلسة المشترك (تطبيق المشتركين — دخول برقم الهاتف + OTP واتساب)
# الحمولة {"p": phone, "r": "subscriber"} — منفصلة عن توكنات الموظّفين ({"u","r"}).
# ---------------------------------------------------------------------------

def make_subscriber_token(phone: str) -> str:
    """يُنتج توكن جلسة مشترك مرتبطاً برقم هاتف مطبَّع."""
    payload = json.dumps({"p": phone, "r": "subscriber"}).encode()
    return _fernet.encrypt(payload).decode()


def read_subscriber_token(token: str, ttl_seconds: int) -> Optional[str]:
    """يفكّ توكن المشترك ويُرجع رقم الهاتف أو None (منتهٍ/غير صالح/ليس توكن مشترك)."""
    if not token:
        return None
    try:
        raw = _fernet.decrypt(token.encode(), ttl=ttl_seconds)
        data = json.loads(raw.decode())
        if isinstance(data, dict) and data.get("r") == "subscriber" and data.get("p"):
            return str(data["p"])
    except Exception:
        pass
    return None
