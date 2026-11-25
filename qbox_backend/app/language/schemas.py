"""What the speech and translation APIs accept and return."""

import base64
import binascii
from typing import Annotated, Literal

from pydantic import Field, field_validator, model_validator

from app.auth.schemas import needs
from app.schemas import CamelModel

# English, Telugu, Hindi, Kannada, Tamil (same codes as the app).
Language = Literal["en", "te", "hi", "kn", "ta"]

MAX_TEXT = 1000
# About one minute of 16 kHz mono 16-bit WAV, as base64.
MAX_AUDIO_BASE64 = 2_800_000


class TranslateIn(CamelModel):
    text: Annotated[str, Field(max_length=MAX_TEXT), needs("Enter something to translate")]
    source: Language
    target: Language
    # A spoken command: a quick answer matters more than fine wording.
    fast: bool = False

    @model_validator(mode="after")
    def different_languages(self):
        if self.source == self.target:
            raise ValueError("Choose two different languages")
        return self


class TranslateOut(CamelModel):
    text: str


class SpeechIn(CamelModel):
    """A WAV recording (base64) of someone speaking [language]."""

    audio: Annotated[str, Field(min_length=100, max_length=MAX_AUDIO_BASE64)]
    language: Language
    sampling_rate: int = Field(default=16000, ge=8000, le=48000)

    @field_validator("audio")
    @classmethod
    def is_base64(cls, value: str) -> str:
        try:
            base64.b64decode(value, validate=True)
        except (binascii.Error, ValueError):
            raise ValueError("The recording could not be read") from None
        return value


class SpeechOut(CamelModel):
    text: str  # empty when nothing could be heard


class LanguageStatusOut(CamelModel):
    online: bool  # false = not set up; the app then uses the phone's own speech/translation
