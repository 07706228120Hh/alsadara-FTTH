"""add agent + merge_finding (SAS agents & merge-detection)

Revision ID: b2c3d4e5f6a7
Revises: a1b2c3d4e5f6
Create Date: 2026-09-04

يُوضع في backend/migrations/versions/b2c3d4e5f6a7_add_agent_merge.py
"""
from typing import Sequence, Union

import sqlalchemy as sa
import sqlmodel  # noqa: F401
from alembic import op

revision: str = "b2c3d4e5f6a7"
down_revision: Union[str, None] = "a1b2c3d4e5f6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "agent",
        sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
        sa.Column("company_id", sa.Integer(), sa.ForeignKey("company.id"), nullable=False),
        sa.Column("manager_id", sa.Integer(), nullable=False),
        sa.Column("username", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("firstname", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("lastname", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("parent_id", sa.Integer(), nullable=True),
        sa.Column("parent_username", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("users_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("balance", sa.Float(), nullable=False, server_default="0"),
        sa.Column("reward_points", sa.Float(), nullable=False, server_default="0"),
        sa.Column("discount_rate", sa.Float(), nullable=False, server_default="0"),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_agent_company_id", "agent", ["company_id"])
    op.create_index("ix_agent_manager_id", "agent", ["manager_id"])
    op.create_index("ix_agent_username", "agent", ["username"])

    op.create_table(
        "mergefinding",
        sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
        sa.Column("company_id", sa.Integer(), sa.ForeignKey("company.id"), nullable=False),
        sa.Column("username", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("kind", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("severity", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default="warning"),
        sa.Column("session_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("nas_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("ip_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("detail", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("ts", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_mergefinding_company_id", "mergefinding", ["company_id"])
    op.create_index("ix_mergefinding_username", "mergefinding", ["username"])
    op.create_index("ix_mergefinding_ts", "mergefinding", ["ts"])


def downgrade() -> None:
    op.drop_index("ix_mergefinding_ts", table_name="mergefinding")
    op.drop_index("ix_mergefinding_username", table_name="mergefinding")
    op.drop_index("ix_mergefinding_company_id", table_name="mergefinding")
    op.drop_table("mergefinding")
    op.drop_index("ix_agent_username", table_name="agent")
    op.drop_index("ix_agent_manager_id", table_name="agent")
    op.drop_index("ix_agent_company_id", table_name="agent")
    op.drop_table("agent")
