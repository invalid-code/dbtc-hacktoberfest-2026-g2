"""replace water_level with humidity and make temperature non-nullable

Revision ID: d3e4f5a6b7c8
Revises: b7c9d1e3f5a2
Create Date: 2026-10-20
"""

from alembic import op
import sqlalchemy as sa

revision = "d3e4f5a6b7c8"
down_revision = "b7c9d1e3f5a2"
branch_labels = None
depends_on = None


def upgrade():
    op.alter_column(
        "sensor_data",
        "temperature",
        existing_type=sa.Float(),
        nullable=False,
    )
    op.add_column(
        "sensor_data",
        sa.Column("humidity", sa.Integer(), nullable=False, server_default="50"),
    )
    op.drop_column("sensor_data", "water_level")


def downgrade():
    op.add_column(
        "sensor_data",
        sa.Column("water_level", sa.Integer(), nullable=False, server_default="50"),
    )
    op.drop_column("sensor_data", "humidity")
    op.alter_column(
        "sensor_data",
        "temperature",
        existing_type=sa.Float(),
        nullable=True,
    )
