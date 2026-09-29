"""تهيئة مشتركة للاختبارات — قاعدة بيانات اختبار معزولة ونظيفة، بلا حلقة مراقبة."""
import os

# ====================================================================
# يجب ضبط كل متغيّرات البيئة قبل أي استيراد من app
# (pydantic-settings تقرأ .env عند أول import للـ Settings)
# ====================================================================

# قاعدة بيانات اختبار معزولة
os.environ["DATABASE_URL"] = "sqlite:///./_pytest.db"

# فرض وضع المحاكاة — يتجاوز USE_MOCK_OLT=false في .env المطوّر
os.environ["USE_MOCK_OLT"] = "true"

# لا توكن API مطلوب في الاختبارات (وضع dev: use_mock_olt=true + api_token="")
os.environ["API_TOKEN"] = ""

# تعطيل سحّاب SNMP الدوري لمنع أي حلقة خلفية أثناء الاختبارات
os.environ.setdefault("SNMP_POLL_ENABLED", "false")

# تفعيل الوحدات التجريبية في الاختبارات (اختباراتها تضرب مساراتها) — الإنتاج مطفأ افتراضياً
os.environ["SEED_DEMO_DATA"] = "true"

# ضمان بيانات المدير الافتراضي ثابتة (test_users_auth يعتمد على admin/admin)
os.environ["SEED_DEFAULT_ADMIN"] = "true"
os.environ["DEFAULT_ADMIN_USER"] = "admin"
os.environ["DEFAULT_ADMIN_PASSWORD"] = "admin"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from app.database import init_db  # noqa: E402
from app.main import app, _seed_demo_device  # noqa: E402


@pytest.fixture(scope="session", autouse=True)
def _init_db():
    # قاعدة نظيفة كل جلسة اختبار (عزل تام عن قاعدة التطوير)
    for f in ("_pytest.db", "_pytest.db-wal", "_pytest.db-shm"):
        try:
            os.remove(f)
        except OSError:
            pass
    init_db()
    _seed_demo_device()


@pytest.fixture
def client():
    return TestClient(app)
