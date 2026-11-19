"""What the calendar APIs accept and return."""

import datetime as dt
from typing import Annotated

from pydantic import Field, field_validator

from app.auth.schemas import needs
from app.models import EventCategory, Repeat, Role
from app.schemas import CamelModel

MAX_REMIND_MINUTES = 7 * 24 * 60  # one week before


class EventIn(CamelModel):
    """A new or changed event. `time` empty = all day."""

    role: Role
    title: Annotated[str, Field(max_length=120), needs("Enter a title")]
    note: str | None = Field(default=None, max_length=500)
    category: EventCategory = EventCategory.OTHER
    day: dt.date
    time: dt.time | None = None
    repeat: Repeat = Repeat.NONE
    remind_minutes: int | None = Field(default=None, ge=0, le=MAX_REMIND_MINUTES)

    @field_validator("day")
    @classmethod
    def sensible_year(cls, value: dt.date) -> dt.date:
        if not 2000 <= value.year <= 2100:
            raise ValueError("Choose a date between 2000 and 2100")
        return value

    @field_validator("time")
    @classmethod
    def whole_minutes(cls, value: dt.time | None) -> dt.time | None:
        return value.replace(second=0, microsecond=0, tzinfo=None) if value else None


class EventOut(CamelModel):
    id: int
    role: Role
    title: str
    note: str | None
    category: EventCategory
    day: dt.date
    time: dt.time | None
    repeat: Repeat
    remind_minutes: int | None


class FestivalOut(CamelModel):
    day: dt.date
    name: str
    region: str
