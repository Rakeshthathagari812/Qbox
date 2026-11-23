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


class PaymentSource(str, enum.Enum):
    """COUNTER = a QR shown at the counter (Razorpay tells us when it is paid).
    UDHAAR = a customer paid their udhaar from their own QBOX app.
    MANUAL = paid to the shop's own UPI ID; the shop confirmed it by hand."""

    COUNTER = "COUNTER"
    UDHAAR = "UDHAAR"
    MANUAL = "MANUAL"


class PaymentStatus(str, enum.Enum):
    WAITING = "WAITING"
    PAID = "PAID"
    EXPIRED = "EXPIRED"
    CANCELLED = "CANCELLED"


class Gateway(str, enum.Enum):
    """Which Razorpay feature collects the money."""

    QR_CODE = "QR_CODE"  # a one-time UPI QR for a fixed amount
    PAYMENT_LINK = "PAYMENT_LINK"  # a payment page; its link is shown as a QR
    ORDER = "ORDER"  # Razorpay's payment screen inside the customer's QBOX app


class StockUnit(str, enum.Enum):
    """How an item is counted. Quantities are stored in thousandths of the unit
    (1.5 kg = 1500), so loose goods never drift by rounding."""

    KG = "KG"
    G = "G"
    L = "L"
    ML = "ML"
    PIECE = "PIECE"
    PACKET = "PACKET"
    BOX = "BOX"
    DOZEN = "DOZEN"
    BAG = "BAG"


class StockMoveKind(str, enum.Enum):
    """IN = stock came in (bought). OUT = sold or used.
    ADJUST = the count was corrected (damaged, expired, counted wrong): + or -, with a reason."""

    IN = "IN"
    OUT = "OUT"
    ADJUST = "ADJUST"


class SupplierEntryKind(str, enum.Enum):
    """PURCHASE = goods bought from the supplier (the shop owes more).
    PAYMENT = the shop paid the supplier (owes less)."""

    PURCHASE = "PURCHASE"
    PAYMENT = "PAYMENT"


class PayMethod(str, enum.Enum):
    CASH = "CASH"
    UPI = "UPI"
    BANK = "BANK"
    OTHER = "OTHER"


class OrderStatus(str, enum.Enum):
    SENT = "SENT"  # sent to the supplier (WhatsApp), waiting for the goods
    RECEIVED = "RECEIVED"  # goods came: recorded as a purchase, stock went up
    CANCELLED = "CANCELLED"


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


