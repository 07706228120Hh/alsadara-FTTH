"""add group_name to gislayer (free-text level/group)

Revision ID: b8c9d0e1f2a3
Revises: a7b8c9d0e1f2
Create Date: 2026-09-07

مستوى/مجموعة حرّة لكل طبقة GIS (اسم يدوي: شركة، «الباك بون»، أي تصنيف)
— أساس التصفية/البحث/التلوين. مستقلّ عن company_id (الذي يبقى للعزل).
"""
from typing import Sequence, Union

import sqlalchemy as sa
import sqlmodel  # noqa: F401
from alembic import op

revision: str = "b8c9d0e1f2a3"
down_revision: Union[str, None] = "a7b8c9d0e1f2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "gislayer",
        sa.Column(
            "group_name",
            sqlmodel.sql.sqltypes.AutoString(),
            nullable=False,
            server_default="",
        ),
    )
    op.create_index("ix_gislayer_group_name", "gislayer", ["group_name"])


def downgrade() -> None:
    op.drop_index("ix_gislayer_group_name", table_name="gislayer")
    op.drop_column("gislayer", "group_name")
