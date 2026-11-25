/// Turns what someone says into checklist items:
///
///   "shampoo 5 packets"                          -> Shampoo, 5 packets
///   "x 12" (how voice typing hears "eggs 12")    -> Eggs, 12
///   "rice 2 kg milk 1 litre soap three"          -> three items
///   "బియ్యం రెండు కిలోలు"                          -> బియ్యం, 2 కిలోలు
library;

import '../calculator/voice_math.dart';
import '../stock/heard_items.dart';
import '../translator/english_numbers.dart';
import '../translator/indic_numbers.dart';
import '../translator/languages.dart';
import 'page_models.dart';

/// [words] as items. [guesses] = what else the phone thought it might have been;
/// one is used only when it names a ready-list item that sounds almost the same.
List<PageItem> readSpokenItems(String words, AppLanguage language, {List<String> guesses = const []}) {
  final first = _read(words, language);
  if (first.every((i) => isKnownItem(i.text))) return first;
  var best = first;
  for (final guess in guesses.take(5)) {
    final other = _read(guess, language);
    if (other.length != first.length) continue;
    var alike = true;
    for (var i = 0; i < other.length && alike; i++) {
      alike = other[i].qty == first[i].qty && heardAlike(other[i].text, first[i].text);
    }
    if (alike && _knownCount(other) > _knownCount(best)) best = other;
  }
  return best;
}

int _knownCount(List<PageItem> items) => items.where((i) => isKnownItem(i.text)).length;

final _before = RegExp(
  r'^(?:please\s+)?(?:(?:add|put|write|buy|get)|i\s+(?:want|need)|we\s+need)\s+(?=\S)',
  caseSensitive: false,
);
final _after = RegExp(
  r'\s+(?:(?:to|in)\s+(?:the|my)\s+(?:check\s*list|list)|please|'
  r'(?:add\s+)?(?:cheyyi|cheyi|cheyandi|karo|kar\s+do|madi)|kavali|chahiye|beku|vendum|'
  r'కావాలి|చేర్చు|చేర్చండి|రాయి|రాయండి|(?:యాడ్\s+)?(?:చేయి|చెయ్యి|చేయండి)|'
  r'चाहिए|जोड़ो|जोड़\s+दो|लिखो|(?:ऐड\s+)?(?:करो|कर\s+दो)|ಬೇಕು|ಸೇರಿಸು|ಸೇರಿಸಿ|வேண்டும்|சேர்|சேர்க்கவும்)[.!?।]*$',
  caseSensitive: false,
);

/// "and", said between items.
const _and = {'and', 'మరియు', 'और', 'ಮತ್ತು', 'மற்றும்'};

