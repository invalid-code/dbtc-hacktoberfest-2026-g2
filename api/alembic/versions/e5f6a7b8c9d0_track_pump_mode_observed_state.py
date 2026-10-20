"""track the pump mode reported by the microcontroller

Revision ID: e5f6a7b8c9d0
Revises: d3e4f5a6b7c8
Create Date: 2026-10-20
"""

from alembic import op
import sqlalchemy as sa

revision = "e5f6a7b8c9d0"
down_revision = "d3e4f5a6b7c8"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "pump_mode",
        sa.Column("observed_mode", sa.Integer(), nullable=True),
    )
    op.add_column(
        "pump_mode",
        sa.Column("last_seen_at", sa.DateTime(), nullable=True),
    )


def downgrade():
    op.drop_column("pump_mode", "last_seen_at")
    op.drop_column("pump_mode", "observed_mode")
