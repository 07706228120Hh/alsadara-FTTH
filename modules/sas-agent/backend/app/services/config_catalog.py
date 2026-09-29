"""
كتالوج التهيئة الموحّد — يصف **كل إجراء تهيئة** من أدلة HCIA/HCIP-Access V2.5
بشكل تعريفي (فئة + حقول + شرح الربط + بانِي أوامر)، بحيث تبني الواجهة نموذجاً
لكل إجراء تلقائياً (واجهة لكل شيء في الأدلة، دون كتابة كود).

كل إجراء:
- `id` / `category` / `title_ar` / `desc_ar` / `wiring_ar` (شرح الربط والخطة).
- `fields`: قائمة حقول للنموذج (name/label_ar/type/default/options/required).
- `dangerous`: هل يتطلب تنبيه/تأكيد (delete/reboot...).
- بانٍ في `_BUILDERS[id]` يُحوّل قيم الحقول إلى خطوات أوامر.

الخطوة = {"title": str, "commands": [str], "kind": read|write|dangerous}.
"""
from typing import Dict, List, Callable
from ..core import command_library as cl
from ..services import provisioning as pv


# ---------------------------------------------------------------------------
# أدوات مساعدة
# ---------------------------------------------------------------------------

def _plan_steps(plan: "pv.ProvisionPlan") -> List[Dict]:
    """يحوّل خطة تزويد إلى خطوات كتالوج."""
    return [{"title": s["title"], "commands": s["commands"], "kind": s["kind"]}
            for s in plan.steps]


def _step(title: str, commands: List[str]) -> Dict:
    """خطوة واحدة — يُحسب نوعها من أخطر أمر فيها."""
    kinds = [cl.classify(c) for c in commands]
    kind = "dangerous" if "dangerous" in kinds else ("write" if "write" in kinds else "read")
    return {"title": title, "commands": commands, "kind": kind}


def _i(params: Dict, key: str, default: int = 0) -> int:
    try:
        return int(params.get(key, default))
    except (TypeError, ValueError):
        return default


def _s(params: Dict, key: str, default: str = "") -> str:
    v = params.get(key, default)
    return str(v).strip() if v is not None else default


def _b(params: Dict, key: str, default: bool = False) -> bool:
    v = params.get(key, default)
    if isinstance(v, bool):
        return v
    return str(v).lower() in ("true", "1", "yes", "on")


# ---------------------------------------------------------------------------
# البُناة (id → دالة تُرجع خطوات)
# ---------------------------------------------------------------------------

def _b_sysname(p):
    return [_step("تسمية الجهاز", [cl.set_sysname(_s(p, "name", "OLT"))])]


def _b_board_confirm(p):
    return [_step("تأكيد البورد", [cl.board_confirm(_s(p, "frame_slot", "0"))])]


def _b_dba_profile(p):
    t = _i(p, "dba_type", 4)
    cmd = cl.dba_profile_add(
        _i(p, "profile_id", 15), t,
        fix=_i(p, "fix", 0) or None,
        assure=_i(p, "assure", 0) or None,
        max_bw=_i(p, "max_bw", 0) or None,
        name=_s(p, "name"))
    return [_step("إنشاء DBA profile", [cmd])]


def _b_line_profile(p):
    return [_step("إنشاء Line profile", cl.line_profile(
        _i(p, "profile_id", 10), _s(p, "name", "hsi"),
        _i(p, "tcont", 10), _i(p, "dba_id", 15),
        _i(p, "gem", 10), _i(p, "vlan", 100)))]


def _b_srv_profile(p):
    return [_step("إنشاء Service profile", cl.srv_profile(
        _i(p, "profile_id", 10), _s(p, "name", "hsi"),
        eth_ports=_i(p, "eth_ports", 4), vlan=_i(p, "vlan", 100),
        pots=_i(p, "pots", 2), catv=_i(p, "catv", 1)))]


def _b_traffic_car(p):
    return [_step("إنشاء جدول CAR (تحديد السرعة)", [cl.traffic_table_car(
        _i(p, "index", 10), _i(p, "cir", 4096), _i(p, "pir", 8064),
        priority=_i(p, "priority", 5))])]


def _b_create_vlan(p):
    vlan = _i(p, "vlan", 2000)
    vtype = _s(p, "type", "smart")
    cmds = [f"vlan {vlan} {vtype}"]
    if _b(p, "qinq"):
        cmds.append(f"vlan attrib {vlan} q-in-q")
    uplink = _s(p, "uplink_fsp", "0/19/0")
    cmds.append(cl.uplink_port_vlan(vlan, uplink))
    return [_step("إنشاء VLAN وربطه بالمنفذ الصاعد", cmds)]


