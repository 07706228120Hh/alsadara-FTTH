"""تهيئة قاعدة البيانات وجلساتها"""
from sqlmodel import SQLModel, create_engine, Session
from sqlalchemy import event
from .config import settings

_is_sqlite = settings.database_url.startswith("sqlite")
# timeout: مهلة انتظار القفل (busy_timeout) بدل الفشل الفوري عند تزامن عدة كتّاب.
connect_args = {"check_same_thread": False, "timeout": 30} if _is_sqlite else {}
engine = create_engine(settings.database_url, echo=False, connect_args=connect_args)


if _is_sqlite:
    @event.listens_for(engine, "connect")
    def _sqlite_pragmas(dbapi_conn, _rec):  # noqa: ANN001
        """WAL يسمح بقارئ+كاتب متزامنين؛ busy_timeout ينتظر القفل بدل «database is locked».
        ضروري لأن مزامنة SAS (حلقة الأحداث) تكتب بالتوازي مع سحّابات SNMP/المراقبة (خيوط)."""
        cur = dbapi_conn.cursor()
        cur.execute("PRAGMA journal_mode=WAL")
        cur.execute("PRAGMA busy_timeout=30000")
        cur.execute("PRAGMA synchronous=NORMAL")
        cur.close()


def _ensure_columns() -> None:
    """هجرة خفيفة idempotent لقواعد SQLite القائمة: يضيف الأعمدة الناقصة على الجداول
    الموجودة (create_all ينشئ الجداول الجديدة فقط ولا يُعدّل القائمة منها).
    للنشر السحابي (Postgres) تُدار الأعمدة عبر Alembic؛ هنا أمان للنشر المحلي (Windows)."""
    if not _is_sqlite:
        return
    # (table, column, DDL type + default) — يُطبَّق فقط إن غاب العمود
    wanted = [
        ("subscriber", "sas_account_id", "INTEGER"),
    ]
    from sqlalchemy import inspect as _inspect, text as _text
    insp = _inspect(engine)
    existing_tables = set(insp.get_table_names())
    with engine.begin() as conn:
        for table, column, ddl in wanted:
            if table not in existing_tables:
                continue                       # الجدول نفسه جديد → create_all يتكفّل به بأعمدته
            cols = {c["name"] for c in insp.get_columns(table)}
            if column not in cols:
                conn.execute(_text(f'ALTER TABLE {table} ADD COLUMN {column} {ddl}'))


def init_db() -> None:
    """إنشاء الجداول عند بدء التشغيل"""
    from . import models  # noqa: F401  (تسجيل النماذج)
    SQLModel.metadata.create_all(engine)
    _ensure_columns()


def get_session():
    """مولّد جلسة لاستخدامه مع Depends في FastAPI"""
    with Session(engine) as session:
        yield session
