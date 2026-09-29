"""add sas_username + sas_password_enc to user (per-agent SAS credentials)

Revision ID: e1f2a3b4c5d6
Revises: d0e1f2a3b4c5
Create Date: 2026-09-12

بيانات اتصال SAS خاصّة بكل وكيل: يتصل الوكيل بحساب المدير الخاص به داخل خادم SAS
شركته (عنوان الخادم يُورَث من الشركة؛ اسم المستخدم/كلمة المرور من حساب الوكيل).
"""
from typing import Sequence, Union

import sqlalchemy as sa
import sqlmodel  # noqa: F401
from alembic import op

revision: str = "e1f2a3b4c5d6"
down_revision: Union[str, None] = "d0e1f2a3b4c5"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("user") as batch:
        batch.add_column(sa.Column(
            "sas_username", sqlmodel.sql.sqltypes.AutoString(),
            nullable=False, server_default=""))
        batch.add_column(sa.Column(
            "sas_password_enc", sqlmodel.sql.sqltypes.AutoString(),
            nullable=False, server_default=""))


def downgrade() -> None:
    with op.batch_alter_table("user") as batch:
        batch.drop_column("sas_password_enc")
        batch.drop_column("sas_username")
