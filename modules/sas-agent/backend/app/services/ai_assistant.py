"""
مساعد الذكاء الاصطناعي الخبير (هجين):
- الطبقة 1: قواعد خبيرة فورية (بدون إنترنت) — من troubleshooting.py
- الطبقة 2: Claude API مع RAG من أدلة HCIA/HCIP + Function Calling آمن

الأمان: الذكاء الاصطناعي يستطيع تنفيذ أوامر العرض (display/ping) تلقائياً،
أما أوامر التغيير فتُقترح فقط وتحتاج موافقة المستخدم قبل التنفيذ.
"""
import os
from typing import Dict, List, Optional
from ..config import settings
from ..core.olt_connection import manager
from ..core import command_library as cl

_KB_PATH = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "knowledge", "commands_reference.md")
)
try:
    with open(_KB_PATH, encoding="utf-8") as fp:
        _KNOWLEDGE = fp.read()
except FileNotFoundError:
    _KNOWLEDGE = ""

SYSTEM_PROMPT = f"""أنت خبير في أجهزة Huawei OLT (MA5680T / MA5800 / EA5800) وشبكات
الوصول GPON/xDSL. تجيب بالعربية بوضوح واختصار. تساعد المهندس في التزويد،
التشخيص، الترابل شوتنك، والمراقبة.

قواعد مهمة:
- استند إلى مرجع الأوامر أدناه (من أدلة HCIA/HCIP-Access الرسمية).
- عند الحاجة لبيانات من الجهاز، استخدم أداة run_display_command (أوامر عرض آمنة فقط).
- لا تنفّذ أبداً أوامر تغيير (config) بنفسك — اقترحها للمستخدم واشرح أثرها، ودعه يوافق.
- إذا كان أمراً خطراً (erase/reboot/delete) نبّه المستخدم بوضوح.

=== مرجع الأوامر ===
{_KNOWLEDGE}
"""

# أدوات Claude (Function Calling)
TOOLS = [
    {
        "name": "run_display_command",
        "description": "تنفيذ أمر عرض آمن على الـ OLT (display/ping فقط) وإرجاع المخرجات الخام.",
        "input_schema": {
            "type": "object",
            "properties": {
                "command": {"type": "string", "description": "أمر العرض، مثال: display ont info 0 all"}
            },
            "required": ["command"],
        },
    }
]


def _get_client():
    key = settings.anthropic_api_key or os.environ.get("ANTHROPIC_API_KEY", "")
    if not key:
        return None
    try:
        from anthropic import Anthropic
        return Anthropic(api_key=key, timeout=settings.ai_timeout)
    except Exception:
        return None


def ask(device, question: str, history: Optional[List[Dict]] = None) -> Dict:
    """
    يجيب على سؤال المهندس. إن توفّر مفتاح Claude يستخدمه مع الأدوات،
    وإلا يرجع إجابة من القواعد المحلية.
    """
    client = _get_client()
    if client is None:
        return _offline_answer(question)

    messages = list(history or [])
    messages.append({"role": "user", "content": question})
    executed: List[Dict] = []

    # حلقة الأدوات (حتى 5 استدعاءات)
    for _ in range(5):
        resp = client.messages.create(
            model=settings.ai_model,
            max_tokens=1500,
            system=SYSTEM_PROMPT,
            tools=TOOLS,
            messages=messages,
        )
        if resp.stop_reason == "tool_use":
            tool_results = []
            for block in resp.content:
                if block.type == "tool_use" and block.name == "run_display_command":
                    command = block.input.get("command", "")
                    # حماية: أوامر العرض فقط
                    if cl.classify(command) != "read":
                        result = "مرفوض: هذا ليس أمر عرض. أوامر التغيير تحتاج موافقة المستخدم."
                    else:
                        try:
                            result = manager.get(device).run(command)
                            executed.append({"command": command, "output": result})
                        except Exception as e:
                            result = f"خطأ: {e}"
                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": result,
                    })
            messages.append({"role": "assistant", "content": resp.content})
            messages.append({"role": "user", "content": tool_results})
            continue
        # إجابة نهائية
        text = "".join(b.text for b in resp.content if b.type == "text")
        return {"answer": text, "executed_commands": executed, "source": "claude"}

    return {"answer": "تعذّر إكمال التحليل (تجاوز حد الأدوات).",
            "executed_commands": executed, "source": "claude"}


# ---------------------------------------------------------------------------
# المساعد المحلي (يعمل بلا إنترنت) — معرفة HCIA/HCIP + استرجاع من مرجع الأوامر
# ---------------------------------------------------------------------------

