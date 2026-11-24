"""Checklist & Notes: a customer's own lists and notes.

Revision ID: 0012
Revises: 0011
Create Date: 2026-11-24
"""

from alembic import op

revision = "0012"
down_revision = "0011"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        CREATE TABLE customer_pages (
            id         BIGSERIAL PRIMARY KEY,
            user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            client_ref VARCHAR(40) NOT NULL,
            kind       VARCHAR(10) NOT NULL,
            title      VARCHAR(80) NOT NULL DEFAULT '',
            text       TEXT NOT NULL DEFAULT '',
            items      JSONB NOT NULL DEFAULT '[]',
            pinned     BOOLEAN NOT NULL DEFAULT false,
            version    INTEGER NOT NULL DEFAULT 1,
            save_ref   VARCHAR(40) NOT NULL,
            deleted_at TIMESTAMPTZ,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT customer_pages_client_ref_key UNIQUE (user_id, client_ref),
            CONSTRAINT customer_pages_kind_check CHECK (kind IN ('LIST', 'NOTE'))
        )
    """)


def downgrade() -> None:
    op.execute("DROP TABLE customer_pages")
