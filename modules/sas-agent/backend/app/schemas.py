"""مخططات الطلب/الاستجابة (Pydantic)"""
from typing import Optional, List, Dict
from pydantic import BaseModel


class DeviceCreate(BaseModel):
    name: str
    host: str
    port: int = 22
    protocol: str = "ssh"
    username: str = "root"
    password: str = "admin"
    model: str = "MA5800"
    # --- SNMPv3 (اختيارية — مع قيم افتراضية) ---
    snmp_enabled: bool = True
    snmp_port: int = 161
    snmp_user: str = "platform-monitor"
    snmp_auth_proto: str = "SHA256"
    snmp_auth_key: str = ""          # نص خام يُشفَّر عند الحفظ
    snmp_priv_proto: str = "AES"
    snmp_priv_key: str = ""          # نص خام يُشفَّر عند الحفظ
    snmp_context: str = ""
    snmp_engine_id: str = ""
    adapter_profile: str = ""


class DeviceOut(BaseModel):
    id: int
    name: str
    host: str
    model: str
    reachable: bool
    enabled: bool
    # --- SNMPv3 (لا مفاتيح — خام ولا مشفَّر) ---
    snmp_enabled: bool
    snmp_user: str
    adapter_profile: str


class SNMPTestResult(BaseModel):
    """نتيجة اختبار اتصال SNMPv3 بجهاز."""
    ok: bool
    sysDescr: str = ""
    uptime: int = 0
    error: Optional[str] = None


class CommandRequest(BaseModel):
    command: str


class FTTHProvisionRequest(BaseModel):
    service_type: str = "hsi"        # hsi (إنترنت) | iptv (multicast) | fttb | xdsl
    fsp: str = "0/5/0"
    ont_id: int
    sn: str
    svlan: int = 2000
    cvlan: int = 35
    uplink_fsp: str = "0/19/0"       # المنفذ الصاعد الذي يمرّ عبره VLAN الخدمة
    preprovision: bool = False       # True = تزويد مُسبق بالـ SN (ont add) بدل الاكتشاف
    profile_name: str = "hsi"
    dba_max: int = 4096
    car_index: Optional[int] = None
    car_cir: int = 4096
    car_pir: int = 8192
    # خاص بـ IPTV
    mvlan: int = 200                 # multicast VLAN
    stb_eth: int = 2                 # منفذ إيثرنت الموصول بالـ STB
    igmp_version: str = "v3"
    igmp_mode: str = "proxy"
    # خاص بـ FTTB/xDSL
    eth_port: int = 1                # منفذ LAN على MDU لـ FTTB
    dsl_type: str = "vdsl"           # vdsl | adsl
    vpi: int = 0
    vci: int = 35
    dry_run: bool = True   # true = عرض الأوامر فقط دون تنفيذ


class MDUSIPUser(BaseModel):
    fsp: str
    telno: str


class MDUSIPProvisionRequest(BaseModel):
    voice_vlan: int = 172
    uplink_fsp: str = "0/19/0"
    mdu_ip: str = "17.1.1.43"
    mask_bits: int = 8
    media_ip: str = "17.1.1.43"
    gateway: str = "17.0.0.1"
    softswitch_net: str = "200.200.200.0"
    softswitch_mask_bits: int = 24
    softswitch_nexthop: str = "17.0.0.1"
    proxy_ip: str = "200.200.200.200"
    mgid: int = 30
    users: Optional[List[MDUSIPUser]] = None
    dry_run: bool = True


class ConfigBuildRequest(BaseModel):
    """طلب بناء/تنفيذ إجراء من كتالوج التهيئة."""
    procedure: str
    params: Optional[Dict] = None


class DiagnoseRequest(BaseModel):
    fsp: str
    ont_id: int


class AIChatRequest(BaseModel):
    question: str
    history: Optional[List[Dict]] = None


# ==== المصادقة وإدارة المستخدمين ====
class LoginRequest(BaseModel):
    username: str
    password: str


class UserCreate(BaseModel):
    username: str
    password: str
    role: str = "viewer"            # viewer | operator | admin
    # النطاق (اختياري — للجهة الرقابية فقط أن تُحدّده):
    #   كلاهما فارغ           → جهة رقابية (وزارة) ترى الكل
    #   scope_company_id فقط  → مدير شركة (مقيّد بالشركة)
    #   الاثنان معاً          → وكيل (مقيّد بالشركة + الوكيل)
    scope_company_id: Optional[int] = None
    scope_agent: str = ""


class UserUpdate(BaseModel):
    username: Optional[str] = None   # تغيير الاسم يُخرج الحساب (توكناته تُبطَل)
    role: Optional[str] = None
    enabled: Optional[bool] = None
    password: Optional[str] = None
    # تعديل النطاق (اختياري): يُطبَّق فقط إن وُرِد أيّ من الحقلين صراحةً.
    #   scope_company_id=None + scope_agent="" → إعادة الحساب جهةً رقابية.
    scope_company_id: Optional[int] = None
    scope_agent: Optional[str] = None


class UserOut(BaseModel):
    id: int
    username: str
    role: str
    enabled: bool
    scope_company_id: Optional[int] = None
    scope_agent: str = ""
