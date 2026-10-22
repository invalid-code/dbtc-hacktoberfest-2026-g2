"""Add the pump activation parameters

Revision ID: 932b8d629ca2
Revises: 843fed31fe6a
Create Date: 2026-10-22 19:05:12.481930

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '932b8d629ca2'
down_revision: Union[str, Sequence[str], None] = '843fed31fe6a'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table('pump_parameter',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('active', sa.Boolean(), nullable=False),
    sa.Column('moisture_threshold', sa.Integer(), nullable=False),
    sa.Column('activation_interval_minutes', sa.Integer(), nullable=False),
    sa.Column('mode', sa.Integer(), nullable=False),
    sa.Column('reason', sa.String(), nullable=False),
    sa.Column('updated_at', sa.DateTime(), nullable=False),
    sa.Column('pump_id', sa.Integer(), nullable=False),
    sa.ForeignKeyConstraint(['pump_id'], ['pump.id'], ),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('pump_id')
    )
    op.create_index(op.f('ix_pump_parameter_id'), 'pump_parameter', ['id'], unique=False)


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(op.f('ix_pump_parameter_id'), table_name='pump_parameter')
    op.drop_table('pump_parameter')
