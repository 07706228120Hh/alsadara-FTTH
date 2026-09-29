"""
مكتبة أوامر Huawei OLT — مستخرجة من دليلي HCIA-Access و HCIP-Access V2.5.
كل دالة تُرجع قائمة أوامر جاهزة للتنفيذ عبر جلسة CLI.
هذا يفصل "معرفة الأوامر" عن "تنفيذها"، فيسهل الصيانة والتوسّع.
"""
import re
from typing import List, Optional

# تصنيف الأوامر: read = عرض آمن | write = تغيير | dangerous = خطر (يحتاج تأكيداً مزدوجاً)
# مطابقة ككلمات مستقلة (\b) لا كسلاسل فرعية — كي لا يُصنَّف مثلاً "display ont deleted" كخطر.
DANGEROUS_PATTERNS = (
    r"\berase\b",
    r"\breboot\b",
    r"\bdelete\b",
    r"\breset\b",
    r"\bfactory-setting\b",
    r"\bundo\s+service-port\b",
)
# أوامر العرض الآمنة فقط — لاحظ إزالة "telnet" (قد يُستخدم للتمحور/التسريب من الجهاز).
READ_PREFIXES = ("display", "ping", "show")


def classify(command: str) -> str:
    low = command.lower().strip()
    if any(re.search(p, low) for p in DANGEROUS_PATTERNS):
        return "dangerous"
    if low.startswith(READ_PREFIXES):
        return "read"
    return "write"


# ---------------------------------------------------------------------------
# أوامر العرض والتشخيص (read)
# ---------------------------------------------------------------------------
DISPLAY = {
    "board":            lambda: "display board 0",
    "board_detail":     lambda fsp: f"display board {fsp}",
    "version":          lambda: "display version",
    "ont_autofind":     lambda port: f"display ont autofind {port}",
    "ont_autofind_all": lambda: "display ont autofind all",
    "ont_info_all":     lambda port: f"display ont info {port} all",
    "ont_info":         lambda f, s, p, o: f"display ont info {f} {s} {p} {o}",
    "port_state":       lambda port: f"display port state {port}",   # القدرة الضوئية والليزر
    "ont_failed":       lambda: "display ont failed-configuration",
    "ont_capability":   lambda f, s, p, o: f"display ont capability {f} {s} {p} {o}",
    "dba_profile_all":  lambda: "display dba-profile all",
    "lineprofile_all":  lambda: "display ont-lineprofile gpon all",
    "srvprofile_all":   lambda: "display ont-srvprofile gpon all",
    "traffic_table":    lambda: "display traffic table ip from-index 0",
    "vlan":             lambda vid: f"display vlan {vid}",
    "service_port_all": lambda: "display service-port all",
    "cpu":              lambda fs: f"display cpu {fs}",
    "security_config":  lambda: "display security config",
    "mac_filter":       lambda: "display security mac-filter",
    "protect_group":    lambda gid: f"display protect-group {gid}",
    "lacp_verbose":     lambda gid: f"display lacp link-aggregation verbose {gid}",
    "esl_online":       lambda fsp: f"display esl online-info startuser {fsp}",  # جودة المكالمة MOS
    "current_config":   lambda: "display current-configuration",
    "client":           lambda: "display client",
    # عرض إضافي (VoIP / IPTV / VLAN) — من HCIP-Access Lab Guide
    "vlan_all":         lambda: "display vlan all",
    "mvlan_all":        lambda: "display multicast-vlan all",
    "igmp_program":     lambda mvlan: f"display igmp program multicast-vlan {mvlan}",
    "protocol_support": lambda: "display protocol support",
    "sippstnuser":      lambda fsp: f"display sippstnuser {fsp}",
    "sip_interface":    lambda mgid: f"display if-sip attribute {mgid}",
    "ont_wan_info":     lambda f, s, p, o: f"display ont wan-info {f} {s} {p} {o}",
    "ont_register":     lambda port: f"display ont register-info {port} all",
}


# ---------------------------------------------------------------------------
# سلاسل التزويد (write) — كل دالة تُرجع قائمة أوامر بالترتيب
# ---------------------------------------------------------------------------

def enter_config() -> List[str]:
    return ["enable", "config"]


def dba_profile_add(profile_id: int, dba_type: int, *,
                    fix: Optional[int] = None, assure: Optional[int] = None,
                    max_bw: Optional[int] = None, name: str = "") -> str:
    """إنشاء DBA profile (الأنواع 1-5)"""
    base = f"dba-profile add profile-id {profile_id}"
    if name:
        base += f" profile-name {name}"
    base += f" type{dba_type}"
    if dba_type == 1 and fix:
        base += f" fix {fix}"
    elif dba_type == 2 and assure:
        base += f" assure {assure}"
    elif dba_type == 3:
        base += f" assure {assure} max {max_bw}"
    elif dba_type == 4 and max_bw:
        base += f" max {max_bw}"
    return base


