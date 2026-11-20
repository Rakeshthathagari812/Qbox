"""Udhaar: "This is not me" becomes a report that the shop decides on.

Before: the customer's tap hid the book at once (disowned_at).
Now:    NONE -> REPORTED (customer) -> CONFIRMED or UNLINKED (shop).
        REPORTED can be cancelled by the customer (back to NONE).
        CONFIRMED: the shop says the number is right; the customer cannot report again.
        UNLINKED:  the shop agrees it is the wrong number; hidden from that phone.
Existing hidden books become REPORTED, so their shops now decide.

Revision ID: 0005
Revises: 0004
Create Date: 2026-11-20
"""

from alembic import op

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        ALTER TABLE udhaar_customers
            ADD COLUMN dispute_status      VARCHAR(10) NOT NULL DEFAULT 'NONE',
            ADD COLUMN disputed_at         TIMESTAMPTZ,
            ADD COLUMN dispute_resolved_at TIMESTAMPTZ,
            ADD CONSTRAINT udhaar_customers_dispute_check
                CHECK (dispute_status IN ('NONE', 'REPORTED', 'CONFIRMED', 'UNLINKED'))
    """)
    op.execute("""
        UPDATE udhaar_customers
           SET dispute_status = 'REPORTED', disputed_at = disowned_at
         WHERE disowned_at IS NOT NULL
    """)
    op.execute("ALTER TABLE udhaar_customers DROP COLUMN disowned_at")


def downgrade() -> None:
    op.execute("ALTER TABLE udhaar_customers ADD COLUMN disowned_at TIMESTAMPTZ")
    op.execute("""
        UPDATE udhaar_customers SET disowned_at = disputed_at
         WHERE dispute_status IN ('REPORTED', 'UNLINKED')
    """)
    op.execute("""
        ALTER TABLE udhaar_customers
            DROP CONSTRAINT udhaar_customers_dispute_check,
            DROP COLUMN dispute_status,
            DROP COLUMN disputed_at,
            DROP COLUMN dispute_resolved_at
    """)