def _b_ont_confirm(p):
    fsp = _s(p, "fsp", "0/5/0")
    f, s, port = fsp.split("/")
    mgmt = _s(p, "mgmt", "omci")
    srv = _i(p, "srv_id", 0) or None
    confirm = (f"ont confirm {port} ontid {_i(p, 'ont_id', 1)} sn-auth {_s(p, 'sn')} "
               f"{mgmt} ont-lineprofile-id {_i(p, 'line_id', 10)}")
    if mgmt == "omci" and srv is not None:
        confirm += f" ont-srvprofile-id {srv}"
    return [_step("اكتشاف وتأكيد ONT", [
        f"interface gpon 0/{s}",
        f"port {int(port)} ont-auto-find enable",
        confirm,
        "quit",
    ])]


def _b_ont_add(p):
    fsp = _s(p, "fsp", "0/5/0")
    f, s, port = fsp.split("/")
    return [_step("تزويد ONT مُسبقاً بالـ SN (ont add)", [
        f"interface gpon 0/{s}",
        cl.ont_add(int(port), _i(p, "ont_id", 1), _s(p, "sn"), _s(p, "mgmt", "omci"),
                   _i(p, "line_id", 10), _i(p, "srv_id", 0) or None),
        "quit",
    ])]


def _b_ont_native_vlan(p):
    fsp = _s(p, "fsp", "0/5/0")
    f, s, port = fsp.split("/")
    return [_step("تعيين VLAN افتراضي لمنفذ ONT", [
        f"interface gpon 0/{s}",
        cl.ont_native_vlan(int(port), _i(p, "ont_id", 1), _i(p, "eth", 1), _i(p, "vlan", 100)),
        "quit",
    ])]


def _b_ont_lifecycle(p):
    """delete / reboot / activate / deactivate لـ ONT."""
    fsp = _s(p, "fsp", "0/5/0")
    f, s, port = fsp.split("/")
    action = _s(p, "action", "activate")   # activate|deactivate|reboot|delete
    return [_step(f"ONT: {action}", [
        f"interface gpon 0/{s}",
        f"ont {action} {int(port)} {_i(p, 'ont_id', 1)}",
        "quit",
    ])]


def _b_ftth_hsi(p):
    plan = pv.build_ftth_plan(
        fsp=_s(p, "fsp", "0/5/0"), ont_id=_i(p, "ont_id", 1), sn=_s(p, "sn"),
        svlan=_i(p, "svlan", 2000), cvlan=_i(p, "cvlan", 101),
        uplink_fsp=_s(p, "uplink_fsp", "0/19/0"), preprovision=_b(p, "preprovision"),
        dba_max=_i(p, "dba_max", 10240), profile_name=_s(p, "profile_name", "hsi"),
        car_index=(_i(p, "car_index", 10) or None))
    return _plan_steps(plan)


def _b_iptv(p):
    plan = pv.build_iptv_plan(
        fsp=_s(p, "fsp", "0/3/0"), ont_id=_i(p, "ont_id", 0), sn=_s(p, "sn"),
        mvlan=_i(p, "mvlan", 200), uplink_fsp=_s(p, "uplink_fsp", "0/19/0"),
        stb_eth=_i(p, "stb_eth", 2), preprovision=_b(p, "preprovision"),
        igmp_version=_s(p, "igmp_version", "v3"), igmp_mode=_s(p, "igmp_mode", "proxy"))
    return _plan_steps(plan)


def _b_voip_sip(p):
    users = []
    if _s(p, "telno") and _s(p, "user_fsp"):
        users = [{"fsp": _s(p, "user_fsp"), "telno": _s(p, "telno")}]
    plan = pv.build_mdu_sip_plan(
        voice_vlan=_i(p, "voice_vlan", 172), uplink_fsp=_s(p, "uplink_fsp", "0/0/1"),
        mdu_ip=_s(p, "mdu_ip", "17.1.1.43"), mask_bits=_i(p, "mask_bits", 8),
        media_ip=_s(p, "media_ip", "17.1.1.43"), gateway=_s(p, "gateway", "17.0.0.1"),
        softswitch_net=_s(p, "softswitch_net", "200.200.200.0"),
        softswitch_mask_bits=_i(p, "softswitch_mask_bits", 24),
        softswitch_nexthop=_s(p, "softswitch_nexthop", "17.0.0.1"),
        proxy_ip=_s(p, "proxy_ip", "200.200.200.200"), mgid=_i(p, "mgid", 30),
        users=users)
    return _plan_steps(plan)


def _b_multicast_vlan(p):
    sp_index = _i(p, "sp_index", 10)
    steps = [_step("تسجيل مستخدم IGMP", cl.igmp_user_add(sp_index))]
    steps.append(_step("تهيئة multicast-vlan", cl.multicast_vlan_setup(
        _i(p, "mvlan", 200), _s(p, "uplink_fsp", "0/19/0"), sp_index,
        version=_s(p, "version", "v3"), mode=_s(p, "mode", "proxy"))))
    return steps