class StockItem(Base):
    """One item a shop keeps in stock. Its quantity is always calculated from
    its moves, so it can never go out of step with the history."""

    __tablename__ = "stock_items"
    __table_args__ = (
        UniqueConstraint("shop_user_id", "client_ref", name="stock_items_client_ref_key"),
        Index("idx_stock_items_shop", "shop_user_id"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    shop_user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    name: Mapped[str] = mapped_column(String(80))
    # The built-in item it came from (names in 5 languages live in the app).
    catalog_code: Mapped[str | None] = mapped_column(String(40))
    unit: Mapped[str] = mapped_column(String(10))
    cost_paise: Mapped[int | None] = mapped_column(BigInteger)  # buying price per unit
    price_paise: Mapped[int | None] = mapped_column(BigInteger)  # selling price per unit
    alert_milli: Mapped[int | None] = mapped_column(BigInteger)  # "running low" at or below this
    client_ref: Mapped[str] = mapped_column(String(40))
    archived_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class StockMove(Base):
    """Stock in, out or corrected. Never erased: a mistake is fixed with a correction."""

    __tablename__ = "stock_moves"
    __table_args__ = (
        UniqueConstraint("item_id", "client_ref", name="stock_moves_client_ref_key"),
        Index("idx_stock_moves_item", "item_id", "move_at"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    item_id: Mapped[int] = mapped_column(ForeignKey("stock_items.id", ondelete="CASCADE"))
    kind: Mapped[str] = mapped_column(String(10))
    # IN and OUT: always positive. ADJUST: + or - (the change to the count).
    qty_milli: Mapped[int] = mapped_column(BigInteger)
    note: Mapped[str | None] = mapped_column(String(200))
    move_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    client_ref: Mapped[str] = mapped_column(String(40))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Supplier(Base):
    """Someone the shop buys from. The shop's own record: no OTP needed."""

    __tablename__ = "suppliers"
    __table_args__ = (
        UniqueConstraint("shop_user_id", "client_ref", name="suppliers_client_ref_key"),
        Index("idx_suppliers_shop", "shop_user_id"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    shop_user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    name: Mapped[str] = mapped_column(String(80))
    mobile: Mapped[str | None] = mapped_column(String(10))
    supplies: Mapped[str | None] = mapped_column(String(200))  # "Rice, dal, oil"
    note: Mapped[str | None] = mapped_column(String(300))
    client_ref: Mapped[str] = mapped_column(String(40))
    archived_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class SupplierEntry(Base):
    """A purchase or a payment in the shop's account with a supplier.
    Never erased: deleting sets deleted_at and a reason."""

    __tablename__ = "supplier_entries"
    __table_args__ = (
        UniqueConstraint("supplier_id", "client_ref", name="supplier_entries_client_ref_key"),
        Index("idx_supplier_entries_supplier", "supplier_id", "entry_at"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    supplier_id: Mapped[int] = mapped_column(ForeignKey("suppliers.id", ondelete="CASCADE"))
    kind: Mapped[str] = mapped_column(String(10))
    amount_paise: Mapped[int] = mapped_column(BigInteger)
    note: Mapped[str | None] = mapped_column(String(200))
    entry_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    due_date: Mapped[date | None] = mapped_column(Date)  # purchases on credit: pay by
    method: Mapped[str | None] = mapped_column(String(10))  # payments: cash / UPI / bank
    order_id: Mapped[int | None] = mapped_column(ForeignKey("supplier_orders.id", ondelete="SET NULL"))
    client_ref: Mapped[str] = mapped_column(String(40))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    delete_reason: Mapped[str | None] = mapped_column(String(200))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class SupplierEntryLine(Base):
    """An item bought in a purchase. Each line added a stock move (stock in)."""

    __tablename__ = "supplier_entry_lines"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    entry_id: Mapped[int] = mapped_column(ForeignKey("supplier_entries.id", ondelete="CASCADE"), index=True)
    item_id: Mapped[int | None] = mapped_column(ForeignKey("stock_items.id", ondelete="SET NULL"))
    name: Mapped[str] = mapped_column(String(80))  # the item's name at the time
    unit: Mapped[str] = mapped_column(String(10))
    qty_milli: Mapped[int] = mapped_column(BigInteger)
    cost_paise: Mapped[int | None] = mapped_column(BigInteger)  # per unit


class SupplierOrder(Base):
    """An order sent to a supplier (by WhatsApp). Received = a purchase."""

    __tablename__ = "supplier_orders"
    __table_args__ = (
        UniqueConstraint("supplier_id", "client_ref", name="supplier_orders_client_ref_key"),
        Index("idx_supplier_orders_supplier", "supplier_id", "created_at"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    supplier_id: Mapped[int] = mapped_column(ForeignKey("suppliers.id", ondelete="CASCADE"))
    status: Mapped[str] = mapped_column(String(10))
    note: Mapped[str | None] = mapped_column(String(200))
    client_ref: Mapped[str] = mapped_column(String(40))
    received_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class SupplierOrderLine(Base):
    __tablename__ = "supplier_order_lines"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    order_id: Mapped[int] = mapped_column(ForeignKey("supplier_orders.id", ondelete="CASCADE"), index=True)
    item_id: Mapped[int | None] = mapped_column(ForeignKey("stock_items.id", ondelete="SET NULL"))
    name: Mapped[str] = mapped_column(String(80))
    unit: Mapped[str] = mapped_column(String(10))
    qty_milli: Mapped[int] = mapped_column(BigInteger)


class ShopPaymentSettings(Base):
    """How a shop takes payments: its own UPI ID, and/or its own Razorpay account.
    The Razorpay secret key is stored encrypted and never sent to any phone."""

    __tablename__ = "shop_payment_settings"

    shop_user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    upi_id: Mapped[str | None] = mapped_column(String(60))
    upi_name: Mapped[str | None] = mapped_column(String(60))
    razorpay_key_id: Mapped[str | None] = mapped_column(String(40))
    razorpay_secret: Mapped[str | None] = mapped_column(String(500))  # encrypted
    razorpay_connected_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class Payment(Base):
    """One payment to a shop: asked for (WAITING), then PAID, EXPIRED or CANCELLED.
    A Razorpay payment is counted only once (gateway_payment_id is unique)."""

    __tablename__ = "payments"
    __table_args__ = (
        UniqueConstraint("shop_user_id", "client_ref", name="payments_shop_client_ref_key"),
        Index("idx_payments_shop", "shop_user_id", "status", "paid_at"),
        CheckConstraint("source IN ('COUNTER', 'UDHAAR', 'MANUAL')", name="payments_source_check"),
        CheckConstraint("status IN ('WAITING', 'PAID', 'EXPIRED', 'CANCELLED')", name="payments_status_check"),
        CheckConstraint("amount_paise > 0", name="payments_amount_check"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    shop_user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    source: Mapped[str] = mapped_column(String(10))
    status: Mapped[str] = mapped_column(String(10))
    amount_paise: Mapped[int] = mapped_column(BigInteger)
    note: Mapped[str | None] = mapped_column(String(100))
    # Set when the payment is for udhaar: a PAYMENT entry is added there once paid.
    udhaar_customer_id: Mapped[int | None] = mapped_column(ForeignKey("udhaar_customers.id", ondelete="SET NULL"))
    udhaar_entry_id: Mapped[int | None] = mapped_column(ForeignKey("udhaar_entries.id", ondelete="SET NULL"))
    # The customer who paid from their own QBOX app (UDHAAR payments).
    payer_user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    gateway: Mapped[str | None] = mapped_column(String(15))
    gateway_ref: Mapped[str | None] = mapped_column(String(40), unique=True)  # qr_..., plink_..., order_...
    gateway_key_id: Mapped[str | None] = mapped_column(String(40))  # which Razorpay account
    qr_image_url: Mapped[str | None] = mapped_column(String(300))
    pay_url: Mapped[str | None] = mapped_column(String(300))
    gateway_payment_id: Mapped[str | None] = mapped_column(String(40), unique=True)  # pay_...
    payer_vpa: Mapped[str | None] = mapped_column(String(100))
    method: Mapped[str | None] = mapped_column(String(20))
    client_ref: Mapped[str] = mapped_column(String(40))
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    paid_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    checked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())