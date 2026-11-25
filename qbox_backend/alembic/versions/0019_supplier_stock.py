"""The supplier's own stock count.

Revision ID: 0019
Revises: 0018
Create Date: 2026-11-25
"""

from alembic import op

revision = "0019"
down_revision = "0018"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE supply_products ADD COLUMN counted BOOLEAN NOT NULL DEFAULT false")
    op.execute("ALTER TABLE supply_products ADD COLUMN alert_milli BIGINT")
    op.execute("""
        CREATE TABLE supply_moves (
            id         BIGSERIAL PRIMARY KEY,
            product_id BIGINT NOT NULL REFERENCES supply_products(id) ON DELETE CASCADE,
            kind       VARCHAR(10) NOT NULL CHECK (kind IN ('IN', 'OUT', 'ADJUST')),
            qty_milli  BIGINT NOT NULL,
            note       VARCHAR(200),
            move_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
            client_ref VARCHAR(40) NOT NULL,
            CONSTRAINT supply_moves_client_ref_key UNIQUE (product_id, client_ref)
        )
    """)
    op.execute("CREATE INDEX idx_supply_moves_product ON supply_moves (product_id, move_at)")


def downgrade() -> None:
    op.execute("DROP TABLE supply_moves")
    op.execute("ALTER TABLE supply_products DROP COLUMN alert_milli")
    op.execute("ALTER TABLE supply_products DROP COLUMN counted")
