"""The app's language codes, and what each model calls them."""

# en, te, hi, kn, ta (same codes as the app) -> IndicTrans2 (FLORES) codes.
INDICTRANS = {
    "en": "eng_Latn",
    "te": "tel_Telu",
    "hi": "hin_Deva",
    "kn": "kan_Knda",
    "ta": "tam_Taml",
}

# IndicConformer understands the 22 Indian languages, but not English
# (the app uses Google speech for English).
SPEECH = {"te", "hi", "kn", "ta"}


class NotSupported(Exception):
    pass


def translation_direction(source: str, target: str) -> str:
    """Which IndicTrans2 model: en-indic, indic-en or indic-indic."""
    if source not in INDICTRANS or target not in INDICTRANS or source == target:
        raise NotSupported()
    if source == "en":
        return "en-indic"
    if target == "en":
        return "indic-en"
    return "indic-indic"
