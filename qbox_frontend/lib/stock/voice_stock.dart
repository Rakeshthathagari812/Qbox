/// Turns a spoken stock sentence into which item, how much, and which way:
///
///   "rice 10 kg came"              -> Rice, 10 kg, stock in
///   "sugar 2 kilo sold"            -> Sugar, 2 kg, sold
///   "బియ్యం 10 కిలోలు వచ్చాయి"      -> Rice, 10 kg, stock in
///   "चीनी 500 ग्राम बिकी"           -> Sugar, 0.5 kg, sold
///
/// Numbers are read on the phone (never translated), and item names match in
/// any of the 5 languages through the ready list's names. The result is always
/// shown to the shopkeeper to check before anything is saved.
library;

import '../calculator/voice_math.dart';
import '../translator/english_numbers.dart';
import '../translator/indic_numbers.dart';
import '../translator/languages.dart';
import '../translator/transliterate.dart';
import 'heard_items.dart';
import 'stock_catalog.dart';
import 'stock_models.dart';

class SpokenStock {
  const SpokenStock({
    required this.heard,
    this.kind,
    this.qtyMilli,
    this.unit,
    this.matches = const [],
    this.newItem,
  });

  final String heard;

  /// Null when it was not clear whether stock came in or went out.
  final MoveKind? kind;

  /// The quantity as said, in [unit] (or in the item's unit when no unit was said).
  final int? qtyMilli;
  final StockUnit? unit;

  /// Items in stock that were named. One = clear; several = ask which one.
  final List<StockItem> matches;

  /// A ready-list item that was named but is not in stock yet.
  final CatalogItem? newItem;

  /// The quantity written in [item]'s unit (500 g -> 0.5 kg). When the units
  /// cannot be converted (kg and packets), the number is kept as it was said.
  int? qtyFor(StockItem item) {
    final qty = qtyMilli;
    final said = unit;
    if (qty == null || said == null) return qty;
    return item.unit.convert(qty, said) ?? qty;
  }
}

SpokenStock? parseSpokenStock(String words, AppLanguage language, List<StockItem> items) {
  final text = _prepare(fixHeard(englishNumberWords(numbersToDigits(words, language))));
  if (text.trim().isEmpty) return null;
  final tokens = text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

  final unit = _unitIn(tokens);
  final kind = _kindIn(tokens);
  final qty = _quantity(text, tokens);

  final scored = <StockItem, int>{};
  for (final item in items) {
    final names = [item.name, ...?catalogItem(item.catalogCode)?.allNames];
    final s = _score(text, names);
    if (s > 0) scored[item] = s;
  }
  var matches = <StockItem>[];
  if (scored.isNotEmpty) {
    final best = scored.values.reduce((a, b) => a > b ? a : b);
    matches = [for (final e in scored.entries) if (e.value == best) e.key];
  }

  CatalogItem? newItem;
  if (matches.isEmpty) {
    final inStock = {for (final i in items) i.catalogCode};
    final names = {for (final i in items) i.name.toLowerCase()};
    var best = 0;
    for (final c in stockCatalog) {
      if (inStock.contains(c.code) || names.contains(c.en.toLowerCase())) continue;
      final s = _score(text, c.allNames);
      if (s > best) {
        best = s;
        newItem = c;
      }
    }
  }

  if (matches.isEmpty && newItem == null && qty == null) return null;
  return SpokenStock(heard: words, kind: kind, qtyMilli: qty, unit: unit, matches: matches, newItem: newItem);
}

/// Lower case, "10kg" -> "10 kg", "1,000" -> "1000".
String _prepare(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'(?<=[0-9]),(?=[0-9]{3})'), '')
    .replaceAllMapped(RegExp(r'([0-9])([^0-9\s.,])'), (m) => '${m[1]} ${m[2]}')
    .replaceAll(RegExp(r'[,!?।]'), ' ');

