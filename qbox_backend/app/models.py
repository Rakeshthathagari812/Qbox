"""Database tables. One class = one table.

Tables are created and changed through Alembic migrations
(alembic/versions/), never by hand.
"""

import enum
from datetime import datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Role(str, enum.Enum):
    """Matches QboxRole in the Flutter app (business, customer, supplier)."""

    BUSINESS = "BUSINESS"
    CUSTOMER = "CUSTOMER"
    SUPPLIER = "SUPPLIER"

    def qbox_id(self, user_id: int) -> str:
        """The QBOX ID shown in the app, e.g. user 7 as a customer is QBC10007."""
        prefix = {"BUSINESS": "QBM", "CUSTOMER": "QBC", "SUPPLIER": "QBS"}[self.value]
        return f"{prefix}{10000 + user_id}"


class OtpPurpose(str, enum.Enum):
    """Why an OTP was sent. A code sent for one purpose cannot be used for another."""

    SIGNUP = "SIGNUP"
    RESET_PIN = "RESET_PIN"


class User(Base):
    """One person = one mobile number = one user, holding any mix of roles."""

    __tablename__ = "users"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    mobile: Mapped[str] = mapped_column(String(10), unique=True)
    pin_hash: Mapped[str] = mapped_column(String(100))
    failed_login_attempts: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    locked_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # Written into every access token; raising it logs out every phone (done on PIN reset).
    token_version: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    roles: Mapped[list["UserRole"]] = relationship(cascade="all, delete-orphan", lazy="selectin")
    shop: Mapped["ShopProfile | None"] = relationship(cascade="all, delete-orphan", lazy="selectin")
    customer: Mapped["CustomerProfile | None"] = relationship(cascade="all, delete-orphan", lazy="selectin")
    supplier: Mapped["SupplierProfile | None"] = relationship(cascade="all, delete-orphan", lazy="selectin")


class UserRole(Base):
    __tablename__ = "user_roles"
    __table_args__ = (
        CheckConstraint("role IN ('BUSINESS', 'CUSTOMER', 'SUPPLIER')", name="user_roles_role_check"),
    )

    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    role: Mapped[str] = mapped_column(String(20), primary_key=True)


class ShopProfile(Base):
    __tablename__ = "shop_profiles"

    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    qbox_id: Mapped[str] = mapped_column(String(20), unique=True)
    shop_name: Mapped[str] = mapped_column(String(120))
    business_type: Mapped[str] = mapped_column(String(60))
    business_type_detail: Mapped[str | None] = mapped_column(String(120))
    shop_category: Mapped[str] = mapped_column(String(60))
    shop_category_detail: Mapped[str | None] = mapped_column(String(120))
    address: Mapped[str] = mapped_column(String(300))
    contact_number: Mapped[str] = mapped_column(String(10))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class CustomerProfile(Base):
    __tablename__ = "customer_profiles"

    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    qbox_id: Mapped[str] = mapped_column(String(20), unique=True)
    full_name: Mapped[str] = mapped_column(String(120))
    mobile_number: Mapped[str] = mapped_column(String(10))
    email: Mapped[str | None] = mapped_column(String(160))
    address: Mapped[str | None] = mapped_column(String(300))
    aadhaar_link_requested: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class SupplierProfile(Base):
    __tablename__ = "supplier_profiles"

    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    qbox_id: Mapped[str] = mapped_column(String(20), unique=True)
    supplier_name: Mapped[str] = mapped_column(String(120))
    business_type: Mapped[str] = mapped_column(String(60))
    business_type_detail: Mapped[str | None] = mapped_column(String(120))
    products_supplied: Mapped[str] = mapped_column(String(300))
    contact_number: Mapped[str] = mapped_column(String(10))
    address: Mapped[str] = mapped_column(String(300))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class OtpCode(Base):
    """One row per OTP sent. Only a hash of the code is stored."""

    __tablename__ = "otp_codes"
    __table_args__ = (
        CheckConstraint("purpose IN ('SIGNUP', 'RESET_PIN')", name="otp_codes_purpose_check"),
        Index("idx_otp_codes_lookup", "mobile", "purpose", "created_at"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    mobile: Mapped[str] = mapped_column(String(10))
    purpose: Mapped[str] = mapped_column(String(20))
    code_hash: Mapped[str] = mapped_column(String(100))
    attempts: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # When the verification token made from this OTP was used (it works only once).
    token_used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
