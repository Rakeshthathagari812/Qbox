"""Payments: each shop's payment settings (UPI ID, own Razorpay account with the
secret key encrypted) and every payment asked for or received.

Revision ID: 0006
Revises: 0005
Create Date: 2026-11-22
"""

from alembic import op

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        CREATE TABLE shop_payment_settings (
            shop_user_id          BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
            upi_id                VARCHAR(60),
            upi_name              VARCHAR(60),
            razorpay_key_id       VARCHAR(40),
            razorpay_secret       VARCHAR(500),
            razorpay_connected_at TIMESTAMPTZ,
            updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
        )
    """)
    op.execute("""
        CREATE TABLE payments (
            id                 BIGSERIAL PRIMARY KEY,
            shop_user_id       BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            source             VARCHAR(10) NOT NULL,
            status             VARCHAR(10) NOT NULL,
            amount_paise       BIGINT NOT NULL,
            note               VARCHAR(100),
            udhaar_customer_id BIGINT REFERENCES udhaar_customers(id) ON DELETE SET NULL,
            udhaar_entry_id    BIGINT REFERENCES udhaar_entries(id) ON DELETE SET NULL,
            payer_user_id      BIGINT REFERENCES users(id) ON DELETE SET NULL,
            gateway            VARCHAR(15),
            gateway_ref        VARCHAR(40) UNIQUE,
            gateway_key_id     VARCHAR(40),
            qr_image_url       VARCHAR(300),
            pay_url            VARCHAR(300),
            gateway_payment_id VARCHAR(40) UNIQUE,
            payer_vpa          VARCHAR(100),
            method             VARCHAR(20),
            client_ref         VARCHAR(40) NOT NULL,
            expires_at         TIMESTAMPTZ,
            paid_at            TIMESTAMPTZ,
            checked_at         TIMESTAMPTZ,
            created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT payments_shop_client_ref_key UNIQUE (shop_user_id, client_ref),
            CONSTRAINT payments_source_check CHECK (source IN ('COUNTER', 'UDHAAR', 'MANUAL')),
            CONSTRAINT payments_status_check CHECK (status IN ('WAITING', 'PAID', 'EXPIRED', 'CANCELLED')),
            CONSTRAINT payments_amount_check CHECK (amount_paise > 0)
        )
    """)
    op.execute("CREATE INDEX idx_payments_shop ON payments (shop_user_id, status, paid_at)")
    op.execute("CREATE INDEX idx_payments_payer ON payments (payer_user_id) WHERE payer_user_id IS NOT NULL")


def downgrade() -> None:
    op.execute("DROP TABLE payments")
    op.execute("DROP TABLE shop_payment_settings")