def _b_igmp_program(p):
    return [_step("إضافة قناة multicast", [cl.igmp_program_add(
        _s(p, "name", "program1"), _s(p, "group_ip", "224.1.1.1"),
        _s(p, "source_ip", "192.168.1.1"))])]


def _b_security(p):
    feature = _s(p, "feature", "anti-dos")   # anti-dos|anti-ipattack|anti-icmpattack
    action = "enable" if _b(p, "enable", True) else "disable"
    return [_step(f"أمان: {feature} {action}", [f"security {feature} {action}"])]


def _b_mac_filter(p):
    return [_step("فلتر MAC", [f"security mac-filter source {_s(p, 'mac')}"])]


def _b_protect_typeb(p):
    gid = _i(p, "group_id", 1)
    return [_step("حماية Type B (منفذ PON)", [
        f"protect-group {gid} protect-target gpon-uni-port workmode timedelay",
        f"protect-group {gid} add-member work {_s(p, 'work_fsp', '0/5')}",
        f"protect-group {gid} add-member protect {_s(p, 'protect_fsp', '0/6')}",
        f"protect-group {gid} enable",
    ])]


def _b_protect_typec(p):
    gid = _i(p, "group_id", 2)
    return [_step("حماية Type C (ONT مزدوج الاستقبال)", [
        f"protect-group {gid} protect-target gpon-uni-ont workmode portstate",
        f"protect-group {gid} add-member work {_s(p, 'work_fsp', '0/5')}",
        f"protect-group {gid} add-member protect {_s(p, 'protect_fsp', '0/6')}",
        f"protect-group {gid} enable",
    ])]


def _b_lacp(p):
    return [_step("تجميع روابط LACP", [
        (f"link-aggregation {_s(p, 'member_a', '0/19/0')} "
         f"{_s(p, 'member_b', '0/19/1')} egress-ingress workmode lacp-static")])]


def _b_voip_h248(p):
    vlan = _i(p, "voice_vlan", 248)
    steps = [
        _step("تحويل البروتوكول إلى H.248 (يتطلب reboot)", [cl.protocol_support("h248")]),
        _step("إنشاء VLAN الصوت وربطه بالمنفذ الصاعد",
              [f"vlan {vlan} smart", cl.uplink_port_vlan(vlan, _s(p, "uplink_fsp", "0/0/1"))]),
        _step("واجهة L3 وعنوان IP", cl.vlanif_ip(vlan, _s(p, "mdu_ip", "17.248.48.11"), _i(p, "mask_bits", 24))),
        _step("مسار ثابت نحو الـ MGC",
              [cl.ip_route_static(_s(p, "mgc_net", "200.200.200.0"), _i(p, "mgc_mask_bits", 24), _s(p, "nexthop", "17.248.48.1"))]),
        _step("إنشاء وتفعيل واجهة H.248",
              cl.h248_interface(_i(p, "mgid", 70), _s(p, "mgip", "17.248.48.11"),
                                _s(p, "media_ip", "17.248.48.11"), _s(p, "mgc_ip", "200.200.200.200"))),
    ]
    if _s(p, "telno") and _s(p, "user_fsp"):
        steps.append(_step("إضافة مشترك PSTN/H.248",
                           cl.mg_pstn_user(_s(p, "user_fsp"), _i(p, "mgid", 70), _s(p, "telno"))))
    steps.append(_step("حفظ الإعدادات", [cl.SAVE]))
    return steps


def _b_inband_mgmt(p):
    vlan = _i(p, "mgmt_vlan", 500)
    steps = [
        _step("إنشاء VLAN الإدارة وربطه بالمنفذ الصاعد",
              [f"vlan {vlan} smart", cl.uplink_port_vlan(vlan, _s(p, "uplink_fsp", "0/19/0"))]),
        _step("واجهة L3 وعنوان IP للإدارة",
              cl.vlanif_ip(vlan, _s(p, "ip", "10.1.1.1"), _i(p, "mask_bits", 24))),
    ]
    if _s(p, "route_net"):
        steps.append(_step("مسار ثابت",
                           [cl.ip_route_static(_s(p, "route_net"), _i(p, "route_mask_bits", 24),
                                               _s(p, "nexthop", "10.1.1.254"))]))
    return steps


