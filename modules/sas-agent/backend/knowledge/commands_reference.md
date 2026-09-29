# مرجع أوامر Huawei OLT (قاعدة معرفة الذكاء الاصطناعي / RAG)

مستخرَج من HCIA-Access و HCIP-Access V2.5. يُستخدم كسياق لمساعد الذكاء الاصطناعي.

## التزويد الأساسي (GPON)
- `dba-profile add profile-id <id> type<1-5> [fix|assure|max] <kbps>` — إدارة النطاق الصاعد. النوع1=ثابت، 2=مضمون، 3=مضمون+أقصى، 4=أقصى فقط، 5=مختلط.
- `ont-lineprofile gpon profile-id <id> profile-name <n>` ثم `tcont`, `gem add`, `gem mapping`, `commit` — ربط T-CONT بالـ DBA وربط GEM بالـ VLAN.
- `ont-srvprofile gpon profile-id <id>` ثم `ont-port`, `port vlan eth`, `commit` — للـ ONT (OMCI) فقط.
- `port <p> ont-auto-find enable` + `display ont autofind <p>` + `ont confirm <p> ontid <o> sn-auth <SN> omci ont-lineprofile-id <id> ont-srvprofile-id <id>`.
- `vlan <v> smart` + `vlan attrib <v> q-in-q` + `port vlan <v> 0/<slot> <port>`.
- `service-port <idx> vlan <svlan> gpon <f>/<s>/<p> ont <o> gemport <g> multi-service user-vlan <cvlan> rx-cttr <t> tx-cttr <t>`.
- `save` — لحفظ الإعدادات. **مهم:** البروفايلات تحتاج `commit`، والإعدادات تحتاج `save`.

## التشخيص والمراقبة
- `display board 0` — حالة البوردات. `display board 0/<slot>` — تفصيل + حالة الموديول الضوئي.
- `display ont info <port> all` — قائمة ONTs مع Run/Config/Match state.
- `display ont info <f> <s> <p> <o>` — تفصيل ONT: الحرارة، CPU، الذاكرة، المسافة، SN.
- `display port state <p>` — القدرة الضوئية (RX/TX dBm)، تيار الليزر، الجهد، سبب آخر انقطاع (LOS).
- `display ont failed-configuration` — بنود التهيئة الفاشلة (وضع diagnose).
- `display ont capability <f> <s> <p> <o>` — قدرات الجهاز (لحل mismatch).
- `display cpu 0/<slot>` — استهلاك المعالج.
- `display service-port all` — تدفقات الخدمة وحالتها.
- `display esl online-info startuser <f>/<s>/<p>` — جودة المكالمة: MOS، R-Factor، jitter، packet loss.

## شجرة تشخيص ONT
| الحالة | السبب | الحل |
|---|---|---|
| Control flag = deactive | معطَّل إدارياً | `ont activate` |
| Run state = offline | فايبر/كهرباء/موديول | فحص `display port state` |
| Config state = failed | فشل تسليم | `display ont failed-configuration` |
| Match state = mismatch | بروفايل غير مطابق | `display ont capability` + تعديل البروفايل |

## الأمان
- `security anti-dos enable` + `security anti-dos control-packet rate <fsp> ont <o> gemport <g> <pps>`.
- `security anti-ipattack enable` / `security anti-icmpattack enable`.
- `security mac-filter source <mac>`. `display security config` لفحص الحالة.
- `firewall enable` + `acl <n>` + rules + `firewall packet-filter <n> inbound`.

## الحماية
- Type B: `protect-group <id> protect-target gpon-uni-port workmode timedelay` + أعضاء work/protect.
- Type C: `protect-target gpon-uni-ont workmode portstate` + `ont add <p> <o> protect-side`.
- LACP: `link-aggregation <f> <s> <f> <s> egress-ingress workmode lacp-static`.
- التبديل اليدوي: `force-switch port <a> to <b>`. الفحص: `display protect-group <id>`.

## الصوت
- SIP على MDU: `interface sip <mgid>` + `if-sip attribute basic ...` + `sippstnuser add`.
- H.248: `interface h248 <mgid>` + `if-h248 attribute mgip ...` + `mgpstnuser add` + `reset coldstart`.
- الفحص: `pots loop-line-test`, `pots circuit-test`, `pots emulational-call` (مكالمة آلية).

## IPTV
- `btv` + `igmp user add service-port <idx> no-auth` + `multicast-vlan <v>` + `igmp uplink-port` + `igmp version v3` + `igmp mode proxy|snooping` + `igmp program add`.

