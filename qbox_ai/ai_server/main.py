"""QBOX AI server: speech-to-text and translation for the QBOX backend.

Only the QBOX backend talks to this server (it sends the shared key). Phones
never reach it directly. Nothing that is said or translated is stored or logged.

Run (from the qbox_ai folder):
    .venv\\Scripts\\python -m uvicorn ai_server.main:app --port 8090
"""

import base64
import binascii
import hmac
import logging
import threading
from contextlib import asynccontextmanager
from typing import Annotated, Literal

from fastapi import Depends, FastAPI, Header, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field
from pydantic.alias_generators import to_camel

from ai_server.audio import BadAudio
from ai_server.config import DEV_KEY, get_settings
from ai_server.languages import NotSupported
from ai_server.models import ModelMissing, Models

log = logging.getLogger("qbox.ai")

Language = Literal["en", "te", "hi", "kn", "ta"]


class _In(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)


class TranslateIn(_In):
    text: Annotated[str, Field(min_length=1, max_length=1000)]
    source: Language
    target: Language


class SpeechIn(_In):
    audio: Annotated[str, Field(min_length=100, max_length=2_800_000)]
    language: Language
    sampling_rate: int = Field(default=16000, ge=8000, le=48000)


class TextOut(BaseModel):
    text: str


class Problem(Exception):
    def __init__(self, status: int, code: str, message: str):
        self.status, self.code, self.message = status, code, message


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    if settings.key == DEV_KEY:
        log.warning("Using the development key. Set QBOX_AI_KEY in qbox_ai/.env before going live.")
    if getattr(app.state, "models", None) is None:  # tests put pretend models here
        app.state.models = Models(settings)
        if settings.preload:
            threading.Thread(target=app.state.models.preload, name="load-models", daemon=True).start()
    yield


app = FastAPI(title="QBOX AI", lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)


@app.exception_handler(Problem)
async def _problem(_: Request, error: Problem):
    return JSONResponse({"code": error.code, "message": error.message}, status_code=error.status)


@app.exception_handler(RequestValidationError)
async def _invalid(_: Request, __: RequestValidationError):
    return JSONResponse({"code": "INVALID_INPUT", "message": "Invalid request"}, status_code=400)


def check_key(x_qbox_ai_key: Annotated[str | None, Header()] = None) -> None:
    if not x_qbox_ai_key or not hmac.compare_digest(x_qbox_ai_key.encode(), get_settings().key.encode()):
        raise Problem(401, "UNAUTHORIZED", "Wrong key")


def models(request: Request) -> Models:
    return request.app.state.models


def _run(work):
    """Runs a model call and turns its problems into clear answers."""
    try:
        return work()
    except NotSupported:
        raise Problem(400, "NOT_SUPPORTED", "This language is not available") from None
    except BadAudio:
        raise Problem(400, "BAD_AUDIO", "The recording could not be read") from None
    except ModelMissing as missing:
        log.warning("Model %s is not downloaded: run download_models.py", missing)
        raise Problem(503, "NOT_READY", "This model is not installed") from None
    except Problem:
        raise
    except Exception:
        log.exception("Model call failed")  # the error only, never the words
        raise Problem(500, "FAILED", "The model could not finish") from None


@app.get("/health", dependencies=[Depends(check_key)])
def health(m: Models = Depends(models)):
    installed = m.installed()
    # Not ready until loading is done and at least one model is downloaded.
    return {"ready": m.ready and any(installed.values()), "models": installed}


@app.post("/translate", response_model=TextOut, dependencies=[Depends(check_key)])
def translate(body: TranslateIn, m: Models = Depends(models)):
    if not m.ready:
        raise Problem(503, "NOT_READY", "Still loading")
    text = body.text.strip()
    if not text:
        raise Problem(400, "INVALID_INPUT", "Nothing to translate")
    return TextOut(text=_run(lambda: m.translate(text, body.source, body.target)))


@app.post("/speech-to-text", response_model=TextOut, dependencies=[Depends(check_key)])
def speech_to_text(body: SpeechIn, m: Models = Depends(models)):
    if not m.ready:
        raise Problem(503, "NOT_READY", "Still loading")
    try:
        wav = base64.b64decode(body.audio, validate=True)
    except (binascii.Error, ValueError):
        raise Problem(400, "BAD_AUDIO", "The recording could not be read") from None
    return TextOut(text=_run(lambda: m.speech_to_text(wav, body.language)))
