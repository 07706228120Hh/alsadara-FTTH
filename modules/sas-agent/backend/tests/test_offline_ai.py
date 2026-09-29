"""اختبارات المساعد المحلي (يعمل بلا إنترنت) — يجب أن يجيب على أسئلة متنوّعة."""
from app.services import ai_assistant as ai


def _ans(q: str) -> str:
    r = ai._offline_answer(q)
    assert r["source"] == "rules"
    assert r["executed_commands"] == []
    return r["answer"]


def test_normalize():
    # توحيد الألف والهمزة والتشكيل والتطويل
    assert ai._normalize("الأِيثـرنت") == ai._normalize("الايثرنت")
    assert ai._normalize("GPON") == "gpon"


def test_concept_gpon():
    a = _ans("ما هو GPON؟")
    assert "2.488" in a or "GPON" in a
    assert "HCIA" in a  # يحوي التذييل المحلي


def test_concept_provisioning():
    a = _ans("كيف افعّل مشترك FTTH؟")
    assert "service-port" in a or "dba-profile" in a or "ont confirm" in a


def test_concept_offline_diagnosis():
    a = _ans("عندي ONT offline شنو اسوي؟")
    assert "port state" in a or "LOS" in a or "الفايبر" in a


def test_concept_optical_power():
    a = _ans("اشرح لي القدرة الضوئية")
    assert "-25" in a or "dBm" in a


def test_concept_vlan():
    a = _ans("شنو الفرق بين smart vlan و q-in-q")
    assert "smart" in a or "Q-in-Q" in a or "q-in-q" in a.lower()


def test_concept_voice():
    a = _ans("مشترك الصوت عنده قطع")
    assert "SIP" in a or "MOS" in a or "esl" in a or "voip" in a.lower()


def test_kb_section_retrieval():
    # سؤال عن IPTV يجب أن يسترجع قسماً من مرجع الأوامر أو مفهوماً
    a = _ans("كيف اسوي IPTV multicast؟")
    assert "igmp" in a.lower() or "multicast" in a.lower() or "btv" in a.lower()


def test_greeting():
    a = _ans("مرحبا")
    assert "المساعد الذكي" in a


def test_unknown_question_helpful():
    a = _ans("ما هي عاصمة فرنسا؟")
    # سؤال خارج النطاق: يعطي مساعدة عامة بالمواضيع المتاحة
    assert "GPON" in a or "التزويد" in a


def test_ask_uses_offline_when_no_key(monkeypatch):
    monkeypatch.setattr(ai, "_get_client", lambda: None)
    r = ai.ask(None, "ما هو DBA؟")
    assert r["source"] == "rules"
    assert "DBA" in r["answer"] or "T-CONT" in r["answer"]