---

# مراجع تهيئة كاملة (Configuration References) — مُتحقَّق منها من الأدلة

## 1) تفعيل مشترك إنترنت HSI — HCIA-Access Lab §3.4.1
```
enable
config
traffic table ip index 10 cir 4096 pir 8064 priority user-cos 5 priority-policy local-Setting
dba-profile add profile-id 15 type4 max 4096
ont-lineprofile gpon profile-id 10 profile-name ftth_hsi
 tcont 10 dba-profile-id 15
 gem add 10 eth tcont 10
 mapping-mode vlan
 gem mapping 10 1 vlan 35
 commit
 quit
ont-srvprofile gpon profile-id 10 profile-name HG824x
 ont-port eth 4 pots 2 catv 1
 port vlan eth 1 35
 commit
 quit
interface gpon 0/5
 port 0 ont-auto-find enable
 ont confirm 0 ontid 3 sn-auth <SN> omci ont-lineprofile-id 10 ont-srvprofile-id 10
 ont port native-vlan 0 3 eth 1 vlan 35
 quit
vlan 2000 smart
vlan attrib 2000 q-in-q
port vlan 2000 0/19 0
service-port 10 vlan 2000 gpon 0/5/0 ont 3 gemport 10 multi-service user-vlan 35 rx-cttr 10 tx-cttr 10
save
```

## 2) تزويد ONT مُسبقاً بالـ SN (دون انتظار الاكتشاف) — HCIA Lab
```
interface gpon 0/5
 ont add 5 5 sn-auth <SN> omci ont-lineprofile-id 31 ont-srvprofile-id 31
 quit
```
- `ont confirm <p> ontid <o> sn-auth <SN> snmp ont-lineprofile-id <id>` — لوضع SNMP (MDU) بدل OMCI (ONT).

## 3) IPTV Multicast (BTV/IGMP) — HCIP-Access Lab §5
```
dba-profile add profile-id 10 profile-name HG8245 type3 assure 10240 max 20240
ont-lineprofile gpon profile-id 11 profile-name IPTV
 tcont 2 dba-profile-id 10
 gem add 0 eth tcont 2
 mapping-mode vlan
 gem mapping 0 0 vlan 200
 commit
 quit
ont-srvprofile gpon profile-id 13 profile-name IPTV
 ont-port eth 4 pots 2
 port vlan eth 2 200
 multicast-forward untag
 commit
 quit
interface gpon 0/3
 port 0 ont-auto-find enable
 ont confirm 0 ontid 0 sn-auth <SN> omci ont-lineprofile-id 11 ont-srvprofile-id 13
 ont port native-vlan 0 0 eth 2 vlan 200
 quit
vlan 200 smart
port vlan 200 0/19 0
service-port 10 vlan 200 gpon 0/3/0 ont 0 gemport 0 multi-service user-vlan 200
btv
 igmp user add service-port 10 no-auth
 quit
multicast-vlan 200
 igmp uplink-port 0/19/0
 igmp version v3
 igmp match mode disable
 igmp mode proxy
 igmp multicast-vlan member service-port 10
 quit
save
```
- لقنوات ثابتة (match mode enable): `igmp program add name <n> ip <group-ip> sourceip <server-ip>`.

## 4) خدمة صوت SIP على MDU/MxU — HCIP-Access Lab §3
```
protocol support sip          ← يتطلب save ثم reboot system لتفعيله
vlan 172 smart
port vlan 172 0/0 1
interface vlanif 172
 ip address 17.1.1.43 8
 quit
ip route-static 200.200.200.0 24 17.0.0.1
voip
 ip address media 17.1.1.43 17.0.0.1
 ip address signaling 17.1.1.43
 quit
interface sip 30
 if-sip attribute basic media-ip 17.1.1.43 signal-ip 17.1.1.43 signal-port 5060 transfer udp primary-proxy-ip1 200.200.200.200 primary-proxy-port 5060 home-domain huawei
 reset
 quit
local-digitmap add SIPmap normal 7727xxx|x.S|x.F
esl user
 sippstnuser add 0/2/1 30 telno 7727043
 sippstnuser auth set 0/2/1 telno 7727043 password-mode password
 quit
save
```
- الفحص: `display sippstnuser <fsp>` · `display if-sip attribute <mgid>` · `pots emulational-call` (مكالمة آلية).
