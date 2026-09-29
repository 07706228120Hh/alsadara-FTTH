"""add agent_report table (تصريحات الوكلاء + مقاطعة SAS)

Revision ID: a2b3c4d5e6f7
Revises: f6a7b8c9d0e1
Create Date: 2026-09-06

ينشئ جدول agentreport لتخزين تصريحات الوكلاء بعدد مشتركيهم (سجل تاريخي).
"""
from typing import Sequence, Union

import sqlalchemy as sa
import sqlmodel  # noqa: F401
from alembic import op

revision: str = "a2b3c4d5e6f7"
down_revision: Union[str, None] = "f6a7b8c9d0e1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "agentreport",
        sa.Column("id", sa.Integer(), nullable=False, primary_key=True),
        sa.Column("company_id", sa.Integer(),
                  sa.ForeignKey("company.id"), nullable=False),
        sa.Column("agent_username", sqlmodel.sql.sqltypes.AutoString(),
                  nullable=False),
        sa.Column("declared_total", sa.Integer(), nullable=False),
        sa.Column("declared_active", sa.Integer(), nullable=False,
                  server_default="0"),
        sa.Column("note", sqlmodel.sql.sqltypes.AutoString(), nullable=False,
                  server_default=""),
        sa.Column("submitted_by", sqlmodel.sql.sqltypes.AutoString(),
                  nullable=False, server_default=""),
        sa.Column("ts", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_agentreport_company_id",
                    "agentreport", ["company_id"])
    op.create_index("ix_agentreport_agent_username",
                    "agentreport", ["agent_username"])
    op.create_index("ix_agentreport_ts",
                    "agentreport", ["ts"])


def downgrade() -> None:
    op.drop_index("ix_agentreport_ts", "agentreport")
    op.drop_index("ix_agentreport_agent_username", "agentreport")
    op.drop_index("ix_agentreport_company_id", "agentreport")
    op.drop_table("agentreport")
