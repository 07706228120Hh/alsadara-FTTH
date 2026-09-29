"""إعدادات التطبيق — تُقرأ من ملف .env"""
import logging
import os
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

_DEFAULT_SECRET = "dev-secret-change-me"
# قيم SECRET_KEY ضعيفة/معروفة (بعضها منشور في .env.example) — تُرفض في الإنتاج
_WEAK_SECRETS = {_DEFAULT_SECRET, "change-this-to-a-long-random-string", "", "changeme", "secret"}
_log = logging.getLogger(__name__)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    secret_key: str = _DEFAULT_SECRET
    database_url: str = "sqlite:///./iraq_digital_platform.db"

    # الأمان / المصادقة
    api_token: str = ""            # توكن الوصول للـ API (Bearer). فارغ = بلا مصادقة (تطوير فقط)
    cors_origins: str = "http://localhost,http://127.0.0.1,http://localhost:8000,http://127.0.0.1:8000"

    # إدارة المستخدمين والصلاحيات
    token_ttl_hours: int = 12               # صلاحية توكن جلسة المستخدم
    seed_default_admin: bool = True         # إنشاء مدير افتراضي عند غياب أي مستخدم
    default_admin_user: str = "admin"
    default_admin_password: str = "admin"

    # ==== تطبيق المشتركين: دخول برقم الهاتف + OTP عبر واتساب ====
    subscriber_token_ttl_hours: int = 720     # جلسة المشترك (30 يوماً) — لا كلمة مرور، فالجلسة أطول
    otp_ttl_seconds: int = 300                # صلاحية رمز التحقّق
    otp_length: int = 6
    otp_max_attempts: int = 5                 # محاولات تحقّق فاشلة قبل إبطال الرمز
    otp_max_per_window: int = 3               # حدّ الإرسال لكل رقم داخل النافذة
    otp_window_seconds: int = 600
    # إظهار الرمز في الاستجابة (للتطوير/الاختبار فقط). None = يتبع use_mock_olt.
    otp_dev_echo: bool | None = None
    # بوابة واتساب (wa-gateway على الـ VPS): POST JSON. القالب يقبل {phone} و{message}.
    whatsapp_api_url: str = ""
    whatsapp_api_token: str = ""
    whatsapp_payload_template: str = '{"phone": "{phone}", "message": "{message}"}'
    whatsapp_timeout: float = 15.0

    # الذكاء الاصطناعي
    anthropic_api_key: str = ""
    ai_model: str = "claude-sonnet-4-6"
    ai_timeout: float = 60.0        # مهلة طلب Claude API (ثوانٍ)

    # مهلات الاتصال بالـ OLT (Netmiko) — تمنع تعليق الطلبات على جهاز غير مستجيب
    ssh_conn_timeout: int = 15      # مهلة إنشاء اتصال TCP/SSH
    ssh_read_timeout: int = 30      # مهلة قراءة مخرجات أمر واحد

    # المحاكاة
    use_mock_olt: bool = True
    monitor_interval: int = 30
    # وضع العرض التوضيحي: يُركّب الوحدات التجريبية (بيانات مولّدة: national/audit/agents/…).
    # مطفأ في الإنتاج → واجهة API حقيقية بالكامل (SAS/OLT فقط).
    seed_demo_data: bool = False

    # ==== مزامنة الشركات عبر SAS ====
    sas_sync_interval: int = 300     # فترة سحب ملخص المشتركين من SAS لكل شركة (ثوانٍ)
    sas_sync_subscribers: bool = True   # سحب قائمة المشتركين الكاملة (index/user) عند المزامنة
    sas_subscriber_cap: int = 50000    # حدّ أقصى لعدد المشتركين المسحوبين لكل شركة (حماية)
    # --- تصليب المزامنة للتوسّع (عشرات/مئات الشركات) ---
    sas_sync_concurrency: int = 6      # عدد الشركات التي تُزامَن بالتوازي (semaphore)
    sas_company_timeout: float = 90.0  # ميزانية زمن قصوى لمزامنة شركة واحدة (ثوانٍ)
    sas_session_cap: int = 20000       # سقف الجلسات لكشف الدمج (فوقه لا يُستبدل الكشف الكامل)
    sas_heavy_every: int = 12          # كل كم جولة تكون «ثقيلة» (جلسات+مشتركون)؛ 12×300ث ≈ ساعة
    company_snapshot_retention_days: int = 14   # حذف لقطات الشركات الأقدم من هذا العمر

    # سياسة الاحتفاظ (تنظيف الجداول الزمنية كي لا تنمو بلا حدود)
    metric_retention_days: int = 14      # حذف قياسات Metric الأقدم من هذا العمر
    alarm_retention_days: int = 30       # حذف الإنذارات غير النشطة الأقدم من هذا العمر
    retention_sweep_hours: int = 6       # فترة تشغيل التنظيف الدوري (ساعات)

    # ==== SNMP ====
    # ملاحظة: مفاتيح SNMPv3 لكل جهاز (community / auth / priv) تُخزَّن على مستوى الجهاز
    # في جدول OLTDevice وتُشفَّر عبر core/security — لا تُوضع هنا.
    snmp_poll_enabled: bool = True           # تشغيل سحّاب SNMP الدوري
    snmp_trap_port: int = 162                # منفذ استقبال SNMP traps (UDP)
    snmp_trap_engine_id: str = ""            # Engine ID لمستقبِل الـ traps (اختياري — فارغ = توليد تلقائي)
    snmp_health_interval: int = 45           # سحب صحّة الـ OLT (ثوانٍ)
    snmp_pon_interval: int = 180             # سحب ملخّص منافذ PON (ثوانٍ)
    snmp_ont_basic_interval: int = 600       # سحب حالة ONT الأساسية (ثوانٍ)
    snmp_ont_detail_interval: int = 2400     # سحب بيانات ONT التفصيلية — ضوئي/إصدارات (ثوانٍ)
    snmp_allowed_sources: str = ""           # IPs المجمّع المسموح لها إرسال traps (مفصولة بفواصل)؛ فارغ = الكل (تطوير)
    snmp_timeout: float = 4.0                # مهلة طلب SNMP الواحد (ثوانٍ)
    snmp_retries: int = 1                    # عدد إعادة المحاولة عند فشل طلب SNMP

    # ==== مستخدم SNMPv3 USM لمستقبِل الـ traps ====
    # مطلوبة لتشغيل مستقبِل SNMPv3 traps في الإنتاج؛ بدونها لا يبدأ المستقبِل الحقيقي.
    snmp_trap_user: str = "platform-monitor"  # اسم مستخدم USM لاستقبال الـ traps
    snmp_trap_auth_proto: str = "SHA256"      # بروتوكول المصادقة: SHA | SHA256 | SHA512 | MD5
    snmp_trap_auth_key: str = ""              # مفتاح مصادقة استقبال الـ traps (فارغ = المستقبِل لن يبدأ)
    snmp_trap_priv_proto: str = "AES"         # بروتوكول التشفير: AES | AES256 | DES
    snmp_trap_priv_key: str = ""              # مفتاح تشفير استقبال الـ traps (فارغ = المستقبِل لن يبدأ)

    def model_post_init(self, __context) -> None:
        """التثبيت على ويندوز يضع الملفات في Program Files (قراءة فقط)، فلا تصلح قاعدة
        SQLite النسبية. عند ضبط ALUKLAA_DATA_DIR (يفعله مُشغّل التطبيق المثبَّت) نوجّه
        قاعدة SQLite إلى ذلك المجلد القابل للكتابة (مثل %LOCALAPPDATA%\\Aluklaa).
        وضع التطوير (بلا المتغيّر) و Postgres السحابي لا يتأثّران."""
        data_dir = os.environ.get("ALUKLAA_DATA_DIR", "").strip()
        if not data_dir or not self.database_url.startswith("sqlite"):
            return
        name = self.database_url.rsplit("/", 1)[-1] or "aluklaa.db"
        try:
            base = Path(data_dir)
            base.mkdir(parents=True, exist_ok=True)
        except Exception:  # noqa: BLE001 — تعذّر الإنشاء: نُبقي المسار الأصلي
            return
        self.database_url = f"sqlite:///{(base / name).as_posix()}"

    @property
    def otp_echo_enabled(self) -> bool:
        """هل يُعاد الرمز في استجابة الطلب؟ صريح عبر OTP_DEV_ECHO وإلا يتبع وضع المحاكاة."""
        return self.use_mock_olt if self.otp_dev_echo is None else self.otp_dev_echo

    @property
    def cors_origins_list(self) -> list[str]:
        """قائمة الأصول المسموح بها لـ CORS (فاصلة). القيمة '*' تعني الكل (تطوير فقط)."""
        value = self.cors_origins.strip()
        if value == "*":
            return ["*"]
        return [o.strip() for o in value.split(",") if o.strip()]

    @property
    def snmp_allowed_sources_list(self) -> list[str]:
        """قائمة IPs المسموح لها إرسال SNMP traps.
        قائمة فارغة تعني قبول الكل — مناسب للتطوير؛ قيّدها في الإنتاج."""
        return [s.strip() for s in self.snmp_allowed_sources.split(",") if s.strip()]

    def validate_runtime(self) -> None:
        """يرفض الإقلاع بإعداد إنتاج حرج غير آمن؛ يحذّر من إعدادات SNMP الناقصة."""
        if self.use_mock_olt:
            return  # وضع التطوير/المحاكاة — تساهل مقصود

        # --- فحوصات حرجة: ترفع استثناءً (تكسر الإقلاع عمداً) ---
        if self.secret_key in _WEAK_SECRETS or len(self.secret_key) < 24:
            raise RuntimeError(
                "SECRET_KEY ضعيف/معروف غير مسموح في الإنتاج (USE_MOCK_OLT=false). "
                "ولّد قيمة قوية: python -c \"import secrets;print(secrets.token_urlsafe(48))\" ثم ضعها في .env."
            )
        if not self.api_token:
            raise RuntimeError(
                "API_TOKEN مطلوب في الإنتاج (USE_MOCK_OLT=false) لحماية نقاط النهاية."
            )
        if self.otp_dev_echo:
            raise RuntimeError("OTP_DEV_ECHO=true غير مسموح في الإنتاج — يكشف رمز التحقّق في الاستجابة.")
        if not self.whatsapp_api_url:
            _log.warning("[OTP] WHATSAPP_API_URL غير مضبوط — لن تُرسَل رموز التحقّق للمشتركين.")
        if self.seed_default_admin and self.default_admin_password == "admin":
            raise RuntimeError(
                "كلمة مرور المدير الافتراضية 'admin' غير مسموحة في الإنتاج. "
                "عيّن DEFAULT_ADMIN_PASSWORD قوية أو أوقف SEED_DEFAULT_ADMIN."
            )

        # --- تحذيرات SNMP: لا ترفع استثناءً — تُبقي الإقلاع ولكن تُنبّه المشغّل ---
        if not self.snmp_allowed_sources_list:
            _log.warning(
                "[SNMP] تقييد مصدر traps غير مضبوط — أي مصدر يستطيع الإرسال؛ "
                "اضبط SNMP_ALLOWED_SOURCES أو قيّد على مستوى الجدار الناري."
            )

        if not self.snmp_trap_auth_key or not self.snmp_trap_priv_key:
            _log.warning(
                "[SNMP] مفاتيح مستقبِل SNMPv3 traps غير مضبوطة "
                "(SNMP_TRAP_AUTH_KEY / SNMP_TRAP_PRIV_KEY) — "
                "لن يبدأ المستقبِل الحقيقي (SNMPv3 حصراً، بلا رجوع لـ v2c)."
            )


settings = Settings()
