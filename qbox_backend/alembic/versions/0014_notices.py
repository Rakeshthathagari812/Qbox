"""The bell: what each user has read and switched off, and when a shop answered
a UPI payment.

Revision ID: 0014
Revises: 0013
Create Date: 2026-11-24
"""

from alembic import op

revision = "0014"
down_revision = "0013"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE payments ADD COLUMN answered_at TIMESTAMPTZ")
    op.execute("""
        CREATE TABLE notice_settings (
            user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            role    VARCHAR(20) NOT NULL,
            read_to TIMESTAMPTZ NOT NULL,
            off     JSONB NOT NULL DEFAULT '[]',
            PRIMARY KEY (user_id, role)
        )
    """)
    op.execute("""
        CREATE TABLE notice_reads (
            user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            role    VARCHAR(20) NOT NULL,
            notice  VARCHAR(60) NOT NULL,
            read_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            PRIMARY KEY (user_id, role, notice)
        )
    """)


def downgrade() -> None:
    op.execute("DROP TABLE notice_reads")
    op.execute("DROP TABLE notice_settings")
    op.execute("ALTER TABLE payments DROP COLUMN answered_at")