def _normalize(text: str) -> str:
    """توحيد النص العربي/الإنجليزي للمطابقة (إزالة التشكيل وتوحيد الألف والهمزة)."""
    text = text.lower()
    # إزالة التشكيل والتطويل
    for ch in "ًٌٍَُِّْـ":
        text = text.replace(ch, "")
    # توحيد الألف والهمزات والتاء المربوطة والألف المقصورة
    trans = {"أ": "ا", "إ": "ا", "آ": "ا", "ئ": "ي", "ؤ": "و", "ى": "ي", "ة": "ه"}
    for a, b in trans.items():
        text = text.replace(a, b)
    return text


# قاعدة معرفة مفاهيمية (HCIA/HCIP-Access) — تجيب على الأسئلة النظرية والعملية محلياً.
# كل مدخل: (كلمات مفتاحية بعد التوحيد، الإجابة).
_CONCEPTS: List[Dict] = [
    {"k": ["gpon", "جيبون", "الشبكه الضوئيه المنفعله", "passive optical"],
     "a": "GPON (شبكة ضوئية سلبية بسرعة جيجابت): سرعة نزول 2.488 Gbps وصعود 1.244 Gbps، "
          "يخدم OLT واحد حتى 64/128 ONT عبر مقسّم ضوئي سلبي (splitter). الأطوال الموجية: "
          "1490nm نزول، 1310nm صعود، 1550nm للـ CATV. يعتمد OMCI لإدارة الـ ONT."},
    {"k": ["olt"], "a": "OLT (Optical Line Terminal): الجهاز المركزي في مكتب المزوّد الذي ينهي "
          "الألياف ويربط المشتركين بالشبكة. يحوي بوردات خدمة (GPON/GE) وبوردات تحكّم وبوردات صاعدة (uplink)."},
    {"k": ["ont", "onu", "الوحده الطرفيه"],
     "a": "ONT/ONU: الوحدة الطرفية لدى المشترك التي تحوّل الضوء إلى Ethernet/Wi-Fi/هاتف. "
          "حالاتها: Run state (online/offline)، Config state (normal/failed)، Match state (match/mismatch)."},
    {"k": ["dba", "t-cont", "tcont", "النطاق الصاعد", "dynamic bandwidth"],
     "a": "DBA (تخصيص النطاق الصاعد ديناميكياً) عبر T-CONT. أنواع DBA: 1=ثابت، 2=مضمون، "
          "3=مضمون+أقصى، 4=أقصى فقط (best-effort)، 5=مختلط. يُربط T-CONT بـ dba-profile ثم الـ GEM بالـ T-CONT."},
    {"k": ["gem", "gemport", "جيم بورت"],
     "a": "GEM Port: قناة نقل منطقية داخل GPON تحمل تدفّق خدمة معيّن وتُربط (mapping) بـ VLAN. "
          "يُضاف بـ `gem add` ثم `gem mapping <gem> <index> vlan <v>`."},
    {"k": ["service-port", "service port", "سيرفس بورت", "منفذ الخدمه"],
     "a": "service-port: يربط تدفّق الخدمة بين VLAN الشبكة (S-VLAN) والـ ONT/GEM ويحدّد قيود السرعة "
          "(rx/tx-cttr). مثال: `service-port <idx> vlan <svlan> gpon <f>/<s>/<p> ont <o> gemport <g> "
          "multi-service user-vlan <cvlan> rx-cttr <t> tx-cttr <t>`."},
    {"k": ["vlan", "في لان", "q-in-q", "qinq", "smart vlan", "mux vlan"],
     "a": "أنواع VLAN في Huawei: standard (منفذ واحد)، smart (عدّة منافذ، شائع للخدمات)، "
          "mux (تعدّد إرسال حسب MAC). Q-in-Q يضيف وسماً خارجياً (S-VLAN) فوق وسم المشترك (C-VLAN): "
          "`vlan <v> smart` + `vlan attrib <v> q-in-q`."},
    {"k": ["lineprofile", "line profile", "srvprofile", "service profile", "البروفايل", "بروفايل"],
     "a": "Line profile يربط T-CONT/DBA والـ GEM/VLAN (نقل)، وService profile يعرّف منافذ الـ ONT "
          "(eth/pots/catv) وربط VLAN بها (OMCI). كلاهما يحتاج `commit`. تُربط عند `ont confirm`."},
    {"k": ["omci", "snmp", "الفرق بين omci"],
     "a": "OMCI: بروتوكول إدارة الـ ONT من نوع HGU (يُستخدم مع ont-srvprofile). "
          "SNMP: يُستخدم لإدارة أجهزة MDU/MxU. عند التأكيد: `... omci ...` لـ ONT، `... snmp ...` لـ MDU."},
    {"k": ["القدره الضوئيه", "optical power", "los", "rx power", "dbm", "الاشاره الضوئيه", "الطاقه الضوئيه"],
     "a": "القدرة الضوئية (Rx): الطبيعي بين -8 و -25 dBm. أقل من -25dBm = تحذير، أقل من -28dBm = حرجة. "
          "LOS يعني فقدان الإشارة (فايبر مقطوع/موصل متّسخ/ONT مطفأ). افحص بـ `display port state <p>`."},
    {"k": ["تزويد", "تفعيل مشترك", "provision", "ftth", "خطوات التفعيل", "تفعيل ftth", "اجهز مشترك"],
     "a": "تسلسل تفعيل مشترك FTTH: (1) traffic table للسرعة → (2) dba-profile → (3) ont-lineprofile "
          "(tcont+gem+mapping+commit) → (4) ont-srvprofile (ont-port+port vlan+commit) → "
          "(5) ont-auto-find ثم `ont confirm` بالـ SN → (6) vlan + port vlan (uplink) → "
          "(7) service-port → (8) `save`."},
    {"k": ["offline", "غير متصل", "اوفلاين", "ont offline", "الجهاز مطفي", "مايشتغل"],
     "a": "ONT offline: تحقّق من (1) الفايبر والموصلات، (2) الكهرباء عند المشترك، (3) القدرة الضوئية "
          "`display port state` (سبب LOS)، (4) المسافة والانحناءات. إن كان معطّلاً إدارياً: `ont activate`."},
    {"k": ["mismatch", "عدم تطابق", "match state"],
     "a": "Match state = mismatch: البروفايل لا يطابق قدرات الـ ONT الحقيقية. شغّل "
          "`display ont capability <f> <s> <p> <o>` وعدّل عدد منافذ eth/pots في ont-srvprofile لتطابقها."},
    {"k": ["config failed", "فشل التهيئه", "failed-configuration", "config state failed"],
     "a": "Config state = failed: فشل تسليم جزء من التهيئة للـ ONT. شغّل "
          "`display ont failed-configuration` لمعرفة البند الفاشل (غالباً VLAN/منفذ غير موجود على الـ ONT)."},
    {"k": ["بطيء", "بطء", "السرعه", "slow", "throughput", "ضعف السرعه"],
     "a": "مشترك بطيء: تحقّق من (1) DBA profile (النطاق الصاعد المخصّص)، (2) traffic table / CAR "
          "(cir/pir و rx/tx-cttr)، (3) القدرة الضوئية (ضعف الإشارة يسبب أخطاء وإعادة إرسال)، "
          "(4) حمل الـ uplink."},
    {"k": ["صوت", "voip", "sip", "h248", "h.248", "المكالمه", "voice", "الهاتف", "pots"],
     "a": "خدمة الصوت: SIP أو H.248 على MDU/MxU. الإعداد: `voip` (عناوين media/signaling) → "
          "`interface sip <mgid>` + `if-sip attribute basic ...` → `sippstnuser add`. "
          "الفحص: `display sippstnuser`، و`pots emulational-call` لمكالمة اختبار آلية."},
    {"k": ["mos", "جوده الصوت", "r-factor", "jitter", "packet loss"],
     "a": "MOS يقيس جودة الصوت (1=سيء، 5=ممتاز؛ >4 جيد). افحص عبر "
          "`display esl online-info startuser <f>/<s>/<p>`: MOS، R-Factor، jitter، packet loss."},
    {"k": ["iptv", "multicast", "igmp", "البث", "القنوات", "بث تلفزيوني"],
     "a": "IPTV/Multicast: فعّل `btv` + `igmp user add service-port <idx> no-auth`، وأنشئ "
          "`multicast-vlan <v>` مع `igmp uplink-port`، `igmp version v3`، `igmp mode proxy|snooping`. "
          "للقنوات الثابتة: `igmp program add name <n> ip <group> sourceip <server>`."},
    {"k": ["save", "commit", "حفظ", "الفرق بين save و commit"],
     "a": "commit: يُطبّق البروفايلات (line/service profile) بعد تعديلها. save: يحفظ إعدادات الجهاز "
          "كلها في الذاكرة الدائمة. القاعدة: البروفايلات تحتاج `commit`، والتهيئة النهائية تحتاج `save`."},
    {"k": ["traffic table", "car", "cir", "pir", "حد السرعه", "قيود السرعه", "تحديد السرعه"],
     "a": "traffic table / CAR يحدّد سرعة المشترك: `traffic table ip index <i> cir <kbps> pir <kbps> "
          "priority user-cos <n>`. ثم تُربط عبر rx-cttr/tx-cttr في service-port. CIR=مضمون، PIR=أقصى."},
    {"k": ["uplink", "المنفذ الصاعد", "الابلينك", "الوصله الصاعده"],
     "a": "المنفذ الصاعد (uplink) يربط الـ OLT بشبكة المزوّد. يُضاف الـ S-VLAN إليه بـ "
          "`port vlan <v> 0/<slot> <port>`. يمكن تجميع عدّة منافذ بـ LACP للموثوقية والسعة."},
    {"k": ["حمايه", "protection", "type b", "type c", "protect-group", "التكرار"],
     "a": "حماية GPON: Type B تحمي منفذ الـ PON على الـ OLT، Type C تحمي المسار كاملاً حتى الـ ONT. "
          "تُعرّف بـ `protect-group` مع أعضاء work/protect، والتبديل: `force-switch port <a> to <b>`."},
    {"k": ["امن", "الامان", "security", "anti-dos", "هجمات", "acl", "firewall", "جدار الحمايه"],
     "a": "أمان الـ OLT: `security anti-dos enable`، `security anti-ipattack/anti-icmpattack enable`، "
          "تصفية MAC، و`firewall enable` مع `acl` وقواعد `firewall packet-filter <n> inbound`."},
    {"k": ["سبليتر", "splitter", "المقسم", "الموزع الضوئي"],
     "a": "المقسّم (Splitter): جهاز ضوئي سلبي (بلا كهرباء) يوزّع إشارة ليف واحد على عدّة مشتركين "
          "(1:8 / 1:16 / 1:32 / 1:64 / 1:128). كل مستوى تقسيم يضيف خسارة ضوئية (~3.5dB لكل 1:2)."},
    {"k": ["autofind", "auto-find", "اكتشاف", "ont confirm", "sn", "الرقم التسلسلي"],
     "a": "اكتشاف ONT: `port <p> ont-auto-find enable` ثم `display ont autofind <p>` لرؤية الـ SN، "
          "ثم `ont confirm <p> ontid <o> sn-auth <SN> omci ont-lineprofile-id <id> ont-srvprofile-id <id>`. "
          "أو أضِفه مسبقاً بـ `ont add`."},
    {"k": ["board", "البورد", "الكارت", "display board", "البوردات"],
     "a": "البوردات: `display board 0` يعرض حالة كل البوردات، و`display board 0/<slot>` يفصّل بورد "
          "معيّن وحالة موديولاته الضوئية. الحالات: Normal / Failed / Offline / Auto_find."},
    {"k": ["الطول الموجي", "wavelength", "1490", "1310", "1550"],
     "a": "الأطوال الموجية في GPON: 1490nm للنزول (downstream)، 1310nm للصعود (upstream)، "
          "1550nm لخدمة الفيديو RF (CATV overlay)."},
    {"k": ["epon", "الفرق بين gpon و epon"],
     "a": "GPON مقابل EPON: GPON من ITU-T (2.488G/1.244G، يعتمد GEM/OMCI، كفاءة أعلى)، "
          "EPON من IEEE (1.25G متماثل، إطارات Ethernet مباشرة). GPON أشيع لدى المشغّلين الكبار."},
    {"k": ["reboot", "اعاده تشغيل", "reset", "erase", "خطير", "حذف"],
     "a": "⚠️ أوامر خطرة (reboot/reset/erase/delete): تُعيد التشغيل أو تمسح إعدادات وقد تقطع الخدمة. "
          "تأكّد من وجود نسخة احتياطية (`save` + snapshot) ونفّذها في نافذة صيانة فقط."},
    {"k": ["ping", "الاتصال", "connectivity", "فحص الاتصال"],
     "a": "فحص الاتصال: استخدم `ping <ip>` من الـ OLT للتحقّق من الوصول للبوابة/الخادم. "
          "في وضع الاتصال يمكن للمساعد تنفيذ أوامر العرض (display/ping) تلقائياً."},
]

