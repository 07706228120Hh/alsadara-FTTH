"""add npn_counter table (per-governorate NPN sequence)

Revision ID: c9d0e1f2a3b4
Revises: b8c9d0e1f2a3
Create Date: 2026-09-07

عدّاد تسلسل رقم العقار الوطني (NPN) لكل محافظة — يضمن تفرّد الأرقام
عبر عمليات الترقيم المتتالية (نظام العنونة NAS-IQ).
"""
from typing import Sequence, Union

import sqlalchemy as sa
import sqlmodel  # noqa: F401
from alembic import op

revision: str = "c9d0e1f2a3b4"
down_revision: Union[str, None] = "b8c9d0e1f2a3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "npncounter",
        sa.Column("gov_code", sa.Integer(), primary_key=True, nullable=False),
        sa.Column("next_seq", sa.Integer(), nullable=False, server_default="0"),
    )


def downgrade() -> None:
    op.drop_table("npncounter")
