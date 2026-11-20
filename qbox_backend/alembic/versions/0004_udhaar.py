"""Udhaar (credit book): each shop's customers and their credit/payment entries.

- A customer is added only after an OTP sent to their mobile is typed in at the
  shop (proves the number is real, theirs, and that they agree to be recorded).
- Amounts are whole paise (no rounding errors). The balance is never stored:
  it is always the sum of the entries.
- Entries are never erased: a deleted entry keeps its row with deleted_at and a reason.
- client_ref is made by the phone, so an entry saved offline and sent twice is kept once.

Revision ID: 0004
Revises: 0003
Create Date: 2026-11-19
"""

from alembic import op

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # OTPs that add a customer belong to the shop that asked for them.
    op.execute("ALTER TABLE otp_codes ADD COLUMN requested_by BIGINT REFERENCES users (id) ON DELETE CASCADE")
    op.execute("ALTER TABLE otp_codes DROP CONSTRAINT otp_codes_purpose_check")
    op.execute("""
        ALTER TABLE otp_codes ADD CONSTRAINT otp_codes_purpose_check
            CHECK (purpose IN ('SIGNUP', 'RESET_PIN', 'UDHAAR_ADD'))
    """)
    op.execute("CREATE INDEX idx_otp_codes_requested_by ON otp_codes (requested_by, created_at)")

    op.execute("""
        CREATE TABLE udhaar_customers (
            id                 BIGSERIAL PRIMARY KEY,
            shop_user_id       BIGINT       NOT NULL REFERENCES users (id) ON DELETE CASCADE,
            name               VARCHAR(80)  NOT NULL,
            mobile             VARCHAR(10)  NOT NULL,
            credit_limit_paise BIGINT,
            verified_at        TIMESTAMPTZ  NOT NULL,
            disowned_at        TIMESTAMPTZ,
            created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
            updated_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
            CONSTRAINT udhaar_customers_shop_mobile_key UNIQUE (shop_user_id, mobile),
            CONSTRAINT udhaar_customers_limit_check
                CHECK (credit_limit_paise IS NULL OR credit_limit_paise > 0)
        )
    """)
    op.execute("CREATE INDEX idx_udhaar_customers_mobile ON udhaar_customers (mobile)")

    op.execute("""
        CREATE TABLE udhaar_entries (
            id            BIGSERIAL PRIMARY KEY,
            customer_id   BIGINT       NOT NULL REFERENCES udhaar_customers (id) ON DELETE CASCADE,
            kind          VARCHAR(10)  NOT NULL,
            amount_paise  BIGINT       NOT NULL,
            note          VARCHAR(200),
            entry_at      TIMESTAMPTZ  NOT NULL,
            client_ref    VARCHAR(40)  NOT NULL,
            deleted_at    TIMESTAMPTZ,
            delete_reason VARCHAR(200),
            created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
            CONSTRAINT udhaar_entries_kind_check CHECK (kind IN ('CREDIT', 'PAYMENT')),
            CONSTRAINT udhaar_entries_amount_check CHECK (amount_paise BETWEEN 1 AND 100000000),
            CONSTRAINT udhaar_entries_client_ref_key UNIQUE (customer_id, client_ref)
        )
    """)
    op.execute("CREATE INDEX idx_udhaar_entries_customer ON udhaar_entries (customer_id, entry_at)")


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS udhaar_entries")
    op.execute("DROP TABLE IF EXISTS udhaar_customers")
    op.execute("DELETE FROM otp_codes WHERE purpose = 'UDHAAR_ADD'")
    op.execute("DROP INDEX IF EXISTS idx_otp_codes_requested_by")
    op.execute("ALTER TABLE otp_codes DROP CONSTRAINT otp_codes_purpose_check")
    op.execute("""
        ALTER TABLE otp_codes ADD CONSTRAINT otp_codes_purpose_check
            CHECK (purpose IN ('SIGNUP', 'RESET_PIN'))
    """)
    op.execute("ALTER TABLE otp_codes DROP COLUMN requested_by")
