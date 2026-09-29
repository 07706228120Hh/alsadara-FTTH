"""
اختبارات محرك التزويد — تتحقّق أن الأوامر المُولَّدة تطابق «Configuration Reference»
في أدلة HCIA/HCIP-Access V2.5 (لا تحتاج جهازاً؛ تفحص توليد الأوامر فقط).
"""
from app.core import command_library as cl
from app.services import provisioning as pv


def _flat(plan):
    """يجمع كل أوامر الخطة في قائمة مسطّحة."""
    out = []
    for step in plan.steps:
        out.extend(step["commands"])
    return out


# --- مكتبة الأوامر: مطابقة الصياغة الرسمية ---------------------------------

def test_dba_type4_matches_reference():
    # HCIA Lab §3.4.1: dba-profile add profile-id 15 type4 max 4096
    assert cl.dba_profile_add(15, 4, max_bw=4096) == \
        "dba-profile add profile-id 15 type4 max 4096"


def test_dba_type3_iptv_matches_reference():
    # HCIP Lab §5: dba-profile add profile-id 10 ... type3 assure 10240 max 20240
    cmd = cl.dba_profile_add(10, 3, assure=10240, max_bw=20240, name="HG8245")
    assert cmd == "dba-profile add profile-id 10 profile-name HG8245 type3 assure 10240 max 20240"


def test_line_profile_sequence():
    seq = cl.line_profile(10, "ftth_hsi", tcont=10, dba_id=15, gem=10, vlan=35)
    assert seq[0] == "ont-lineprofile gpon profile-id 10 profile-name ftth_hsi"
    assert "tcont 10 dba-profile-id 15" in seq
    assert "gem add 10 eth tcont 10" in seq
    assert "mapping-mode vlan" in seq
    assert "gem mapping 10 1 vlan 35" in seq
    assert seq[-2:] == ["commit", "quit"]


def test_ont_add_preprovision():
    # HCIA Lab: ont add <port> <ontid> sn-auth <SN> omci ont-lineprofile-id .. ont-srvprofile-id ..
    cmd = cl.ont_add(5, 5, "48575443D8F92405", "omci", 31, 31)
    assert cmd == "ont add 5 5 sn-auth 48575443D8F92405 omci ont-lineprofile-id 31 ont-srvprofile-id 31"


def test_ont_add_snmp_has_no_srvprofile():
    cmd = cl.ont_add(0, 2, "SN123456789012", "snmp", 32)
    assert cmd == "ont add 0 2 sn-auth SN123456789012 snmp ont-lineprofile-id 32"
    assert "srvprofile" not in cmd


def test_uplink_port_vlan():
    assert cl.uplink_port_vlan(2000, "0/19/0") == "port vlan 2000 0/19 0"


def test_multicast_vlan_setup_sequence():
    seq = cl.multicast_vlan_setup(200, "0/19/0", 10, version="v3", mode="proxy")
    assert seq[0] == "multicast-vlan 200"
    assert "igmp uplink-port 0/19/0" in seq
    assert "igmp version v3" in seq
    assert "igmp mode proxy" in seq
    assert "igmp multicast-vlan member service-port 10" in seq
    assert seq[-1] == "quit"


def test_sip_interface_attribute_line():
    seq = cl.sip_interface(30, "17.1.1.43", "17.1.1.43", "200.200.200.200")
    assert seq[0] == "interface sip 30"
    line = seq[1]
    assert line.startswith("if-sip attribute basic media-ip 17.1.1.43")
    assert "signal-port 5060 transfer udp" in line
    assert "primary-proxy-ip1 200.200.200.200 primary-proxy-port 5060 home-domain huawei" in line
    assert "reset" in seq


# --- خطط التزويد: التسلسل والترتيب -----------------------------------------

