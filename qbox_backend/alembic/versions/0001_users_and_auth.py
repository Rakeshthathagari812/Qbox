"""Users, roles, role profiles and OTP codes.

Revision ID: 0001
Revises:
Create Date: 2026-11-19
"""

from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        CREATE TABLE users (
            id                    BIGSERIAL PRIMARY KEY,
            mobile                VARCHAR(10)  NOT NULL UNIQUE,
            pin_hash              VARCHAR(100) NOT NULL,
            failed_login_attempts INT          NOT NULL DEFAULT 0,
            locked_until          TIMESTAMPTZ,
            created_at            TIMESTAMPTZ  NOT NULL DEFAULT now(),
            updated_at            TIMESTAMPTZ  NOT NULL DEFAULT now()
        )
    """)
    op.execute("""
        CREATE TABLE user_roles (
            user_id BIGINT      NOT NULL REFERENCES users (id) ON DELETE CASCADE,
            role    VARCHAR(20) NOT NULL,
            PRIMARY KEY (user_id, role),
            CONSTRAINT user_roles_role_check CHECK (role IN ('BUSINESS', 'CUSTOMER', 'SUPPLIER'))
        )
    """)
    op.execute("""
        CREATE TABLE shop_profiles (
            user_id              BIGINT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
            qbox_id              VARCHAR(20)  NOT NULL UNIQUE,
            shop_name            VARCHAR(120) NOT NULL,
            business_type        VARCHAR(60)  NOT NULL,
            business_type_detail VARCHAR(120),
            shop_category        VARCHAR(60)  NOT NULL,
            shop_category_detail VARCHAR(120),
            address              VARCHAR(300) NOT NULL,
            contact_number       VARCHAR(10)  NOT NULL,
            created_at           TIMESTAMPTZ  NOT NULL DEFAULT now()
        )
    """)
    op.execute("""
        CREATE TABLE customer_profiles (
            user_id                BIGINT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
            qbox_id                VARCHAR(20)  NOT NULL UNIQUE,
            full_name              VARCHAR(120) NOT NULL,
            mobile_number          VARCHAR(10)  NOT NULL,
            email                  VARCHAR(160),
            address                VARCHAR(300),
            aadhaar_link_requested BOOLEAN      NOT NULL DEFAULT FALSE,
            created_at             TIMESTAMPTZ  NOT NULL DEFAULT now()
        )
    """)
    op.execute("""
        CREATE TABLE supplier_profiles (
            user_id              BIGINT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
            qbox_id              VARCHAR(20)  NOT NULL UNIQUE,
            supplier_name        VARCHAR(120) NOT NULL,
            business_type        VARCHAR(60)  NOT NULL,
            business_type_detail VARCHAR(120),
            products_supplied    VARCHAR(300) NOT NULL,
            contact_number       VARCHAR(10)  NOT NULL,
            address              VARCHAR(300) NOT NULL,
            created_at           TIMESTAMPTZ  NOT NULL DEFAULT now()
        )
    """)
    op.execute("""
        CREATE TABLE otp_codes (
            id          BIGSERIAL PRIMARY KEY,
            mobile      VARCHAR(10)  NOT NULL,
            purpose     VARCHAR(20)  NOT NULL,
            code_hash   VARCHAR(100) NOT NULL,
            attempts    INT          NOT NULL DEFAULT 0,
            expires_at  TIMESTAMPTZ  NOT NULL,
            consumed_at TIMESTAMPTZ,
            created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
            CONSTRAINT otp_codes_purpose_check CHECK (purpose IN ('SIGNUP', 'RESET_PIN'))
        )
    """)
    op.execute("CREATE INDEX idx_otp_codes_lookup ON otp_codes (mobile, purpose, created_at)")


def downgrade() -> None:
    for table in ("otp_codes", "supplier_profiles", "customer_profiles", "shop_profiles", "user_roles", "users"):
        op.execute(f"DROP TABLE IF EXISTS {table}")
