"""
محرك التزويد — يبني تسلسل أوامر تفعيل الخدمة كاملاً ثم ينفّذه خطوة خطوة مع تسجيل كل أمر.
كل سلسلة مُتحقَّق منها مقابل «Configuration Reference» في أدلة HCIA/HCIP-Access V2.5:
- HSI (إنترنت)      → HCIA-Access Lab §3.4.1
- IPTV (Multicast)  → HCIP-Access Lab §5–6
- VoIP (SIP على MDU)→ HCIP-Access Lab §3
"""
from typing import List, Dict, Optional
from ..core import command_library as cl
from ..core.olt_connection import manager


class ProvisionPlan:
    """خطة تزويد — تُبنى ثم تُنفَّذ خطوة خطوة، وتُسجّل كل أمر"""

    def __init__(self):
        self.steps: List[Dict] = []

    def add(self, title: str, commands: List[str], kind: str = "write"):
        self.steps.append({"title": title, "commands": commands, "kind": kind})
        return self


def _confirm_or_add(*, fsp: str, ont_id: int, sn: str, line_id: int,
                    srv_id: Optional[int], mgmt: str, preprovision: bool,
                    native_eth: int, native_vlan: int) -> Dict:
    """يبني خطوة تسجيل الـ ONT: إمّا اكتشاف تلقائي + confirm، أو تزويد مُسبق بالـ SN."""
    f, s, p = fsp.split("/")
    port = int(p)
    if preprovision:
        # تزويد مُسبق بالـ SN دون انتظار الاكتشاف (HCIA Lab — ont add)
        cmds = [
            f"interface gpon 0/{s}",
            cl.ont_add(port, ont_id, sn, mgmt, line_id, srv_id),
            cl.ont_native_vlan(port, ont_id, native_eth, native_vlan),
            "quit",
        ]
        title = "تزويد مُسبق للـ ONT بالـ SN (ont add)"
    else:
        confirm = (f"ont confirm {port} ontid {ont_id} sn-auth {sn} {mgmt} "
                   f"ont-lineprofile-id {line_id}")
        if mgmt == "omci" and srv_id is not None:
            confirm += f" ont-srvprofile-id {srv_id}"
        cmds = [
            f"interface gpon 0/{s}",
            f"port {port} ont-auto-find enable",
            confirm,
            cl.ont_native_vlan(port, ont_id, native_eth, native_vlan),
            "quit",
        ]
        title = "تفعيل الاكتشاف التلقائي وتأكيد الـ ONT"
    return {"title": title, "commands": cmds}


def build_ftth_plan(*, fsp: str, ont_id: int, sn: str, svlan: int, cvlan: int,
                    uplink_fsp: str = "0/19/0", preprovision: bool = False,
                    mgmt: str = "omci",
                    dba_id: int = 15, dba_max: int = 4096,
                    line_id: int = 10, srv_id: int = 10,
                    gem: int = 10, tcont: int = 10,
                    sp_index: int = 100, car_index: Optional[int] = None,
                    car_cir: int = 4096, car_pir: int = 8192,
                    profile_name: str = "hsi", qinq: bool = True) -> ProvisionPlan:
    """
    خطة تفعيل مشترك FTTH HSI (إنترنت، ONT بوضع OMCI) — HCIA-Access Lab §3.4.1.
    fsp مثال: "0/5/0" — cvlan = VLAN المستخدم الداخلي — svlan = VLAN الخدمة الخارجي.
    """
    plan = ProvisionPlan()
    plan.add("الدخول لوضع التهيئة", cl.enter_config(), "read")

    # 1) CAR (اختياري) — يجب إنشاؤه قبل الإشارة إليه في service-port
    if car_index is not None:
        plan.add("إنشاء جدول CAR (تحديد السرعة)",
                 [cl.traffic_table_car(car_index, car_cir, car_pir)])

    # 2) DBA profile
    plan.add("إنشاء DBA profile (النطاق الصاعد)",
             [cl.dba_profile_add(dba_id, 4, max_bw=dba_max, name=profile_name)])

    # 3) Line profile
    plan.add("إنشاء Line profile",
             cl.line_profile(line_id, profile_name, tcont, dba_id, gem, cvlan))

    # 4) Service profile (OMCI)
    plan.add("إنشاء Service profile",
             cl.srv_profile(srv_id, profile_name, eth_ports=4, vlan=cvlan))

    # 5) اكتشاف/تزويد وتأكيد الـ ONT + native-vlan
    step = _confirm_or_add(fsp=fsp, ont_id=ont_id, sn=sn, line_id=line_id,
                           srv_id=srv_id, mgmt=mgmt, preprovision=preprovision,
                           native_eth=1, native_vlan=cvlan)
    plan.add(step["title"], step["commands"])

    # 6) VLAN الخدمة + المنفذ الصاعد
    plan.add("إنشاء VLAN الخدمة وربطه بالمنفذ الصاعد",
             cl.create_service_vlan(svlan, uplink_fsp, qinq=qinq))

    # 7) Service-port
    plan.add("إنشاء تدفق الخدمة (service-port)",
             [cl.service_port(sp_index, svlan, fsp, ont_id, gem, cvlan,
                              rx_cttr=car_index, tx_cttr=car_index)])

    # 8) حفظ
    plan.add("حفظ الإعدادات", [cl.SAVE])
    return plan


