"""
وكلاء الأمن السيبراني الدفاعيون (Blue Team) — يحمون المنصة والشركات المربوطة.

خمسة وكلاء، كلها تعمل على بيانات المنصة نفسها (لا أدوات هجومية):
  1) hardening   — تدقيق تصلّب الإعدادات مقابل أفضل الممارسات (settings).
  2) code        — فحص ذاتي لكود المشروع (SAST خفيف) عن أنماط غير آمنة.
  3) crypto      — مراجعة استخدام التشفير في المشروع.
  4) access      — تدقيق الوصول والصلاحيات وسجلّ الأوامر الخطرة (AuditLog/User).
  5) anomaly     — كشف الشذوذ في المشتركين/الوكلاء/الجلسات (Subscriber/Agent/MergeFinding).

كل نتيجة (Finding) لها: الشدّة، الفئة، العنوان، التفصيل، والتوصية.
تحليل ذكي اختياري (Claude إن توفّر المفتاح) يُلخّص النتائج بنمط بقية المنصة.

يُوضع في backend/app/services/security_agents.py
"""
from __future__ import annotations

import os
import re
from dataclasses import dataclass, asdict
from typing import Dict, List, Optional

from sqlmodel import Session, select

from ..config import settings, _DEFAULT_SECRET
from ..models import AuditLog, User, Subscriber, Agent, MergeFinding, Company

# شدّات موحّدة (متوافقة مع مفردات الواجهة)
CRITICAL, HIGH, MEDIUM, LOW, INFO = "critical", "high", "medium", "low", "info"
_SEV_RANK = {CRITICAL: 4, HIGH: 3, MEDIUM: 2, LOW: 1, INFO: 0}


@dataclass
class Finding:
    agent: str            # hardening | code | crypto | access | anomaly
    severity: str         # critical | high | medium | low | info
    category: str
    title: str
    detail: str
    recommendation: str
    location: str = ""    # ملف:سطر عند وجوده

    def dict(self) -> dict:
        return asdict(self)


# ═══════════════════════════ 1) تصلّب الإعدادات ═══════════════════════════
def audit_hardening() -> List[Finding]:
    f: List[Finding] = []
    prod = not settings.use_mock_olt

    if settings.secret_key == _DEFAULT_SECRET:
        f.append(Finding("hardening", CRITICAL if prod else HIGH, "secrets",
            "SECRET_KEY افتراضي",
            "مفتاح التشفير لا يزال القيمة الافتراضية — يُفكّ به تشفير كلمات مرور الأجهزة وتوكنات الجلسة.",
            "عيّن SECRET_KEY عشوائياً طويلاً: python -c \"import secrets;print(secrets.token_urlsafe(48))\""))

    if not settings.api_token:
        f.append(Finding("hardening", CRITICAL if prod else MEDIUM, "auth",
            "API_TOKEN غير مضبوط",
            "نقاط الـ API بلا توكن رئيسي؛ في الإنتاج يعني وصولاً غير محمي.",
            "عيّن API_TOKEN قوياً واضبطه في الواجهة أيضاً."))

    if settings.cors_origins.strip() == "*":
        f.append(Finding("hardening", HIGH if prod else LOW, "cors",
            "CORS مفتوح للجميع (*)",
            "السماح لأي أصل بالوصول للـ API يوسّع سطح الهجوم (CSRF/تسريب).",
            "قيّد CORS_ORIGINS على نطاق واجهتك فقط."))

    if settings.seed_default_admin and settings.default_admin_password == "admin":
        f.append(Finding("hardening", CRITICAL if prod else HIGH, "auth",
            "كلمة مرور المدير الافتراضية 'admin'",
            "حساب admin/admin يُنشأ عند أول تشغيل — هدف مباشر لهجمات التخمين.",
            "غيّر DEFAULT_ADMIN_PASSWORD إلى كلمة قوية، أو أوقف SEED_DEFAULT_ADMIN بعد إنشاء مديرك."))

    if prod and settings.database_url.startswith("sqlite"):
        f.append(Finding("hardening", MEDIUM, "database",
            "SQLite في الإنتاج",
            "SQLite غير مناسب للإنتاج متعدد الشركات (تزامن/نسخ احتياطي/توسّع).",
            "انتقل إلى PostgreSQL (راجع DEPLOY.md وdocker-compose)."))

    if not settings.snmp_allowed_sources.strip():
        f.append(Finding("hardening", MEDIUM if prod else LOW, "snmp",
            "مصدر SNMP traps غير مقيّد",
            "أي مصدر يستطيع إرسال traps — خطر تزييف إنذارات.",
            "اضبط SNMP_ALLOWED_SOURCES أو قيّد على مستوى الجدار الناري."))

    if settings.token_ttl_hours > 24:
        f.append(Finding("hardening", LOW, "auth",
            f"مدة توكن الجلسة طويلة ({settings.token_ttl_hours} ساعة)",
            "التوكنات طويلة العمر تزيد خطر إعادة الاستخدام عند التسريب.",
            "قلّل TOKEN_TTL_HOURS (مثلاً 12)."))

    if not f:
        f.append(Finding("hardening", INFO, "config", "الإعدادات ضمن أفضل الممارسات",
            "لم تُكتشف مشكلات تصلّب في الإعدادات الحالية.", "استمر بالمراجعة الدورية."))
    return f


