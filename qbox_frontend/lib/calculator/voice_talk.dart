/// Reading a spoken sum, and what the calculator says back, in 5 languages.
library;

import '../translator/english_numbers.dart';
import '../translator/indic_numbers.dart';
import '../translator/languages.dart';
import 'calculator_engine.dart';
import 'spoken_operators.dart';
import 'voice_math.dart';

/// [words] with numbers and calculator words the calculator can read.
String mathText(String words, AppLanguage language) => language == AppLanguage.english
    ? words
    : operatorsToSymbols(englishNumberWords(numbersToDigits(words, language)), language);

/// The sum in [words], or null. "plus 10" carries on from [last], the answer showing.
String? readSum(String words, AppLanguage language, {double? last}) {
  final text = mathText(words, language);
  if (last != null && startsWithOperator(text)) {
    final carriedOn = parseSpokenMath('${formatPlain(last)} $text');
    if (carriedOn != null) return carriedOn;
  }
  return parseSpokenMath(text);
}

bool _isSum(String sum) => sum.contains(percent) || sum.split('').skip(1).any(operators.contains);

String _digits(String sum) => sum.replaceAll(RegExp(r'[^0-9]'), '');

/// [words], or one of the phone's other [guesses] when that is a sum and [words]
/// is not ("2030" was "20 + 30").
String? bestSum(String words, List<String> guesses, AppLanguage language, {double? last}) {
  final first = readSum(words, language, last: last);
  if (first != null && _isSum(first)) return first;
  for (final guess in guesses) {
    final sum = readSum(guess, language, last: last);
    if (sum == null || !_isSum(sum)) continue;
    // "20" was only the start of "20 + 30".
    if (first == null || _digits(sum).startsWith(_digits(first))) return sum;
  }
  return first;
}

/// "20 plus": more must follow.
bool sumUnfinished(String words, AppLanguage language) => endsWithOperator(mathText(words, language));

const _stop = {
  'stop', 'stop it', 'stop listening', 'స్టాప్', 'ఆపు', 'చాలు', 'स्टॉप', 'रुको', 'बस', 'ಸ್ಟಾಪ್', 'ನಿಲ್ಲಿಸು', 'ಸಾಕು',
  'ஸ்டாப்', 'நிறுத்து', 'போதும்',
};
const _clear = {
  'clear', 'all clear', 'clear all', 'start again', 'క్లియర్', 'తుడిచేయి', 'క్లియర్ చేయి', 'क्लियर', 'साफ करो', 'साफ़ करो',
  'ಕ್ಲಿಯರ್', 'ಅಳಿಸು', 'கிளியர்', 'அழி',
};

String _plain(String words) => words.toLowerCase().replaceAll(RegExp(r'[.,!?।]'), '').trim();

bool saysStop(String words) => _stop.contains(_plain(words));
bool saysClear(String words) => _clear.contains(_plain(words));

typedef _Words = ({String plus, String minus, String times, String by, String percent, String equals});

const _said = <AppLanguage, _Words>{
  AppLanguage.telugu: (plus: 'ప్లస్', minus: 'మైనస్', times: 'ఇంటూ', by: 'బై', percent: 'శాతం', equals: 'సమానం'),
  AppLanguage.hindi: (plus: 'प्लस', minus: 'माइनस', times: 'गुणा', by: 'भाग', percent: 'प्रतिशत', equals: 'बराबर'),
  AppLanguage.kannada: (plus: 'ಪ್ಲಸ್', minus: 'ಮೈನಸ್', times: 'ಇಂಟು', by: 'ಬೈ', percent: 'ಪರ್ಸೆಂಟ್', equals: 'ಸಮ'),
  AppLanguage.tamil: (plus: 'பிளஸ்', minus: 'மைனஸ்', times: 'பெருக்கல்', by: 'வகுத்தல்', percent: 'சதவீதம்', equals: 'சமம்'),
};

/// The whole sum read out: "20 ప్లస్ 30 సమానం 50". The phone's voice for that
/// language reads the numbers.
String spokenSum(String sum, double answer, AppLanguage language) {
  final w = _said[language];
  if (w == null) return spokenCalculation(sum, answer);
  String number(String n) => n.startsWith(minus) || n.startsWith('-') ? '${w.minus} ${n.substring(1)}' : n;
  final total = number(formatPlain(answer));
  final pieces = splitPieces(sum);
  if (pieces.length <= 1) return total;
  final out = <String>[
    for (final p in pieces)
      switch (p) {
        plus => w.plus,
        minus => w.minus,
        times => w.times,
        divide => w.by,
        _ => p.endsWith(percent) ? '${number(p.replaceAll(percent, ''))} ${w.percent}' : number(p),
      },
  ];
  return '${out.join(' ')} ${w.equals} $total';
}

String sayAgain(AppLanguage language) => switch (language) {
  AppLanguage.english => 'Sorry, please say the sum again',
  AppLanguage.telugu => 'అర్థం కాలేదు, లెక్క మళ్ళీ చెప్పండి',
  AppLanguage.hindi => 'समझ नहीं आया, हिसाब फिर से बोलें',
  AppLanguage.kannada => 'ಅರ್ಥವಾಗಲಿಲ್ಲ, ಲೆಕ್ಕವನ್ನು ಮತ್ತೆ ಹೇಳಿ',
  AppLanguage.tamil => 'புரியவில்லை, கணக்கை மீண்டும் சொல்லுங்கள்',
};