List<PageItem> _read(String words, AppLanguage language) {
  var text = englishNumberWords(numbersToDigits(words, language)).trim();
  for (var cut = text.replaceFirst(_after, ''); cut != text; cut = text.replaceFirst(_after, '')) {
    text = cut;
  }
  text = fixHeard(text.replaceFirst(_before, ''));
  final found = <PageItem>[];
  for (final part in text.split(RegExp(r'[,،;\n](?!\d)'))) {
    final tokens = part
        .replaceAllMapped(RegExp(r'(\d|½|¼)([a-z]{1,9})(?![a-z])', caseSensitive: false), (m) => '${m[1]} ${m[2]}')
        .replaceAll(RegExp(r'[.!?।]+(?=\s|$)'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) continue;
    final pieces = _pieces(tokens);
    // "Rice, 2 kg"
    if (pieces.length == 1 && pieces.single.isQty && found.isNotEmpty && found.last.qty.isEmpty) {
      found.last = makeItem(found.last.text, pieces.single.text);
      continue;
    }
    found.addAll(_items(tokens, pieces));
  }
  return found;
}

/// A name, or a quantity, in the order said.
class _Piece {
  _Piece.name(this.text) : isQty = false;
  _Piece.qty(this.text) : isQty = true;

  final String text;
  final bool isQty;
}

List<_Piece> _pieces(List<String> tokens) {
  final out = <_Piece>[];
  final name = <String>[];
  void closeName() {
    while (name.isNotEmpty && _and.contains(name.first.toLowerCase())) {
      name.removeAt(0);
    }
    if (name.isNotEmpty && out.isNotEmpty && out.last.isQty && name.first.toLowerCase() == 'of') name.removeAt(0);
    while (name.isNotEmpty && _and.contains(name.last.toLowerCase())) {
      name.removeLast();
    }
    if (name.isNotEmpty) out.add(_Piece.name(name.join(' ')));
    name.clear();
  }

  var i = 0;
  while (i < tokens.length) {
    final q = _qtyAt(tokens, i, name, afterQty: name.isEmpty && out.isNotEmpty && out.last.isQty);
    if (q == null) {
      name.add(tokens[i++]);
      continue;
    }
    closeName();
    if (out.isNotEmpty && out.last.isQty) {
      out.last = _Piece.qty('${out.last.text} ${q.text}');
    } else {
      out.add(_Piece.qty(q.text));
    }
    i = q.next;
  }
  closeName();
  return out;
}

const _halves = {'half', 'aadha', 'adha', 'అర', 'आधा', 'आधी', 'ಅರ್ಧ', 'அரை'};
const _quarters = {'quarter', 'పావు', 'पाव', 'ಕಾಲು', 'கால்'};
const _ones = {'a', 'an', 'one', 'ఒక', 'ఒక్క', 'एक', 'ಒಂದು', 'ஒரு'};
const _twos = {'दो'};
const _numberWords = {
  'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen',
  'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty', 'thirty', 'forty', 'fifty',
  'sixty', 'seventy', 'eighty', 'ninety', 'hundred',
};
final _digits = RegExp(r'^\d{1,5}(?:\.\d+)?$');

String _fmt(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

/// The quantity that starts at [i], if one does. A number with no unit counts
/// only where it cannot be part of a name ("7 up", "vitamin b 12").
({String text, int next})? _qtyAt(List<String> tokens, int i, List<String> name, {required bool afterQty}) {
  String low(int at) => at < tokens.length ? tokens[at].toLowerCase() : '';
  bool unitAt(int at) => at < tokens.length && isUnitWord(low(at));
  final t = low(i);

  // The unit, and a second unit straight after ("2 kg bag").
  ({String text, int next}) withUnit(String number, int at) {
    var next = at + 1;
    var text = '$number ${low(at)}';
    if (unitAt(next) && !unitAt(next + 1) && low(next).length > 2) text = '$text ${low(next++)}';
    return (text: text, next: next);
  }

  if (_halves.contains(t) || _quarters.contains(t)) {
    final at = low(i + 1) == 'a' || low(i + 1) == 'of' ? i + 2 : i + 1;
    return unitAt(at) ? withUnit(t, at) : null;
  }
  final joined = RegExp(r'^(అర|పావు)(కిలో\S*|లీటర్?\S*)$').firstMatch(t);
  if (joined != null) return (text: '${joined[1]} ${joined[2]}', next: i + 1);
  if (RegExp(r'^(dozen|డజను?|दर्जन|ಡಜನ್|டஜன்)$').hasMatch(t)) return (text: '1 $t', next: i + 1);
  if (_ones.contains(t) && unitAt(i + 1) && t != 'one') return withUnit('1', i + 1);
  if (_twos.contains(t)) {
    if (unitAt(i + 1)) return withUnit('2', i + 1);
  }

  double? value;
  var next = i;
  if (_digits.hasMatch(t) || RegExp(r'^\d+\s*/\s*\d+$|^[½¼]$').hasMatch(t)) {
    next = i + 1;
    value = double.tryParse(t);
    if (value == null) return unitAt(next) ? withUnit(t, next) : null;
  } else if (_numberWords.contains(t)) {
    final run = <String>[];
    while (_numberWords.contains(low(next))) {
      run.add(low(next++));
    }
    value = double.tryParse(parseSpokenMath(run.join(' ')) ?? '');
    if (value == null) return null;
  } else {
    return null;
  }
  if (value <= 0) return null;
  // "one and a half kg"
  if (_and.contains(low(next))) {
    final at = low(next + 1) == 'a' ? next + 2 : next + 1;
    if (_halves.contains(low(at)) && unitAt(at + 1)) return withUnit(_fmt(value + 0.5), at + 1);
  }
  if (unitAt(next)) return withUnit(_fmt(value), next);

  // No unit.
  if (value > 999 || afterQty) return null;
  final said = name.join(' ');
  final bool sure;
  if (name.isEmpty) {
    // "12 eggs", but not "7 up" or "5 star".
    var end = next;
    while (end < tokens.length && !_digits.hasMatch(low(end)) && !_and.contains(low(end))) {
      end++;
    }
    sure = [for (var e = end; e > next; e--) tokens.sublist(next, e).join(' ')].any(
      (n) => isKnownItem(n) && (n.split(' ').length == end - next || end < tokens.length),
    );
  } else {
    final lettered = RegExp(r'\p{L}', unicode: true).hasMatch(said);
    sure = lettered && name.last.runes.length > 1 && (next == tokens.length || endsInKnownItem(said));
  }
  return sure ? (text: _fmt(value), next: next) : null;
}

List<PageItem> _items(List<String> tokens, List<_Piece> pieces) {
  final whole = [makeItem(tokens.join(' '), '')];
  if (pieces.isEmpty) return const [];
  final hasLetters = RegExp(r'\p{L}', unicode: true);
  if (pieces.any((p) => !p.isQty && !hasLetters.hasMatch(p.text))) return whole;
  if (pieces.length == 1) return pieces.single.isQty ? whole : _names(pieces.single.text);

  final out = <PageItem>[];
  if (!pieces.first.isQty) {
    // "rice 2 kg milk 1 litre", and perhaps a last one with no quantity.
    for (var i = 0; i < pieces.length; i += 2) {
      final names = _names(pieces[i].text);
      if (i + 1 < pieces.length) {
        out.addAll(names.take(names.length - 1));
        out.add(makeItem(names.last.text, pieces[i + 1].text));
        continue;
      }
      final sure = pieces.length > 3 || endsInKnownItem(pieces[i - 2].text) || names.every((n) => isKnownItem(n.text));
      if (!sure) return whole;
      out.addAll(names);
    }
    return out;
  }
  // "2 kg rice 1 litre milk"
  for (var i = 0; i + 1 < pieces.length; i += 2) {
    final names = _names(pieces[i + 1].text);
    final lastOne = i + 3 == pieces.length;
    final apart = splitKnownItems(pieces[i + 1].text);
    if (lastOne && names.length == 1 && apart != null && apart.length == 2) {
      // "12 eggs milk 1 litre"
      return out
        ..add(makeItem(apart[0], pieces[i].text))
        ..add(makeItem(apart[1], pieces[i + 2].text));
    }
    if (lastOne && names.length > 1) {
      // "2 kg rice milk 1 litre"
      out.add(makeItem(names.first.text, pieces[i].text));
      out.addAll(names.sublist(1, names.length - 1));
      out.add(makeItem(names.last.text, pieces[i + 2].text));
      return out;
    }
    // "2 packets milk 500 ml"
    out.add(makeItem(names.first.text, lastOne ? '${pieces[i].text} ${pieces[i + 2].text}' : pieces[i].text));
    out.addAll(names.skip(1));
  }
  return out;
}

/// "milk and eggs" and "milk eggs bread" are several items; "butter milk" is one.
List<PageItem> _names(String text) {
  final words = text.split(' ');
  final byAnd = <List<String>>[[]];
  for (final w in words) {
    if (_and.contains(w.toLowerCase())) {
      byAnd.add([]);
    } else {
      byAnd.last.add(w);
    }
  }
  final parts = [for (final p in byAnd) p.join(' ')];
  final flavour = RegExp(r'\b(?:salt and (?:vinegar|pepper)|cream and onion)\b', caseSensitive: false).hasMatch(text);
  if (parts.length > 1 &&
      !flavour && parts.every((p) => p.isNotEmpty && endsInKnownItem(p))) {
    return [for (final p in parts) ..._names(p)];
  }
  final split = splitKnownItems(text);
  if (split != null && split.length >= 3) return [for (final s in split) makeItem(s, '')];
  return [makeItem(text, '')];
}

// ---------- what is said back ----------

String itemLabel(PageItem i) => i.qty.isEmpty ? i.text : '${i.text} ${i.qty}';

/// "Shampoo 5 packets added successfully".
String addedSays(List<PageItem> added, AppLanguage language) {
  final n = added.length;
  final what = n <= 4
      ? added.map(itemLabel).join(', ')
      : switch (language) {
          AppLanguage.english => '$n items',
          AppLanguage.telugu => '$n వస్తువులు',
          AppLanguage.hindi => '$n चीज़ें',
          AppLanguage.kannada => '$n ವಸ್ತುಗಳು',
          AppLanguage.tamil => '$n பொருட்கள்',
        };
  return switch (language) {
    AppLanguage.english => '$what added successfully',
    AppLanguage.telugu => '$what విజయవంతంగా చేర్చాను',
    AppLanguage.hindi => '$what सफलतापूर्वक जोड़ दिया',
    AppLanguage.kannada => '$what ಯಶಸ್ವಿಯಾಗಿ ಸೇರಿಸಿದ್ದೇನೆ',
    AppLanguage.tamil => '$what வெற்றிகரமாக சேர்த்துவிட்டேன்',
  };
}

String alreadySays(List<String> names, AppLanguage language) {
  final what = names.join(', ');
  return switch (language) {
    AppLanguage.english => '$what ${names.length == 1 ? 'is' : 'are'} already in the list',
    AppLanguage.telugu => '$what ఇప్పటికే జాబితాలో ఉంది',
    AppLanguage.hindi => '$what पहले से सूची में है',
    AppLanguage.kannada => '$what ಈಗಾಗಲೇ ಪಟ್ಟಿಯಲ್ಲಿದೆ',
    AppLanguage.tamil => '$what ஏற்கனவே பட்டியலில் உள்ளது',
  };
}

String notUnderstoodSays(AppLanguage language) => switch (language) {
  AppLanguage.english => 'Could not understand. Say: shampoo 5 packets',
  AppLanguage.telugu => 'అర్థం కాలేదు. ఇలా చెప్పండి: షాంపూ 5 ప్యాకెట్లు',
  AppLanguage.hindi => 'समझ नहीं आया। ऐसे बोलें: शैम्पू 5 पैकेट',
  AppLanguage.kannada => 'ಅರ್ಥವಾಗಲಿಲ್ಲ. ಹೀಗೆ ಹೇಳಿ: ಶಾಂಪೂ 5 ಪ್ಯಾಕೆಟ್',
  AppLanguage.tamil => 'புரியவில்லை. இப்படி சொல்லுங்கள்: ஷாம்பு 5 பாக்கெட்',
};
