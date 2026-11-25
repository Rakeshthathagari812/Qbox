"""Supplier side: connecting a shop's supplier with a QBOX Supplier account,
orders the supplier answers, and entries both agree on.

Revision ID: 0016
Revises: 0015
Create Date: 2026-11-24
"""

from alembic import op

revision = "0016"
down_revision = "0015"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        CREATE TABLE supply_links (
            id               BIGSERIAL PRIMARY KEY,
            supplier_id      BIGINT NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
            shop_user_id     BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            supplier_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            status           VARCHAR(10) NOT NULL,
            asked_at         TIMESTAMPTZ NOT NULL,
            answered_at      TIMESTAMPTZ,
            decline_reason   VARCHAR(200),
            opening_paise    BIGINT,
            opening_entry_id BIGINT,
            ended_at         TIMESTAMPTZ,
            ended_by_shop    BOOLEAN,
            CONSTRAINT supply_links_status_check
                CHECK (status IN ('ASKED', 'ON', 'DECLINED', 'CANCELLED', 'ENDED'))
        )
    """)
    # One connection at a time: for a supplier in a shop's list, and for a pair of accounts.
    op.execute("CREATE UNIQUE INDEX supply_links_one_per_supplier ON supply_links (supplier_id)"
               " WHERE status IN ('ASKED', 'ON')")
    op.execute("CREATE UNIQUE INDEX supply_links_one_per_pair ON supply_links (shop_user_id, supplier_user_id)"
               " WHERE status IN ('ASKED', 'ON')")
    op.execute("CREATE INDEX idx_supply_links_supplier_user ON supply_links (supplier_user_id)")

    op.execute("ALTER TABLE supplier_entries ADD COLUMN link_id BIGINT REFERENCES supply_links(id) ON DELETE SET NULL")
    op.execute("ALTER TABLE supplier_entries ADD COLUMN confirm VARCHAR(10)")
    op.execute("ALTER TABLE supplier_entries ADD COLUMN answered_at TIMESTAMPTZ")
    op.execute("ALTER TABLE supplier_entries ADD COLUMN dispute_reason VARCHAR(200)")
    op.execute("ALTER TABLE supplier_entries ADD CONSTRAINT supplier_entries_confirm_check"
               " CHECK (confirm IS NULL OR confirm IN ('WAITING', 'CONFIRMED', 'DISPUTED', 'CLOSED'))")
    op.execute("CREATE INDEX idx_supplier_entries_link ON supplier_entries (link_id) WHERE link_id IS NOT NULL")

    op.execute("ALTER TABLE supplier_orders ADD COLUMN link_id BIGINT REFERENCES supply_links(id) ON DELETE SET NULL")
    op.execute("ALTER TABLE supplier_orders ADD COLUMN total_paise BIGINT")
    op.execute("ALTER TABLE supplier_orders ADD COLUMN answer_note VARCHAR(200)")
    op.execute("ALTER TABLE supplier_orders ADD COLUMN answered_at TIMESTAMPTZ")
    op.execute("ALTER TABLE supplier_orders ADD COLUMN dispatched_at TIMESTAMPTZ")
    op.execute("ALTER TABLE supplier_orders ADD COLUMN cancelled_at TIMESTAMPTZ")
    op.execute("ALTER TABLE supplier_orders DROP CONSTRAINT supplier_orders_status_check")
    op.execute("ALTER TABLE supplier_orders ADD CONSTRAINT supplier_orders_status_check"
               " CHECK (status IN ('SENT', 'ACCEPTED', 'REJECTED', 'DISPATCHED', 'RECEIVED', 'CANCELLED'))")
    op.execute("CREATE INDEX idx_supplier_orders_link ON supplier_orders (link_id) WHERE link_id IS NOT NULL")
    op.execute("ALTER TABLE supplier_order_lines ADD COLUMN cost_paise BIGINT")
    op.execute("ALTER TABLE supplier_order_lines ADD COLUMN available BOOLEAN NOT NULL DEFAULT true")


def downgrade() -> None:
    op.execute("ALTER TABLE supplier_order_lines DROP COLUMN available")
    op.execute("ALTER TABLE supplier_order_lines DROP COLUMN cost_paise")
    op.execute("UPDATE supplier_orders SET status = 'SENT' WHERE status IN ('ACCEPTED', 'DISPATCHED')")
    op.execute("UPDATE supplier_orders SET status = 'CANCELLED' WHERE status = 'REJECTED'")
    op.execute("ALTER TABLE supplier_orders DROP CONSTRAINT supplier_orders_status_check")
    op.execute("ALTER TABLE supplier_orders ADD CONSTRAINT supplier_orders_status_check"
               " CHECK (status IN ('SENT', 'RECEIVED', 'CANCELLED'))")
    for column in ("link_id", "total_paise", "answer_note", "answered_at", "dispatched_at", "cancelled_at"):
        op.execute(f"ALTER TABLE supplier_orders DROP COLUMN {column}")
    for column in ("link_id", "confirm", "answered_at", "dispute_reason"):
        op.execute(f"ALTER TABLE supplier_entries DROP COLUMN {column}")
    op.execute("DROP TABLE supply_links")
