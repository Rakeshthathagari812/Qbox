"""A payment the customer added that is the same as another one: kept, not counted.

Revision ID: 0015
Revises: 0014
Create Date: 2026-11-24
"""

from alembic import op

revision = "0015"
down_revision = "0014"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE customer_records ADD COLUMN same BOOLEAN NOT NULL DEFAULT false")


def downgrade() -> None:
    op.execute("ALTER TABLE customer_records DROP COLUMN same")