_GREETINGS = ["مرحبا", "السلام", "اهلا", "هاي", "hello", "hi", "صباح", "مساء"]


def _kb_sections() -> List[Dict]:
    """تقسيم مرجع الأوامر إلى أقسام حسب العناوين (##) للاسترجاع."""
    sections: List[Dict] = []
    title, body = None, []
    for line in _KNOWLEDGE.splitlines():
        if line.startswith("## ") or (line.startswith("# ") and not line.startswith("## ")):
            if title:
                sections.append({"title": title, "body": "\n".join(body).strip()})
            title, body = line.lstrip("# ").strip(), []
        else:
            body.append(line)
    if title:
        sections.append({"title": title, "body": "\n".join(body).strip()})
    return [s for s in sections if s["body"]]


_KB_SECTIONS = _kb_sections()


def _best_section(qn: str) -> Optional[Dict]:
    """أفضل قسم من مرجع الأوامر يطابق كلمات السؤال."""
    tokens = [t for t in qn.replace("`", " ").replace("/", " ").split() if len(t) >= 3]
    best, best_score = None, 0
    for sec in _KB_SECTIONS:
        tn = _normalize(sec["title"])
        bn = _normalize(sec["body"])
        score = 0
        for tok in tokens:
            if tok in tn:
                score += 3
            elif tok in bn:
                score += 1
        if score > best_score:
            best, best_score = sec, score
    return best if best_score >= 3 else None


