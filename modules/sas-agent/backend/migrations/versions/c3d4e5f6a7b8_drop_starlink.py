"""drop starlinkdevice table (Starlink feature removed)

Revision ID: c3d4e5f6a7b8
Revises: b2c3d4e5f6a7
Create Date: 2026-09-05

يُوضع في backend/migrations/versions/c3d4e5f6a7b8_drop_starlink.py
"""
from typing import Sequence, Union

import sqlalchemy as sa
import sqlmodel  # noqa: F401
from alembic import op

revision: str = "c3d4e5f6a7b8"
down_revision: Union[str, None] = "b2c3d4e5f6a7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # حذف جدول أجهزة ستار لنك (المزيّة أُزيلت بالكامل). آمن إن كان غير موجود.
    bind = op.get_bind()
    insp = sa.inspect(bind)
    if "starlinkdevice" in insp.get_table_names():
        op.drop_table("starlinkdevice")


def downgrade() -> None:
    # إعادة إنشاء الجدول (مطابق لهجرة الإنشاء الأصلية c902d37b1884).
    op.create_table(
        "starlinkdevice",
        sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
        sa.Column("device_name", sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column("hardware", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default="Standard"),
        sa.Column("kit_serial", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("governorate", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_starlinkdevice_kit_serial", "starlinkdevice", ["kit_serial"])
    op.create_index("ix_starlinkdevice_governorate", "starlinkdevice", ["governorate"])
    op.create_index("ix_starlinkdevice_created_at", "starlinkdevice", ["created_at"])
