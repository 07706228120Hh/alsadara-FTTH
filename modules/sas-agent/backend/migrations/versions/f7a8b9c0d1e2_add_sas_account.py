"""add SasAccount table + subscriber.sas_account_id (multi SAS accounts per agent)

Revision ID: f7a8b9c0d1e2
Revises: b3c4d5e6f7a8
Create Date: 2026-09-29

تعدد حسابات SAS للوكيل: جدول SasAccount يربط عدة حسابات (قد تكون على خوادم مختلفة)
بوكيل واحد، وكل مشترك يُوسَم بـ sas_account_id لتوجيه العمليات تلقائياً إلى الحساب الصحيح.
"""
from typing import Sequence, Union

import sqlalchemy as sa
import sqlmodel  # noqa: F401
from alembic import op

revision: str = "f7a8b9c0d1e2"
down_revision: Union[str, None] = "b3c4d5e6f7a8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "sasaccount",
        sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
        sa.Column("owner_user_id", sa.Integer(), nullable=False),
        sa.Column("company_id", sa.Integer(), nullable=True),
        sa.Column("label", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("sas_host", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("sas_https", sa.Boolean(), nullable=False, server_default=sa.text("0")),
        sa.Column("sas_verify_tls", sa.Boolean(), nullable=False, server_default=sa.text("0")),
        sa.Column("sas_username", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("sas_password_enc", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.text("1")),
        sa.Column("last_sync_at", sa.DateTime(), nullable=True),
        sa.Column("last_sync_ok", sa.Boolean(), nullable=False, server_default=sa.text("0")),
        sa.Column("last_sync_error", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["owner_user_id"], ["user.id"]),
        sa.ForeignKeyConstraint(["company_id"], ["company.id"]),
    )
    op.create_index("ix_sasaccount_owner_user_id", "sasaccount", ["owner_user_id"])
    op.create_index("ix_sasaccount_company_id", "sasaccount", ["company_id"])

    with op.batch_alter_table("subscriber") as batch:
        batch.add_column(sa.Column("sas_account_id", sa.Integer(), nullable=True))
        batch.create_index("ix_subscriber_sas_account_id", ["sas_account_id"])


def downgrade() -> None:
    with op.batch_alter_table("subscriber") as batch:
        batch.drop_index("ix_subscriber_sas_account_id")
        batch.drop_column("sas_account_id")
    op.drop_index("ix_sasaccount_company_id", table_name="sasaccount")
    op.drop_index("ix_sasaccount_owner_user_id", table_name="sasaccount")
    op.drop_table("sasaccount")
