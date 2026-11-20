/// Calculator words in Telugu, Hindi, Kannada and Tamil -> + − × ÷ %.
///
///   "250 ఇంటు 3"      -> "250 × 3"      (English "into", heard in Telugu letters)
///   "1000 भाग 4"      -> "1000 ÷ 4"
///   "500 ಗುಣಿಸು 3"     -> "500 × 3"
///
/// Used with numbersToDigits, so a spoken sum becomes "250 + 180" on the phone
/// and is worked out directly, without translating.
library;

import '../translator/languages.dart';

const _plus = '+';
const _minus = '-';
const _times = '×';
const _divide = '÷';
const _percent = 'percent';

const _words = <AppLanguage, Map<String, String>>{
  AppLanguage.telugu: {
    'ప్లస్': _plus,
    'ప్లస్సు': _plus,
    'కూడిక': _plus,
    'కలుపు': _plus,
    'కలిపి': _plus,
    'కలిపితే': _plus,
    'మైనస్': _minus,
    'మైనస్సు': _minus,
    'తీసివేత': _minus,
    'తీసివేయి': _minus,
    'తీసేస్తే': _minus,
    'ఇంటు': _times,
    'ఇంటూ': _times,
    'ఇన్టు': _times,
    'గుణించు': _times,
    'గుణిస్తే': _times,
    'గుణకారం': _times,
    'సార్లు': _times,
    'టైమ్స్': _times,
    'బై': _divide,
    'భాగించు': _divide,
    'భాగిస్తే': _divide,
    'భాగహారం': _divide,
    'డివైడ్': _divide,
    'శాతం': _percent,
    'పర్సెంట్': _percent,
  },
  AppLanguage.hindi: {
    'प्लस': _plus,
    'जोड': _plus,
    'जोड़': _plus,
    'जोडो': _plus,
    'जोड़ो': _plus,
    'माइनस': _minus,
    'मायनस': _minus,
    'घटा': _minus,
    'घटाओ': _minus,
    'इंटू': _times,
    'इन्टू': _times,
    'इनटू': _times,
    'गुणा': _times,
    'गुना': _times,
    'टाइम्स': _times,
    'बाय': _divide,
    'बाई': _divide,
    'भाग': _divide,
    'डिवाइड': _divide,
    'प्रतिशत': _percent,
    'परसेंट': _percent,
    'फीसदी': _percent,
  },
  AppLanguage.kannada: {
    'ಪ್ಲಸ್': _plus,
    'ಕೂಡು': _plus,
    'ಕೂಡಿಸು': _plus,
    'ಸೇರಿಸು': _plus,
    'ಮೈನಸ್': _minus,
    'ಕಳೆ': _minus,
    'ಕಳೆಯು': _minus,
    'ಇಂಟು': _times,
    'ಇಂಟೂ': _times,
    'ಗುಣಿಸು': _times,
    'ಗುಣಾಕಾರ': _times,
    'ಟೈಮ್ಸ್': _times,
    'ಬೈ': _divide,
    'ಭಾಗಿಸು': _divide,
    'ಭಾಗಾಕಾರ': _divide,
    'ಡಿವೈಡ್': _divide,
    'ಶೇಕಡಾ': _percent,
    'ಪರ್ಸೆಂಟ್': _percent,
  },
  AppLanguage.tamil: {
    'பிளஸ்': _plus,
    'ப்ளஸ்': _plus,
    'கூட்டல்': _plus,
    'கூட்டு': _plus,
    'மைனஸ்': _minus,
    'கழித்தல்': _minus,
    'கழி': _minus,
    'இன்டு': _times,
    'இண்டு': _times,
    'இன்ட்டு': _times,
    'பெருக்கல்': _times,
    'பெருக்கு': _times,
    'டைம்ஸ்': _times,
    'பை': _divide,
    'வகுத்தல்': _divide,
    'வகு': _divide,
    'டிவைடு': _divide,
    'சதவீதம்': _percent,
    'பர்சென்ட்': _percent,
  },
};

/// [text] with the calculator words of [language] written as + − × ÷ / percent.
String operatorsToSymbols(String text, AppLanguage language) {
  final words = _words[language];
  if (words == null) return text;
  return text
      .replaceAllMapped(RegExp(r'\S+'), (m) {
        final word = m[0]!;
        return words[word] == null ? word : ' ${words[word]} ';
      })
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();
}