def line_profile(profile_id: int, name: str, tcont: int, dba_id: int,
                 gem: int, vlan: int, mapping_index: int = 1) -> List[str]:
    """إنشاء Line profile كامل مع commit"""
    return [
        f"ont-lineprofile gpon profile-id {profile_id} profile-name {name}",
        f"tcont {tcont} dba-profile-id {dba_id}",
        f"gem add {gem} eth tcont {tcont}",
        "mapping-mode vlan",
        f"gem mapping {gem} {mapping_index} vlan {vlan}",
        "commit",
        "quit",
    ]


def srv_profile(profile_id: int, name: str, eth_ports: int, vlan: int,
                pots: int = 2, catv: int = 1) -> List[str]:
    """إنشاء Service profile (للـ ONT بوضع OMCI)"""
    return [
        f"ont-srvprofile gpon profile-id {profile_id} profile-name {name}",
        f"ont-port eth {eth_ports} pots {pots} catv {catv}",
        f"port vlan eth 1 {vlan}",
        "commit",
        "quit",
    ]


def traffic_table_car(index: int, cir: int, pir: int, priority: int = 0) -> str:
    """جدول CAR لتحديد السرعة"""
    return f"traffic table ip index {index} cir {cir} pir {pir} priority {priority} priority-policy local-Setting"


def confirm_ont(port: int, ont_id: int, sn: str, mgmt: str,
                line_id: int, srv_id: Optional[int] = None) -> List[str]:
    """تأكيد ONT مكتشَف وربطه بالبروفايلات"""
    cmd = f"ont confirm {port} ontid {ont_id} sn-auth {sn} {mgmt} ont-lineprofile-id {line_id}"
    if mgmt == "omci" and srv_id is not None:
        cmd += f" ont-srvprofile-id {srv_id}"
    return [f"interface gpon 0/{port}", cmd]


def create_service_vlan(vlan: int, upstream_fsp: str, qinq: bool = False) -> List[str]:
    """إنشاء VLAN خدمة وربطه بالمنفذ الصاعد"""
    slot, port = upstream_fsp.split("/")[1], upstream_fsp.split("/")[2]
    cmds = [f"vlan {vlan} smart"]
    if qinq:
        cmds.append(f"vlan attrib {vlan} q-in-q")
    cmds.append(f"port vlan {vlan} 0/{slot} {port}")
    return cmds


def service_port(index: int, svlan: int, fsp: str, ont_id: int, gem: int,
                 user_vlan: int, rx_cttr: Optional[int] = None,
                 tx_cttr: Optional[int] = None) -> str:
    """إنشاء تدفق الخدمة (service-port)"""
    f, s, p = fsp.split("/")
    cmd = (f"service-port {index} vlan {svlan} gpon {f}/{s}/{p} ont {ont_id} "
           f"gemport {gem} multi-service user-vlan {user_vlan}")
    if rx_cttr is not None and tx_cttr is not None:
        cmd += f" rx-cttr {rx_cttr} tx-cttr {tx_cttr}"
    return cmd


# ---------------------------------------------------------------------------
# أوامر إدارة عامة (System) — من HCIA Lab §3.4.1
# ---------------------------------------------------------------------------

def set_sysname(name: str) -> str:
    """تسمية الجهاز"""
    return f"sysname {name}"


def board_confirm(fs: str = "0") -> str:
    """تأكيد بورد بعد تركيبه — fs مثل '0' أو '0/5'"""
    return f"board confirm {fs}"


def uplink_port_vlan(vlan: int, uplink_fsp: str) -> str:
    """السماح لـ VLAN بالمرور عبر المنفذ الصاعد. uplink_fsp مثل '0/19/0'."""
    parts = uplink_fsp.split("/")
    fs = "/".join(parts[:2])          # 0/19
    port = parts[2] if len(parts) > 2 else "0"
    return f"port vlan {vlan} {fs} {port}"


def ont_add(port: int, ont_id: int, sn: str, mgmt: str,
            line_id: int, srv_id: Optional[int] = None) -> str:
    """تزويد مُسبق لـ ONT بالـ SN دون انتظار الاكتشاف التلقائي (HCIA Lab).
    مثال المرجع: ont add 0 5 sn-auth <SN> omci ont-lineprofile-id 31 ont-srvprofile-id 31"""
    cmd = f"ont add {port} {ont_id} sn-auth {sn} {mgmt} ont-lineprofile-id {line_id}"
    if mgmt == "omci" and srv_id is not None:
        cmd += f" ont-srvprofile-id {srv_id}"
    return cmd


