"""
عميل SAS4 (Snono Systems) — الاتصال بواجهة API الإدارية لنسخة ساس تابعة لشركة.

المرجع الكامل لكل نقاط النهاية والحقول: backend/knowledge/sas4_api_reference.md

آلية SAS4 (مطابقة لما يفعله لوحة الإدارة نفسها ولمكتبة sasconnector-php):
  - القاعدة:      http(s)://<host>/admin/api/index.php/api/<route>
  - تسجيل الدخول: POST login  → {"token": "..."}   ثم Authorization: Bearer <token>
  - الحمولة:      كل POST يُرسل {"payload": <AES>} حيث AES = OpenSSL aes-256-cbc
                  بصيغة "Salted__" + salt(8) + ciphertext، والمفتاح/IV مشتقّان من
                  عبارة المرور الثابتة عبر EVP_BytesToKey(MD5) — نفس ما يستخدمه SAS4.

الاستخدام:
    async with SASClient("sas.company.iq", "admin", "secret") as sas:
        users = await sas.list("user", page=1, count=100)

يُوضع في backend/app/integrations/sas_client.py
"""
from __future__ import annotations

import asyncio
import base64
import re
import contextlib
import hashlib
import json
import os
import ssl
from typing import Any, Dict, Optional

import httpx
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

# عبارة المرور الثابتة التي تستخدمها لوحة SAS4 لتشفير الحمولة (ليست سرّاً — مضمّنة في الواجهة)
SAS_PAYLOAD_PASSPHRASE = b"abcdefghijuklmno0123456789012345"


# ─────────────────────────── التشفير المتوافق مع OpenSSL ───────────────────────────
def _evp_bytes_to_key(passphrase: bytes, salt: bytes, key_len: int = 32, iv_len: int = 16):
    """اشتقاق مفتاح وIV بطريقة OpenSSL القديمة (MD5 متسلسل) — مطابق لـ evpkdf في PHP."""
    derived = b""
    block = b""
    while len(derived) < key_len + iv_len:
        block = hashlib.md5(block + passphrase + salt).digest()
        derived += block
    return derived[:key_len], derived[key_len:key_len + iv_len]


def sas_encrypt(plaintext: str, passphrase: bytes = SAS_PAYLOAD_PASSPHRASE) -> str:
    salt = os.urandom(8)
    key, iv = _evp_bytes_to_key(passphrase, salt)
    padder = padding.PKCS7(128).padder()
    data = padder.update(plaintext.encode("utf-8")) + padder.finalize()
    enc = Cipher(algorithms.AES(key), modes.CBC(iv)).encryptor()
    ct = enc.update(data) + enc.finalize()
    return base64.b64encode(b"Salted__" + salt + ct).decode("ascii")


def sas_decrypt(b64: str, passphrase: bytes = SAS_PAYLOAD_PASSPHRASE) -> str:
    raw = base64.b64decode(b64)
    if raw[:8] != b"Salted__":
        raise ValueError("ليست حمولة OpenSSL صالحة (Salted__ مفقود)")
    salt, ct = raw[8:16], raw[16:]
    key, iv = _evp_bytes_to_key(passphrase, salt)
    dec = Cipher(algorithms.AES(key), modes.CBC(iv)).decryptor()
    padded = dec.update(ct) + dec.finalize()
    unpadder = padding.PKCS7(128).unpadder()
    return (unpadder.update(padded) + unpadder.finalize()).decode("utf-8")


# ─────────────────────────────────── العميل ───────────────────────────────────
class SASError(RuntimeError):
    pass


def is_cert_error(exc: BaseException) -> bool:
    """هل الاستثناء بسبب فشل التحقّق من شهادة TLS (شهادة ذاتية التوقيع)؟
    يفحص نوع ssl (والسبب الملفوف من httpx) ثم يرجع لمطابقة نصّية احتياطية."""
    cur: Optional[BaseException] = exc
    for _ in range(5):                     # httpx يلفّ استثناء ssl في __cause__/__context__
        if isinstance(cur, ssl.SSLCertVerificationError):
            return True
        cur = getattr(cur, "__cause__", None) or getattr(cur, "__context__", None)
        if cur is None:
            break
    s = str(exc).lower()
    return ("certificate_verify_failed" in s or "self-signed certificate" in s
            or "self signed certificate" in s or "certificate verify failed" in s)


