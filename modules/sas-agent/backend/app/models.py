"""نماذج قاعدة البيانات (SQLModel)"""
from datetime import datetime, timezone
from typing import Optional
from sqlmodel import SQLModel, Field


def utcnow() -> datetime:
    """توقيت UTC واعٍ بالمنطقة الزمنية — بديل `datetime.utcnow()` المهمَل."""
    return datetime.now(timezone.utc)


class OLTDevice(SQLModel, table=True):
    """جهاز OLT مُدار"""
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str
    host: str
    port: int = 22
    protocol: str = "ssh"          # ssh | telnet
    username: str = "root"
    password_enc: str = ""          # كلمة المرور مشفّرة
    model: str = "MA5800"           # MA5800 | MA5680T | EA5800
    enabled: bool = True
    reachable: bool = False
    last_seen: Optional[datetime] = None
    created_at: datetime = Field(default_factory=utcnow)

    # --- SNMPv3 ---
    snmp_enabled: bool = True
    snmp_port: int = 161
    snmp_user: str = "platform-monitor"
    snmp_auth_proto: str = "SHA256"     # SHA | SHA256 | SHA512 | MD5
    snmp_auth_key_enc: str = ""         # مفتاح المصادقة مشفَّراً (Fernet)
    snmp_priv_proto: str = "AES"        # AES | AES256 | DES
    snmp_priv_key_enc: str = ""         # مفتاح التشفير مشفَّراً (Fernet)
    snmp_context: str = ""
    snmp_engine_id: str = ""
    adapter_profile: str = ""           # اسم ملف Adapter؛ فارغ = يُستنتج من model+الإصدار


class ONTRecord(SQLModel, table=True):
    """سجل ONT/ONU في المخزون"""
    id: Optional[int] = Field(default=None, primary_key=True)
    olt_id: int = Field(foreign_key="oltdevice.id", index=True)
    fsp: str                        # frame/slot/port مثال 0/5/0
    ont_id: int
    sn: str = Field(index=True)
    description: str = ""
    line_profile: str = ""
    srv_profile: str = ""
    mgmt_mode: str = "omci"         # omci | snmp
    run_state: str = "unknown"      # online | offline | unknown
    config_state: str = "unknown"   # normal | failed
    match_state: str = "unknown"    # match | mismatch
    rx_power: Optional[float] = None  # dBm
    distance_m: Optional[int] = None
    updated_at: datetime = Field(default_factory=utcnow)

    # --- حقول القراءة الضوئية/التفصيلية ---
    tx_power: Optional[float] = None          # قدرة الإرسال (dBm)
    olt_rx_power: Optional[float] = None      # قدرة الاستقبال على طرف OLT (dBm)
    temperature: Optional[float] = None       # درجة حرارة الوحدة (°C)
    voltage: Optional[float] = None           # الجهد الكهربي (V)
    bias_current: Optional[float] = None      # تيار الإضاءة (mA)
    last_up: Optional[datetime] = None        # آخر وقت اتصال
    last_down: Optional[datetime] = None      # آخر وقت انقطاع
    last_down_cause: str = ""                 # سبب آخر انقطاع
    ont_model: str = ""                       # طراز الـ ONT
    hw_version: str = ""                      # إصدار العتاد
    sw_version: str = ""                      # إصدار البرنامج
    reg_method: str = ""                      # طريقة التسجيل (sn | loid | password)


class AuditLog(SQLModel, table=True):
    """سجل كل أمر نُفِّذ على أي جهاز"""
    id: Optional[int] = Field(default=None, primary_key=True)
    olt_id: Optional[int] = Field(default=None, index=True)
    user: str = "system"
    command: str
    result: str = ""
    success: bool = True
    kind: str = "read"              # read | write | dangerous
    created_at: datetime = Field(default_factory=utcnow)


class Metric(SQLModel, table=True):
    """قياس زمني (للرسوم البيانية التاريخية)"""
    id: Optional[int] = Field(default=None, primary_key=True)
    olt_id: int = Field(index=True)
    target: str                     # مثال: ONT 0/5/0/3 أو board 0/9
    metric: str                     # rx_power | cpu | temperature | ...
    value: float
    ts: datetime = Field(default_factory=utcnow, index=True)


