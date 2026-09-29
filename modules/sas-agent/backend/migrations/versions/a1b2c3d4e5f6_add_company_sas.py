"""add company + company_snapshot (SAS integration)

Revision ID: a1b2c3d4e5f6
Revises: 3f8a21d6c094
Create Date: 2026-09-04

يُوضع في backend/migrations/versions/a1b2c3d4e5f6_add_company_sas.py
"""
from typing import Sequence, Union

import sqlalchemy as sa
import sqlmodel  # noqa: F401  (أنواع أعمدة SQLModel)
from alembic import op

revision: str = "a1b2c3d4e5f6"
down_revision: Union[str, None] = "3f8a21d6c094"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "company",
        sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
        sa.Column("name", sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column("code", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("governorate", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("color", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default="#22D3EE"),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("sas_host", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("sas_https", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("sas_verify_tls", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("sas_username", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("sas_password_enc", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("last_sync_at", sa.DateTime(), nullable=True),
        sa.Column("last_sync_ok", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("last_sync_error", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_company_name", "company", ["name"])
    op.create_index("ix_company_code", "company", ["code"])

    op.create_table(
        "companysnapshot",
        sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
        sa.Column("company_id", sa.Integer(), sa.ForeignKey("company.id"), nullable=False),
        sa.Column("ts", sa.DateTime(), nullable=False),
        sa.Column("total", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("active", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("expired", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("online", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("offline", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("expiring_today", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("expiring_soon", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("fup", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("managers", sa.Integer(), nullable=False, server_default="0"),
    )
    op.create_index("ix_companysnapshot_company_id", "companysnapshot", ["company_id"])
    op.create_index("ix_companysnapshot_ts", "companysnapshot", ["ts"])


def downgrade() -> None:
    op.drop_index("ix_companysnapshot_ts", table_name="companysnapshot")
    op.drop_index("ix_companysnapshot_company_id", table_name="companysnapshot")
    op.drop_table("companysnapshot")
    op.drop_index("ix_company_code", table_name="company")
    op.drop_index("ix_company_name", table_name="company")
    op.drop_table("company")