def build_iptv_plan(*, fsp: str, ont_id: int, sn: str, mvlan: int,
                    uplink_fsp: str = "0/19/0", stb_eth: int = 2,
                    preprovision: bool = False,
                    dba_id: int = 10, dba_assure: int = 10240, dba_max: int = 20240,
                    line_id: int = 11, srv_id: int = 13,
                    gem: int = 0, tcont: int = 2, sp_index: int = 10,
                    igmp_version: str = "v3", igmp_mode: str = "proxy",
                    profile_name: str = "IPTV") -> ProvisionPlan:
    """
    خطة تفعيل خدمة IPTV (Multicast عبر BTV/IGMP) — HCIP-Access Lab §5.
    mvlan = multicast VLAN — stb_eth = منفذ الإيثرنت الموصول بالـ STB.
    """
    plan = ProvisionPlan()
    plan.add("الدخول لوضع التهيئة", cl.enter_config(), "read")

    # 1) DBA (type3: assure + max)
    plan.add("إنشاء DBA profile (type3)",
             [cl.dba_profile_add(dba_id, 3, assure=dba_assure, max_bw=dba_max,
                                 name=profile_name)])

    # 2) Line profile — يربط GEM بالـ multicast VLAN
    plan.add("إنشاء Line profile",
             cl.line_profile(line_id, profile_name, tcont, dba_id, gem, mvlan))

    # 3) Service profile IPTV (multicast-forward untag)
    plan.add("إنشاء Service profile لـ IPTV",
             cl.srv_profile_iptv(srv_id, profile_name, eth_ports=4,
                                 stb_eth=stb_eth, mvlan=mvlan))

    # 4) اكتشاف/تزويد وتأكيد الـ ONT + native-vlan للـ STB
    step = _confirm_or_add(fsp=fsp, ont_id=ont_id, sn=sn, line_id=line_id,
                           srv_id=srv_id, mgmt="omci", preprovision=preprovision,
                           native_eth=stb_eth, native_vlan=mvlan)
    plan.add(step["title"], step["commands"])

    # 5) VLAN الخدمة (multicast) + المنفذ الصاعد
    plan.add("إنشاء multicast VLAN وربطه بالمنفذ الصاعد", [
        f"vlan {mvlan} smart",
        cl.uplink_port_vlan(mvlan, uplink_fsp),
    ])

    # 6) Service-port للـ IPTV
    plan.add("إنشاء تدفق خدمة IPTV (service-port)",
             [cl.service_port(sp_index, mvlan, fsp, ont_id, gem, mvlan)])

    # 7) مستخدم IGMP
    plan.add("تسجيل مستخدم IGMP", cl.igmp_user_add(sp_index))

    # 8) تهيئة multicast-vlan (uplink/version/mode/member)
    plan.add("تهيئة multicast-vlan",
             cl.multicast_vlan_setup(mvlan, uplink_fsp, sp_index,
                                     version=igmp_version, mode=igmp_mode))

    # 9) حفظ
    plan.add("حفظ الإعدادات", [cl.SAVE])
    return plan