class User(SQLModel, table=True):
    """مستخدم التطبيق — للمصادقة والصلاحيات (viewer/operator/admin)."""
    id: Optional[int] = Field(default=None, primary_key=True)
    username: str = Field(index=True, unique=True)
    password_hash: str = ""
    role: str = "viewer"            # viewer | operator | admin (مستوى الصلاحية)
    # --- النطاق (منصّة رقابية): فارغ = جهة رقابية ترى الكل؛ وإلا مقيّد بشركة/وكيل ---
    scope_company_id: Optional[int] = Field(default=None, index=True)  # مقيّد بهذه الشركة
    scope_agent: str = Field(default="")                               # مقيّد بهذا الوكيل (username)
    # --- بيانات SAS الخاصّة بالوكيل (اختياري): الوكيل يُدخل خادمه واسم مستخدمه وكلمة مروره بنفسه ---
    sas_host: str = Field(default="")                                  # عنوان خادم SAS الخاص بالوكيل (host[:port] أو رابط)
    sas_https: bool = False
    sas_verify_tls: bool = False                                       # شهادات ذاتية غالباً → الافتراض بلا تحقّق
    sas_username: str = Field(default="")
    sas_password_enc: str = Field(default="")                          # مشفّرة Fernet
    # --- معلومات الوكيل (يملؤها الأدمن عند إنشاء الحساب) ---
    display_name: str = Field(default="")
    phone: str = Field(default="")
    enabled: bool = True
    created_at: datetime = Field(default_factory=utcnow)


class AlarmRecord(SQLModel, table=True):
    """تنبيه/إنذار"""
    id: Optional[int] = Field(default=None, primary_key=True)
    olt_id: int = Field(index=True)
    severity: str = "warning"       # critical | major | warning | info
    source: str = ""
    message: str = ""
    active: bool = True
    ts: datetime = Field(default_factory=utcnow, index=True)

    # --- حقول تطبيع الإنذار (Alarm Normalizer) ---
    alarm_uid: str = Field(default="", index=True)   # معرّف فريد للإنذار عبر المصادر
    source_type: str = ""                             # OLT | PON | ONT | BOARD | SYSTEM
    frame: Optional[int] = None
    slot: Optional[int] = None
    pon: Optional[int] = None
    ont_id_ref: Optional[int] = None                 # مرجع ONT (تجنّب تعارض اسم ont_id)
    code: str = ""                                    # رمز الإنذار مثل ONT_LOS
    title: str = ""                                   # عنوان قصير للإنذار
    occurred_at: Optional[datetime] = None            # وقت الحدوث الفعلي


class ConfigSnapshot(SQLModel, table=True):
    """نسخة احتياطية من إعدادات الجهاز (display current-configuration)."""
    id: Optional[int] = Field(default=None, primary_key=True)
    olt_id: int = Field(foreign_key="oltdevice.id", index=True)
    content: str = ""
    note: str = ""
    created_at: datetime = Field(default_factory=utcnow, index=True)


class DeviceHealth(SQLModel, table=True):
    """أحدث قراءة صحّة لكل جهاز OLT — صف واحد لكل olt_id (upsert)."""
    id: Optional[int] = Field(default=None, primary_key=True)
    olt_id: int = Field(foreign_key="oltdevice.id", index=True, unique=True)
    cpu: Optional[float] = None           # نسبة استخدام المعالج (%)
    memory: Optional[float] = None        # نسبة استخدام الذاكرة (%)
    temperature: Optional[float] = None   # درجة الحرارة الإجمالية (°C)
    uptime: Optional[int] = None          # وقت التشغيل المتواصل (ثوانٍ)
    power_status: str = ""               # حالة مصدر الطاقة
    fan_status: str = ""                 # حالة المراوح
    sw_version: str = ""                 # إصدار البرنامج الحالي
    active_alarms: int = 0               # عدد الإنذارات النشطة
    updated_at: datetime = Field(default_factory=utcnow)


class PonPortStatus(SQLModel, table=True):
    """أحدث ملخّص لكل منفذ PON — upsert بمفتاح (olt_id, frame, slot, port)."""
    id: Optional[int] = Field(default=None, primary_key=True)
    olt_id: int = Field(foreign_key="oltdevice.id", index=True)
    frame: int
    slot: int
    port: int
    status: str = ""                      # up | down
    tech: str = ""                        # GPON | XG-PON | XGS-PON
    onts_registered: int = 0
    onts_online: int = 0
    onts_offline: int = 0
    rx_traffic: Optional[float] = None    # معدّل حركة الاستقبال (Mbps)
    tx_traffic: Optional[float] = None    # معدّل حركة الإرسال (Mbps)
    utilization: Optional[float] = None   # نسبة الاستخدام (%)
    updated_at: datetime = Field(default_factory=utcnow)


