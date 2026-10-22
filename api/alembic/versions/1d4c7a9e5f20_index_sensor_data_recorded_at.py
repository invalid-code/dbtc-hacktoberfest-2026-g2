"""Index the sensor readings by their recorded time

Revision ID: 1d4c7a9e5f20
Revises: 932b8d629ca2
Create Date: 2026-10-23 10:42:11.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '1d4c7a9e5f20'
down_revision: Union[str, Sequence[str], None] = '932b8d629ca2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_index(
        op.f('ix_sensor_data_recorded_at'),
        'sensor_data',
        ['recorded_at'],
        unique=False,
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(op.f('ix_sensor_data_recorded_at'), table_name='sensor_data')