def build_mdu_sip_plan(*, voice_vlan: int, uplink_fsp: str,
                       mdu_ip: str, mask_bits: int, media_ip: str,
                       gateway: str, softswitch_net: str, softswitch_mask_bits: int,
                       softswitch_nexthop: str, proxy_ip: str, mgid: int = 30,
                       users: Optional[List[Dict]] = None,
                       digitmap_name: str = "SIPmap",
                       digitmap_body: str = "x.T|x.S",
                       home_domain: str = "huawei") -> ProvisionPlan:
    """
    خطة تفعيل خدمة الصوت SIP على MDU/MxU (بوابة صوت) — HCIP-Access Lab §3.
    users = [{"fsp": "0/2/1", "telno": "7727043"}, ...]
    ملاحظة: `protocol support sip` يتطلب `save` ثم `reboot` لتفعيله (ينبَّه المستخدم).
    """
    users = users or []
    plan = ProvisionPlan()
    plan.add("الدخول لوضع التهيئة", cl.enter_config(), "read")

    plan.add("تحويل بروتوكول الصوت إلى SIP (يتطلب save + reboot)",
             [cl.protocol_support_sip()])

    plan.add("إنشاء VLAN الصوت وربطه بالمنفذ الصاعد", [
        f"vlan {voice_vlan} smart",
        cl.uplink_port_vlan(voice_vlan, uplink_fsp),
    ])

    plan.add("واجهة L3 وعنوان IP للصوت", cl.vlanif_ip(voice_vlan, mdu_ip, mask_bits))

    plan.add("مسار ثابت نحو السوفت-سويتش",
             [cl.ip_route_static(softswitch_net, softswitch_mask_bits, softswitch_nexthop)])

    plan.add("تعريف عناوين media/signaling (voip)",
             cl.voip_ip_pool(media_ip, gateway, media_ip))

    plan.add("إنشاء وتفعيل واجهة SIP",
             cl.sip_interface(mgid, media_ip, media_ip, proxy_ip,
                              home_domain=home_domain))

    plan.add("خطة الترقيم المحلية (digitmap)",
             [cl.local_digitmap(digitmap_name, digitmap_body)])

    for u in users:
        plan.add(f"إضافة مشترك PSTN/SIP: {u.get('telno', '')}",
                 cl.sip_pstn_user(u["fsp"], mgid, u["telno"]))

    plan.add("حفظ الإعدادات", [cl.SAVE])
    return plan


# سلاسل التزويد المتاحة حسب نوع الخدمة (للاستخدام من طبقة الـ API)
SERVICE_TYPES = ("hsi", "iptv", "voip", "fttb", "xdsl")


