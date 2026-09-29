"""اختبارات تصنيف الأوامر (classify) — نقية بلا اعتمادات خارجية."""
from app.core.command_library import classify


def test_read_commands():
    assert classify("display ont info 0 all") == "read"
    assert classify("ping 8.8.8.8") == "read"
    assert classify("show version") == "read"


def test_dangerous_whole_word():
    assert classify("reboot") == "dangerous"
    assert classify("ont delete 0 1") == "dangerous"
    assert classify("reset slot 0/5") == "dangerous"
    assert classify("undo service-port 100") == "dangerous"
    assert classify("erase flash") == "dangerous"
    assert classify("factory-setting restore") == "dangerous"


def test_no_false_positive_substring():
    # "deleted" ليست "delete" — يجب أن تبقى أمر عرض لا خطر
    assert classify("display ont deleted") == "read"


def test_telnet_not_read():
    # telnet لم يعد أمر عرض آمناً (منع التمحور/التسريب)
    assert classify("telnet 10.0.0.1") != "read"


def test_write_default():
    assert classify(
        "service-port 1 vlan 100 gpon 0/5/0 ont 1 gemport 1"
    ) == "write"
