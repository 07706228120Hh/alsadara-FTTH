"""
مدير الاتصال بالـ OLT — يوحّد الواجهة بين المحاكي والجهاز الحقيقي (Netmiko).
يحتفظ بجلسة حية لكل جهاز ويطبّق طابور أوامر آمن.
"""
import threading
from typing import Dict, List, Optional
from ..config import settings
from .mock_olt import MockOLT

try:
    from netmiko import ConnectHandler
    HAS_NETMIKO = True
except Exception:  # pragma: no cover
    HAS_NETMIKO = False


class OLTSession:
    """جلسة اتصال واحدة بجهاز OLT"""

    def __init__(self, host: str, username: str, password: str,
                 protocol: str = "ssh", port: int = 22, name: str = "OLT"):
        self.host = host
        self.username = username
        self.password = password
        self.protocol = protocol
        self.port = port
        self.name = name
        self._lock = threading.Lock()     # جلسة واحدة = أمر واحد في كل مرة
        self._conn = None
        self._mock: Optional[MockOLT] = None
        self.connected = False

    def connect(self) -> bool:
        if settings.use_mock_olt:
            self._mock = MockOLT(self.name)
            self.connected = True
            return True
        if not HAS_NETMIKO:
            raise RuntimeError("Netmiko غير مثبّت — ثبّت المتطلبات أو فعّل وضع المحاكاة")
        if self.protocol == "ssh":
            device_type = "huawei_smartax"
        elif self.protocol == "telnet":
            device_type = "huawei_olt_telnet"
        else:
            raise ValueError(f"Protocol غير مدعوم: {self.protocol}")
        self._conn = ConnectHandler(
            device_type=device_type,
            host=self.host,
            username=self.username,
            password=self.password,
            port=self.port,
            fast_cli=False,
            conn_timeout=settings.ssh_conn_timeout,   # مهلة إنشاء الاتصال
            timeout=settings.ssh_conn_timeout,        # مهلة عمليات القناة
        )
        self.connected = True
        return True

    def run(self, command: str) -> str:
        """تنفيذ أمر عرض واحد وإرجاع المخرجات"""
        with self._lock:
            if settings.use_mock_olt:
                return self._mock.execute(command)
            if not self._conn:
                self.connect()
            return self._conn.send_command_timing(
                command, read_timeout=settings.ssh_read_timeout)

    def run_config(self, commands: List[str]) -> str:
        """تنفيذ سلسلة أوامر تهيئة"""
        with self._lock:
            out = []
            if settings.use_mock_olt:
                for cmd in commands:
                    out.append(self._mock.execute(cmd))
                return "\n".join(out)
            if not self._conn:
                self.connect()
            return self._conn.send_config_set(
                commands, read_timeout=settings.ssh_read_timeout)

    def disconnect(self):
        if self._conn:
            try:
                self._conn.disconnect()
            except Exception:
                pass
        self.connected = False


class ConnectionManager:
    """يدير كل الجلسات الحية (جلسة لكل OLT)"""

    def __init__(self):
        self._sessions: Dict[int, OLTSession] = {}
        self._lock = threading.Lock()

    def get(self, device) -> OLTSession:
        from .security import decrypt
        with self._lock:
            sess = self._sessions.get(device.id)
            if sess is None or not sess.connected:
                sess = OLTSession(
                    host=device.host,
                    username=device.username,
                    password=decrypt(device.password_enc),
                    protocol=device.protocol,
                    port=device.port,
                    name=device.name,
                )
                sess.connect()
                self._sessions[device.id] = sess
            return sess

    def drop(self, device_id: int):
        with self._lock:
            sess = self._sessions.pop(device_id, None)
            if sess:
                sess.disconnect()


# مثيل عام واحد
manager = ConnectionManager()
