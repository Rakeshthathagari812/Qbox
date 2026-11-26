"""Connection to PostgreSQL."""

from collections.abc import Iterator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import get_settings

_settings = get_settings()
engine = create_engine(
    _settings.database_url,
    pool_pre_ping=True,
    pool_size=_settings.db_pool_size,
    max_overflow=_settings.db_pool_extra,
    pool_timeout=_settings.db_pool_wait_seconds,
)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    """Parent of every table class in models.py."""


def let_go(db: Session) -> None:
    """Gives the database connection back before a slow call to another server
    (speech, translation, Razorpay). Otherwise a few slow calls use up every
    connection and everyone else waits. What was read stays usable; the next
    query takes a connection again. Nothing may be waiting to be saved."""
    db.commit()


def get_db() -> Iterator[Session]:
    """Gives each request its own database session, closed when the request ends.
    Anything not committed is rolled back."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
