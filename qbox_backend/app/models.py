"""Database tables. One class = one table.

Tables are created and changed through Alembic migrations
(alembic/versions/), never by hand.
"""

import datetime as dt
import enum
from datetime import date, datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Time,
    UniqueConstraint,
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
    UDHAAR_ADD = "UDHAAR_ADD"  # a shop adding this mobile to its udhaar book


class EntryKind(str, enum.Enum):
    """CREDIT = the shop gave goods on udhaar (customer owes more).
    PAYMENT = the customer paid back (customer owes less)."""

    CREDIT = "CREDIT"
    PAYMENT = "PAYMENT"


class Dispute(str, enum.Enum):
    """A customer saying "this is not my number" about a shop's udhaar book.
    The customer reports; only the shop decides."""

    NONE = "NONE"
    REPORTED = "REPORTED"  # customer reported, waiting for the shop
    CONFIRMED = "CONFIRMED"  # shop says the number is right (cannot be reported again)
    UNLINKED = "UNLINKED"  # shop agrees it is the wrong number: hidden from that phone


class EventCategory(str, enum.Enum):
    """Matches EventCategory in the Flutter app; each has its own colour there."""

    SHOP = "SHOP"
    SUPPLIER = "SUPPLIER"
    PAYMENT = "PAYMENT"
    PERSONAL = "PERSONAL"
    OTHER = "OTHER"


class Repeat(str, enum.Enum):
    NONE = "NONE"
    DAILY = "DAILY"
    WEEKLY = "WEEKLY"
    MONTHLY = "MONTHLY"
    YEARLY = "YEARLY"


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
        CheckConstraint("purpose IN ('SIGNUP', 'RESET_PIN', 'UDHAAR_ADD')", name="otp_codes_purpose_check"),
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
    # For UDHAAR_ADD: the shop that asked. Only that shop can use the code.
    requested_by: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class CalendarEvent(Base):
    """One event or reminder in a user's calendar. Each role has its own
    calendar (the Shop calendar and the Customer calendar never mix)."""

    __tablename__ = "calendar_events"
    __table_args__ = (Index("idx_calendar_events_owner", "user_id", "role", "event_date"),)

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    role: Mapped[str] = mapped_column(String(20))
    title: Mapped[str] = mapped_column(String(120))
    note: Mapped[str | None] = mapped_column(String(500))
    category: Mapped[str] = mapped_column(String(20))
    day: Mapped[date] = mapped_column("event_date", Date)
    time: Mapped[dt.time | None] = mapped_column("event_time", Time)
    repeat: Mapped[str] = mapped_column(String(10), default="NONE", server_default="NONE")
    remind_minutes: Mapped[int | None] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class Festival(Base):
    """Built-in festivals and holidays, shared by everyone (read-only for users)."""

    __tablename__ = "festivals"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    day: Mapped[date] = mapped_column(Date)
    name: Mapped[str] = mapped_column(String(80))
    region: Mapped[str] = mapped_column(String(10))


class UdhaarCustomer(Base):
    """One customer in one shop's udhaar book. The same person can be in many
    shops' books; each shop sees only its own. Added only after OTP check."""

    __tablename__ = "udhaar_customers"
    __table_args__ = (
        UniqueConstraint("shop_user_id", "mobile", name="udhaar_customers_shop_mobile_key"),
        Index("idx_udhaar_customers_mobile", "mobile"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    shop_user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    name: Mapped[str] = mapped_column(String(80))
    mobile: Mapped[str] = mapped_column(String(10))
    credit_limit_paise: Mapped[int | None] = mapped_column(BigInteger)
    verified_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    # "This is not me": the customer reports, the shop decides (see Dispute).
    dispute_status: Mapped[str] = mapped_column(String(10), default="NONE", server_default="NONE")
    disputed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    dispute_resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class UdhaarEntry(Base):
    """One credit or payment. Never erased: deleting sets deleted_at and a reason."""

    __tablename__ = "udhaar_entries"
    __table_args__ = (
        UniqueConstraint("customer_id", "client_ref", name="udhaar_entries_client_ref_key"),
        Index("idx_udhaar_entries_customer", "customer_id", "entry_at"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    customer_id: Mapped[int] = mapped_column(ForeignKey("udhaar_customers.id", ondelete="CASCADE"))
    kind: Mapped[str] = mapped_column(String(10))
    amount_paise: Mapped[int] = mapped_column(BigInteger)
    note: Mapped[str | None] = mapped_column(String(200))
    entry_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    client_ref: Mapped[str] = mapped_column(String(40))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    delete_reason: Mapped[str | None] = mapped_column(String(200))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())