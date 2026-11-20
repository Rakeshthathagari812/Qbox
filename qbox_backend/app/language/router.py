"""Speech-to-text and translation API paths. All need login. The rules are in service.py."""

from fastapi import APIRouter, Depends

from app.deps import current_user
from app.language import service
from app.language.ai_client import AiClient, get_ai
from app.language.schemas import LanguageStatusOut, SpeechIn, SpeechOut, TranslateIn, TranslateOut
from app.models import User

router = APIRouter(prefix="/api/language", tags=["Speech & translation"])


@router.get("/status", response_model=LanguageStatusOut, summary="Is online speech/translation running?")
def status(_: User = Depends(current_user), ai: AiClient = Depends(get_ai)):
    return LanguageStatusOut(online=service.is_online(ai))


@router.post("/translate", response_model=TranslateOut, summary="Translate text (IndicTrans2)")
def translate(body: TranslateIn, user: User = Depends(current_user), ai: AiClient = Depends(get_ai)):
    return TranslateOut(text=service.translate(user, ai, body.text, body.source, body.target))


@router.post("/speech-to-text", response_model=SpeechOut, summary="Words in a WAV recording (IndicConformer)")
def speech_to_text(body: SpeechIn, user: User = Depends(current_user), ai: AiClient = Depends(get_ai)):
    return SpeechOut(text=service.speech_to_text(user, ai, body.audio, body.language, body.sampling_rate))
