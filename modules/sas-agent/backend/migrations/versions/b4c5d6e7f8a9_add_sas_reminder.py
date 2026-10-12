"""add SasReminderSettings + SasReminderLog (pre-expiry auto reminder)

Revision ID: b4c5d6e7f8a9
Revises: f7a8b9c0d1e2
Create Date: 2026-10-12

جدولا «التذكير التلقائي قبل الانتهاء» لمشتركي حساب ساس:
  - sasremindersettings: إعدادات التذكير (صفّ واحد لكل company_id+owner_user_id+account_id).
  - sasreminderlog: سجلّ تنفيذ كل دورة تذكير (آلية/يدوية).
كلاهما معزول بثلاثي العزل المتّبع (company_id + owner_user_id + account_id)؛ لا أسرار فيهما.
"""
from typing import Sequence, Union

import sqlalchemy as sa
import sqlmodel  # noqa: F401
from alembic import op

revision: str = "b4c5d6e7f8a9"
down_revision: Union[str, None] = "f7a8b9c0d1e2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "sasremindersettings",
        sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
        sa.Column("company_id", sa.Integer(), nullable=False),
        sa.Column("owner_user_id", sa.Integer(), nullable=False),
        sa.Column("account_id", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.text("0")),
        sa.Column("days_before", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default="1"),
        sa.Column("send_hour", sa.Integer(), nullable=False, server_default=sa.text("10")),
        sa.Column("send_minute", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("template_id", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default="reminder"),
        sa.Column("last_run_date", sqlmodel.sql.sqltypes.AutoString(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint(
            "company_id", "owner_user_id", "account_id",
            name="uq_sasremindersettings_scope",
        ),
    )
    op.create_index("ix_sasremindersettings_company_id", "sasremindersettings", ["company_id"])
    op.create_index("ix_sasremindersettings_owner_user_id", "sasremindersettings", ["owner_user_id"])
    op.create_index("ix_sasremindersettings_account_id", "sasremindersettings", ["account_id"])

    op.create_table(
        "sasreminderlog",
        sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
        sa.Column("company_id", sa.Integer(), nullable=False),
        sa.Column("owner_user_id", sa.Integer(), nullable=False),
        sa.Column("account_id", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("executed_at", sa.DateTime(), nullable=False),
        sa.Column("days_before", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("total", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("sent", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("failed", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("is_manual", sa.Boolean(), nullable=False, server_default=sa.text("0")),
        sa.Column("triggered_by", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("note", sqlmodel.sql.sqltypes.AutoString(), nullable=True),
    )
    op.create_index("ix_sasreminderlog_company_id", "sasreminderlog", ["company_id"])
    op.create_index("ix_sasreminderlog_owner_user_id", "sasreminderlog", ["owner_user_id"])
    op.create_index("ix_sasreminderlog_account_id", "sasreminderlog", ["account_id"])
    op.create_index("ix_sasreminderlog_executed_at", "sasreminderlog", ["executed_at"])


def downgrade() -> None:
    op.drop_index("ix_sasreminderlog_executed_at", table_name="sasreminderlog")
    op.drop_index("ix_sasreminderlog_account_id", table_name="sasreminderlog")
    op.drop_index("ix_sasreminderlog_owner_user_id", table_name="sasreminderlog")
    op.drop_index("ix_sasreminderlog_company_id", table_name="sasreminderlog")
    op.drop_table("sasreminderlog")

    op.drop_index("ix_sasremindersettings_account_id", table_name="sasremindersettings")
    op.drop_index("ix_sasremindersettings_owner_user_id", table_name="sasremindersettings")
    op.drop_index("ix_sasremindersettings_company_id", table_name="sasremindersettings")
    op.drop_table("sasremindersettings")
