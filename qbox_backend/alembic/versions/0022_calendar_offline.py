"""Calendar events added offline: the same one sent twice is kept once.

Revision ID: 0022
Revises: 0021
Create Date: 2026-11-25
"""

from alembic import op

revision = "0022"
down_revision = "0021"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE calendar_events ADD COLUMN client_ref VARCHAR(40)")
    op.execute("CREATE UNIQUE INDEX uq_calendar_events_ref ON calendar_events (user_id, client_ref)")


def downgrade() -> None:
    op.execute("DROP INDEX uq_calendar_events_ref")
    op.execute("ALTER TABLE calendar_events DROP COLUMN client_ref")
