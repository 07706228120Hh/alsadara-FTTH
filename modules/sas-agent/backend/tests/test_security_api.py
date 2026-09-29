"""اختبارات تكامل للأمان — تتطلب الاعتمادات (fastapi/httpx). تعمل في وضع المحاكاة."""
from app.config import settings


def test_health_open(client):
    # فحص الصحّة مفتوح بلا مصادقة
    assert client.get("/api/health").status_code == 200


def test_devices_open_in_mock_without_token(client):
    # وضع المحاكاة بلا توكن → مسموح (تطوير محلي)
    assert settings.use_mock_olt is True
    assert settings.api_token == ""
    assert client.get("/api/devices").status_code == 200


def test_auth_rejects_wrong_token(client, monkeypatch):
    monkeypatch.setattr(settings, "api_token", "secret123")
    # بلا ترويسة → 401
    assert client.get("/api/devices").status_code == 401
    # توكن خاطئ → 401
    assert client.get(
        "/api/devices", headers={"Authorization": "Bearer wrong"}
    ).status_code == 401
    # توكن صحيح → 200
    assert client.get(
        "/api/devices", headers={"Authorization": "Bearer secret123"}
    ).status_code == 200


def test_dangerous_command_requires_confirm(client):
    # الجهاز التجريبي (id=1) مزروع في وضع المحاكاة
    r = client.post("/api/devices/1/command", json={"command": "reboot"})
    assert r.status_code == 400
    r2 = client.post(
        "/api/devices/1/command?confirm=true", json={"command": "reboot"}
    )
    assert r2.status_code == 200
