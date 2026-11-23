"""Suppliers: who the shop buys from, its account with them (purchases and
payments, never erased), the items bought (each added to stock), and orders.

Revision ID: 0008
Revises: 0007
Create Date: 2026-11-23
"""

from alembic import op

revision = "0008"
down_revision = "0007"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        CREATE TABLE suppliers (
            id           BIGSERIAL PRIMARY KEY,
            shop_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            name         VARCHAR(80) NOT NULL,
            mobile       VARCHAR(10),
            supplies     VARCHAR(200),
            note         VARCHAR(300),
            client_ref   VARCHAR(40) NOT NULL,
            archived_at  TIMESTAMPTZ,
            created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT suppliers_client_ref_key UNIQUE (shop_user_id, client_ref)
        )
    """)
    op.execute("CREATE INDEX idx_suppliers_shop ON suppliers (shop_user_id)")
    op.execute("""
        CREATE UNIQUE INDEX suppliers_shop_name_key
            ON suppliers (shop_user_id, lower(name)) WHERE archived_at IS NULL
    """)
    op.execute("""
        CREATE TABLE supplier_orders (
            id          BIGSERIAL PRIMARY KEY,
            supplier_id BIGINT NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
            status      VARCHAR(10) NOT NULL,
            note        VARCHAR(200),
            client_ref  VARCHAR(40) NOT NULL,
            received_at TIMESTAMPTZ,
            created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT supplier_orders_client_ref_key UNIQUE (supplier_id, client_ref),
            CONSTRAINT supplier_orders_status_check CHECK (status IN ('SENT', 'RECEIVED', 'CANCELLED'))
        )
    """)
    op.execute("CREATE INDEX idx_supplier_orders_supplier ON supplier_orders (supplier_id, created_at)")
    op.execute("""
        CREATE TABLE supplier_order_lines (
            id        BIGSERIAL PRIMARY KEY,
            order_id  BIGINT NOT NULL REFERENCES supplier_orders(id) ON DELETE CASCADE,
            item_id   BIGINT REFERENCES stock_items(id) ON DELETE SET NULL,
            name      VARCHAR(80) NOT NULL,
            unit      VARCHAR(10) NOT NULL,
            qty_milli BIGINT NOT NULL CHECK (qty_milli > 0)
        )
    """)
    op.execute("CREATE INDEX ix_supplier_order_lines_order_id ON supplier_order_lines (order_id)")
    op.execute("""
        CREATE TABLE supplier_entries (
            id            BIGSERIAL PRIMARY KEY,
            supplier_id   BIGINT NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
            kind          VARCHAR(10) NOT NULL,
            amount_paise  BIGINT NOT NULL,
            note          VARCHAR(200),
            entry_at      TIMESTAMPTZ NOT NULL,
            due_date      DATE,
            method        VARCHAR(10),
            order_id      BIGINT REFERENCES supplier_orders(id) ON DELETE SET NULL,
            client_ref    VARCHAR(40) NOT NULL,
            deleted_at    TIMESTAMPTZ,
            delete_reason VARCHAR(200),
            created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT supplier_entries_client_ref_key UNIQUE (supplier_id, client_ref),
            CONSTRAINT supplier_entries_kind_check CHECK (kind IN ('PURCHASE', 'PAYMENT')),
            CONSTRAINT supplier_entries_amount_check CHECK (amount_paise > 0),
            CONSTRAINT supplier_entries_method_check
                CHECK (method IS NULL OR method IN ('CASH', 'UPI', 'BANK', 'OTHER'))
        )
    """)
    op.execute("CREATE INDEX idx_supplier_entries_supplier ON supplier_entries (supplier_id, entry_at)")
    op.execute("""
        CREATE TABLE supplier_entry_lines (
            id         BIGSERIAL PRIMARY KEY,
            entry_id   BIGINT NOT NULL REFERENCES supplier_entries(id) ON DELETE CASCADE,
            item_id    BIGINT REFERENCES stock_items(id) ON DELETE SET NULL,
            name       VARCHAR(80) NOT NULL,
            unit       VARCHAR(10) NOT NULL,
            qty_milli  BIGINT NOT NULL CHECK (qty_milli > 0),
            cost_paise BIGINT CHECK (cost_paise IS NULL OR cost_paise >= 0)
        )
    """)
    op.execute("CREATE INDEX ix_supplier_entry_lines_entry_id ON supplier_entry_lines (entry_id)")


def downgrade() -> None:
    op.execute("DROP TABLE supplier_entry_lines")
    op.execute("DROP TABLE supplier_entries")
    op.execute("DROP TABLE supplier_order_lines")
    op.execute("DROP TABLE supplier_orders")
    op.execute("DROP TABLE suppliers")
