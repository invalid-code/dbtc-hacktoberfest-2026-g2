"""flag the garbled sensor readings sent as a halloween easter egg

Revision ID: b2c3d4e5f6a7
Revises: e5f6a7b8c9d0
Create Date: 2026-10-20
"""

from alembic import op
import sqlalchemy as sa

revision = "b2c3d4e5f6a7"
down_revision = "e5f6a7b8c9d0"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "sensor_data",
        sa.Column(
            "garbled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )


def downgrade():
    op.drop_column("sensor_data", "garbled")