def ont_native_vlan(port: int, ont_id: int, eth: int, vlan: int) -> str:
    """تعيين VLAN افتراضي لمنفذ إيثرنت على الـ ONT"""
    return f"ont port native-vlan {port} {ont_id} eth {eth} vlan {vlan}"


def srv_profile_iptv(profile_id: int, name: str, eth_ports: int,
                     stb_eth: int, mvlan: int, pots: int = 2) -> List[str]:
    """Service profile لـ IPTV — يضيف multicast-forward untag (HCIP Lab §5)."""
    return [
        f"ont-srvprofile gpon profile-id {profile_id} profile-name {name}",
        f"ont-port eth {eth_ports} pots {pots}",
        f"port vlan eth {stb_eth} {mvlan}",
        "multicast-forward untag",
        "commit",
        "quit",
    ]


# ---------------------------------------------------------------------------
# IPTV / Multicast (BTV + IGMP) — من HCIP-Access Lab §5–6
# ---------------------------------------------------------------------------

def igmp_user_add(sp_index: int) -> List[str]:
    """تسجيل مستخدم IGMP مربوط بتدفق الخدمة"""
    return [
        "btv",
        f"igmp user add service-port {sp_index} no-auth",
        "quit",
    ]


def multicast_vlan_setup(mvlan: int, uplink_fsp: str, sp_index: int,
                         version: str = "v3", mode: str = "proxy") -> List[str]:
    """تهيئة multicast-vlan كاملة: المنفذ الصاعد، النسخة، الوضع، والعضوية."""
    return [
        f"multicast-vlan {mvlan}",
        f"igmp uplink-port {uplink_fsp}",
        f"igmp version {version}",
        "igmp match mode disable",
        f"igmp mode {mode}",
        f"igmp multicast-vlan member service-port {sp_index}",
        "quit",
    ]


def igmp_program_add(name: str, group_ip: str, source_ip: str) -> str:
    """إضافة قناة multicast (لوضع igmp match mode enable)"""
    return f"igmp program add name {name} ip {group_ip} sourceip {source_ip}"


# ---------------------------------------------------------------------------
# VoIP (SIP على MDU/MxU) — من HCIP-Access Lab §3
# ---------------------------------------------------------------------------

def protocol_support_sip() -> str:
    """تحويل بروتوكول الصوت إلى SIP (يتطلب save + reboot لاحقاً)"""
    return "protocol support sip"


def vlanif_ip(vlanif: int, ip: str, mask_bits: int) -> List[str]:
    """واجهة L3 للـ VLAN وعنوان IP"""
    return [
        f"interface vlanif {vlanif}",
        f"ip address {ip} {mask_bits}",
        "quit",
    ]


def ip_route_static(dest: str, mask_bits: int, next_hop: str) -> str:
    """مسار ثابت افتراضي نحو السوفت-سويتش"""
    return f"ip route-static {dest} {mask_bits} {next_hop}"


def voip_ip_pool(media_ip: str, gateway: str, signaling_ip: str) -> List[str]:
    """تعريف عناوين media/signaling في وضع voip"""
    return [
        "voip",
        f"ip address media {media_ip} {gateway}",
        f"ip address signaling {signaling_ip}",
        "quit",
    ]


def sip_interface(mgid: int, media_ip: str, signal_ip: str, proxy_ip: str, *,
                  signal_port: int = 5060, proxy_port: int = 5060,
                  home_domain: str = "huawei", transfer: str = "udp") -> List[str]:
    """إنشاء وضبط وتفعيل واجهة SIP (media-gateway)."""
    return [
        f"interface sip {mgid}",
        (f"if-sip attribute basic media-ip {media_ip} signal-ip {signal_ip} "
         f"signal-port {signal_port} transfer {transfer} "
         f"primary-proxy-ip1 {proxy_ip} primary-proxy-port {proxy_port} "
         f"home-domain {home_domain}"),
        "reset",
        "quit",
    ]


def sip_pstn_user(fsp: str, mgid: int, telno: str) -> List[str]:
    """إضافة مشترك PSTN عبر SIP مع بيانات المصادقة."""
    return [
        "esl user",
        f"sippstnuser add {fsp} {mgid} telno {telno}",
        f"sippstnuser auth set {fsp} telno {telno} password-mode password",
        "quit",
    ]


