"""Suppliers write goods and payments too; the shop confirms.

Revision ID: 0020
Revises: 0019
Create Date: 2026-11-25
"""

from alembic import op

revision = "0020"
down_revision = "0019"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE supplier_entries ADD COLUMN by_supplier BOOLEAN NOT NULL DEFAULT false")
    op.execute("ALTER TABLE supplier_entry_lines ADD COLUMN catalog_code VARCHAR(40)")


def downgrade() -> None:
    op.execute("DELETE FROM supplier_entries WHERE by_supplier")
    op.execute("ALTER TABLE supplier_entry_lines DROP COLUMN catalog_code")
    op.execute("ALTER TABLE supplier_entries DROP COLUMN by_supplier")