class SasAccount(SQLModel, table=True):
    """حساب SAS إضافي يربطه الوكيل بحسابه — يدعم **عدة حسابات** لوكيل واحد (قد تكون على
    خوادم SAS مختلفة). كل حساب يُزامَن مستقلاً، ومشتركوه يُوسَمون بـ Subscriber.sas_account_id
    فتُعرَض كل المستخدمين مدموجين وتُوجَّه أي عملية تلقائياً إلى الحساب/الخادم الصحيح.

    التوافق الخلفي: الوكيل الذي ضبط حساباً واحداً على User.sas_* يُرحَّل تلقائياً إلى صفّ
    SasAccount أساسي (انظر companies.ensure_agent_accounts)."""
    id: Optional[int] = Field(default=None, primary_key=True)
    owner_user_id: int = Field(foreign_key="user.id", index=True)      # الوكيل المالك للحساب
    company_id: Optional[int] = Field(default=None, foreign_key="company.id", index=True)  # مزوّد الوكيل (للنسبة)
    label: str = Field(default="")                                     # اسم مميّز يظهر في الواجهة
    # --- بيانات الاتصال بـ SAS4 (لكل حساب خادمه الخاص — قد يختلف بين الحسابات) ---
    sas_host: str = Field(default="")
    sas_https: bool = False
    sas_verify_tls: bool = False
    sas_username: str = Field(default="")
    sas_password_enc: str = Field(default="")                          # مشفّرة Fernet — لا تُعاد أبداً
    enabled: bool = True
    # --- حالة آخر مزامنة (مستقلّة لكل حساب: فشل حساب لا يوقف البقية) ---
    last_sync_at: Optional[datetime] = None
    last_sync_ok: bool = False
    last_sync_error: str = Field(default="")
    created_at: datetime = Field(default_factory=utcnow)


class Company(SQLModel, table=True):
    """شركة مزوّدة خدمة إنترنت مربوطة بالمنصة عبر واجهة SAS4 الخاصة بها."""
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(index=True)
    code: str = Field(default="", index=True)
    governorate: str = Field(default="")
    color: str = Field(default="#22D3EE")
    enabled: bool = True
    kind: str = Field(default="primary")          # primary=رئيسية | secondary=ثانوية
    access_type: str = Field(default="ftth")       # ftth | wireless

    # --- بيانات الاتصال بـ SAS4 ---
    sas_host: str = Field(default="")
    sas_https: bool = False
    sas_verify_tls: bool = False   # لوحات SAS غالباً بشهادة ذاتية التوقيع → الافتراض بلا تحقّق
    sas_username: str = Field(default="")
    sas_password_enc: str = Field(default="")

    # --- حالة آخر مزامنة ---
    last_sync_at: Optional[datetime] = None
    last_sync_ok: bool = False
    last_sync_error: str = Field(default="")

    created_at: datetime = Field(default_factory=utcnow)


class CompanySnapshot(SQLModel, table=True):
    """لقطة دورية لملخص مشتركي شركة — مصدرها advancedDashboard/subscribers في SAS."""
    id: Optional[int] = Field(default=None, primary_key=True)
    company_id: int = Field(foreign_key="company.id", index=True)
    ts: datetime = Field(default_factory=utcnow, index=True)

    total: int = 0
    active: int = 0
    expired: int = 0
    online: int = 0
    offline: int = 0
    expiring_today: int = 0
    expiring_soon: int = 0
    fup: int = 0
    managers: int = 0


class Agent(SQLModel, table=True):
    """وكيل (Manager في SAS) تابع لشركة — لقطة محدَّثة كل مزامنة (upsert على company_id+manager_id)."""
    id: Optional[int] = Field(default=None, primary_key=True)
    company_id: int = Field(foreign_key="company.id", index=True)
    manager_id: int = Field(index=True)            # id الوكيل في SAS
    username: str = Field(default="", index=True)
    firstname: str = ""
    lastname: str = ""
    parent_id: Optional[int] = None                # الوكيل الأعلى (هرم)
    parent_username: str = ""
    users_count: int = 0                           # عدد مشتركي الوكيل (company-reported)
    balance: float = 0.0
    reward_points: float = 0.0
    discount_rate: float = 0.0
    enabled: bool = True
    updated_at: datetime = Field(default_factory=utcnow)


