"""Profile photos: one for each role a user has.

Revision ID: 0013
Revises: 0012
Create Date: 2026-11-24
"""

from alembic import op

revision = "0013"
down_revision = "0012"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        CREATE TABLE profile_photos (
            user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            role       VARCHAR(20) NOT NULL,
            ref        VARCHAR(32) NOT NULL UNIQUE,
            jpeg       BYTEA NOT NULL,
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            PRIMARY KEY (user_id, role),
            CONSTRAINT profile_photos_role_check CHECK (role IN ('BUSINESS', 'CUSTOMER', 'SUPPLIER'))
        )
    """)


def downgrade() -> None:
    op.execute("DROP TABLE profile_photos")
