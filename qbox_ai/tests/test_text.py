"""Text preparation for IndicTrans2."""

from ai_server.indic_text import (ascii_digits, drop_end_mark, finish, has_end_mark, looks_cut,
                                  prepare, split_sentences, transliterate)


def test_letters_swap_between_scripts_and_back():
    telugu = "బియ్యం ధర ఎంత?"
    devanagari = transliterate(telugu, "te", "hi")
    assert devanagari == "बिय्यं धर ऎंत?"  # ఎ (short e) -> ऎ
    assert transliterate(devanagari, "hi", "te") == telugu
    kannada = "ಅಕ್ಕಿ ಬೆಲೆ ಎಷ್ಟು"
    assert transliterate(transliterate(kannada, "kn", "hi"), "hi", "kn") == kannada
    tamil = "அரிசி விலை என்ன"
    assert transliterate(transliterate(tamil, "ta", "hi"), "hi", "ta") == tamil


def test_tamil_uses_its_nearest_letters():
    assert transliterate("भारत", "hi", "ta") == "பாரத"  # bha -> pa


def test_english_and_dandas_are_untouched():
    assert transliterate("Ramesh 500 । ok", "hi", "te") == "Ramesh 500 । ok"


def test_sentences():
    assert split_sentences("Hello there. How are you?\nFine") == ["Hello there.", "How are you?", "Fine"]
    assert split_sentences("రాము వచ్చాడు। డబ్బు ఇచ్చాడు") == ["రాము వచ్చాడు।", "డబ్బు ఇచ్చాడు"]
    assert split_sentences("   ") == []


def test_prepare_indian_language():
    assert prepare("బియ్యం, ధర ఎంత?", "te", "en") == "tel_Telu eng_Latn बिय्यं , धर ऎंत ?"
    # a full stop is added when missing (without it the model stops half-way)
    assert prepare("Rs 1,000.50 ఇచ్చాడు", "te", "hi").endswith("Rs 1,000.50 इच्चाडु .")
    assert prepare("रमेश ने 200 रुपये उधार लिए", "hi", "te").endswith("लिए ।")


def test_prepare_english():
    assert prepare("Hello, how much is rice?", "en", "te") == "eng_Latn tel_Telu Hello , how much is rice ?"


def test_shop_words():
    # IndicTrans2 read "udhaar" as "Aadhaar card" and ఉద్దెర as "wickets"
    assert prepare("Your udhaar is 750", "en", "te") == "eng_Latn tel_Telu Your dues is 750 ."
    assert "dues" in prepare("UDHAR of Ramesh", "en", "hi")
    assert "dues" in prepare("udhari 50", "en", "hi")
    assert transliterate("అప్పు", "te", "hi") in prepare("రమేష్ 200 ఉద్దెర", "te", "en")


def test_end_marks():
    assert has_end_mark("ok.") and has_end_mark("ठीक।") and not has_end_mark("ok")
    assert drop_end_mark("నేను రేపు వస్తాను.") == "నేను రేపు వస్తాను"
    assert drop_end_mark("ठीक है।") == "ठीक है"


def test_looks_cut():
    assert looks_cut("రమేష్ ఈ రోజు 500 రూపాయలు ఇచ్చాడు", "ರಮೇಶ್ ಇಂದು ರೂ")  # lost the amount
    assert not looks_cut("రమేష్ ఈ రోజు 500 రూపాయలు ఇచ్చాడు", "ರಮೇಶ್ ಇಂದು 500 ರೂಪಾಯಿ ಕೊಟ್ಟರು")
    assert not looks_cut("Rs 1,000 paid", "1000 रुपये दिए")
    assert looks_cut("one two three four five six seven eight", "one two three")
    assert not looks_cut("ನಾಳೆ ಬನ್ನಿ", "రేపు రండి")


def test_indian_script_digits():
    assert ascii_digits("२५० प्लस १८०") == "250 प्लस 180"
    assert ascii_digits("౨౫౦ ೨೫೦ ௨௫௦") == "250 250 250"
    assert prepare("౨౫౦ ప్లస్ ౧౮౦", "te", "en").startswith("tel_Telu eng_Latn 250")


def test_finish():
    assert finish("बिय्यं धर ऎंत ?", "te") == "బియ్యం ధర ఎంత?"
    assert finish("How much is rice ?", "en") == "How much is rice?"
    # if the model already wrote Telugu letters, they stay as they are
    assert finish("ధర ఎంత ?", "te") == "ధర ఎంత?"
