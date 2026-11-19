"""Single-use verification tokens, and ending old logins after a PIN reset.

- otp_codes.token_used_at: set when the verification token made from this OTP
  is used to sign up or reset the PIN, so the same token cannot be used twice.
- users.token_version: written into every access token. A PIN reset raises it,
  which logs the account out on every phone that was logged in before.

Revision ID: 0002
Revises: 0001
Create Date: 2026-11-19
"""

from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE otp_codes ADD COLUMN token_used_at TIMESTAMPTZ")
    op.execute("ALTER TABLE users ADD COLUMN token_version INT NOT NULL DEFAULT 0")


def downgrade() -> None:
    op.execute("ALTER TABLE users DROP COLUMN token_version")
    op.execute("ALTER TABLE otp_codes DROP COLUMN token_used_at")
