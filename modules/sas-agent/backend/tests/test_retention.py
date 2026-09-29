"""اختبار سياسة الاحتفاظ — حذف القياسات/الإنذارات القديمة والإبقاء على الحديثة والنشطة."""
from datetime import timedelta
from sqlmodel import Session, select
from app.database import engine
from app.models import Metric, AlarmRecord, utcnow
from app.services.monitoring import purge_old_records
from app.config import settings


def test_purge_removes_old_keeps_recent_and_active():
    now = utcnow()
    old = now - timedelta(days=settings.metric_retention_days + 5)
    recent = now - timedelta(days=1)
    old_alarm_ts = now - timedelta(days=settings.alarm_retention_days + 5)

    with Session(engine) as db:
        db.add(Metric(olt_id=999, target="T", metric="rx_power", value=-20.0, ts=old))
        db.add(Metric(olt_id=999, target="T", metric="rx_power", value=-19.0, ts=recent))
        # إنذار قديم غير نشط → يُحذف ؛ إنذار قديم نشط → يبقى
        db.add(AlarmRecord(olt_id=999, severity="info", message="old-inactive",
                           active=False, ts=old_alarm_ts))
        db.add(AlarmRecord(olt_id=999, severity="critical", message="old-active",
                           active=True, ts=old_alarm_ts))
        db.commit()

        deleted = purge_old_records(db)
        assert deleted["metrics"] >= 1
        assert deleted["alarms"] >= 1

        metrics = db.exec(select(Metric).where(Metric.olt_id == 999)).all()
        # بقي القياس الحديث فقط
        assert all(m.value != -20.0 for m in metrics)
        assert any(m.value == -19.0 for m in metrics)

        alarms = db.exec(select(AlarmRecord).where(AlarmRecord.olt_id == 999)).all()
        msgs = {a.message for a in alarms}
        assert "old-active" in msgs          # النشط يبقى رغم قِدمه
        assert "old-inactive" not in msgs    # غير النشط القديم يُحذف
