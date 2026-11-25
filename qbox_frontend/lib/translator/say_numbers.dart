/// Numbers written out in words before the phone says them.
///
/// Some phones' voices read 200 as "two O O", and "₹" or "Rs." not at all. Words
/// are read the same way by every phone:
///   "The total is Rs 200"  -> "The total is two hundred rupees"
///   "మొత్తం 250 రూపాయలు"   -> "మొత్తం రెండు వందల యాభై రూపాయలు"
library;

import '../calculator/calculator_engine.dart' show indianWords;
import 'languages.dart';

/// [text] as the phone should say it in [language].
String sayable(String text, AppLanguage language) {
  final l = _langs[language]!;
  // ₹200, Rs. 200, రూ. 200 -> 200 rupees
  var out = text.replaceAllMapped(
    RegExp(r'(?:₹|\b[Rr][Ss]\.?|రూ\.|रु\.|रू\.|ರೂ\.|ரூ\.)\s*(\d[\d,]*(?:\.\d+)?)(\s*(?:rupees?|రూపాయ\S*|रुपय\S*|रुपए|ರೂಪಾಯಿ\S*|ரூபாய்?\S*))?'),
    (m) => '${m[1]} ${m[2]?.trim() ?? l.rupees}',
  );
  // 10:05, 10:30 (the ":" is not a sum)
  out = out.replaceAllMapped(RegExp(r'(?<![\d:])(\d{1,2}):(\d{2})(?![\d:])'), (m) {
    final minutes = int.parse(m[2]!);
    return minutes == 0 ? m[1]! : '${m[1]} $minutes';
  });
  final said = out.replaceAllMapped(RegExp(r'(?<![\p{L}\d])(-|−)?(\d[\d,]*)(\.\d+)?(\s?%)?', unicode: true), (m) {
    final digits = m[2]!.replaceAll(RegExp(r',+$'), '');
    final tail = m[2]!.substring(digits.length); // "200," keeps its comma
    final plain = digits.replaceAll(',', '');
    final minus = m[1] == null ? '' : '${l.minus} ';
    String whole;
    if (plain.length >= 10 || (plain.length > 1 && plain.startsWith('0'))) {
      whole = plain.split('').map((d) => l.number(int.parse(d))).join(' '); // a phone number
    } else {
      whole = l.number(int.parse(plain));
    }
    var decimals = '';
    if (m[3] != null) {
      final d = m[3]!.substring(1).replaceFirst(RegExp(r'0+$'), '');
      if (d.isNotEmpty) decimals = ' ${l.point} ${d.split('').map((x) => l.number(int.parse(x))).join(' ')}';
    }
    final percent = m[4] == null ? '' : ' ${l.percent}';
    // "5kg" -> "five kg"
    final next = m.end < out.length ? out[m.end] : '';
    final space = percent.isEmpty && tail.isEmpty && RegExp(r'\p{L}', unicode: true).hasMatch(next) ? ' ' : '';
    return '$minus$whole$decimals$percent$tail$space';
  });
  if (language != AppLanguage.telugu) return said;
  // రెండు వందల రూపాయలు (not వందలు రూపాయలు)
  return said.replaceAllMapped(
    RegExp(r'(వంద|వే|లక్ష|కోట్)(లు|ట్లు|్లు) (?=రూపాయ|కిలో|కేజీ|గ్రా|లీట|ప్యాకె)'),
    (m) => '${m[1]}${m[2]!.replaceFirst('ు', '')} ',
  );
}

/// [n] (0 or more) in the words of [language].
String numberWords(int n, AppLanguage language) => _langs[language]!.number(n);

class _Lang {
  const _Lang({required this.number, required this.rupees, required this.point, required this.percent, required this.minus});

  final String Function(int n) number;
  final String rupees;
  final String point;
  final String percent;
  final String minus;
}

const _langs = <AppLanguage, _Lang>{
  AppLanguage.english: _Lang(number: indianWords, rupees: 'rupees', point: 'point', percent: 'percent', minus: 'minus'),
  AppLanguage.telugu: _Lang(number: _telugu, rupees: 'రూపాయలు', point: 'పాయింట్', percent: 'శాతం', minus: 'మైనస్'),
  AppLanguage.hindi: _Lang(number: _hindi, rupees: 'रुपये', point: 'पॉइंट', percent: 'प्रतिशत', minus: 'माइनस'),
  AppLanguage.kannada: _Lang(number: _kannada, rupees: 'ರೂಪಾಯಿ', point: 'ಪಾಯಿಂಟ್', percent: 'ಪರ್ಸೆಂಟ್', minus: 'ಮೈನಸ್'),
  AppLanguage.tamil: _Lang(number: _tamil, rupees: 'ரூபாய்', point: 'புள்ளி', percent: 'சதவீதம்', minus: 'மைனஸ்'),
};

/// Crore, lakh, thousand and the rest, biggest first.
List<(int, int)> _parts(int n) {
  final out = <(int, int)>[];
  var rest = n;
  for (final size in const [10000000, 100000, 1000, 100]) {
    final count = rest ~/ size;
    rest %= size;
    if (count > 0) out.add((size, count));
  }
  if (rest > 0) out.add((1, rest));
  return out;
}