def build_fttb_plan(*, fsp: str, ont_id: int, sn: str, svlan: int, cvlan: int,
                    uplink_fsp: str = "0/19/0", preprovision: bool = False,
                    eth_port: int = 1, sp_index: int = 100,
                    car_index: Optional[int] = None,
                    car_cir: int = 4096, car_pir: int = 8192) -> ProvisionPlan:
    """
    خطة تفعيل خدمة FTTB LAN على MDU/ONT (بدون بروفايلات OMCI).
    fsp = منفذ GPON المُربط فيه الـ MDU.
    """
    plan = ProvisionPlan()
    plan.add("الدخول لوضع التهيئة", cl.enter_config(), "read")

    if car_index is not None:
        plan.add("إنشاء جدول CAR (تحديد السرعة)",
                 [cl.traffic_table_car(car_index, car_cir, car_pir)])

    plan.add("إنشاء VLAN الخدمة وربطه بالمنفذ الصاعد",
             cl.create_service_vlan(svlan, uplink_fsp))

    # تأكيد ONT/MDU (بدون srv-profile لأن MDU بوضع SNMP/OMCI بسيط)
    step = _confirm_or_add(fsp=fsp, ont_id=ont_id, sn=sn, line_id=10,
                           srv_id=None, mgmt="snmp", preprovision=preprovision,
                           native_eth=eth_port, native_vlan=cvlan)
    plan.add(step["title"], step["commands"])

    plan.add("إنشاء تدفق خدمة FTTB (service-port)",
             [cl.fttb_service_port(sp_index, svlan, fsp, ont_id, cvlan,
                                   eth_port=eth_port,
                                   rx_cttr=car_index, tx_cttr=car_index)])

    plan.add("حفظ الإعدادات", [cl.SAVE])
    return plan


def build_xdsl_plan(*, dsl_type: str = "vdsl", fsp: str, ont_id: int, sn: str,
                    svlan: int, cvlan: int, uplink_fsp: str = "0/19/0",
                    preprovision: bool = False, profile_id: int = 20,
                    vpi: int = 0, vci: int = 35, sp_index: int = 200,
                    car_index: Optional[int] = None,
                    car_cir: int = 4096, car_pir: int = 8192) -> ProvisionPlan:
    """
    خطة تفعيل خدمة xDSL عبر MDU/ONT (VDSL/ADSL).
    dsl_type: vdsl | adsl
    """
    plan = ProvisionPlan()
    plan.add("الدخول لوضع التهيئة", cl.enter_config(), "read")

    if car_index is not None:
        plan.add("إنشاء جدول CAR (تحديد السرعة)",
                 [cl.traffic_table_car(car_index, car_cir, car_pir)])

    if dsl_type.lower() == "vdsl":
        plan.add("إنشاء VDSL profile و line template",
                 cl.vdsl_profile_add(profile_id))
    else:
        plan.add("إنشاء ADSL profile و line template",
                 cl.adsl_profile_add(profile_id))

    plan.add("إنشاء VLAN الخدمة وربطه بالمنفذ الصاعد",
             cl.create_service_vlan(svlan, uplink_fsp))

    step = _confirm_or_add(fsp=fsp, ont_id=ont_id, sn=sn, line_id=10,
                           srv_id=None, mgmt="snmp", preprovision=preprovision,
                           native_eth=1, native_vlan=cvlan)
    plan.add(step["title"], step["commands"])

    plan.add("إنشاء تدفق خدمة xDSL (service-port)",
             [cl.xdsl_service_port(sp_index, svlan, fsp, ont_id, cvlan,
                                   vpi=vpi, vci=vci,
                                   rx_cttr=car_index, tx_cttr=car_index)])

    plan.add("حفظ الإعدادات", [cl.SAVE])
    return plan


# سلاسل التزويد المتاحة حسب نوع الخدمة (للاستخدام من طبقة الـ API)
SERVICE_TYPES = ("hsi", "iptv", "voip", "fttb", "xdsl")


def execute_plan(device, plan: ProvisionPlan, log_fn=None) -> Dict:
    """ينفّذ الخطة على الجهاز ويُرجع نتيجة كل خطوة"""
    sess = manager.get(device)
    results = []
    ok = True
    for step in plan.steps:
        try:
            out = sess.run_config(step["commands"])
            success = "failure" not in out.lower() and "error" not in out.lower()
            results.append({
                "title": step["title"],
                "commands": step["commands"],
                "output": out,
                "success": success,
            })
            if log_fn:
                for c in step["commands"]:
                    log_fn(device.id, c, cl.classify(c), success, out)
        except Exception as e:
            ok = False
            results.append({
                "title": step["title"],
                "commands": step["commands"],
                "output": str(e),
                "success": False,
            })
            break
    return {"ok": ok, "steps": results}