def test_hsi_plan_matches_reference_order():
    plan = pv.build_ftth_plan(fsp="0/5/0", ont_id=3, sn="48575443E1F0A409",
                              svlan=2000, cvlan=35, uplink_fsp="0/19/0",
                              car_index=10, car_cir=4096, car_pir=8064)
    cmds = _flat(plan)
    # CAR يُنشأ قبل service-port الذي يشير إليه
    car_i = next(i for i, c in enumerate(cmds) if c.startswith("traffic table ip index 10"))
    sp_i = next(i for i, c in enumerate(cmds) if c.startswith("service-port"))
    assert car_i < sp_i
    # عناصر جوهرية موجودة
    assert any(c.startswith("dba-profile add profile-id 15") and "type4 max 4096" in c for c in cmds)
    assert "ont-lineprofile gpon profile-id 10 profile-name hsi" in cmds
    assert any("ont confirm 0 ontid 3 sn-auth 48575443E1F0A409 omci" in c for c in cmds)
    assert "vlan 2000 smart" in cmds
    assert "port vlan 2000 0/19 0" in cmds
    assert cmds[-1] == "save"
    # service-port يحمل rx/tx-cttr لأن CAR مُفعّل
    assert any("rx-cttr 10 tx-cttr 10" in c for c in cmds)


def test_hsi_plan_without_car_has_no_cttr():
    plan = pv.build_ftth_plan(fsp="0/5/0", ont_id=3, sn="SN0000000001",
                              svlan=2000, cvlan=35)
    cmds = _flat(plan)
    assert not any("rx-cttr" in c for c in cmds)


def test_hsi_preprovision_uses_ont_add():
    plan = pv.build_ftth_plan(fsp="0/5/0", ont_id=3, sn="SN0000000001",
                              svlan=2000, cvlan=35, preprovision=True)
    cmds = _flat(plan)
    assert any(c.startswith("ont add 0 3 sn-auth SN0000000001 omci") for c in cmds)
    assert not any("ont-auto-find" in c for c in cmds)


def test_iptv_plan_has_multicast_and_btv():
    plan = pv.build_iptv_plan(fsp="0/3/0", ont_id=0, sn="323031312E396341",
                              mvlan=200, uplink_fsp="0/19/0", stb_eth=2)
    cmds = _flat(plan)
    assert any(c.startswith("dba-profile add profile-id 10") and "type3" in c for c in cmds)
    assert "multicast-forward untag" in cmds
    assert "btv" in cmds
    assert "igmp user add service-port 10 no-auth" in cmds
    assert "multicast-vlan 200" in cmds
    assert "igmp uplink-port 0/19/0" in cmds
    assert cmds[-1] == "save"


def test_mdu_sip_plan_sequence():
    plan = pv.build_mdu_sip_plan(
        voice_vlan=172, uplink_fsp="0/0/1", mdu_ip="17.1.1.43", mask_bits=8,
        media_ip="17.1.1.43", gateway="17.0.0.1", softswitch_net="200.200.200.0",
        softswitch_mask_bits=24, softswitch_nexthop="17.0.0.1",
        proxy_ip="200.200.200.200", mgid=30,
        users=[{"fsp": "0/2/1", "telno": "7727043"}])
    cmds = _flat(plan)
    assert "protocol support sip" in cmds
    assert "interface vlanif 172" in cmds
    assert "ip route-static 200.200.200.0 24 17.0.0.1" in cmds
    assert "interface sip 30" in cmds
    assert any(c.startswith("sippstnuser add 0/2/1 30 telno 7727043") for c in cmds)
    assert cmds[-1] == "save"


# --- المحاكي يستجيب للأوامر الجديدة ----------------------------------------

def test_mock_acknowledges_new_commands():
    from app.core.mock_olt import MockOLT
    olt = MockOLT()
    for c in ("btv", "multicast-vlan 200", "igmp uplink-port 0/19/0",
              "protocol support sip", "interface sip 30", "ont add 0 3 sn-auth X omci",
              "sysname huawei", "board confirm 0", "ip route-static 200.200.200.0 24 17.0.0.1"):
        out = olt.execute(c)
        assert "successfully" in out.lower() or "executed" in out.lower(), c
