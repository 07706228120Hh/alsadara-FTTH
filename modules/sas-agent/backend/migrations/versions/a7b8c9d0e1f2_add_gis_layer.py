"""add gis_layer table for fiber/route GIS uploads

Revision ID: a7b8c9d0e1f2
Revises: a2b3c4d5e6f7
Create Date: 2026-09-07

طبقة GIS لرفع مسارات الألياف/الشبكة — تُحوَّل إلى GeoJSON وتُخزَّن
مع ربط اختياري بشركة (company_id=None = طبقة عامّة).
"""
from typing import Sequence, Union

import sqlalchemy as sa
import sqlmodel  # noqa: F401
from alembic import op

revision: str = "a7b8c9d0e1f2"
down_revision: Union[str, None] = "a2b3c4d5e6f7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "gislayer",
        sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
        sa.Column("name", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default=""),
        sa.Column("kind", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default="fiber"),
        sa.Column("company_id", sa.Integer(), sa.ForeignKey("company.id"), nullable=True),
        sa.Column("geojson", sqlmodel.sql.sqltypes.AutoString(), nullable=False, server_default="{}"),
        sa.Column("feature_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_gislayer_name", "gislayer", ["name"])
    op.create_index("ix_gislayer_company_id", "gislayer", ["company_id"])


def downgrade() -> None:
    op.drop_index("ix_gislayer_company_id", table_name="gislayer")
    op.drop_index("ix_gislayer_name", table_name="gislayer")
    op.drop_table("gislayer")
