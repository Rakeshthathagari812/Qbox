"""All settings in one place.

Values come from environment variables or the .env file, with safe
development defaults below. On a real server, set them in the environment
and set QBOX_APP_ENV=production: the server then refuses to start while any
development-only setting is still switched on.
"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict

DEV_JWT_SECRET = "qbox-dev-only-secret-change-me-before-going-live-2026"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_prefix="QBOX_", extra="ignore")

    # "dev" on this PC, "production" on the real server.
    app_env: str = "dev"

    # PostgreSQL connection
    database_url: str = "postgresql+psycopg://qbox:qbox_dev_2026@localhost:5432/qbox"

    # Login tokens. Development key only: set QBOX_JWT_SECRET (32+ characters) when going live.
    jwt_secret: str = DEV_JWT_SECRET
    access_token_days: int = 30
    verification_token_minutes: int = 30

    # OTP rules
    otp_expiry_seconds: int = 300
    otp_resend_seconds: int = 30
    otp_max_attempts: int = 5
    otp_max_per_hour: int = 5
    # Test mode: no SMS provider yet, so the OTP is printed in the log and sent
    # back to the app. Set QBOX_OTP_EXPOSE=false once real SMS is connected.
    otp_expose: bool = True

    # Wrong-PIN lock: every 5th wrong PIN in a row locks the account.
    # The first lock is short; later ones are long, so guessing a 4-digit PIN is not practical.
    login_max_failed_attempts: int = 5
    login_lock_minutes: int = 15
    login_long_lock_minutes: int = 24 * 60

    @property
    def is_production(self) -> bool:
        return self.app_env.lower() == "production"


def check_settings(settings: Settings) -> Settings:
    if len(settings.jwt_secret.encode()) < 32:
        raise ValueError("QBOX_JWT_SECRET must be at least 32 characters")
    if settings.is_production:
        if settings.jwt_secret == DEV_JWT_SECRET:
            raise ValueError("Set a private QBOX_JWT_SECRET before running in production")
        if settings.otp_expose:
            raise ValueError("Set QBOX_OTP_EXPOSE=false in production (OTPs must only go by SMS)")
    return settings


@lru_cache
def get_settings() -> Settings:
    return check_settings(Settings())