int? _quantity(String text, List<String> tokens) {
  final number = RegExp(r'(?<![0-9.])([0-9]{1,7}(?:\.[0-9]{1,3})?)(?![0-9])').firstMatch(text);
  if (number != null) {
    final value = double.parse(number[1]!);
    return value > 0 ? (value * milli).round() : null;
  }
  if (tokens.any(_half.contains)) return milli ~/ 2;
  // English number words ("ten kilo rice", "two fifty grams").
  final spoken = tokens.where(_numberWords.contains).join(' ');
  if (spoken.isEmpty) return null;
  final value = double.tryParse(parseSpokenMath(spoken) ?? '');
  return value == null || value <= 0 ? null : (value * milli).round();
}

StockUnit? _unitIn(List<String> tokens) {
  for (final token in tokens) {
    for (final entry in _units.entries) {
      final (exact, stems) = entry.value;
      if (exact.contains(token) || stems.any(token.startsWith)) return entry.key;
    }
  }
  return null;
}

MoveKind? _kindIn(List<String> tokens) {
  bool any((Set<String>, List<String>) words) =>
      tokens.any((t) => words.$1.contains(t) || words.$2.any(t.startsWith));
  if (any(_outWords)) return MoveKind.out;
  if (any(_inWords)) return MoveKind.stockIn;
  return null;
}

/// How well [names] are heard in [text]: 0 = not at all. Names in Indian
/// script count when heard as they are; every name also counts when all its
/// words are heard in English letters (allowing one wrong letter).
int _score(String text, List<String> names) {
  final heardLatin = latinWords(text);
  var best = 0;
  for (final name in names) {
    final lower = name.toLowerCase();
    if (hasIndianScript(lower) && text.contains(lower)) {
      best = best > lower.length * 2 ? best : lower.length * 2;
      continue;
    }
    final words = latinWords(lower).where((w) => w.length >= 2 && !_ignore.contains(w)).toList();
    if (words.isEmpty) continue;
    final allHeard = words.every((w) => heardLatin.any((h) => h == w || (w.length >= 4 && h.length >= 4 && soundsClose(h, w))));
    if (allHeard) {
      final s = words.fold(0, (sum, w) => sum + w.length);
      if (s > best) best = s;
    }
  }
  return best;
}

/// Words in English letters, with long vowels made short (so "biyyaam",
/// "biyyam" and "biyam" agree).
List<String> latinWords(String text) => transliterate(text)
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
    .replaceAll(RegExp(r'aa+'), 'a')
    .replaceAll(RegExp(r'(ee|ii)+'), 'i')
    .replaceAll(RegExp(r'(oo|uu)+'), 'u')
    .replaceAll(RegExp(r'([a-z])\1+'), r'$1')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .toList();

/// [a] and [b] differ by at most one letter (added, removed or changed).
bool soundsClose(String a, String b) {
  if ((a.length - b.length).abs() > 1) return false;
  var i = 0;
  var j = 0;
  var edits = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      i++;
      j++;
      continue;
    }
    if (++edits > 1) return false;
    if (a.length > b.length) {
      i++;
    } else if (b.length > a.length) {
      j++;
    } else {
      i++;
      j++;
    }
  }
  return edits + (a.length - i) + (b.length - j) <= 1;
}

/// Words in item names that alone do not identify an item.
const _ignore = {'of', 'the', 'ka', 'ki', 'ke', 'powder', 'oil'};

const _half = {'half', 'aadha', 'adha', 'ara', 'అర', 'आधा', 'आधी', 'ಅರ್ಧ', 'அரை'};

const _numberWords = {
  'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve',
  'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty', 'thirty',
  'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety', 'hundred', 'thousand', 'point',
};

