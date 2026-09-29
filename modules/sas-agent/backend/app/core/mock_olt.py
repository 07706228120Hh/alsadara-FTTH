"""
محاكي Huawei OLT — يحاكي جلسة CLI ويرد بمخرجات واقعية مأخوذة من أدلة
HCIA/HCIP-Access. يسمح بتطوير واختبار التطبيق كاملاً بدون جهاز حقيقي.
غيّر USE_MOCK_OLT=false في .env للاتصال بجهاز فعلي.
"""
import random
import re
from typing import Dict, List


class MockONT:
    def __init__(self, port: int, ont_id: int, sn: str, desc: str = ""):
        self.port = port
        self.ont_id = ont_id
        self.sn = sn
        self.desc = desc or f"ONT-{sn[-4:]}"
        self.run_state = "online"
        self.config_state = "normal"
        self.match_state = "match"
        self.control_flag = "active"
        self.rx_power = round(random.uniform(-25.0, -8.0), 2)
        self.distance = random.randint(80, 12000)
        self.temperature = random.randint(45, 72)
        self.cpu = random.randint(1, 15)
        self.memory = random.randint(20, 40)
        self.line_profile = 10
        self.mgmt = "omci"


class MockOLT:
    """يحاكي جهاز OLT واحد مع بوردات وONTs"""

    def __init__(self, name: str = "MockMA5800"):
        self.name = name
        self.onts: Dict[str, MockONT] = {}
        # ONTs افتراضية للعرض
        seed = [
            (0, 1, "48575443D8EAC605", "زبون-الرصافة-01"),
            (0, 2, "48575443D8F92405", "زبون-الرصافة-02"),
            (0, 3, "48575443E1F0A409", "مقهى-النخيل"),
            (1, 1, "4857544329518907", "برج-السلام"),
            (1, 2, "48575443F444CB04", "مدرسة-بغداد"),
        ]
        for port, oid, sn, desc in seed:
            self.onts[f"0/5/{port}/{oid}"] = MockONT(port, oid, sn, desc)
        # اجعل واحداً فيه مشكلة للعرض التوضيحي للتشخيص
        bad = self.onts["0/5/1/2"]
        bad.run_state = "offline"
        bad.control_flag = "active"
        bad.rx_power = -30.5
        self._autofind_queue = [("0", "6", "48575443AABBCC0D", "HWTC")]

    # -- محرك المحاكاة --------------------------------------------------------
    def execute(self, command: str) -> str:
        c = command.strip()
        low = c.lower()

        if low in ("enable", "config", "quit", "save", "disable", "btv",
                   "voip", "esl user", "reset") or low.startswith(
            ("interface ", "vlan ", "port ", "dba-profile", "ont-lineprofile",
             "ont-srvprofile", "tcont", "t-cont", "gem ", "mapping-mode", "commit",
             "traffic table", "traffic ", "service-port", "ont ",
             "security", "protect-group", "firewall", "acl", "btv", "igmp",
             "multicast-vlan", "multicast-forward", "sysname", "board ",
             "ip ", "protocol support", "sippstnuser", "local-digitmap",
             "if-sip", "if-h248", "link-aggregation")):
            return self._ack(c)

        if low.startswith("display board 0/"):
            return self._board_detail(c)
        if low.startswith("display board"):
            return self._board_list()
        if low.startswith("display version"):
            return self._version()
        if low.startswith("display ont autofind"):
            return self._autofind(c)
        if low.startswith("display ont info"):
            return self._ont_info(c)
        if low.startswith("display port state"):
            return self._port_state(c)
        if low.startswith("display ont failed"):
            return self._ont_failed()
        if low.startswith("display cpu"):
            return f"  It will take several minutes, please wait...\n  CPU occupancy: {random.randint(3,18)}%"
        if low.startswith("display security config"):
            return self._security_config()
        if low.startswith("display service-port"):
            return self._service_port_all()
        if low.startswith("display esl online-info"):
            return self._esl_online(c)
        if low.startswith("ping"):
            return self._ping(c)

        return f"  Command executed.\n{self._prompt()}"

    # -- مساعدات المخرجات -----------------------------------------------------
    def _prompt(self) -> str:
        return f"{self.name}(config)#"

    def _ack(self, c: str) -> str:
        return f"  {c}\n  Command executes successfully\n{self._prompt()}"

    def _board_list(self) -> str:
        return (
            "-------------------------------------------------------------------------\n"
            "  SlotID  BoardName  Status         SubType0 SubType1  Online/Offline\n"
            "-------------------------------------------------------------------------\n"
            "  0       H901GPSF   Normal\n"
            "  5       H805GPBD   Normal\n"
            "  6       H805GPBD   Normal\n"
            "  9       H901MPLB   Active_normal\n"
            "  10      H901MPLB   Standby_normal\n"
            "  19      H901GICG   Normal\n"
            "-------------------------------------------------------------------------\n"
            f"{self._prompt()}"
        )

    def _board_detail(self, c: str) -> str:
        return (
            "  Board Name          : H805GPBD\n"
            "  Board Status        : Normal\n"
            "  Min Distance(km)    : 0\n"
            "  Max Distance(km)    : 20\n"
            "  Port 0 optical-module: Online\n"
            "  Port 0 ONT online   : 3 / 3\n"
            f"{self._prompt()}"
        )

    def _version(self) -> str:
        return (
            "  MA5800V100R017C10\n"
            "  PRODUCT : MA5800-X17\n"
            "  Uptime is 128 day(s), 6 hour(s), 42 minute(s)\n"
            f"{self._prompt()}"
        )

    def _autofind(self, c: str) -> str:
        if not self._autofind_queue:
            return f"  The automatically found ONT is 0\n{self._prompt()}"
        lines = ["  ----------------------------------------------------------------------"]
        lines.append("  Number : 1")
        for i, (f, s, sn, vendor) in enumerate(self._autofind_queue, 1):
            lines.append(f"  F/S/P                   : 0/5/{f}")
            lines.append(f"  Ont SN                  : {sn} ({vendor}-{sn[-8:]})")
            lines.append(f"  Password                : 0x00000000000000000000")
            lines.append(f"  VendorID                : {vendor}")
            lines.append(f"  Ont EquipmentID         : EG8145V5")
        lines.append("  ----------------------------------------------------------------------")
        lines.append(f"{self._prompt()}")
        return "\n".join(lines)

    def _ont_info(self, c: str) -> str:
        # display ont info <port> all  أو  display ont info f s p o
        m = re.search(r"display ont info (\d+) all", c.lower())
        rows = []
        header = (
            "  -----------------------------------------------------------------------------\n"
            "  F /S /P     ONT-ID   SN                Control     Run      Config   Match\n"
            "                                          flag        state    state    state\n"
            "  -----------------------------------------------------------------------------"
        )
        if m:
            port = int(m.group(1))
            for key, o in self.onts.items():
                if o.port == port:
                    rows.append(
                        f"  0 /5 /{o.port}     {o.ont_id:<8} {o.sn}  {o.control_flag:<11} "
                        f"{o.run_state:<8} {o.config_state:<8} {o.match_state}"
                    )
            body = "\n".join(rows) if rows else "  No related information."
            return f"{header}\n{body}\n  -----------------------------------------------------------------------------\n{self._prompt()}"
        # تفصيل ONT واحد
        parts = c.split()
        try:
            f, s, p, o = parts[3], parts[4], parts[5], parts[6]
            key = f"{f}/{s}/{p}/{o}"
            ont = self.onts.get(key)
        except Exception:
            ont = None
        if not ont:
            return f"  No related information.\n{self._prompt()}"
        return (
            f"  F/S/P                   : {f}/{s}/{p}\n"
            f"  ONT-ID                  : {o}\n"
            f"  Control flag            : {ont.control_flag}\n"
            f"  Run state               : {ont.run_state}\n"
            f"  Config state            : {ont.config_state}\n"
            f"  Match state             : {ont.match_state}\n"
            f"  DBA type                : SR\n"
            f"  ONT distance(m)         : {ont.distance}\n"
            f"  ONT last distance(m)    : {ont.distance}\n"
            f"  Memory occupation       : {ont.memory}%\n"
            f"  CPU occupation          : {ont.cpu}%\n"
            f"  Temperature(C)          : {ont.temperature}\n"
            f"  Authentic type          : SN-auth\n"
            f"  SN                      : {ont.sn}\n"
            f"  Management mode         : {ont.mgmt.upper()}\n"
            f"  Line profile ID         : {ont.line_profile}\n"
            f"  Description             : {ont.desc}\n"
            f"{self._prompt()}"
        )

    def _port_state(self, c: str) -> str:
        # القدرة الضوئية والليزر
        port_key = None
        for key, o in self.onts.items():
            port_key = o
            break
        rx = port_key.rx_power if port_key else -18.0
        return (
            "  ------------------------------------------------------------------\n"
            "  Optical Module status              : Online\n"
            "  Port state                         : Online\n"
            "  Laser state                        : Normal\n"
            f"  Temperature(C)                     : {random.randint(40,55)}\n"
            f"  TX Bias current(mA)                : {random.randint(15,45)}\n"
            f"  Supply Voltage(V)                  : {round(random.uniform(3.2,3.4),2)}\n"
            f"  TX power(dBm)                      : {round(random.uniform(2.5,4.5),2)}\n"
            f"  RX power(dBm)                      : {rx}\n"
            "  Wave length(nm)                    : 1490\n"
            "  Fiber type                         : Single Mode\n"
            "  Last down cause                    : LOS\n"
            "  ------------------------------------------------------------------\n"
            f"{self._prompt()}"
        )

    def _ont_failed(self) -> str:
        return (
            "  ------------------------------------------------------------\n"
            "  F/S/P    ONT   Failed item        Cause\n"
            "  0/5/1    2     service-port       GEM port not exist\n"
            "  ------------------------------------------------------------\n"
            f"{self._prompt()}"
        )

    def _security_config(self) -> str:
        return (
            "  Anti-ipspoofing function      : disable\n"
            "  Anti-dos function             : enable\n"
            "  Anti-macspoofing function     : disable\n"
            "  Anti-ipattack function        : enable\n"
            "  Anti-icmpattack function      : enable\n"
            "  Anti-macduplicate function    : disable\n"
            "  Anti-dos control-packet policy: permit\n"
            f"{self._prompt()}"
        )

    def _service_port_all(self) -> str:
        rows = []
        idx = 1
        for key, o in self.onts.items():
            state = "up" if o.run_state == "online" else "down"
            rows.append(f"  {idx:<6} 2000  gpon  0/5/{o.port} {o.ont_id}  {o.ont_id}  {o.line_profile}  {state}")
            idx += 1
        body = "\n".join(rows)
        return (
            "  INDEX  VLAN  TYPE  F /S /P     VPI  VCI  FLOW  STATE\n"
            "  -------------------------------------------------------\n"
            f"{body}\n"
            f"  Total : {len(rows)}\n"
            f"{self._prompt()}"
        )

    def _esl_online(self, c: str) -> str:
        return (
            "  User Port                     : 0/2/1\n"
            "  Codec                         : G711A\n"
            "  Local IP/Port                 : 17.1.1.43 / 5004\n"
            "  Remote IP/Port                : 200.200.200.200 / 5004\n"
            f"  Rx Packets                    : {random.randint(1000,5000)}\n"
            f"  Local Packet loss rate(%)     : {round(random.uniform(0,1.2),2)}\n"
            f"  Local Jitter(ms)              : {random.randint(2,15)}\n"
            f"  RTCP RTT(ms)                  : {random.randint(20,80)}\n"
            f"  Estimated MOSLQ               : {round(random.uniform(3.6,4.4),1)}\n"
            f"  Estimated MOSCQ               : {round(random.uniform(3.6,4.4),1)}\n"
            f"  R Factor                      : {random.randint(75,93)}\n"
            f"{self._prompt()}"
        )

    def _ping(self, c: str) -> str:
        ok = random.random() > 0.1
        if ok:
            return (
                "  Reply from target: bytes=56 Sequence=1 ttl=255 time=10 ms\n"
                "  Reply from target: bytes=56 Sequence=2 ttl=255 time=9 ms\n"
                "  --- ping statistics ---\n"
                "  2 packet(s) transmitted, 2 packet(s) received, 0.00% packet loss\n"
                f"{self._prompt()}"
            )
        return (
            "  Request timeout!\n"
            "  --- ping statistics ---\n"
            "  2 packet(s) transmitted, 0 packet(s) received, 100.00% packet loss\n"
            f"{self._prompt()}"
        )