class MergeFinding(SQLModel, table=True):
    """نتيجة كشف دمج مُحتسبة من جلسات SAS (index/online) لشركة — تُستبدل كل مزامنة."""
    id: Optional[int] = Field(default=None, primary_key=True)
    company_id: int = Field(foreign_key="company.id", index=True)
    username: str = Field(default="", index=True)
    kind: str = Field(default="")     # LOAD_BALANCING_SUSPECTED | BONDING_SUSPECTED | SHARED_LINE_SUSPECTED
    severity: str = "warning"         # warning | major | critical
    session_count: int = 0
    nas_count: int = 0
    ip_count: int = 0
    detail: str = ""                  # وصف موجز + قيم (NAS/IPs/MAC)
    ts: datetime = Field(default_factory=utcnow, index=True)


class AgentReport(SQLModel, table=True):
    """تصريح وكيل بعدد مشتركيه — سجل تاريخي (كل تصريح صف مستقل)."""
    id: Optional[int] = Field(default=None, primary_key=True)
    company_id: int = Field(foreign_key="company.id", index=True)
    agent_username: str = Field(index=True)
    declared_total: int
    declared_active: int = 0
    note: str = ""
    submitted_by: str = ""
    ts: datetime = Field(default_factory=utcnow, index=True)


class Subscriber(SQLModel, table=True):
    """مشترك (user في SAS) تابع لشركة — لقطة محدَّثة كل مزامنة (upsert على company_id+sub_id).
    المصدر: index/user. ملاحظة: قائمة SAS تعطي المدينة لا الإحداثيات، فالخريطة تجميعية بالمحافظة."""
    id: Optional[int] = Field(default=None, primary_key=True)
    # اختياري: مشترك مُضاف يدوياً (مواطن) قد لا يتبع شركة (company_id=None)
    company_id: Optional[int] = Field(default=None, foreign_key="company.id", index=True)
    # حساب SAS الذي جاء منه المشترك (تعدد حسابات الوكيل) — None للمشترك اليدوي أو حساب الشركة.
    # يُوجِّه أي عملية إلى الخادم/الاعتماد الصحيح: (sas_account_id, sub_id) هو المعرّف الفعلي.
    sas_account_id: Optional[int] = Field(default=None, foreign_key="sasaccount.id", index=True)
    sub_id: int = Field(default=0, index=True)      # id المشترك في SAS (0 = يدوي)
    username: str = Field(default="", index=True)
    firstname: str = ""
    lastname: str = ""
    agent_username: str = Field(default="", index=True)   # parent_username (الوكيل)
    profile_id: Optional[int] = None
    profile_name: str = ""
    status: str = Field(default="", index=True)     # active | expired | online ...
    online: bool = False
    enabled: bool = True
    expiration: str = ""
    city: str = Field(default="", index=True)
    governorate: str = Field(default="", index=True) # مُشتقّة من city (تطبيع)
    phone: str = ""
    phone_norm: str = Field(default="", index=True)  # مطبَّع 9647XXXXXXXXX — مفتاح دخول تطبيق المشتركين
    # --- ربط بوابة SAS (اختياري): يملؤها المشترك مرة واحدة لتنفيذ عمليات بوابته ---
    # (تغيير كلمة المرور/استبدال كرت). لا تُلمَس في مزامنة sas_sync (upsert يعيّن حقولاً محدّدة).
    sas_username: str = Field(default="")
    sas_password_enc: str = Field(default="")        # مشفّرة Fernet — لا تُعاد أبداً في أي استجابة
    updated_at: datetime = Field(default_factory=utcnow)


class GisLayer(SQLModel, table=True):
    """طبقة GIS (ألياف/مسارات) — تُرفع كملف GeoJSON أو KML وتُخزَّن بصيغة GeoJSON."""
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(index=True)
    # مستوى/مجموعة حرّة (اسم يدوي: شركة، «الباك بون»، أي تصنيف) — أساس التصفية/التلوين
    group_name: str = Field(default="", index=True)
    kind: str = Field(default="fiber")               # fiber | route | zone | ...
    # شركة مالكة: None = طبقة عامّة (كل المستخدمين)؛ وإلا مقيّدة بتلك الشركة (للعزل)
    company_id: Optional[int] = Field(default=None, foreign_key="company.id", index=True)
    geojson: str = Field(default="{}")               # FeatureCollection كاملة (JSON)
    feature_count: int = Field(default=0)
    created_at: datetime = Field(default_factory=utcnow)


