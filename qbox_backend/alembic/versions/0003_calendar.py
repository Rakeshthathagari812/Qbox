"""Calendar: each user's events (per role) and the built-in festival list.

Festival sources:
- 2026: Telangana government holiday list (general + optional), as reported
  by Siasat, 10 Dec 2025 (G.O.Rt.No.1715). Moon-sighting festivals may shift.
- 2027: Drik Panchang (New Delhi) for Hindu festivals, plus fixed national days.
  Islamic festivals, Bonalu and Bathukamma for 2027 are added by a later
  migration once the official 2027 list is published.

Revision ID: 0003
Revises: 0002
Create Date: 2026-11-19
"""

from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None

# (date, name, region)  region: ALL = all-India, TELUGU = Telangana / Andhra Pradesh
FESTIVALS = [
    # ---- 2026 ----
    ("2026-01-01", "New Year's Day", "ALL"),
    ("2026-01-14", "Bhogi", "TELUGU"),
    ("2026-01-15", "Makar Sankranti / Pongal", "ALL"),
    ("2026-01-16", "Kanuma", "TELUGU"),
    ("2026-01-23", "Vasant Panchami", "ALL"),
    ("2026-01-26", "Republic Day", "ALL"),
    ("2026-02-15", "Maha Shivaratri", "ALL"),
    ("2026-03-03", "Holi", "ALL"),
    ("2026-03-19", "Ugadi", "TELUGU"),
    ("2026-03-21", "Eid-ul-Fitr (Ramzan)", "ALL"),
    ("2026-03-27", "Sri Rama Navami", "ALL"),
    ("2026-03-31", "Mahavir Jayanti", "ALL"),
    ("2026-04-03", "Good Friday", "ALL"),
    ("2026-04-05", "Babu Jagjivan Ram Jayanti", "TELUGU"),
    ("2026-04-14", "Dr. B.R. Ambedkar Jayanti", "ALL"),
    ("2026-05-01", "Buddha Purnima", "ALL"),
    ("2026-05-27", "Eid-ul-Adha (Bakrid)", "ALL"),
    ("2026-06-26", "Muharram", "ALL"),
    ("2026-08-10", "Bonalu", "TELUGU"),
    ("2026-08-15", "Independence Day", "ALL"),
    ("2026-08-21", "Varalakshmi Vratam", "TELUGU"),
    ("2026-08-26", "Milad-un-Nabi", "ALL"),
    ("2026-08-28", "Raksha Bandhan", "ALL"),
    ("2026-09-04", "Sri Krishna Janmashtami", "ALL"),
    ("2026-09-14", "Vinayaka Chavithi", "ALL"),
    ("2026-10-02", "Gandhi Jayanti", "ALL"),
    ("2026-10-18", "Saddula Bathukamma", "TELUGU"),
    ("2026-10-19", "Maha Navami", "ALL"),
    ("2026-10-20", "Vijaya Dashami (Dussehra)", "ALL"),
    ("2026-11-08", "Deepavali", "ALL"),
    ("2026-11-24", "Kartika Purnima / Guru Nanak Jayanti", "ALL"),
    ("2026-12-25", "Christmas", "ALL"),
    # ---- 2027 ----
    ("2027-01-01", "New Year's Day", "ALL"),
    ("2027-01-14", "Bhogi", "TELUGU"),
    ("2027-01-15", "Makar Sankranti / Pongal", "ALL"),
    ("2027-01-16", "Kanuma", "TELUGU"),
    ("2027-01-26", "Republic Day", "ALL"),
    ("2027-03-06", "Maha Shivaratri", "ALL"),
    ("2027-03-22", "Holi", "ALL"),
    ("2027-03-26", "Good Friday", "ALL"),
    ("2027-04-07", "Ugadi", "TELUGU"),
    ("2027-04-14", "Dr. B.R. Ambedkar Jayanti", "ALL"),
    ("2027-04-15", "Sri Rama Navami", "ALL"),
    ("2027-04-20", "Hanuman Jayanti", "ALL"),
    ("2027-05-09", "Akshaya Tritiya", "ALL"),
    ("2027-08-13", "Varalakshmi Vratam", "TELUGU"),
    ("2027-08-15", "Independence Day", "ALL"),
    ("2027-08-17", "Raksha Bandhan", "ALL"),
    ("2027-08-25", "Sri Krishna Janmashtami", "ALL"),
    ("2027-09-04", "Vinayaka Chavithi", "ALL"),
    ("2027-10-02", "Gandhi Jayanti", "ALL"),
    ("2027-10-09", "Vijaya Dashami (Dussehra)", "ALL"),
    ("2027-10-27", "Dhanteras", "ALL"),
    ("2027-10-28", "Naraka Chaturdashi", "TELUGU"),
    ("2027-10-29", "Deepavali", "ALL"),
    ("2027-11-14", "Kartika Purnima", "ALL"),
    ("2027-12-25", "Christmas", "ALL"),
]


def upgrade() -> None:
    op.execute("""
        CREATE TABLE calendar_events (
            id             BIGSERIAL PRIMARY KEY,
            user_id        BIGINT       NOT NULL REFERENCES users (id) ON DELETE CASCADE,
            role           VARCHAR(20)  NOT NULL,
            title          VARCHAR(120) NOT NULL,
            note           VARCHAR(500),
            category       VARCHAR(20)  NOT NULL,
            event_date     DATE         NOT NULL,
            event_time     TIME,
            repeat         VARCHAR(10)  NOT NULL DEFAULT 'NONE',
            remind_minutes INT,
            created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
            updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
            CONSTRAINT calendar_events_role_check
                CHECK (role IN ('BUSINESS', 'CUSTOMER', 'SUPPLIER')),
            CONSTRAINT calendar_events_category_check
                CHECK (category IN ('SHOP', 'SUPPLIER', 'PAYMENT', 'PERSONAL', 'OTHER')),
            CONSTRAINT calendar_events_repeat_check
                CHECK (repeat IN ('NONE', 'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY')),
            CONSTRAINT calendar_events_remind_check
                CHECK (remind_minutes IS NULL OR remind_minutes BETWEEN 0 AND 10080)
        )
    """)
    op.execute("CREATE INDEX idx_calendar_events_owner ON calendar_events (user_id, role, event_date)")

    op.execute("""
        CREATE TABLE festivals (
            id     SERIAL PRIMARY KEY,
            day    DATE        NOT NULL,
            name   VARCHAR(80) NOT NULL,
            region VARCHAR(10) NOT NULL,
            CONSTRAINT festivals_region_check CHECK (region IN ('ALL', 'TELUGU')),
            CONSTRAINT festivals_day_name_key UNIQUE (day, name)
        )
    """)
    rows = ",\n".join(
        "('{}', '{}', '{}')".format(day, name.replace("'", "''"), region) for day, name, region in FESTIVALS
    )
    op.execute(f"INSERT INTO festivals (day, name, region) VALUES\n{rows}")


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS festivals")
    op.execute("DROP TABLE IF EXISTS calendar_events")
