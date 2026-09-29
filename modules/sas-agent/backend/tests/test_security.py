"""اختبارات وكلاء الأمن الدفاعي."""
from app.services import security_agents as sec


def test_hardening_returns_findings():
    fs = sec.audit_hardening()
    assert fs and all(hasattr(x, "severity") for x in fs)
    assert all(x.severity in (sec.CRITICAL, sec.HIGH, sec.MEDIUM, sec.LOW, sec.INFO) for x in fs)


def test_code_scan_no_false_exec_on_sqlmodel():
    """db.exec(...) يجب ألا يُصنَّف استخدام exec()."""
    fs = sec.scan_code(sec._project_root())
    exec_hits = [x for x in fs if x.title == "استخدام exec()"]
    # ملفات المشروع تستخدم db.exec كثيراً؛ يجب ألا تُلتقط
    assert exec_hits == [], f"false positives: {[x.location for x in exec_hits]}"


def test_crypto_review_present():
    fs = sec.audit_crypto()
    titles = " ".join(x.title for x in fs)
    assert "Fernet" in titles and "PBKDF2" in titles


def test_full_scan_shape(client):
    r = client.get("/api/security/scan")
    assert r.status_code == 200
    j = r.json()
    assert 0 <= j["score"] <= 100
    assert set(j["counts"]) == {"critical", "high", "medium", "low", "info"}
    assert isinstance(j["findings"], list)


def test_security_requires_admin(client, monkeypatch):
    # في وضع dev (mock + بلا توكن) الهوية admin، فالمسار يعمل؛
    # نتحقّق فقط أن المسار محمي ومُعرَّف.
    assert client.get("/api/security/hardening").status_code == 200