def _b_ont_ipconfig(p):
    fsp = _s(p, "fsp", "0/5/0")
    f, s, port = fsp.split("/")
    return [_step("عنوان IP إداري للـ ONT/MDU (inband)", [
        f"interface gpon 0/{s}",
        cl.ont_ipconfig_static(int(port), _i(p, "ont_id", 3), _s(p, "ip", "10.1.1.3"),
                               _s(p, "mask", "255.255.255.0"), _s(p, "gateway", "10.1.1.1"),
                               _i(p, "vlan", 500)),
        "quit",
    ])]


def _b_save_config(p):
    return [_step("حفظ الإعدادات", [cl.SAVE])]


def _b_queue_scheduler(p):
    return [_step("جدولة الطوابير (QoS)", [cl.queue_scheduler(_s(p, "mode", "pq"))])]


_BUILDERS: Dict[str, Callable[[Dict], List[Dict]]] = {
    "sysname": _b_sysname,
    "board_confirm": _b_board_confirm,
    "dba_profile": _b_dba_profile,
    "line_profile": _b_line_profile,
    "srv_profile": _b_srv_profile,
    "traffic_car": _b_traffic_car,
    "create_vlan": _b_create_vlan,
    "ont_confirm": _b_ont_confirm,
    "ont_add": _b_ont_add,
    "ont_native_vlan": _b_ont_native_vlan,
    "ont_lifecycle": _b_ont_lifecycle,
    "ftth_hsi": _b_ftth_hsi,
    "iptv": _b_iptv,
    "voip_sip": _b_voip_sip,
    "multicast_vlan": _b_multicast_vlan,
    "igmp_program": _b_igmp_program,
    "security": _b_security,
    "mac_filter": _b_mac_filter,
    "protect_typeb": _b_protect_typeb,
    "protect_typec": _b_protect_typec,
    "lacp": _b_lacp,
    "voip_h248": _b_voip_h248,
    "inband_mgmt": _b_inband_mgmt,
    "ont_ipconfig": _b_ont_ipconfig,
    "save_config": _b_save_config,
    "queue_scheduler": _b_queue_scheduler,
}


# ---------------------------------------------------------------------------
# الكتالوج التعريفي (يُرسَل للواجهة لبناء النماذج)
# ---------------------------------------------------------------------------

def _f(name, label, ftype="str", default=None, options=None, required=False):
    d = {"name": name, "label_ar": label, "type": ftype, "required": required}
    if default is not None:
        d["default"] = default
    if options is not None:
        d["options"] = options
    return d


