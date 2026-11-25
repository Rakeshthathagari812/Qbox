"""Ordering from a supplier: how it will be paid, and the supplier's UPI ID.

Revision ID: 0018
Revises: 0017
Create Date: 2026-11-25
"""

from alembic import op

revision = "0018"
down_revision = "0017"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE supplier_orders ADD COLUMN pay_plan VARCHAR(10)")
    op.execute("ALTER TABLE supplier_orders ADD CONSTRAINT supplier_orders_pay_plan_check"
               " CHECK (pay_plan IN ('LATER', 'CASH', 'UPI'))")
    op.execute("ALTER TABLE supplier_orders ADD COLUMN pay_by DATE")
    op.execute("ALTER TABLE supplier_order_lines ADD COLUMN catalog_code VARCHAR(40)")
    op.execute("CREATE INDEX idx_supplier_entries_order ON supplier_entries (order_id) WHERE order_id IS NOT NULL")
    op.execute("""
        CREATE TABLE supply_pay (
            user_id    BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
            upi_id     VARCHAR(60),
            upi_name   VARCHAR(60),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
        )
    """)


def downgrade() -> None:
    op.execute("DROP TABLE supply_pay")
    op.execute("DROP INDEX idx_supplier_entries_order")
    op.execute("ALTER TABLE supplier_order_lines DROP COLUMN catalog_code")
    op.execute("ALTER TABLE supplier_orders DROP COLUMN pay_by")
    op.execute("ALTER TABLE supplier_orders DROP CONSTRAINT supplier_orders_pay_plan_check")
    op.execute("ALTER TABLE supplier_orders DROP COLUMN pay_plan")