def local_digitmap(name: str, body: str, dm_type: str = "normal") -> str:
    """إضافة خطة ترقيم محلية (digitmap) لـ SIP"""
    return f"local-digitmap add {name} {dm_type} {body}"


def protocol_support(proto: str = "sip") -> str:
    """تحويل بروتوكول الصوت (sip/h248) — يتطلب save + reboot لاحقاً."""
    return f"protocol support {proto}"


def h248_interface(mgid: int, mgip: str, media_ip: str, mgc_ip: str, *,
                   mgport: int = 2944, mgc_port: int = 2944,
                   transfer: str = "udp") -> List[str]:
    """إنشاء وضبط وتفعيل واجهة H.248 (MG) — HCIP-Access Lab §3."""
    return [
        f"interface h248 {mgid}",
        (f"if-h248 attribute mgip {mgip} mgport {mgport} mg-media-ip1 {media_ip} "
         f"primary-mgc-ip1 {mgc_ip} primary-mgc-port {mgc_port} transfer {transfer} "
         f"code text start-negotiate-version 0"),
        "reset coldstart",
        "quit",
    ]


def mg_pstn_user(fsp: str, mgid: int, telno: str, terminalid: int = 0) -> List[str]:
    """إضافة مشترك PSTN عبر H.248."""
    return [
        "esl user",
        f"mgpstnuser add {fsp} {mgid} telno {telno} terminalid {terminalid}",
        "quit",
    ]


def ont_ipconfig_static(port: int, ont_id: int, ip: str, mask: str,
                        gateway: str, vlan: int) -> str:
    """عنوان IP إداري ثابت لـ ONT/MDU عبر القناة الداخلية (inband)."""
    return (f"ont ipconfig {port} {ont_id} static ip-address {ip} "
            f"mask {mask} gateway {gateway} vlan {vlan}")


def queue_scheduler(mode: str = "pq") -> str:
    """جدولة الطوابير العامة (QoS): pq = أولوية صارمة · wrr = دوري مرجّح."""
    if mode == "wrr":
        return "queue-scheduler wrr 0 10 20 30 40 50 60 70"
    return "queue-scheduler pq"


# ---------------------------------------------------------------------------
# FTTB/xDSL — تزويد عبر MDU/DSLAM (بناءً على HCIA/HCIP-Access Lab)
# ---------------------------------------------------------------------------

def fttb_service_port(index: int, svlan: int, fsp: str, ont_id: int,
                      user_vlan: int, eth_port: int = 1,
                      rx_cttr: Optional[int] = None,
                      tx_cttr: Optional[int] = None) -> str:
    """service-port لخدمة FTTB LAN على منفذ إيثرنت لـ MDU/ONT."""
    f, s, p = fsp.split("/")
    cmd = (f"service-port {index} vlan {svlan} gpon {f}/{s}/{p} ont {ont_id} "
           f"eth {eth_port} multi-service user-vlan {user_vlan}")
    if rx_cttr is not None and tx_cttr is not None:
        cmd += f" rx-cttr {rx_cttr} tx-cttr {tx_cttr}"
    return cmd


def vdsl_profile_add(profile_id: int, name: str = "vdsl_profile",
                     max_rate: int = 100000, snr: int = 6) -> List[str]:
    """إنشاء VDSL profile و line template."""
    return [
        f"vdsl-profile add {profile_id} {name}",
        f"vdsl line-template add {profile_id} profile-id {profile_id}",
        f"vdsl line-template attribute {profile_id} snr-margin {snr}",
        "quit",
    ]


def adsl_profile_add(profile_id: int, name: str = "adsl_profile",
                     max_rate: int = 24000) -> List[str]:
    """إنشاء ADSL profile."""
    return [
        f"adsl-profile add {profile_id} {name}",
        f"adsl line-template add {profile_id} profile-id {profile_id}",
        "quit",
    ]


def xdsl_service_port(index: int, svlan: int, fsp: str, ont_id: int,
                      user_vlan: int, vpi: int = 0, vci: int = 35,
                      rx_cttr: Optional[int] = None,
                      tx_cttr: Optional[int] = None) -> str:
    """service-port لخدمة xDSL عبر PVC."""
    f, s, p = fsp.split("/")
    cmd = (f"service-port {index} vlan {svlan} gpon {f}/{s}/{p} ont {ont_id} "
           f"vpi {vpi} vci {vci} multi-service user-vlan {user_vlan}")
    if rx_cttr is not None and tx_cttr is not None:
        cmd += f" rx-cttr {rx_cttr} tx-cttr {tx_cttr}"
    return cmd


SAVE = "save"