CATALOG: List[Dict] = [
    {
        "category": "system", "category_ar": "النظام والبوردات",
        "procedures": [
            {"id": "sysname", "title_ar": "تسمية الجهاز",
             "desc_ar": "تعيين اسم مضيف للـ OLT.",
             "wiring_ar": "اسم إداري فقط — لا يؤثر على المرور.",
             "fields": [_f("name", "اسم الجهاز", "str", "OLT", required=True)]},
            {"id": "board_confirm", "title_ar": "تأكيد بورد",
             "desc_ar": "تأكيد بورد جديد بعد تركيبه ليعمل.",
             "wiring_ar": "بعد تركيب بورد GPON/uplink، يجب تأكيده قبل استخدام منافذه.",
             "fields": [_f("frame_slot", "الإطار/الفتحة (frame أو frame/slot)", "str", "0", required=True)]},
            {"id": "save_config", "title_ar": "حفظ الإعدادات",
             "desc_ar": "حفظ الإعدادات الحالية إلى الذاكرة الدائمة.",
             "wiring_ar": "البروفايلات تحتاج commit، لكن الإعدادات العامة تحتاج save كي تبقى بعد إعادة التشغيل.",
             "fields": []},
        ],
    },
    {
        "category": "profiles", "category_ar": "البروفايلات",
        "procedures": [
            {"id": "dba_profile", "title_ar": "DBA profile (النطاق الصاعد)",
             "desc_ar": "يصف تخصيص النطاق الديناميكي للـ T-CONT.",
             "wiring_ar": "النوع: 1=ثابت(fix) · 2=مضمون(assure) · 3=مضمون+أقصى · 4=أقصى فقط(max) · 5=مختلط. يُربط لاحقاً بـ T-CONT في Line profile.",
             "fields": [
                 _f("profile_id", "معرّف البروفايل", "int", 15, required=True),
                 _f("dba_type", "النوع", "select", 4, options=[1, 2, 3, 4, 5]),
                 _f("name", "الاسم", "str", "ftth"),
                 _f("fix", "fix (kbps) — للنوع 1", "int", 0),
                 _f("assure", "assure (kbps) — للنوع 2/3", "int", 0),
                 _f("max_bw", "max (kbps) — للنوع 3/4", "int", 4096),
             ]},
            {"id": "line_profile", "title_ar": "Line profile",
             "desc_ar": "يربط T-CONT بـ DBA، وGEM بالـ VLAN (mapping).",
             "wiring_ar": "T-CONT ← DBA profile · GEM ← T-CONT · GEM mapping ← C-VLAN. ينتهي بـ commit.",
             "fields": [
                 _f("profile_id", "معرّف البروفايل", "int", 10, required=True),
                 _f("name", "الاسم", "str", "ftth_hsi"),
                 _f("tcont", "T-CONT", "int", 10),
                 _f("dba_id", "DBA profile-id", "int", 15),
                 _f("gem", "GEM index", "int", 10),
                 _f("vlan", "C-VLAN", "int", 100),
             ]},
            {"id": "srv_profile", "title_ar": "Service profile (OMCI)",
             "desc_ar": "قدرات ONT ومنافذه (LAN/POTS/CATV) وربط VLAN بمنفذ الإيثرنت.",
             "wiring_ar": "للـ ONT بوضع OMCI فقط. ont-port يحدد عدد المنافذ · port vlan eth يربط منفذ LAN بالـ VLAN.",
             "fields": [
                 _f("profile_id", "معرّف البروفايل", "int", 10, required=True),
                 _f("name", "الاسم", "str", "HG824x"),
                 _f("eth_ports", "منافذ LAN", "int", 4),
                 _f("vlan", "C-VLAN لمنفذ eth 1", "int", 100),
                 _f("pots", "منافذ POTS", "int", 2),
                 _f("catv", "منافذ CATV", "int", 1),
             ]},
            {"id": "traffic_car", "title_ar": "جدول CAR (تحديد السرعة)",
             "desc_ar": "يحدّد CIR/PIR لتقييد سرعة تدفق الخدمة.",
             "wiring_ar": "يُشار إليه من service-port عبر rx-cttr/tx-cttr. CIR=مضمون، PIR=أقصى.",
             "fields": [
                 _f("index", "الفهرس", "int", 10, required=True),
                 _f("cir", "CIR (kbps)", "int", 4096),
                 _f("pir", "PIR (kbps)", "int", 8064),
                 _f("priority", "الأولوية (0-7)", "int", 5),
             ]},
            {"id": "queue_scheduler", "title_ar": "جدولة الطوابير (QoS)",
             "desc_ar": "وضع جدولة الطوابير على مستوى النظام.",
             "wiring_ar": "PQ = أولوية صارمة (الأعلى أولاً) · WRR = دوري مرجّح (توزيع عادل حسب الوزن).",
             "fields": [_f("mode", "الوضع", "select", "pq", options=["pq", "wrr"])]},
        ],
    },
    {
        "category": "vlan", "category_ar": "شبكات VLAN",
        "procedures": [
            {"id": "create_vlan", "title_ar": "إنشاء VLAN وربط المنفذ الصاعد",
             "desc_ar": "إنشاء VLAN خدمة وربطها بالمنفذ الصاعد.",
             "wiring_ar": "smart للخدمات المتعددة · QinQ لتغليف VLAN المشترك داخل VLAN خدمة. port vlan يمرّرها عبر المنفذ الصاعد.",
             "fields": [
                 _f("vlan", "معرّف VLAN", "int", 2000, required=True),
                 _f("type", "النوع", "select", "smart", options=["smart", "standard", "mux", "super"]),
                 _f("qinq", "تفعيل QinQ", "bool", False),
                 _f("uplink_fsp", "المنفذ الصاعد F/S/P", "str", "0/19/0"),
             ]},
        ],
    },
    {
        "category": "ont", "category_ar": "إدارة ONT",
        "procedures": [
            {"id": "ont_confirm", "title_ar": "تأكيد ONT مكتشَف",
             "desc_ar": "تفعيل الاكتشاف التلقائي وتأكيد ONT وربطه بالبروفايلات.",
             "wiring_ar": "sn-auth = مصادقة بالرقم التسلسلي · omci للـ ONT · snmp للـ MDU. يربط line/srv profile.",
             "fields": [
                 _f("fsp", "المنفذ F/S/P", "str", "0/5/0", required=True),
                 _f("ont_id", "ONT ID", "int", 1, required=True),
                 _f("sn", "الرقم التسلسلي SN", "str", required=True),
                 _f("mgmt", "وضع الإدارة", "select", "omci", options=["omci", "snmp"]),
                 _f("line_id", "Line profile-id", "int", 10),
                 _f("srv_id", "Service profile-id (OMCI)", "int", 10),
             ]},
            {"id": "ont_add", "title_ar": "تزويد ONT مُسبقاً (ont add)",
             "desc_ar": "تسجيل ONT بالـ SN دون انتظار الاكتشاف التلقائي.",
             "wiring_ar": "مفيد عند معرفة الـ SN مسبقاً — يُسجَّل فوراً وسيتصل عند توصيله.",
             "fields": [
                 _f("fsp", "المنفذ F/S/P", "str", "0/5/0", required=True),
                 _f("ont_id", "ONT ID", "int", 1, required=True),
                 _f("sn", "الرقم التسلسلي SN", "str", required=True),
                 _f("mgmt", "وضع الإدارة", "select", "omci", options=["omci", "snmp"]),
                 _f("line_id", "Line profile-id", "int", 10),
                 _f("srv_id", "Service profile-id (OMCI)", "int", 10),
             ]},
            {"id": "ont_native_vlan", "title_ar": "VLAN افتراضي لمنفذ ONT",
             "desc_ar": "تعيين VLAN افتراضي لمنفذ إيثرنت على الـ ONT.",
             "wiring_ar": "عند وصول حزمة بلا وسم من المستخدم، يُضاف هذا الـ VLAN؛ وعند الإرسال إليه يُنزع.",
             "fields": [
                 _f("fsp", "المنفذ F/S/P", "str", "0/5/0", required=True),
                 _f("ont_id", "ONT ID", "int", 1, required=True),
                 _f("eth", "منفذ eth", "int", 1),
                 _f("vlan", "VLAN", "int", 100),
             ]},
            {"id": "ont_lifecycle", "title_ar": "دورة حياة ONT (تفعيل/إعادة/حذف)",
             "desc_ar": "تفعيل أو تعطيل أو إعادة تشغيل أو حذف ONT.",
             "wiring_ar": "deactivate يوقف الخدمة مؤقتاً · reboot يعيد التشغيل · delete يزيل التسجيل نهائياً.",
             "dangerous": True,
             "fields": [
                 _f("fsp", "المنفذ F/S/P", "str", "0/5/0", required=True),
                 _f("ont_id", "ONT ID", "int", 1, required=True),
                 _f("action", "الإجراء", "select", "activate",
                    options=["activate", "deactivate", "reboot", "delete"]),
             ]},
        ],
    },
    {
        "category": "services", "category_ar": "تزويد الخدمات",
        "procedures": [
            {"id": "ftth_hsi", "title_ar": "إنترنت FTTH (HSI) كامل",
             "desc_ar": "تفعيل مشترك إنترنت كامل من البروفايلات حتى service-port.",
             "wiring_ar": "خطة البيانات: DBA→Line→Srv profile ثم تأكيد ONT ثم VLAN خدمة (QinQ) ثم service-port يربط الكل. C-VLAN=داخلي، S-VLAN=خارجي.",
             "fields": [
                 _f("fsp", "المنفذ F/S/P", "str", "0/5/0", required=True),
                 _f("ont_id", "ONT ID", "int", 6, required=True),
                 _f("sn", "SN", "str", required=True),
                 _f("svlan", "Service VLAN", "int", 2000),
                 _f("cvlan", "User VLAN", "int", 101),
                 _f("uplink_fsp", "المنفذ الصاعد F/S/P", "str", "0/19/0"),
                 _f("dba_max", "أقصى نطاق (kbps)", "int", 10240),
                 _f("profile_name", "اسم الباقة", "str", "hsi_10M"),
                 _f("preprovision", "تزويد مُسبق بالـ SN", "bool", False),
             ]},
            {"id": "iptv", "title_ar": "IPTV (Multicast) كامل",
             "desc_ar": "تفعيل خدمة IPTV عبر BTV/IGMP و multicast-vlan.",
             "wiring_ar": "STB على منفذ eth محدد ضمن multicast VLAN. DBA type3 (assure+max)، srv profile يضيف multicast-forward untag، ثم btv/igmp و multicast-vlan.",
             "fields": [
                 _f("fsp", "المنفذ F/S/P", "str", "0/3/0", required=True),
                 _f("ont_id", "ONT ID", "int", 0, required=True),
                 _f("sn", "SN", "str", required=True),
                 _f("mvlan", "Multicast VLAN", "int", 200),
                 _f("uplink_fsp", "المنفذ الصاعد F/S/P", "str", "0/19/0"),
                 _f("stb_eth", "منفذ STB (eth)", "int", 2),
                 _f("igmp_version", "نسخة IGMP", "select", "v3", options=["v2", "v3"]),
                 _f("igmp_mode", "وضع IGMP", "select", "proxy", options=["proxy", "snooping"]),
                 _f("preprovision", "تزويد مُسبق بالـ SN", "bool", False),
             ]},
            {"id": "voip_sip", "title_ar": "صوت VoIP (SIP على MDU)",
             "desc_ar": "تفعيل خدمة الصوت SIP على بوابة MDU/MxU.",
             "wiring_ar": "protocol support sip (يتطلب reboot) ثم VLAN صوت + IP + مسار للسوفت-سويتش + عناوين media/signaling + واجهة SIP + مشترك PSTN. تنبيه: تفعيل SIP يتطلب إعادة تشغيل.",
             "dangerous": True,
             "fields": [
                 _f("voice_vlan", "VLAN الصوت", "int", 172, required=True),
                 _f("uplink_fsp", "المنفذ الصاعد F/S/P", "str", "0/0/1"),
                 _f("mdu_ip", "IP الـ MDU", "str", "17.1.1.43"),
                 _f("mask_bits", "طول القناع (bits)", "int", 8),
                 _f("media_ip", "media IP", "str", "17.1.1.43"),
                 _f("gateway", "البوابة", "str", "17.0.0.1"),
                 _f("softswitch_net", "شبكة السوفت-سويتش", "str", "200.200.200.0"),
                 _f("softswitch_mask_bits", "قناع السوفت-سويتش (bits)", "int", 24),
                 _f("softswitch_nexthop", "القفزة التالية", "str", "17.0.0.1"),
                 _f("proxy_ip", "SIP proxy IP", "str", "200.200.200.200"),
                 _f("mgid", "MGID", "int", 30),
                 _f("user_fsp", "منفذ المشترك F/S/P", "str", "0/2/1"),
                 _f("telno", "رقم الهاتف", "str", "7727043"),
             ]},
            {"id": "voip_h248", "title_ar": "صوت VoIP (H.248 على MDU)",
             "desc_ar": "تفعيل خدمة الصوت بروتوكول H.248/Megaco على بوابة MDU.",
             "wiring_ar": "protocol support h248 (يتطلب reboot) ثم VLAN صوت + IP + مسار + واجهة H.248 (mgip/mgc) + reset coldstart + مشترك mgpstnuser.",
             "dangerous": True,
             "fields": [
                 _f("voice_vlan", "VLAN الصوت", "int", 248, required=True),
                 _f("uplink_fsp", "المنفذ الصاعد F/S/P", "str", "0/0/1"),
                 _f("mdu_ip", "IP الـ MDU", "str", "17.248.48.11"),
                 _f("mask_bits", "طول القناع (bits)", "int", 24),
                 _f("media_ip", "media IP", "str", "17.248.48.11"),
                 _f("mgip", "mgip (عنوان الـ MG)", "str", "17.248.48.11"),
                 _f("mgc_ip", "MGC IP (السوفت-سويتش)", "str", "200.200.200.200"),
                 _f("mgc_net", "شبكة الـ MGC", "str", "200.200.200.0"),
                 _f("mgc_mask_bits", "قناع الـ MGC (bits)", "int", 24),
                 _f("nexthop", "القفزة التالية", "str", "17.248.48.1"),
                 _f("mgid", "MGID", "int", 70),
                 _f("user_fsp", "منفذ المشترك F/S/P", "str", "0/2/1"),
                 _f("telno", "رقم الهاتف", "str", "18980100"),
             ]},
        ],
    },
    {
        "category": "network", "category_ar": "الشبكة والإدارة",
        "procedures": [
            {"id": "inband_mgmt", "title_ar": "إدارة داخلية (inband) للـ OLT",
             "desc_ar": "VLAN إدارة + واجهة L3 + عنوان IP + مسار ثابت.",
             "wiring_ar": "قناة إدارة داخل الشبكة عبر VLAN مخصص وواجهة vlanif — تتيح الوصول للجهاز عن بُعد.",
             "fields": [
                 _f("mgmt_vlan", "VLAN الإدارة", "int", 500, required=True),
                 _f("uplink_fsp", "المنفذ الصاعد F/S/P", "str", "0/19/0"),
                 _f("ip", "عنوان IP", "str", "10.1.1.1"),
                 _f("mask_bits", "طول القناع (bits)", "int", 24),
                 _f("route_net", "شبكة المسار (اختياري)", "str", ""),
                 _f("route_mask_bits", "قناع المسار (bits)", "int", 24),
                 _f("nexthop", "القفزة التالية", "str", "10.1.1.254"),
             ]},
            {"id": "ont_ipconfig", "title_ar": "عنوان IP إداري لـ ONT/MDU",
             "desc_ar": "تعيين IP إداري ثابت لـ MDU عبر القناة الداخلية (inband).",
             "wiring_ar": "يتيح إدارة الـ MDU (SNMP) عبر VLAN إدارة مخصص — من HCIP Lab §2.",
             "fields": [
                 _f("fsp", "المنفذ F/S/P", "str", "0/5/0", required=True),
                 _f("ont_id", "ONT ID", "int", 3, required=True),
                 _f("ip", "عنوان IP", "str", "10.1.1.3"),
                 _f("mask", "قناع الشبكة", "str", "255.255.255.0"),
                 _f("gateway", "البوابة", "str", "10.1.1.1"),
                 _f("vlan", "VLAN الإدارة", "int", 500),
             ]},
        ],
    },
    {
        "category": "multicast", "category_ar": "البث المتعدد (Multicast)",
        "procedures": [
            {"id": "multicast_vlan", "title_ar": "تهيئة multicast-vlan",
             "desc_ar": "إعداد مستخدم IGMP و multicast-vlan (منفذ صاعد/نسخة/وضع).",
             "wiring_ar": "igmp user add يربط service-port بالبث · uplink-port مصدر البث · proxy/snooping وضع الوسيط.",
             "fields": [
                 _f("mvlan", "Multicast VLAN", "int", 200, required=True),
                 _f("uplink_fsp", "المنفذ الصاعد F/S/P", "str", "0/19/0"),
                 _f("sp_index", "service-port index", "int", 10),
                 _f("version", "نسخة IGMP", "select", "v3", options=["v2", "v3"]),
                 _f("mode", "الوضع", "select", "proxy", options=["proxy", "snooping"]),
             ]},
            {"id": "igmp_program", "title_ar": "إضافة قناة (program)",
             "desc_ar": "إضافة قناة بث ثابتة (لوضع match mode enable).",
             "wiring_ar": "group-ip = عنوان المجموعة (224.x) · source-ip = خادم البث.",
             "fields": [
                 _f("name", "اسم القناة", "str", "program1", required=True),
                 _f("group_ip", "عنوان المجموعة", "str", "224.1.1.1"),
                 _f("source_ip", "عنوان الخادم", "str", "192.168.1.1"),
             ]},
        ],
    },
    {
        "category": "security", "category_ar": "الأمان",
        "procedures": [
            {"id": "security", "title_ar": "حماية ضد الهجمات",
             "desc_ar": "تفعيل/تعطيل حمايات anti-DoS / anti-ipattack / anti-icmpattack.",
             "wiring_ar": "تحمي المعالج من إغراق الحزم. راجع display security config للحالة.",
             "fields": [
                 _f("feature", "الميزة", "select", "anti-dos",
                    options=["anti-dos", "anti-ipattack", "anti-icmpattack", "anti-macspoofing"]),
                 _f("enable", "تفعيل", "bool", True),
             ]},
            {"id": "mac_filter", "title_ar": "فلتر MAC",
             "desc_ar": "حظر عنوان MAC مصدر.",
             "wiring_ar": "يمنع مرور الإطارات من هذا الـ MAC.",
             "fields": [_f("mac", "عنوان MAC", "str", "", required=True)]},
        ],
    },
    {
        "category": "protection", "category_ar": "الحماية (Protection)",
        "procedures": [
            {"id": "protect_typeb", "title_ar": "حماية Type B (منفذ PON)",
             "desc_ar": "حماية على مستوى منفذ PON (بورد عامل + احتياطي).",
             "wiring_ar": "عند فشل المنفذ العامل يتحوّل تلقائياً للاحتياطي (timedelay).",
             "fields": [
                 _f("group_id", "معرّف المجموعة", "int", 1, required=True),
                 _f("work_fsp", "العامل (frame/slot)", "str", "0/5"),
                 _f("protect_fsp", "الاحتياطي (frame/slot)", "str", "0/6"),
             ]},
            {"id": "protect_typec", "title_ar": "حماية Type C (ONT مزدوج)",
             "desc_ar": "حماية على مستوى ONT مزدوج الاستقبال (portstate).",
             "wiring_ar": "ONT يستقبل من منفذين؛ يتحوّل بحسب حالة المنفذ.",
             "fields": [
                 _f("group_id", "معرّف المجموعة", "int", 2, required=True),
                 _f("work_fsp", "العامل (frame/slot)", "str", "0/5"),
                 _f("protect_fsp", "الاحتياطي (frame/slot)", "str", "0/6"),
             ]},
            {"id": "lacp", "title_ar": "تجميع روابط LACP",
             "desc_ar": "تجميع منفذين صاعدين (link-aggregation) بوضع LACP.",
             "wiring_ar": "يزيد النطاق ويوفّر تكرار المنفذ الصاعد.",
             "fields": [
                 _f("member_a", "العضو 1 F/S/P", "str", "0/19/0"),
                 _f("member_b", "العضو 2 F/S/P", "str", "0/19/1"),
             ]},
        ],
    },
]


def build(procedure_id: str, params: Dict) -> List[Dict]:
    """يبني خطوات الأوامر لإجراء معيّن من قيم الحقول."""
    fn = _BUILDERS.get(procedure_id)
    if fn is None:
        raise KeyError(procedure_id)
    return fn(params or {})


def procedure_ids() -> List[str]:
    return list(_BUILDERS.keys())
