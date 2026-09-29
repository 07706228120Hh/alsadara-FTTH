"""subscriber.company_id nullable (مشترك مُضاف يدوياً/مواطن بلا شركة)

Revision ID: b3c4d5e6f7a8
Revises: e1f2a3b4c5d6
Create Date: 2026-09-13

يسمح بإضافة مشترك (مواطن) يدوياً من لوحة الوزارة بالهاتف + الاسم فقط، دون
انتمائه لشركة. يدخل عبر رقم الهاتف + OTP واتساب (phone_norm مفتاح الدخول).
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "b3c4d5e6f7a8"
down_revision: Union[str, None] = "e1f2a3b4c5d6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("subscriber") as batch:
        batch.alter_column("company_id", existing_type=sa.Integer(), nullable=True)


def downgrade() -> None:
    # تعبئة الصفوف اليتيمة (company_id IS NULL) بصفر قبل إعادة NOT NULL
    op.execute("UPDATE subscriber SET company_id = 0 WHERE company_id IS NULL")
    with op.batch_alter_table("subscriber") as batch:
        batch.alter_column("company_id", existing_type=sa.Integer(), nullable=False)