// ---------- Telugu ----------

const _teOnes = [
  'సున్నా', 'ఒకటి', 'రెండు', 'మూడు', 'నాలుగు', 'ఐదు', 'ఆరు', 'ఏడు', 'ఎనిమిది', 'తొమ్మిది', 'పది', 'పదకొండు', 'పన్నెండు',
  'పదమూడు', 'పద్నాలుగు', 'పదిహేను', 'పదహారు', 'పదిహేడు', 'పద్దెనిమిది', 'పందొమ్మిది',
];
const _teTens = ['', '', 'ఇరవై', 'ముప్పై', 'నలభై', 'యాభై', 'అరవై', 'డెబ్బై', 'ఎనభై', 'తొంభై'];

String _telugu(int n) {
  if (n < 20) return _teOnes[n];
  if (n < 100) return n % 10 == 0 ? _teTens[n ~/ 10] : '${_teTens[n ~/ 10]} ${_teOnes[n % 10]}';
  final parts = _parts(n);
  final out = <String>[];
  for (final (i, (size, count)) in parts.indexed) {
    final last = i == parts.length - 1;
    out.add(switch (size) {
      10000000 => count == 1 ? (last ? 'కోటి' : 'కోటి') : '${_telugu(count)} ${last ? 'కోట్లు' : 'కోట్ల'}',
      100000 => count == 1 ? 'లక్ష' : '${_telugu(count)} ${last ? 'లక్షలు' : 'లక్షల'}',
      1000 => count == 1 ? 'వెయ్యి' : '${_telugu(count)} ${last ? 'వేలు' : 'వేల'}',
      100 => count == 1 ? (last ? 'వంద' : 'నూట') : '${_telugu(count)} ${last ? 'వందలు' : 'వందల'}',
      _ => _telugu(count),
    });
  }
  return out.join(' ');
}

// ---------- Hindi ----------

const _hi = [
  'शून्य', 'एक', 'दो', 'तीन', 'चार', 'पाँच', 'छह', 'सात', 'आठ', 'नौ', 'दस', 'ग्यारह', 'बारह', 'तेरह', 'चौदह', 'पंद्रह',
  'सोलह', 'सत्रह', 'अठारह', 'उन्नीस', 'बीस', 'इक्कीस', 'बाईस', 'तेईस', 'चौबीस', 'पच्चीस', 'छब्बीस', 'सत्ताईस', 'अट्ठाईस',
  'उनतीस', 'तीस', 'इकतीस', 'बत्तीस', 'तैंतीस', 'चौंतीस', 'पैंतीस', 'छत्तीस', 'सैंतीस', 'अड़तीस', 'उनतालीस', 'चालीस',
  'इकतालीस', 'बयालीस', 'तैंतालीस', 'चवालीस', 'पैंतालीस', 'छियालीस', 'सैंतालीस', 'अड़तालीस', 'उनचास', 'पचास', 'इक्यावन',
  'बावन', 'तिरपन', 'चौवन', 'पचपन', 'छप्पन', 'सत्तावन', 'अट्ठावन', 'उनसठ', 'साठ', 'इकसठ', 'बासठ', 'तिरसठ', 'चौंसठ',
  'पैंसठ', 'छियासठ', 'सड़सठ', 'अड़सठ', 'उनहत्तर', 'सत्तर', 'इकहत्तर', 'बहत्तर', 'तिहत्तर', 'चौहत्तर', 'पचहत्तर', 'छिहत्तर',
  'सतहत्तर', 'अठहत्तर', 'उन्यासी', 'अस्सी', 'इक्यासी', 'बयासी', 'तिरासी', 'चौरासी', 'पचासी', 'छियासी', 'सत्तासी', 'अट्ठासी',
  'नवासी', 'नब्बे', 'इक्यानवे', 'बानवे', 'तिरानवे', 'चौरानवे', 'पंचानवे', 'छियानवे', 'सत्तानवे', 'अट्ठानवे', 'निन्यानवे',
];

String _hindi(int n) {
  if (n < 100) return _hi[n];
  return [
    for (final (size, count) in _parts(n))
      switch (size) {
        10000000 => '${_hindi(count)} करोड़',
        100000 => '${_hindi(count)} लाख',
        1000 => '${_hindi(count)} हज़ार',
        100 => '${_hindi(count)} सौ',
        _ => _hindi(count),
      },
  ].join(' ');
}

// ---------- Kannada ----------