class NpnCounter(SQLModel, table=True):
    """عدّاد تسلسل NPN لكل محافظة (كتلة تخصيص) — يضمن تفرّد رقم العقار الوطني."""
    gov_code: int = Field(primary_key=True)          # كود المحافظة (10, 31, …)
    next_seq: int = Field(default=0)                 # التسلسل التالي المتاح


# ═══════════════════════ تطبيق المشتركين — OTP واتساب ═══════════════════════

class OtpCode(SQLModel, table=True):
    """رمز تحقّق لمرة واحدة (OTP) يُرسَل عبر واتساب لرقم هاتف المشترك.
    يُخزَّن مجزّأً (لا يُحفظ الرمز نصّاً)؛ صالح لدقائق محدودة وبعدد محاولات محدود."""
    id: Optional[int] = Field(default=None, primary_key=True)
    phone: str = Field(index=True)                  # رقم مطبَّع بصيغة دولية (9647xxxxxxxxx)
    code_hash: str = ""
    attempts: int = 0                               # محاولات التحقّق الفاشلة
    consumed: bool = False
    expires_at: datetime = Field(default_factory=utcnow, index=True)
    created_at: datetime = Field(default_factory=utcnow, index=True)


# ═══════════════════════ التذاكر — شكاوى/طلبات المشتركين ═══════════════════════

class Ticket(SQLModel, table=True):
    """تذكرة (شكوى/طلب) يفتحها مشترك أو موظّف نيابةً عنه.
    مسار المتابعة: المشترك → الوكيل → الشركة → الوزارة (كلٌّ يرى نطاقه)."""
    id: Optional[int] = Field(default=None, primary_key=True)
    company_id: int = Field(foreign_key="company.id", index=True)
    agent_username: str = Field(default="", index=True)     # وكيل المشترك (من SAS)
    subscriber_username: str = Field(default="", index=True)
    subscriber_phone: str = Field(default="", index=True)   # مطبَّع (9647…)
    subscriber_name: str = ""
    category: str = Field(default="complaint", index=True)  # complaint | outage | billing | speed | other
    subject: str = ""
    body: str = ""
    status: str = Field(default="open", index=True)         # open | in_progress | resolved | closed
    priority: str = Field(default="normal")                 # low | normal | high | urgent
    escalated: bool = Field(default=False, index=True)      # مُصعَّدة للوزارة
    created_by: str = ""                                    # phone أو username الموظّف
    created_by_kind: str = "subscriber"                     # subscriber | agent | company | regulator
    assigned_to: str = ""
    created_at: datetime = Field(default_factory=utcnow, index=True)
    updated_at: datetime = Field(default_factory=utcnow)
    resolved_at: Optional[datetime] = None


class SasPortalAudit(SQLModel, table=True):
    """تدقيق عمليات بوابة المشترك (تغيير كلمة مرور/استبدال كرت/تغيير اشتراك…) —
    ومنع تكرار العمليات المالية عبر transaction_id الفريد (idempotency)."""
    id: Optional[int] = Field(default=None, primary_key=True)
    account_id: int = Field(index=True)                 # Subscriber.id صاحب العملية
    action: str = Field(default="")                     # link | change_password | redeem | change_subscription | activate | extend
    # فريد عند وجوده؛ None مسموح تكراره (SQLite يسمح بعدّة NULL تحت UNIQUE)
    transaction_id: Optional[str] = Field(default=None, index=True, unique=True)
    status: str = Field(default="ok")                   # ok | failed
    detail: str = Field(default="")
    ts: datetime = Field(default_factory=utcnow, index=True)


class TicketReply(SQLModel, table=True):
    """ردّ على تذكرة — من المشترك أو أي طرف في سلسلة المتابعة."""
    id: Optional[int] = Field(default=None, primary_key=True)
    ticket_id: int = Field(foreign_key="ticket.id", index=True)
    author: str = ""
    author_kind: str = "subscriber"                         # subscriber | agent | company | regulator
    body: str = ""
    internal: bool = False                                  # ملاحظة داخلية لا يراها المشترك
    ts: datetime = Field(default_factory=utcnow, index=True)
