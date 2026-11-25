"""Connecting with a supplier by code, and the supplier's products.

Revision ID: 0017
Revises: 0016
Create Date: 2026-11-24
"""

from alembic import op

revision = "0017"
down_revision = "0016"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE otp_codes DROP CONSTRAINT otp_codes_purpose_check")
    op.execute("ALTER TABLE otp_codes ADD CONSTRAINT otp_codes_purpose_check"
               " CHECK (purpose IN ('SIGNUP', 'RESET_PIN', 'UDHAAR_ADD', 'SUPPLIER_ADD'))")
    op.execute("ALTER TABLE otp_codes ADD COLUMN detail VARCHAR(60)")
    op.execute("ALTER TABLE suppliers ADD COLUMN verified_at TIMESTAMPTZ")
    op.execute("CREATE INDEX idx_suppliers_verified ON suppliers (mobile) WHERE verified_at IS NOT NULL")
    op.execute("""
        CREATE TABLE supply_products (
            id               BIGSERIAL PRIMARY KEY,
            supplier_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            name             VARCHAR(80) NOT NULL,
            catalog_code     VARCHAR(40),
            unit             VARCHAR(10) NOT NULL,
            price_paise      BIGINT,
            available        BOOLEAN NOT NULL DEFAULT true,
            client_ref       VARCHAR(40) NOT NULL,
            archived_at      TIMESTAMPTZ,
            created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT supply_products_client_ref_key UNIQUE (supplier_user_id, client_ref),
            CONSTRAINT supply_products_price_check CHECK (price_paise IS NULL OR price_paise >= 0)
        )
    """)
    op.execute("CREATE UNIQUE INDEX supply_products_name ON supply_products (supplier_user_id, lower(name), unit)"
               " WHERE archived_at IS NULL")
    op.execute("ALTER TABLE supplier_order_lines ADD COLUMN product_id BIGINT"
               " REFERENCES supply_products(id) ON DELETE SET NULL")


def downgrade() -> None:
    op.execute("ALTER TABLE supplier_order_lines DROP COLUMN product_id")
    op.execute("DROP TABLE supply_products")
    op.execute("DROP INDEX idx_suppliers_verified")
    op.execute("ALTER TABLE suppliers DROP COLUMN verified_at")
    op.execute("DELETE FROM otp_codes WHERE purpose = 'SUPPLIER_ADD'")
    op.execute("ALTER TABLE otp_codes DROP COLUMN detail")
    op.execute("ALTER TABLE otp_codes DROP CONSTRAINT otp_codes_purpose_check")
    op.execute("ALTER TABLE otp_codes ADD CONSTRAINT otp_codes_purpose_check"
               " CHECK (purpose IN ('SIGNUP', 'RESET_PIN', 'UDHAAR_ADD'))")
