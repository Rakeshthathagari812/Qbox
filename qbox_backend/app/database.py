"""Connection to PostgreSQL."""

from collections.abc import Iterator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import get_settings

engine = create_engine(get_settings().database_url, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    """Parent of every table class in models.py."""


def get_db() -> Iterator[Session]:
    """Gives each request its own database session, closed when the request ends.
    Anything not committed is rolled back."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