// (exact words, word beginnings): beginnings cover endings like కిలోలు / ಕಿಲೋಗಳು.
const _units = <StockUnit, (Set<String>, List<String>)>{
  StockUnit.kg: ({'kg', 'kgs', 'kilo', 'kilos', 'kilogram', 'kilograms'}, ['కిలో', 'కేజీ', 'किलो', 'केजी', 'ಕಿಲೋ', 'ಕೆಜಿ', 'கிலோ']),
  StockUnit.g: ({'g', 'gm', 'gms', 'gram', 'grams', 'கிராம்'}, ['గ్రాము', 'గ్రాం', 'ग्राम', 'ಗ್ರಾಂ', 'ಗ್ರಾಮ್']),
  StockUnit.ml: ({'ml', 'mls', 'millilitre', 'milliliter', 'millilitres', 'milliliters'}, ['మిల్లీ', 'मिली', 'ಮಿಲಿ', 'மில்லி']),
  StockUnit.l: ({'l', 'ltr', 'ltrs', 'litre', 'litres', 'liter', 'liters'}, ['లీటర్', 'లీటరు', 'लीटर', 'ಲೀಟರ್', 'லிட்டர்']),
  StockUnit.dozen: ({'dozen', 'dozens', 'darjan'}, ['డజ', 'दर्जन', 'ಡಜನ್', 'டஜன்']),
  StockUnit.packet: ({'packet', 'packets', 'pkt', 'pkts', 'pack', 'packs'}, ['ప్యాకెట్', 'పాకెట్', 'पैकेट', 'ಪ್ಯಾಕೆಟ್', 'பாக்கெட்']),
  StockUnit.box: ({'box', 'boxes', 'carton', 'cartons', 'பெட்டி'}, ['బాక్స్', 'డబ్బా', 'डिब्बा', 'बॉक्स', 'ಬಾಕ್ಸ್', 'ಡಬ್ಬ', 'பாக்ஸ்']),
  StockUnit.bag: ({'bag', 'bags', 'sack', 'sacks', 'bori', 'basta', 'பை'}, ['బస్తా', 'బ్యాగ్', 'बोरी', 'बैग', 'ಮೂಟೆ', 'ಚೀಲ', 'மூட்டை']),
  StockUnit.piece: ({'piece', 'pieces', 'pcs', 'pc', 'nos', 'नग'}, ['ముక్క', 'పీసు', 'పీస్', 'पीस', 'ತುಂಡು', 'ಪೀಸ್', 'துண்டு', 'பீஸ்']),
};

const _inWords = (
  {
    'came', 'come', 'arrived', 'received', 'receive', 'bought', 'buy', 'purchased', 'purchase', 'added', 'add',
    'got', 'new', 'in', 'delivered', 'delivery', 'aaya', 'aya', 'aayi', 'aaye', 'kharida', 'kharidi', 'kharide',
    'vachindi', 'vachayi', 'vachai', 'konna', 'konnanu', 'bantu', 'vandhadhu',
  },
  [
    'వచ్చ', 'కొన్న', 'కొనా', 'తెచ్చ', 'చేర్చ', // Telugu: came, bought, brought, added
    'आया', 'आई', 'आए', 'आये', 'खरीद', 'ख़रीद', 'मंगा', 'मँगा', 'जोड़', // Hindi
    'ಬಂತು', 'ಬಂದ', 'ಖರೀದಿ', 'ತಂದ', 'ಸೇರಿಸ', // Kannada
    'வந்த', 'வாங்க', 'சேர்', // Tamil
  ],
);

const _outWords = (
  {
    'sold', 'sell', 'sale', 'sales', 'gone', 'used', 'use', 'out', 'went', 'given', 'gave', 'give', 'issued',
    'bika', 'biki', 'bike', 'becha', 'bechi', 'beche', 'ammanu', 'ammesa', 'ammesanu', 'ayipoyindi', 'maride',
  },
  [
    'అమ్మ', 'అమ్ము', 'అయిపోయ', 'ఖర్చ', // Telugu: sold, finished, used
    'बिक', 'बेच', 'ख़त्म', 'खत्म', // Hindi
    'ಮಾರ', 'ಖರ್ಚ', // Kannada
    'விற்', 'செலவ', // Tamil
  ],
);
