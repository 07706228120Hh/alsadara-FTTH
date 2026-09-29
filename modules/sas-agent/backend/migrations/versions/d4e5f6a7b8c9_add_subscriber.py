"""add subscriber table (SAS subscribers sync)

Revision ID: d4e5f6a7b8c9
Revises: c3d4e5f6a7b8
Create Date: 2026-09-05

يُوضع في backend/migrations/versions/d4e5f6a7b8c9_add_subscriber.py
"""
from typing import Sequence, Union

import sqlalchemy as sa
import sqlmodel  # noqa: F401
from alembic import op

revision: str = "d4e5f6a7b8c9"
down_revision: Union[str, None] = "c3d4e5f6a7b8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "subscriber",
        sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
        sa.Column("company_id", sa.Integer(), sa.ForeignKey("company.id"), nullable=False),
        sa.Column("sub_id", sa.Integer(), nullable=False),
        sa.Column("username", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("firstname", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("lastname", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("agent_username", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("profile_id", sa.Integer(), nullable=True),
        sa.Column("profile_name", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("status", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("online", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("expiration", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("city", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("governorate", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("phone", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
    )
    for col in ("company_id", "sub_id", "username", "agent_username", "status", "city", "governorate"):
        op.create_index(f"ix_subscriber_{col}", "subscriber", [col])


def downgrade() -> None:
    for col in ("governorate", "city", "status", "agent_username", "username", "sub_id", "company_id"):
        op.drop_index(f"ix_subscriber_{col}", table_name="subscriber")
    op.drop_table("subscriber")
