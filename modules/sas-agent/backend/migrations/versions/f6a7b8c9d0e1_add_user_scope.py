"""add user scope (regulator/company/agent)

Revision ID: f6a7b8c9d0e1
Revises: e5f6a7b8c9d0
Create Date: 2026-09-06

نطاق المستخدم لمنصّة رقابية: scope_company_id (مقيّد بشركة) + scope_agent (مقيّد بوكيل).
فارغ = جهة رقابية ترى الكل. يُوضع في backend/migrations/versions/.
"""
from typing import Sequence, Union

import sqlalchemy as sa
import sqlmodel  # noqa: F401
from alembic import op

revision: str = "f6a7b8c9d0e1"
down_revision: Union[str, None] = "e5f6a7b8c9d0"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("user", sa.Column("scope_company_id", sa.Integer(), nullable=True))
    op.add_column("user", sa.Column(
        "scope_agent", sqlmodel.sql.sqltypes.AutoString(),
        nullable=False, server_default=""))
    op.create_index("ix_user_scope_company_id", "user", ["scope_company_id"])


def downgrade() -> None:
    with op.batch_alter_table("user") as batch:
        batch.drop_index("ix_user_scope_company_id")
        batch.drop_column("scope_agent")
        batch.drop_column("scope_company_id")