const _knOnes = [
  'ಸೊನ್ನೆ', 'ಒಂದು', 'ಎರಡು', 'ಮೂರು', 'ನಾಲ್ಕು', 'ಐದು', 'ಆರು', 'ಏಳು', 'ಎಂಟು', 'ಒಂಬತ್ತು', 'ಹತ್ತು', 'ಹನ್ನೊಂದು', 'ಹನ್ನೆರಡು',
  'ಹದಿಮೂರು', 'ಹದಿನಾಲ್ಕು', 'ಹದಿನೈದು', 'ಹದಿನಾರು', 'ಹದಿನೇಳು', 'ಹದಿನೆಂಟು', 'ಹತ್ತೊಂಬತ್ತು',
];
const _knTens = ['', '', 'ಇಪ್ಪತ್ತು', 'ಮೂವತ್ತು', 'ನಲವತ್ತು', 'ಐವತ್ತು', 'ಅರವತ್ತು', 'ಎಪ್ಪತ್ತು', 'ಎಂಬತ್ತು', 'ತೊಂಬತ್ತು'];
const _knStems = ['', '', 'ಇಪ್ಪತ್ತ', 'ಮೂವತ್ತ', 'ನಲವತ್ತ', 'ಐವತ್ತ', 'ಅರವತ್ತ', 'ಎಪ್ಪತ್ತ', 'ಎಂಬತ್ತ', 'ತೊಂಬತ್ತ'];
const _knEnds = ['', 'ೊಂದು', 'ೆರಡು', 'ಮೂರು', 'ನಾಲ್ಕು', 'ೈದು', 'ಾರು', 'ೇಳು', 'ೆಂಟು', 'ೊಂಬತ್ತು'];
const _knHundreds = ['', 'ನೂರು', 'ಇನ್ನೂರು', 'ಮುನ್ನೂರು', 'ನಾನೂರು', 'ಐನೂರು', 'ಆರುನೂರು', 'ಏಳುನೂರು', 'ಎಂಟುನೂರು', 'ಒಂಬೈನೂರು'];
const _knHundredsOf = ['', 'ನೂರ', 'ಇನ್ನೂರ', 'ಮುನ್ನೂರ', 'ನಾನೂರ', 'ಐನೂರ', 'ಆರುನೂರು', 'ಏಳುನೂರು', 'ಎಂಟುನೂರು', 'ಒಂಬೈನೂರು'];

String _kannada(int n) {
  if (n < 20) return _knOnes[n];
  if (n < 100) return n % 10 == 0 ? _knTens[n ~/ 10] : '${_knStems[n ~/ 10]}${_knEnds[n % 10]}';
  final parts = _parts(n);
  return [
    for (final (i, (size, count)) in parts.indexed)
      switch (size) {
        10000000 => '${_kannada(count)} ಕೋಟಿ',
        100000 => '${_kannada(count)} ${i == parts.length - 1 ? 'ಲಕ್ಷ' : 'ಲಕ್ಷದ'}',
        1000 => '${count == 1 ? '' : '${_kannada(count)} '}${i == parts.length - 1 ? 'ಸಾವಿರ' : 'ಸಾವಿರದ'}',
        100 => i == parts.length - 1 ? _knHundreds[count] : _knHundredsOf[count],
        _ => _kannada(count),
      },
  ].join(' ');
}

// ---------- Tamil ----------

const _taOnes = [
  'பூஜ்ஜியம்', 'ஒன்று', 'இரண்டு', 'மூன்று', 'நான்கு', 'ஐந்து', 'ஆறு', 'ஏழு', 'எட்டு', 'ஒன்பது', 'பத்து', 'பதினொன்று',
  'பன்னிரண்டு', 'பதிமூன்று', 'பதினான்கு', 'பதினைந்து', 'பதினாறு', 'பதினேழு', 'பதினெட்டு', 'பத்தொன்பது',
];
const _taTens = ['', '', 'இருபது', 'முப்பது', 'நாற்பது', 'ஐம்பது', 'அறுபது', 'எழுபது', 'எண்பது', 'தொண்ணூறு'];
const _taTensOf = ['', '', 'இருபத்து', 'முப்பத்து', 'நாற்பத்து', 'ஐம்பத்து', 'அறுபத்து', 'எழுபத்து', 'எண்பத்து', 'தொண்ணூற்று'];
const _taHundreds = ['', 'நூறு', 'இருநூறு', 'முந்நூறு', 'நானூறு', 'ஐநூறு', 'அறுநூறு', 'எழுநூறு', 'எண்ணூறு', 'தொள்ளாயிரம்'];
const _taHundredsOf = [
  '', 'நூற்று', 'இருநூற்று', 'முந்நூற்று', 'நானூற்று', 'ஐநூற்று', 'அறுநூற்று', 'எழுநூற்று', 'எண்ணூற்று', 'தொள்ளாயிரத்து',
];

String _tamil(int n) {
  if (n < 20) return _taOnes[n];
  if (n < 100) return n % 10 == 0 ? _taTens[n ~/ 10] : '${_taTensOf[n ~/ 10]} ${_taOnes[n % 10]}';
  final parts = _parts(n);
  return [
    for (final (i, (size, count)) in parts.indexed)
      switch (size) {
        10000000 => '${_tamil(count)} கோடி',
        100000 => '${_tamil(count)} ${i == parts.length - 1 ? 'லட்சம்' : 'லட்சத்து'}',
        1000 => '${count == 1 ? '' : '${_tamil(count)} '}${i == parts.length - 1 ? 'ஆயிரம்' : 'ஆயிரத்து'}',
        100 => i == parts.length - 1 ? _taHundreds[count] : _taHundredsOf[count],
        _ => _tamil(count),
      },
  ].join(' ');
}
