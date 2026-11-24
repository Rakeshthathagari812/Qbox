"""Shared base for request/response bodies.

Python uses snake_case (shop_name); the app sends and expects camelCase
(shopName). CamelModel converts between the two automatically.
"""

from pydantic import BaseModel, ConfigDict, field_validator
from pydantic.alias_generators import to_camel


class CamelModel(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)

    @field_validator("*", mode="before")
    @classmethod
    def no_nul(cls, value):
        """The one character the database cannot keep."""
        return value.replace("\x00", "") if isinstance(value, str) else value
