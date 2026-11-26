"""Settings, from environment variables or qbox_ai/.env."""

from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

DEV_KEY = "qbox-ai-dev-only-key-change-me"
ROOT = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=ROOT / ".env", env_prefix="QBOX_AI_", extra="ignore")

    # "dev" on this PC, "production" on the real server.
    app_env: str = "dev"
    # Shared secret: the QBOX backend sends it with every request (its QBOX_AI_KEY).
    key: str = DEV_KEY
    # Where download_models.py put the models.
    models_dir: Path = ROOT / "models"
    # Load the models when the server starts (takes about a minute), so the first
    # person does not wait. False = load each one the first time it is needed.
    preload: bool = True
    # IndicConformer decoding: "rnnt" (more accurate) or "ctc" (faster).
    asr_decoding: str = "rnnt"
    # IndicTrans2 beam size: higher = a little better, slower.
    num_beams: int = 4
    # CPU threads for the models. 0 = let PyTorch decide.
    threads: int = 0


def check_settings(settings: Settings) -> Settings:
    if settings.app_env.lower() == "production" and (settings.key == DEV_KEY or len(settings.key) < 32):
        raise ValueError("Set a private QBOX_AI_KEY (32+ characters) in production, the same as in qbox_backend")
    return settings


@lru_cache
def get_settings() -> Settings:
    return check_settings(Settings())
