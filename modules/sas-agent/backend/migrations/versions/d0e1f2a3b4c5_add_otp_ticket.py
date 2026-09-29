"""add otpcode + ticket + ticketreply (subscriber app + tickets chain)

Revision ID: d0e1f2a3b4c5
Revises: c9d0e1f2a3b4
Create Date: 2026-09-09

تطبيق المشتركين (دخول OTP واتساب) وسلسلة متابعة التذاكر
(المشترك → الوكيل → الشركة → الوزارة).
"""
from typing import Sequence, Union

import sqlalchemy as sa
import sqlmodel  # noqa: F401
from alembic import op

revision: str = "d0e1f2a3b4c5"
down_revision: Union[str, None] = "c9d0e1f2a3b4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _normalize_phone(raw: str) -> str:
    """نسخة مستقلة من services/otp.normalize_phone (الهجرة لا تستورد من app)."""
    import re
    if not raw:
        return ""
    s = raw.translate(str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹", "01234567890123456789"))
    s = re.sub(r"\D", "", s)
    if s.startswith("00"):
        s = s[2:]
    if s.startswith("964"):
        s = s[3:]
    s = s.lstrip("0")
    return "964" + s if (len(s) == 10 and s.startswith("7")) else ""


def upgrade() -> None:
    # عمود الهاتف المطبَّع على المشتركين + تعبئة رجعية من العمود النصّي
    with op.batch_alter_table("subscriber") as batch:
        batch.add_column(sa.Column("phone_norm", sqlmodel.sql.sqltypes.AutoString(),
                                   nullable=False, server_default=""))
    op.create_index("ix_subscriber_phone_norm", "subscriber", ["phone_norm"])
    conn = op.get_bind()
    rows = conn.execute(sa.text("SELECT id, phone FROM subscriber WHERE phone <> ''")).fetchall()
    for rid, phone in rows:
        norm = _normalize_phone(phone or "")
        if norm:
            conn.execute(sa.text("UPDATE subscriber SET phone_norm = :n WHERE id = :i"),
                         {"n": norm, "i": rid})

    op.create_table(
        "otpcode",
        sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
        sa.Column("phone", sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column("code_hash", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("consumed", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("expires_at", sa.DateTime(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_otpcode_phone", "otpcode", ["phone"])
    op.create_index("ix_otpcode_expires_at", "otpcode", ["expires_at"])
    op.create_index("ix_otpcode_created_at", "otpcode", ["created_at"])

    op.create_table(
        "ticket",
        sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
        sa.Column("company_id", sa.Integer(), sa.ForeignKey("company.id"), nullable=False),
        sa.Column("agent_username", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("subscriber_username", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("subscriber_phone", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("subscriber_name", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("category", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default="complaint"),
        sa.Column("subject", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("body", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("status", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default="open"),
        sa.Column("priority", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default="normal"),
        sa.Column("escalated", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("created_by", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("created_by_kind", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default="subscriber"),
        sa.Column("assigned_to", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.Column("resolved_at", sa.DateTime(), nullable=True),
    )
    for col in ("company_id", "agent_username", "subscriber_username", "subscriber_phone",
                "category", "status", "escalated", "created_at"):
        op.create_index(f"ix_ticket_{col}", "ticket", [col])

    op.create_table(
        "ticketreply",
        sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
        sa.Column("ticket_id", sa.Integer(), sa.ForeignKey("ticket.id"), nullable=False),
        sa.Column("author", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("author_kind", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default="subscriber"),
        sa.Column("body", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("internal", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("ts", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_ticketreply_ticket_id", "ticketreply", ["ticket_id"])
    op.create_index("ix_ticketreply_ts", "ticketreply", ["ts"])


def downgrade() -> None:
    op.drop_table("ticketreply")
    op.drop_table("ticket")
    op.drop_table("otpcode")
    op.drop_index("ix_subscriber_phone_norm", table_name="subscriber")
    with op.batch_alter_table("subscriber") as batch:
        batch.drop_column("phone_norm")