class SASClient:
    def __init__(self, host: str, username: str, password: str, *,
                 https: bool = False, timeout: float = 20.0, verify_tls: bool = True,
                 transport: Optional[httpx.BaseTransport] = None):
        # transport: مقبس اختبار — يُمرَّر httpx.MockTransport لمحاكاة خادم SAS بلا شبكة.
        # تطبيع العنوان: يقبل host فقط أو رابطاً كاملاً ملصوقاً (https://host/... )
        raw = (host or "").strip()
        forced_https = raw.lower().startswith("https://")
        raw = re.sub(r"^https?://", "", raw)          # إزالة البروتوكول إن وُجد
        raw = raw.split("/")[0]                          # إبقاء المضيف (والمنفذ) فقط
        raw = raw.rstrip(":/").strip()                   # إزالة ":" أو "/" زائدة
        scheme = "https" if (https or forced_https) else "http"
        self.base_url = f"{scheme}://{raw}/admin/api/index.php/api/"
        self.username = username
        self.password = password
        self._token: Optional[str] = None
        self._http = httpx.AsyncClient(timeout=timeout, verify=verify_tls, transport=transport)

    async def __aenter__(self) -> "SASClient":
        await self.login()
        return self

    async def __aexit__(self, *exc) -> None:
        # إغلاق يصمد للإلغاء (عند asyncio.wait_for timeout) كي لا يتسرّب اتصال TCP.
        with contextlib.suppress(Exception):
            await asyncio.shield(self._http.aclose())

    # ── الأساسيات ──
    def _headers(self) -> Dict[str, str]:
        # رؤوس شبيهة بالمتصفّح: بعض نقاط SAS4 (مثل user/traffic) تحرسها لارافيل بـ
        # X-Requested-With وتُرجع 200 بجسم فارغ بدونها. Origin/Referer من أصل اللوحة.
        origin = self.base_url.split("/admin/", 1)[0]
        h = {
            "Accept": "application/json",
            "X-Requested-With": "XMLHttpRequest",
            "Origin": origin,
            "Referer": origin + "/admin/",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Sadara-SAS-Agent",
        }
        if self._token:
            h["Authorization"] = f"Bearer {self._token}"
        return h

    async def post(self, route: str, payload: Optional[Dict[str, Any]] = None) -> Any:
        body = {"payload": sas_encrypt(json.dumps(payload or {}, ensure_ascii=False))}
        r = await self._http.post(self.base_url + route, json=body, headers=self._headers())
        return self._unwrap(r, route)

    async def get(self, route: str, params: Optional[Dict[str, Any]] = None) -> Any:
        r = await self._http.get(self.base_url + route, params=params, headers=self._headers())
        return self._unwrap(r, route)

    async def delete(self, route: str) -> Any:
        r = await self._http.delete(self.base_url + route, headers=self._headers())
        return self._unwrap(r, route)

    @staticmethod
    def _unwrap(r: httpx.Response, route: str) -> Any:
        if r.status_code == 401:
            raise SASError(f"SAS رفض المصادقة على {route} (401) — انتهى التوكن أو بيانات الدخول خاطئة")
        if r.status_code == 404:
            raise SASError(
                f"SAS أعاد 404 على {route} — المسار غير موجود على هذا المضيف؛ "
                "تأكّد أن عنوان لوحة SAS صحيح (المضيف/البروتوكول) وأن الواجهة الإدارية عليه")
        # لا تُغرِق رسالة الخطأ بصفحة HTML (nginx/تحويل) — لخّصها
        def _snip(txt: str) -> str:
            t = (txt or "").strip()
            return "استجابة HTML (صفحة خطأ/تحويل — تحقّق من العنوان)" if t[:1] == "<" else t[:200]
        if r.status_code >= 400:
            raise SASError(f"SAS أعاد {r.status_code} على {route}: {_snip(r.text)}")
        try:
            return r.json()
        except ValueError:
            # تشخيص: اكشف لماذا فشل التحليل (نوع المحتوى/الترميز/الطول/أوّل البايتات).
            ct = r.headers.get("content-type", "")
            ce = r.headers.get("content-encoding", "")
            raw = bytes(r.content[:160])
            raise SASError(
                f"استجابة غير JSON من {route} "
                f"(ct={ct}; ce={ce}; len={len(r.content)}; raw={raw!r})")

    async def login(self) -> str:
        data = await self.post("login", {"username": self.username, "password": self.password})
        token = data.get("token") if isinstance(data, dict) else None
        if not token:
            raise SASError(f"تسجيل الدخول لم يُرجع توكناً: {data}")
        self._token = token
        return token

    # ── قوائم SAS4 (كل شاشة في لوحة SAS تستدعي index/<entity> بنفس معاملات الترقيم) ──
    async def list(self, entity: str, *, page: int = 1, count: int = 100,
                   sort_by: str = "id", direction: str = "asc",
                   search: str = "", **extra) -> Any:
        payload = {"page": page, "count": count, "sortBy": sort_by,
                   "direction": direction, "search": search, **extra}
        return await self.post(f"index/{entity}", payload)

    async def iter_all(self, entity: str, *, count: int = 200, **extra):
        """مولّد يمرّ على كل الصفحات. SAS4 يعيد {"data": [...], "total": N} عادةً."""
        page = 1
        while True:
            res = await self.list(entity, page=page, count=count, **extra)
            rows = res.get("data", res) if isinstance(res, dict) else res
            if not rows:
                return
            for row in rows:
                yield row
            total = res.get("total") if isinstance(res, dict) else None
            if total is not None and page * count >= int(total):
                return
            if len(rows) < count:
                return
            page += 1

    # ── اختصارات مؤكَّدة حيّاً على SAS4 v4.59.1 (demo4.sasradius.com) ──
    # المشتركون: POST index/user (قائمة بترقيم) — الحقول: id, username, firstname,
    # lastname, expiration, parent (الوكيل @), profile, balance, company, last_online,
    # city, static_ip, group, remaining_days.
    async def users(self, **kw):
        return await self.list("user", **kw)

    async def iter_users(self, *, count: int = 500):
        async for row in self.iter_all("user", count=count):
            yield row

    # الوكلاء/المدراء (Resellers): GET index/manager — الحقول: id, username,
    # firstname, lastname (شجرة الملكية عبر GET manager/tree).
    async def managers(self) -> Any:
        return await self.get("index/manager")

    async def manager_tree(self) -> Any:
        return await self.get("manager/tree")

    # القائمة الكاملة للوكلاء (POST index/manager) — تحمل users_count/balance/reward_points.
    # الحقول: id, username, firstname, lastname, city, phone, acl_group_id, balance,
    # parent_id, enabled, reward_points, created_at, discount_rate, users_count.
    async def managers_full(self, *, page: int = 1, count: int = 500, **extra) -> Any:
        return await self.list("manager", page=page, count=count, **extra)

    async def iter_managers(self, *, count: int = 500):
        async for row in self.iter_all("manager", count=count):
            yield row

    # الجلسات الحالية (POST index/online) — حقول RADIUS accounting لكشف الدمج:
    # radacctid, nasipaddress, framedipaddress, callingstationid, acctsessiontime,
    # acctstarttime, acctinputoctets, acctoutputoctets, username, profile_id, fup...
    async def online(self, *, page: int = 1, count: int = 500, **extra) -> Any:
        return await self.list("online", page=page, count=count, **extra)

    async def iter_online(self, *, count: int = 500):
        async for row in self.iter_all("online", count=count):
            yield row

    # الباقات: GET list/profile/0 → [{id, name}]
    async def profiles(self) -> Any:
        return await self.get("list/profile/0")

    # ── ملخّصات جاهزة للّوحة الوطنية (GET، بلا ترقيم — طلب واحد لكل شركة) ──
    # {status, data:{active, expired, expiring_today, expiring_soon, fup,
    #                managers, offline, online, total}}
    async def dashboard_subscribers(self) -> Any:
        return await self.get("advancedDashboard/subscribers")

    async def dashboard_finance(self) -> Any:
        return await self.get("advancedDashboard/finance")

    async def dashboard_system_health(self) -> Any:
        return await self.get("advancedDashboard/systemHealth")

    async def user(self, user_id: int) -> Any:
        return await self.get(f"user/{user_id}")


