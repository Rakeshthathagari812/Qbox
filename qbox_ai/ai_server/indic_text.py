"""Gets text ready for IndicTrans2 and cleans up what it writes back.

IndicTrans2 was trained on text prepared in a set way, and gives its best
translations when it gets the same:
  * English is punctuation-normalised and split into words (Moses);
  * Indian languages have punctuation split off, and are written in Devanagari
    letters (Telugu, Kannada and Tamil letters line up one-to-one with Devanagari
    in Unicode, so this is a simple, exact letter swap);
  * each sentence starts with the two language tags, e.g. "tel_Telu hin_Deva ...".
The answer is swapped back into the right script and joined up again.

This does the same job as AI4Bharat's IndicTransToolkit, which has no Windows build.
"""

import re
import string

from ai_server.languages import INDICTRANS

# Start of each script's Unicode block. The first 0x70 letters line up across scripts.
_BLOCK = {"hi": 0x0900, "ta": 0x0B80, "te": 0x0C00, "kn": 0x0C80}
_ALIGNED = 0x70
_DANDAS = {"।", "॥"}  # । ॥ are shared by all scripts: never swapped

# Tamil has no separate letters for these sounds: use the nearest Tamil letter.
_TAMIL = {
    0x16: 0x15, 0x17: 0x15, 0x18: 0x15,  # kha ga gha -> ka
    0x1B: 0x1A,                          # cha -> ca
    0x1D: 0x1C,                          # jha -> ja
    0x20: 0x1F, 0x21: 0x1F, 0x22: 0x1F,  # ttha dda ddha -> tta
    0x25: 0x24, 0x26: 0x24, 0x27: 0x24,  # tha da dha -> ta
    0x2B: 0x2A, 0x2C: 0x2A, 0x2D: 0x2A,  # pha ba bha -> pa
}

_PUNCT = re.escape(string.punctuation) + "।॥"
_SPLIT_PUNCT = re.compile(f"([{_PUNCT}])")
_NUMBER = re.compile(r"(\d) ([,.:/]) (?=\d)")
_SENTENCE_END = re.compile(r"(?<=[.!?।॥])\s+|\n+")
_ZERO_WIDTH = re.compile("[​﻿]")


def transliterate(text: str, source: str, target: str) -> str:
    """Swap letters between Devanagari, Telugu, Kannada and Tamil."""
    if source == target:
        return text
    src, dst = _BLOCK[source], _BLOCK[target]
    out = []
    for ch in text:
        offset = ord(ch) - src
        if 0 <= offset < _ALIGNED and ch not in _DANDAS:
            if target == "ta":
                offset = _TAMIL.get(offset, offset)
            ch = chr(dst + offset)
        out.append(ch)
    return "".join(out)


def split_sentences(text: str) -> list[str]:
    return [s.strip() for s in _SENTENCE_END.split(text.strip()) if s and s.strip()]


def _tokenize_indic(text: str) -> str:
    spaced = _SPLIT_PUNCT.sub(r" \1 ", text.replace("\t", " "))
    spaced = re.sub(r" +", " ", spaced).strip()
    # keep numbers like 1,000 and 2.5 together
    while True:
        joined = _NUMBER.sub(r"\1\2", spaced)
        if joined == spaced:
            return joined
        spaced = joined


def _detokenize_indic(text: str) -> str:
    text = re.sub(r"\s+([,.!?:;%)\]}।॥])", r"\1", text)
    text = re.sub(r"([(\[{])\s+", r"\1", text)
    text = re.sub(r'"\s*(.*?)\s*"', r'"\1"', text)
    return re.sub(r" +", " ", text).strip()


# Shop words IndicTrans2 gets wrong, swapped for words it knows before translating.
# (It read "udhaar" as "Aadhaar card" and ఉద్దెర as "wickets".)
_GLOSSARY = {
    "en": [(re.compile(r"\budh+aa?r(i|y)?\b|\budhari\b", re.IGNORECASE), "dues")],
    "te": [(re.compile("ఉద్దెర|ఉద్ధెర|ఉద్దర|ఉదారి"), "అప్పు")],
}


def _use_glossary(sentence: str, source: str) -> str:
    for pattern, word in _GLOSSARY.get(source, []):
        sentence = pattern.sub(word, sentence)
    return sentence


_moses: dict = {}


def _english():
    """Moses tools, made once (loading them is a little slow)."""
    if not _moses:
        from sacremoses import MosesDetokenizer, MosesPunctNormalizer, MosesTokenizer

        _moses["norm"] = MosesPunctNormalizer(lang="en")
        _moses["tok"] = MosesTokenizer(lang="en")
        _moses["detok"] = MosesDetokenizer(lang="en")
    return _moses


_END_MARKS = ".!?।॥"
_DIGITS = re.compile(r"\d[\d,]*(?:\.\d+)?")


def _numbers(text: str) -> set[str]:
    return {n.replace(",", "").rstrip(".") for n in _DIGITS.findall(text)}


def looks_cut(original: str, translated: str) -> bool:
    """True when a translation lost a number or stopped far too early.
    (The Indian-to-Indian model sometimes stops at the short form for rupees.)"""
    if not _numbers(original) <= _numbers(translated):
        return True
    return len(original.split()) >= 4 and len(translated.split()) * 2 < len(original.split())


def has_end_mark(sentence: str) -> bool:
    return sentence.rstrip()[-1:] in tuple(_END_MARKS)


def drop_end_mark(text: str) -> str:
    return text.rstrip().rstrip(_END_MARKS).rstrip()


_NATIVE_DIGITS = {start + i: str(i) for start in (0x0966, 0x0BE6, 0x0C66, 0x0CE6) for i in range(10)}


def ascii_digits(text: str) -> str:
    """२५० / ౨౫౦ / ೨೫೦ / ௨௫௦ -> 250 (the model garbles digits written in Indian scripts)."""
    return text.translate(_NATIVE_DIGITS)


def prepare(sentence: str, source: str, target: str) -> str:
    """One sentence -> what IndicTrans2 reads."""
    sentence = _use_glossary(ascii_digits(_ZERO_WIDTH.sub("", sentence)).strip(), source)
    # Without a full stop IndicTrans2 often stops half-way (spoken sentences have none).
    if sentence and not has_end_mark(sentence):
        sentence += "।" if source == "hi" else "."
    if source == "en":
        moses = _english()
        body = moses["tok"].tokenize(moses["norm"].normalize(sentence), escape=False, return_str=True)
    else:
        body = transliterate(_tokenize_indic(sentence), source, "hi").replace(" ् ", "्")
    return f"{INDICTRANS[source]} {INDICTRANS[target]} {body}"


def finish(translated: str, target: str) -> str:
    """What IndicTrans2 wrote -> normal text in the target language."""
    if target == "en":
        return _english()["detok"].detokenize(translated.split())
    return _detokenize_indic(transliterate(translated, "hi", target))