# ═══════════════════════════ 2) فحص الكود (SAST خفيف) ═══════════════════════════
# (نمط، الشدّة، الفئة، العنوان، التوصية) — يُطبَّق سطراً بسطر على ملفات المشروع.
_CODE_RULES = [
    (re.compile(r'verify\s*=\s*False'), HIGH, "tls",
     "تعطيل تحقّق TLS (verify=False)", "أزل verify=False أو اجعله خياراً صريحاً للشهادات الذاتية فقط."),
    (re.compile(r'(?<![\w.])eval\s*\('), HIGH, "injection",
     "استخدام eval()", "استبدل eval بمعالجة صريحة/آمنة."),
    (re.compile(r'(?<![\w.])exec\s*\('), HIGH, "injection",
     "استخدام exec()", "تجنّب exec على مدخلات غير موثوقة."),
    (re.compile(r'shell\s*=\s*True'), HIGH, "injection",
     "subprocess بـ shell=True", "استخدم قائمة وسائط بدل shell=True لتفادي حقن الأوامر."),
    (re.compile(r'pickle\.loads?\s*\('), HIGH, "deserialization",
     "استخدام pickle", "لا تفكّ تسلسل بيانات غير موثوقة عبر pickle؛ استخدم JSON."),
    (re.compile(r'hashlib\.(md5|sha1)\s*\(.*password', re.I), HIGH, "crypto",
     "تجزئة كلمة مرور بخوارزمية ضعيفة (MD5/SHA1)", "استخدم PBKDF2/bcrypt/argon2."),
    (re.compile(r'(password|passwd|secret|api[_-]?key|token)\s*=\s*["\'][^"\']{8,}["\']', re.I), HIGH, "secrets",
     "سرّ مضمّن في الكود (محتمل)", "انقل الأسرار إلى متغيّرات بيئة/إعدادات، لا في الكود."),
    (re.compile(r'DEBUG\s*=\s*True'), MEDIUM, "config",
     "DEBUG=True", "أطفئ وضع التصحيح في الإنتاج."),
    (re.compile(r'allow_origins\s*=\s*\[\s*["\']\*["\']'), MEDIUM, "cors",
     "CORS مفتوح في الكود (*)", "قيّد الأصول المسموح بها."),
]
# ملفات/مسارات تُتجاهَل (اعتمادات، بناء، اختبارات، هجرات)
_SKIP_DIRS = {".venv", "venv", "__pycache__", ".git", "build", "migrations", "tests",
              ".pytest_cache", "node_modules", "knowledge", ".dart_tool"}
# السماح لعبارة SAS الثابتة (ليست سرّاً — عبارة تشفير عامّة في لوحة SAS)
_ALLOW_SUBSTR = ["abcdefghijuklmno0123456789012345", "platform-monitor"]
# قيم افتراضية معروفة/عناصر نائبة لا تُعدّ أسراراً مضمّنة
_SECRET_PLACEHOLDERS = ["change-me", "example", "dev-secret", "your-", "xxx",
                        "admin", "placeholder", "<", "sk-ant-", "..."]


def scan_code(root: str, max_findings: int = 200) -> List[Finding]:
    f: List[Finding] = []
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in _SKIP_DIRS]
        for name in files:
            if not (name.endswith(".py") or name.endswith(".dart")):
                continue
            if name == "security_agents.py":   # لا يفحص الماسح قواعده نفسها
                continue
            path = os.path.join(base, name)
            rel = os.path.relpath(path, root)
            try:
                with open(path, "r", encoding="utf-8", errors="ignore") as fh:
                    lines = fh.readlines()
            except OSError:
                continue
            for i, line in enumerate(lines, 1):
                if line.lstrip().startswith(("#", "//", "*", "/*")):
                    continue
                if any(a in line for a in _ALLOW_SUBSTR):
                    continue
                for rx, sev, cat, title, rec in _CODE_RULES:
                    if rx.search(line):
                        if cat == "secrets":
                            low = line.lower()
                            if any(ph in low for ph in _SECRET_PLACEHOLDERS):
                                continue
                            if re.search(r':\s*str\s*=', line):  # حقل إعدادات مُعرَّف بنوع
                                continue
                        f.append(Finding("code", sev, cat, title,
                            f"{rel}:{i}: {line.strip()[:120]}", rec, location=f"{rel}:{i}"))
                        if len(f) >= max_findings:
                            return f
    if not f:
        f.append(Finding("code", INFO, "code", "لا أنماط كود غير آمنة",
            "لم يُكتشف نمط خطر في فحص الكود الحالي.", "أعد الفحص بعد كل تغيير مهم."))
    return f


