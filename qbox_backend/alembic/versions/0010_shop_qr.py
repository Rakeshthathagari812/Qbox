"""The shop's QBOX QR: a random code that customers scan to pay the shop.

Revision ID: 0010
Revises: 0009
Create Date: 2026-11-24
"""

from alembic import op

revision = "0010"
down_revision = "0009"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE shop_payment_settings ADD COLUMN pay_code VARCHAR(16) UNIQUE")


def downgrade() -> None:
    op.execute("ALTER TABLE shop_payment_settings DROP COLUMN pay_code")