def _best_concept(qn: str):
    """أفضل مفهوم يطابق السؤال (score, answer)."""
    best_ans, best_score = None, 0
    for c in _CONCEPTS:
        score = 0
        for kw in c["k"]:
            kwn = _normalize(kw)
            if kwn and kwn in qn:
                score += 2 if " " in kwn else 1
        if score > best_score:
            best_ans, best_score = c["a"], score
    return best_score, best_ans


_HOW_HINTS = ["كيف", "شلون", "شنو", "اسوي", "اعمل", "طريقه", "خطوات", "امر",
              "اوامر", "command", "config", "تهيئه", "اعداد", "how", "اجهز"]

_OFFLINE_FOOTER = "— إجابة محلية (بلا إنترنت) من معرفة HCIA/HCIP-Access."


def _offline_answer(question: str) -> Dict:
    """إجابة ذكية محلية بلا إنترنت: معرفة مفاهيمية + استرجاع من مرجع الأوامر."""
    qn = _normalize(question)

    # تحية
    if any(g in qn for g in _GREETINGS) and len(qn) <= 25:
        return {"answer": "مرحباً 👋 أنا المساعد الذكي لأجهزة Huawei OLT — أعمل الآن بلا إنترنت. "
                          "اسألني عن GPON، التزويد، التشخيص (offline/mismatch)، VLAN، DBA، الصوت، IPTV، "
                          "القدرة الضوئية، أو أي أمر Huawei.",
                "executed_commands": [], "source": "rules"}

    score, concept = _best_concept(qn)
    section = _best_section(qn)
    wants_how = any(h in qn for h in _HOW_HINTS)

    parts: List[str] = []
    if concept and score >= 1:
        parts.append(concept)
        # أرفق أوامر ذات صلة إذا كان السؤال عملياً والقسم مطابق
        if section and (wants_how or score < 2):
            parts.append(f"\n📋 أوامر ذات صلة — {section['title']}:\n{_snippet(section['body'])}")
    elif section:
        parts.append(f"📋 من مرجع الأوامر — {section['title']}:\n{_snippet(section['body'])}")
    else:
        # لا مطابقة قوية: مساعدة عامة مع المواضيع المتاحة
        return {"answer": "لم أجد إجابة دقيقة محلياً لهذا السؤال. أستطيع مساعدتك (بلا إنترنت) في: "
                          "مفهوم GPON/OLT/ONT، خطوات التزويد (FTTH/IPTV/صوت)، DBA وT-CONT وGEM، "
                          "أنواع VLAN وQ-in-Q، service-port، تشخيص offline/mismatch/config failed، "
                          "القدرة الضوئية وLOS، MOS، الحماية، والأمان. "
                          "أعِد صياغة سؤالك بكلمة مفتاحية من هذه المواضيع.\n\n"
                          "💡 لتحليل أعمق ومتصل بالجهاز، أضِف ANTHROPIC_API_KEY في ملف .env.",
                "executed_commands": [], "source": "rules"}

    parts.append(f"\n{_OFFLINE_FOOTER}")
    return {"answer": "\n".join(parts).strip(), "executed_commands": [], "source": "rules"}


def _snippet(body: str, limit: int = 1000) -> str:
    body = body.strip()
    return body if len(body) <= limit else body[:limit].rsplit("\n", 1)[0] + "\n…"