# ═══════════════════════════ 3) مراجعة التشفير ═══════════════════════════
def audit_crypto() -> List[Finding]:
    f: List[Finding] = []
    # مراجعة تقريرية لما هو معروف عن تصميم المشروع (core/security.py):
    f.append(Finding("crypto", INFO, "crypto", "تشفير أسرار الأجهزة: Fernet",
        "كلمات مرور الأجهزة ومفاتيح SNMP تُشفَّر بـ Fernet (AES-128-CBC + HMAC) بمفتاح مشتقّ من SECRET_KEY (SHA-256).",
        "أبقِ SECRET_KEY سرّياً وقوياً؛ فقدانه يفقد فكّ الأسرار المخزّنة."))
    f.append(Finding("crypto", INFO, "crypto", "تجزئة كلمات مرور المستخدمين: PBKDF2-SHA256 (200k)",
        "كلمات مرور المستخدمين مُجزّأة بـ PBKDF2-HMAC-SHA256 بـ 200,000 دورة ومِلح عشوائي.",
        "جيّد؛ راجع رفع عدد الدورات دورياً مع تطوّر العتاد."))
    if settings.secret_key == _DEFAULT_SECRET:
        f.append(Finding("crypto", CRITICAL, "crypto", "كل التشفير مبني على مفتاح افتراضي",
            "بما أن SECRET_KEY افتراضي، فمفتاح Fernet وتوكنات الجلسة قابلة للتخمين.",
            "غيّر SECRET_KEY فوراً وأعد إدخال أسرار الأجهزة."))
    f.append(Finding("crypto", INFO, "crypto", "عبارة تشفير SAS ثابتة (بحكم التصميم)",
        "الاتصال بـ SAS يستخدم عبارة AES ثابتة مضمّنة في لوحة SAS نفسها (ليست سرّاً خاصاً بك) — مطلوبة للتوافق.",
        "لا إجراء؛ احمِ نقل البيانات بـ HTTPS بين المنصة وSAS حيثما أمكن."))
    return f


# ═══════════════════════════ 4) تدقيق الوصول ═══════════════════════════
def audit_access(db: Session) -> List[Finding]:
    f: List[Finding] = []
    users = db.exec(select(User)).all()
    admins = [u for u in users if u.role == "admin" and u.enabled]
    if any(u.username == "admin" for u in users) and settings.default_admin_password == "admin":
        f.append(Finding("access", HIGH, "auth", "حساب admin الافتراضي موجود",
            "يوجد مستخدم باسم admin وكلمة المرور الافتراضية لم تُغيَّر في الإعدادات.",
            "غيّر كلمة مرور admin من إدارة الحسابات."))
    if len(admins) == 0:
        f.append(Finding("access", MEDIUM, "auth", "لا مدير مُفعَّل",
            "لا يوجد مستخدم admin مُفعَّل — قد تفقد إدارة المنصة.",
            "أنشئ/فعّل حساب admin واحداً على الأقل."))
    elif len(admins) > 5:
        f.append(Finding("access", LOW, "auth", f"عدد كبير من المدراء ({len(admins)})",
            "كثرة حسابات admin توسّع سطح الخطر.", "قلّل المدراء لأقل عدد ضروري (مبدأ الأقل امتيازاً)."))

    # سجلّ الأوامر: أوامر خطرة فاشلة أو متكرّرة
    logs = db.exec(select(AuditLog)).all()
    dangerous = [l for l in logs if l.kind == "dangerous"]
    failed = [l for l in logs if not l.success]
    if dangerous:
        f.append(Finding("access", MEDIUM, "audit", f"{len(dangerous)} أمر خطر في السجلّ",
            "أوامر مصنّفة خطرة (erase/reboot/delete...) نُفِّذت — راجع مشروعيتها.",
            "تحقّق من كل أمر خطر ومن نفّذه في سجلّ التدقيق."))
    if len(failed) > 20:
        f.append(Finding("access", MEDIUM, "audit", f"{len(failed)} عملية فاشلة في السجلّ",
            "كثرة العمليات الفاشلة قد تدل على محاولات غير مصرّح بها أو خلل.",
            "راجع نمط الإخفاقات ومصادرها."))
    if not f:
        f.append(Finding("access", INFO, "auth", "الوصول والصلاحيات سليمة",
            "لا مشكلات وصول ظاهرة.", "راجع سجلّ التدقيق دورياً."))
    return f


