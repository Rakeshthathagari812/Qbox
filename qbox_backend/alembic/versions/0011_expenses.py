"""Expenses: payments a customer adds themselves (cash, other apps, scanned QRs),
their choices about automatic ones (category, left out), and a monthly budget.

Revision ID: 0011
Revises: 0010
Create Date: 2026-11-24
"""

from alembic import op

revision = "0011"
down_revision = "0010"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        CREATE TABLE customer_records (
            id           BIGSERIAL PRIMARY KEY,
            user_id      BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            scanned      BOOLEAN NOT NULL DEFAULT false,
            title        VARCHAR(80) NOT NULL,
            upi_id       VARCHAR(330),
            amount_paise BIGINT NOT NULL,
            category     VARCHAR(20) NOT NULL,
            spent_at     TIMESTAMPTZ NOT NULL,
            note         VARCHAR(200),
            not_same     BOOLEAN NOT NULL DEFAULT false,
            client_ref   VARCHAR(40) NOT NULL,
            deleted_at   TIMESTAMPTZ,
            created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT customer_records_client_ref_key UNIQUE (user_id, client_ref),
            CONSTRAINT customer_records_amount_check CHECK (amount_paise > 0)
        )
    """)
    op.execute("CREATE INDEX idx_customer_records_user ON customer_records (user_id, spent_at)")
    op.execute("""
        CREATE TABLE expense_marks (
            user_id  BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            item     VARCHAR(40) NOT NULL,
            category VARCHAR(20),
            hidden   BOOLEAN NOT NULL DEFAULT false,
            PRIMARY KEY (user_id, item)
        )
    """)
    op.execute("""
        CREATE TABLE expense_budgets (
            user_id     BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
            month_paise BIGINT NOT NULL,
            CONSTRAINT expense_budgets_check CHECK (month_paise > 0)
        )
    """)


def downgrade() -> None:
    op.execute("DROP TABLE expense_budgets")
    op.execute("DROP TABLE expense_marks")
    op.execute("DROP TABLE customer_records")
