/// Puts right what voice typing often mishears about shop items.
///
/// Voice typing does not know that someone is naming shop items: "eggs 12" comes
/// back as "x 12". It is only put right next to a quantity (or a word like "sold"),
/// so "2 x 500 ml" and "x ray" stay as they were heard.
library;

import 'stock_catalog.dart';
import 'voice_stock.dart' show latinWords, soundsClose;

const _eggSounds = {'x', 'xs', "x's", 'ex', 'exs', 'eks', 'eggz', 'aegs', 'egs'};
const _nativeEggSounds = {'ఎక్స్': 'ఎగ్స్', 'एक्स': 'एग्स', 'ಎಕ್ಸ್': 'ಎಗ್ಸ್', 'எக்ஸ்': 'எக்ஸ்'};

const _countWords = {
  'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen',
  'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty', 'thirty', 'forty', 'fifty',
  'sixty', 'seventy', 'eighty', 'ninety', 'hundred', 'half', 'dozen', 'dozens', 'tray', 'trays',
};
const _eggUnits = {'dozen', 'dozens', 'tray', 'trays', 'piece', 'pieces'};
const _aboutStock = {'sold', 'came', 'stock', 'left', 'price', 'finished', 'available', 'arrived'};

final _numberToken = RegExp(r'^\d+(?:\.\d+)?[.,]?$');

/// [text] with those put right.
String fixHeard(String text) {
  final tokens = text.trim().split(RegExp(r'\s+'));
  bool isNumber(int i) => i >= 0 && i < tokens.length && _numberToken.hasMatch(tokens[i]);
  bool isCount(int i) =>
      i >= 0 && i < tokens.length && (isNumber(i) || _countWords.contains(tokens[i].toLowerCase()));
  bool inSet(int i, Set<String> words) => i >= 0 && i < tokens.length && words.contains(tokens[i].toLowerCase());

  final out = List.of(tokens);
  for (var i = 0; i < tokens.length; i++) {
    final bare = tokens[i].replaceAll(RegExp(r'[.,!?]+$'), '');
    final after = tokens[i].substring(bare.length);
    final native = _nativeEggSounds[bare];
    if (native == null && !_eggSounds.contains(bare.toLowerCase())) continue;
    // "2 x 500 ml" and "3 x 4" are sums, not eggs.
    if (isNumber(i - 1) && isNumber(i + 1) && after.isEmpty) continue;
    final sure = tokens.length == 1 ||
        isCount(i + 1) ||
        isCount(i - 1) ||
        inSet(i - 1, _eggUnits) ||
        inSet(i + 1, _aboutStock) ||
        (inSet(i - 1, const {'many', 'much'}) && inSet(i - 2, const {'how'}));
    if (!sure) continue;
    out[i] = '${native ?? 'eggs'}$after';
  }
  return out.join(' ');
}

/// "Eggs" and "egg", "ఉల్లిపాయలు"... in one shape, to compare.
String _shape(String name) => latinWords(name.replaceAll(RegExp(r'\(.*?\)'), ' '))
    .map((w) => w.length > 2 && w.endsWith('s') ? w.substring(0, w.length - 1) : w)
    .join(' ');

final Set<String> _known = {
  for (final c in stockCatalog)
    for (final name in c.allNames) ...[
      _shape(name),
      // "Cumin (jeera)" is also jeera.
      for (final inside in RegExp(r'\((.*?)\)').allMatches(name)) _shape(inside[1]!),
    ],
}..remove('');

/// Is [name] an item in the ready list (in any of the 5 languages)?
bool isKnownItem(String name) => _known.contains(_shape(name));

/// Does [name] end in one ("brown bread")?
bool endsInKnownItem(String name) {
  final words = name.trim().split(RegExp(r'\s+'));
  for (var i = 0; i < words.length; i++) {
    if (isKnownItem(words.sublist(i).join(' '))) return true;
  }
  return false;
}

/// Two item names that together are one thing.
const _together = {
  'butter milk', 'coconut milk', 'milk bread', 'milk biscuits', 'butter biscuits', 'coconut biscuits', 'milk chocolate',
  'salt biscuits', 'tomato rice', 'lemon rice', 'coconut rice', 'onion chips', 'potato chips', 'banana chips',
  'lemon tea', 'ginger tea', 'lemon pickle', 'garlic bread', 'garlic pickle', 'tomato pickle', 'milk chocolates',
};

/// [text] cut into items of the ready list, longest first; null if any word is left over.
List<String>? splitKnownItems(String text) {
  final words = text.trim().split(RegExp(r'\s+'));
  final found = <String>[];
  var at = 0;
  while (at < words.length) {
    var end = words.length < at + 4 ? words.length : at + 4;
    bool isOne(String name) => isKnownItem(name) || _together.contains(name.toLowerCase());
    while (end > at && !isOne(words.sublist(at, end).join(' '))) {
      end--;
    }
    if (end == at) return null;
    found.add(words.sublist(at, end).join(' '));
    at = end;
  }
  return found;
}

/// Could [a] have been meant when [b] was heard?
bool heardAlike(String a, String b) {
  final x = latinWords(a).join();
  final y = latinWords(b).join();
  return x == y || (x.length >= 3 && y.length >= 3 && soundsClose(x, y));
}