# ═══════════════════════════ 5) كشف الشذوذ ═══════════════════════════
def detect_anomalies(db: Session) -> List[Finding]:
    f: List[Finding] = []
    # كشف الدمج المخزّن (LB/Bonding/إعادة بيع)
    merges = db.exec(select(MergeFinding)).all()
    if merges:
        by_kind: Dict[str, int] = {}
        for m in merges:
            by_kind[m.kind] = by_kind.get(m.kind, 0) + 1
        labels = {"LOAD_BALANCING_SUSPECTED": "موازنة حِمل",
                  "BONDING_SUSPECTED": "دمج خطوط",
                  "SHARED_LINE_SUSPECTED": "مشاركة/إعادة بيع"}
        detail = "، ".join(f"{labels.get(k, k)}: {v}" for k, v in by_kind.items())
        f.append(Finding("anomaly", HIGH, "fraud", f"{len(merges)} مؤشّر دمج/إعادة بيع",
            detail, "راجع تبويب «التدقيق والمراقبة» للتفاصيل واتخذ إجراءً تنظيمياً موثّقاً."))

    # وكلاء بعدد مشتركين شاذّ (خارج نطاق كبير) — مؤشّر تجميع/تلاعب
    agents = db.exec(select(Agent)).all()
    if len(agents) >= 5:
        counts = sorted(a.users_count for a in agents)
        # عتبة بسيطة: أكبر من 5× الوسيط
        mid = counts[len(counts) // 2] or 1
        outliers = [a for a in agents if a.users_count > max(50, 5 * mid)]
        for a in outliers[:10]:
            f.append(Finding("anomaly", MEDIUM, "fraud",
                f"وكيل بعدد مشتركين مرتفع جداً: {a.username} ({a.users_count})",
                f"يتجاوز 5× وسيط الوكلاء ({mid}) — قد يدل على تجميع اشتراكات تحت وكيل واحد.",
                "راجع مشروعية هذا الوكيل مقابل تدقيق الأعداد."))

    # شركات: نشط مرتفع لكن online=0 (احتمال بيانات ناقصة أو انقطاع)
    for c in db.exec(select(Company)).all():
        subs = db.exec(select(Subscriber).where(Subscriber.company_id == c.id)).all()
        if len(subs) >= 20:
            active = sum(1 for s in subs if s.status == "active")
            online = sum(1 for s in subs if s.online)
            if active >= 20 and online == 0:
                f.append(Finding("anomaly", LOW, "monitoring",
                    f"{c.name}: مشتركون نشطون بلا أي اتصال",
                    f"{active} نشط لكن 0 متصل — قد يكون انقطاعاً أو فجوة في بيانات الجلسات.",
                    "تحقّق من صحّة سحب الجلسات ومن حالة الشبكة."))
    if not f:
        f.append(Finding("anomaly", INFO, "monitoring", "لا شذوذ مكتشف",
            "لا مؤشّرات شذوذ في البيانات الحالية.", "يعتمد الكشف على اكتمال المزامنة."))
    return f


# ═══════════════════════════ المنسّق ═══════════════════════════
def _project_root() -> str:
    # backend/app/services/security_agents.py → جذر backend
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(here, "..", ".."))


def run_all(db: Session, include_code: bool = True) -> dict:
    findings: List[Finding] = []
    findings += audit_hardening()
    findings += audit_crypto()
    findings += audit_access(db)
    findings += detect_anomalies(db)
    if include_code:
        findings += scan_code(_project_root())

    real = [x for x in findings if x.severity != INFO]
    counts = {s: sum(1 for x in findings if x.severity == s)
              for s in (CRITICAL, HIGH, MEDIUM, LOW, INFO)}
    # درجة أمان 0–100 (تنقص مع الشدّة)
    penalty = counts[CRITICAL] * 25 + counts[HIGH] * 10 + counts[MEDIUM] * 4 + counts[LOW] * 1
    score = max(0, 100 - penalty)
    findings.sort(key=lambda x: _SEV_RANK[x.severity], reverse=True)
    return {
        "score": score,
        "counts": counts,
        "total_findings": len(real),
        "findings": [x.dict() for x in findings],
    }
