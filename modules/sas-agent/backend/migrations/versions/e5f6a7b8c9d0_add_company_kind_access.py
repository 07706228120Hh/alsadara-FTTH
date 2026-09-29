"""add company kind + access_type

Revision ID: e5f6a7b8c9d0
Revises: d4e5f6a7b8c9
Create Date: 2026-09-06

نوع الشركة (رئيسية/ثانوية) ونوع الوصول (FTTH/وايرليس).
يُوضع في backend/migrations/versions/e5f6a7b8c9d0_add_company_kind_access.py
"""
from typing import Sequence, Union

import sqlalchemy as sa
import sqlmodel  # noqa: F401
from alembic import op

revision: str = "e5f6a7b8c9d0"
down_revision: Union[str, None] = "d4e5f6a7b8c9"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("company", sa.Column(
        "kind", sqlmodel.sql.sqltypes.AutoString(),
        nullable=False, server_default="primary"))
    op.add_column("company", sa.Column(
        "access_type", sqlmodel.sql.sqltypes.AutoString(),
        nullable=False, server_default="ftth"))


def downgrade() -> None:
    with op.batch_alter_table("company") as batch:
        batch.drop_column("access_type")
        batch.drop_column("kind")
