"""Pay to Shop: a customer pays a shop from their own QBOX app (source DIRECT).
claimed_at = the customer says they paid the shop's UPI ID; the shop confirms.

Revision ID: 0009
Revises: 0008
Create Date: 2026-11-24
"""

from alembic import op

revision = "0009"
down_revision = "0008"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE payments ADD COLUMN claimed_at TIMESTAMPTZ")
    op.execute("ALTER TABLE payments DROP CONSTRAINT payments_source_check")
    op.execute("ALTER TABLE payments ADD CONSTRAINT payments_source_check "
               "CHECK (source IN ('COUNTER', 'UDHAAR', 'MANUAL', 'DIRECT'))")


def downgrade() -> None:
    # Refuses (constraint error) while DIRECT payments exist: money records are never thrown away.
    op.execute("ALTER TABLE payments DROP CONSTRAINT payments_source_check")
    op.execute("ALTER TABLE payments ADD CONSTRAINT payments_source_check "
               "CHECK (source IN ('COUNTER', 'UDHAAR', 'MANUAL'))")
    op.execute("ALTER TABLE payments DROP COLUMN claimed_at")
