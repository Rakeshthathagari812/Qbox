"""The AI models: IndicTrans2 (translation) and IndicConformer (speech-to-text).

Both run on the CPU. Each model is loaded once and then kept in memory. One
request at a time per model, so the computer is not overloaded.

PyTorch and transformers are only imported when a model is loaded, so the
server's tests run without them.
"""

import logging
import os
import threading
from pathlib import Path

# The server only uses the models download_models.py fetched (pinned versions):
# it never goes online to fetch new model code by itself.
os.environ.setdefault("HF_HUB_OFFLINE", "1")

from ai_server import indic_text
from ai_server.audio import TARGET_RATE, clean, read_wav
from ai_server.config import Settings
from ai_server.languages import SPEECH, NotSupported, translation_direction

log = logging.getLogger("qbox.ai")

# The exact versions download_models.py fetches (checked AI4Bharat code, MIT licence).
REPOS = {
    "en-indic": ("ai4bharat/indictrans2-en-indic-dist-200M", "2cfd0a20057756d756bf3e53528f492afc52f91a"),
    "indic-en": ("ai4bharat/indictrans2-indic-en-dist-200M", "d66a2122ad6d28184f3dc3797b652bd80ae3f65f"),
    "indic-indic": ("ai4bharat/indictrans2-indic-indic-dist-320M", "ffb7582b6d43791f1fb26b2153fc065f2e9ea575"),
    "speech": ("ai4bharat/indic-conformer-600m-multilingual", "2a77d305038dfc502fd9464e7d028b90381976cb"),
}


def model_path(models_dir: Path, name: str) -> Path:
    return models_dir / REPOS[name][0].split("/")[1]


class ModelMissing(Exception):
    pass


class _Translator:
    """One IndicTrans2 model (one direction)."""

    def __init__(self, path: Path, num_beams: int):
        import torch
        from transformers import AutoModelForSeq2SeqLM, AutoTokenizer

        self._torch = torch
        self.tokenizer = AutoTokenizer.from_pretrained(path, trust_remote_code=True, local_files_only=True)
        self.model = AutoModelForSeq2SeqLM.from_pretrained(path, trust_remote_code=True, local_files_only=True)
        self.model.eval()
        self.num_beams = num_beams
        self.lock = threading.Lock()

    def translate(self, text: str, source: str, target: str) -> str:
        sentences = indic_text.split_sentences(text)
        if not sentences:
            return ""
        batch = [indic_text.prepare(s, source, target) for s in sentences]
        with self.lock, self._torch.inference_mode():
            inputs = self.tokenizer(batch, truncation=True, padding="longest",
                                    return_tensors="pt", return_attention_mask=True)
            # use_cache=False: AI4Bharat's model code predates the cache format of
            # transformers 4.5x; short shop sentences stay fast without it.
            tokens = self.model.generate(**inputs, use_cache=False, min_length=0, max_length=256,
                                         num_beams=self.num_beams, num_return_sequences=1)
            decoded = self.tokenizer.batch_decode(tokens, skip_special_tokens=True,
                                                  clean_up_tokenization_spaces=True)
        finished = []
        for sentence, out in zip(sentences, decoded):
            out = indic_text.finish(out, target)
            # A full stop was only added for the model: keep the person's own style.
            finished.append(out if indic_text.has_end_mark(sentence) else indic_text.drop_end_mark(out))
        return " ".join(finished).strip()


class _SpeechModel:
    """IndicConformer, for the 22 Indian languages."""

    def __init__(self, path: Path, decoding: str):
        import importlib.util

        import torch

        self._torch = torch
        # AI4Bharat's loader always tries to download by name, so their model class
        # is loaded straight from our downloaded (pinned) copy instead.
        spec = importlib.util.spec_from_file_location("indic_conformer_onnx", path / "model_onnx.py")
        code = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(code)
        config = code.IndicASRConfig.from_pretrained(path)
        config.ts_folder = str(path)
        self.model = code.IndicASRModel(config)
        self.model.eval()
        self.decoding = decoding
        self.lock = threading.Lock()

    def transcribe(self, wav: bytes, language: str) -> str:
        samples, rate = read_wav(wav)
        samples = clean(samples, rate)
        audio = self._torch.from_numpy(samples).unsqueeze(0)
        if rate != TARGET_RATE:
            import torchaudio

            audio = torchaudio.functional.resample(audio, rate, TARGET_RATE)
        with self.lock, self._torch.inference_mode():
            text = self.model(audio, language, self.decoding)
        if isinstance(text, (list, tuple)):
            text = text[0] if text else ""
        return str(text or "").strip()


class Models:
    """All models, each loaded the first time it is needed (or at start-up)."""

    def __init__(self, settings: Settings):
        self.settings = settings
        self._loaded: dict[str, object] = {}
        self._loading = threading.Lock()
        self.ready = not settings.preload

    def installed(self) -> dict[str, bool]:
        return {name: (model_path(self.settings.models_dir, name) / "config.json").exists() for name in REPOS}

    def preload(self) -> None:
        """Load every downloaded model, in the background at start-up."""
        try:
            if self.settings.threads > 0:
                import torch

                torch.set_num_threads(self.settings.threads)
            for name, present in self.installed().items():
                if present:
                    self._get(name)
                else:
                    log.warning("Model %s is not downloaded: run download_models.py", name)
        except Exception:
            log.exception("Loading the models failed")
        finally:
            self.ready = True

    def _get(self, name: str):
        model = self._loaded.get(name)
        if model is not None:
            return model
        with self._loading:
            model = self._loaded.get(name)
            if model is None:
                path = model_path(self.settings.models_dir, name)
                if not (path / "config.json").exists():
                    raise ModelMissing(name)
                log.info("Loading %s ...", name)
                if name == "speech":
                    model = _SpeechModel(path, self.settings.asr_decoding)
                else:
                    model = _Translator(path, self.settings.num_beams)
                self._loaded[name] = model
                log.info("Loaded %s", name)
        return model

    def translate(self, text: str, source: str, target: str) -> str:
        direction = translation_direction(source, target)
        text = indic_text.ascii_digits(text)
        result = self._get(direction).translate(text, source, target)
        if direction == "indic-indic" and indic_text.looks_cut(text, result):
            # Never lose an amount: go through English instead (e.g. Telugu -> English -> Kannada).
            english = self._get("indic-en").translate(text, source, "en")
            through_english = self._get("en-indic").translate(english, "en", target)
            if not indic_text.looks_cut(text, through_english):
                return through_english
        return result

    def speech_to_text(self, wav: bytes, language: str) -> str:
        if language not in SPEECH:
            raise NotSupported()
        return self._get("speech").transcribe(wav, language)
