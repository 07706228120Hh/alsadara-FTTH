"""بيئة Alembic — مربوطة بـ SQLModel.metadata وإعدادات التطبيق."""
import os
import sys
from logging.config import fileConfig

from sqlalchemy import engine_from_config, pool
from alembic import context

# اجعل حزمة app قابلة للاستيراد عند تشغيل alembic من مجلد backend
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from sqlmodel import SQLModel  # noqa: E402
from app.config import settings  # noqa: E402
import app.models  # noqa: F401,E402  — استيراد لتسجيل الجداول في الـ metadata

config = context.config
# عنوان القاعدة من إعدادات التطبيق (يسمح بتجاوزه عبر متغيّر البيئة DATABASE_URL)
config.set_main_option("sqlalchemy.url", settings.database_url)

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = SQLModel.metadata


def run_migrations_offline() -> None:
    """توليد SQL دون اتصال بقاعدة البيانات."""
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        render_as_batch=True,      # ضروري لدعم ALTER على SQLite
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """تنفيذ الهجرات باتصال حي بقاعدة البيانات."""
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            render_as_batch=True,
            compare_type=True,
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
