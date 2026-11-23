"""Stock: each shop's items and every stock movement (in, out, corrected).

Quantities are thousandths of the item's unit (1.5 kg = 1500). The current
quantity is always the sum of the moves.

Revision ID: 0007
Revises: 0006
Create Date: 2026-11-23
"""

from alembic import op

revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        CREATE TABLE stock_items (
            id           BIGSERIAL PRIMARY KEY,
            shop_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            name         VARCHAR(80) NOT NULL,
            catalog_code VARCHAR(40),
            unit         VARCHAR(10) NOT NULL,
            cost_paise   BIGINT,
            price_paise  BIGINT,
            alert_milli  BIGINT,
            client_ref   VARCHAR(40) NOT NULL,
            archived_at  TIMESTAMPTZ,
            created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT stock_items_client_ref_key UNIQUE (shop_user_id, client_ref),
            CONSTRAINT stock_items_unit_check
                CHECK (unit IN ('KG', 'G', 'L', 'ML', 'PIECE', 'PACKET', 'BOX', 'DOZEN', 'BAG')),
            CONSTRAINT stock_items_prices_check
                CHECK ((cost_paise IS NULL OR cost_paise >= 0) AND (price_paise IS NULL OR price_paise >= 0)
                       AND (alert_milli IS NULL OR alert_milli >= 0))
        )
    """)
    op.execute("CREATE INDEX idx_stock_items_shop ON stock_items (shop_user_id)")
    # One live item per name in a shop ("Rice" and "rice" are the same item).
    op.execute("""
        CREATE UNIQUE INDEX stock_items_shop_name_key
            ON stock_items (shop_user_id, lower(name)) WHERE archived_at IS NULL
    """)
    op.execute("""
        CREATE TABLE stock_moves (
            id         BIGSERIAL PRIMARY KEY,
            item_id    BIGINT NOT NULL REFERENCES stock_items(id) ON DELETE CASCADE,
            kind       VARCHAR(10) NOT NULL,
            qty_milli  BIGINT NOT NULL,
            note       VARCHAR(200),
            move_at    TIMESTAMPTZ NOT NULL,
            client_ref VARCHAR(40) NOT NULL,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT stock_moves_client_ref_key UNIQUE (item_id, client_ref),
            CONSTRAINT stock_moves_kind_check CHECK (kind IN ('IN', 'OUT', 'ADJUST')),
            CONSTRAINT stock_moves_qty_check
                CHECK ((kind = 'ADJUST' AND qty_milli <> 0) OR (kind <> 'ADJUST' AND qty_milli > 0))
        )
    """)
    op.execute("CREATE INDEX idx_stock_moves_item ON stock_moves (item_id, move_at)")


def downgrade() -> None:
    op.execute("DROP TABLE stock_moves")
    op.execute("DROP TABLE stock_items")