# ─────────────────────────────── فحص ذاتي سريع ───────────────────────────────
# الاستخدام:  python app/integrations/sas_client.py <host[:port]> <user> <pass> [https]
#   - أضِف الكلمة الرابعة  https  إن كان خادم SAS يعمل على HTTPS.
if __name__ == "__main__":
    import asyncio
    import sys

    # 1) التشفير ذهاباً وإياباً (بلا شبكة)
    sample = json.dumps({"username": "admin", "password": "x", "ع": "عربي"}, ensure_ascii=False)
    assert sas_decrypt(sas_encrypt(sample)) == sample
    print("[OK] تشفير الحمولة متوافق (Salted__ / EVP MD5 / AES-256-CBC)")

    # 2) اتصال حقيقي إن مُرّر host user pass
    if len(sys.argv) >= 4:
        host, user, pwd = sys.argv[1], sys.argv[2], sys.argv[3]
        https = len(sys.argv) >= 5 and sys.argv[4].lower() in ("https", "true", "1", "yes")

        async def main():
            try:
                async with SASClient(host, user, pwd, https=https, verify_tls=False) as sas:
                    print(f"[OK] تسجيل الدخول ناجح — token: {sas._token[:12]}…")
                    # نفس المسار الذي تستخدمه المزامنة الفعلية:
                    res = await sas.dashboard_subscribers()
                    data = res.get("data", res) if isinstance(res, dict) else {}
                    print("[OK] advancedDashboard/subscribers:")
                    for k in ("total", "active", "expired", "online", "offline", "managers"):
                        print(f"     {k:10}= {data.get(k)}")
                    # عيّنة مشتركين لتأكيد حقل parent (=الوكيل) اللازم للمقاطعة لاحقاً:
                    try:
                        users = await sas.users(page=1, count=3)
                        rows = users.get("data", users) if isinstance(users, dict) else users
                        print(f"[OK] عيّنة مشتركين ({len(rows)}): "
                              f"{[{'user': u.get('username'), 'parent': u.get('parent')} for u in rows]}")
                    except SASError as e:
                        print(f"[تحذير] تعذّر جلب المشتركين (الملخّص كافٍ للمزامنة): {e}")
                print("\n✅ الجلب يعمل — يمكنك الآن إضافة الشركة والمزامنة من التطبيق.")
            except SASError as e:
                print(f"\n❌ فشل SAS: {e}")
            except Exception as e:   # noqa: BLE001
                print(f"\n❌ تعذّر الاتصال (شبكة/عنوان/بروتوكول): {e}")
        asyncio.run(main())
    else:
        print("لاختبار خادم حقيقي:  python app/integrations/sas_client.py <host> <user> <pass> [https]")
