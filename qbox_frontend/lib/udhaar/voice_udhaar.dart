/// Turns a spoken udhaar sentence into who, how much, and which way.
///
///   "Ramesh 250 udhaar"          -> Ramesh, ₹250, udhaar given
///   "Ramesh paid 100"            -> Ramesh, ₹100, payment received
///   "received two fifty from Ravi" -> Ravi, ₹250, payment received
///   "gave Suresh 500"            -> Suresh, ₹500, udhaar given
///   "Suresh gave 500"            -> Suresh, ₹500, payment received
///
/// English only for now. The result is always shown to the shopkeeper to
/// check before anything is saved.
library;

import '../calculator/voice_math.dart';
import 'udhaar_models.dart';

class SpokenUdhaar {
  const SpokenUdhaar({
    required this.kind,
    required this.matches,
    required this.spokenName,
    this.amountPaise,
  });

  final EntryKind kind;
  final int? amountPaise;

  /// Customers whose name was heard. One = clear; several = ask which one;
  /// none = maybe a new customer called [spokenName].
  final List<UdhaarCustomer> matches;

  /// The words left over that look like a name ("Suresh"), for a new customer.
  final String spokenName;
}

const _paymentWords = {
  'paid', 'pay', 'pays', 'payment', 'received', 'receive', 'got', 'returned',
  'return', 'deposit', 'deposited', 'jama', 'cleared', 'settled', 'repaid',
  // Telugu (in English letters): he paid / he gave / it came
  'kattadu', 'kattindi', 'kattaru', 'katti', 'chellinchadu', 'ichadu', 'icchadu',
  'ichindi', 'ichaaru', 'vachindi', 'vacchindi',
  // Hindi (in English letters): returned / paid off
  'wapas', 'vapas', 'lautaya', 'lautaye', 'chukaya', 'chukaye', 'chuka', 'bharpai',
};
const _creditWords = {
  'udhaar', 'udhar', 'udaar', 'udhari', 'udhaari', 'credit', 'took', 'take',
  'taken', 'borrowed', 'loan', 'baki', 'baaki', 'owes', 'due', 'given', 'khata',
  // Telugu: he took / I gave
  'teesukunnadu', 'tisukunnadu', 'teeskunnadu', 'tiskunnadu', 'teesukundi',
  'ichanu', 'icchanu', 'appu',
  // Hindi: took
  'liya', 'liye',
};
// Hindi "diya/diye" (gave) depends on who: "Teja ne 500 diye" = he paid,
// "Teja ko 500 diye" = udhaar given to him.
const _hindiGave = {'diya', 'diye', 'di', 'de', 'dia'};
const _fillerWords = {
  'rupees', 'rupee', 'rs', 'to', 'from', 'for', 'the', 'a', 'an', 'me', 'us',
  'of', 'and', 'on', 'has', 'have', 'is', 'was', 'today', 'add', 'write',
  'entry', 'he', 'she', 'ki', 'ko', 'ka', 'se', 'ne', 'hai', 'please', 'mr',
  'mrs', 'sir', 'garu', 'anna', 'akka', 'bhai', 'ji', 'amount', 'cash', 'by',
  'in', 'with', 'customer', 'gave', 'give',
};

SpokenUdhaar? parseSpokenUdhaar(String spoken, List<UdhaarCustomer> customers) {
  final words = spoken
      .toLowerCase()
      .replaceAll(RegExp(r'(?<=[0-9]),(?=[0-9])'), '') // 1,500 -> 1500
      .replaceAll(RegExp(r'[₹]'), ' ')
      .replaceAll(RegExp(r"[^a-z0-9.\s]"), ' ')
      .split(RegExp(r'\s+'))
      .map((w) => w.endsWith('.') ? w.substring(0, w.length - 1) : w)
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return null;

  // 1. Who: customers whose name words were heard.
  final nameWordIndexes = <int>{};
  var best = 0;
  var matches = <UdhaarCustomer>[];
  for (final c in customers) {
    final hit = nameHits(c.name, words);
    if (hit.isEmpty) continue;
    if (hit.length > best) {
      best = hit.length;
      matches = [c];
    } else if (hit.length == best) {
      matches.add(c);
    }
  }
  for (final c in matches) {
    nameWordIndexes.addAll(nameHits(c.name, words));
  }
  final firstNameAt = nameWordIndexes.isEmpty
      ? -1
      : nameWordIndexes.reduce((a, b) => a < b ? a : b);

  // 2. Which way.
  var kind = EntryKind.credit;
  final gaveAt = words.indexOf('gave');
  if (words.any(_paymentWords.contains)) {
    kind = EntryKind.payment;
  } else if (words.any(_hindiGave.contains) && (words.contains('ne') || words.contains('ko'))) {
    kind = words.contains('ne') ? EntryKind.payment : EntryKind.credit;
  } else if (gaveAt >= 0) {
    // "Suresh gave 500" / "gave me 500" = he paid; "gave Suresh 500" = udhaar.
    final next = gaveAt + 1 < words.length ? words[gaveAt + 1] : '';
    final customerBefore = firstNameAt >= 0 && firstNameAt < gaveAt;
    if (next == 'me' || next == 'us' || customerBefore) kind = EntryKind.payment;
  }

  // 3. How much: the rest of the words, read like the calculator does.
  final rest = [
    for (var i = 0; i < words.length; i++)
      if (!nameWordIndexes.contains(i) &&
          !_paymentWords.contains(words[i]) &&
          !_creditWords.contains(words[i]) &&
          !_hindiGave.contains(words[i]))
        words[i],
  ];
  // Words the calculator would read as + or ÷ ("add 250", "paid by cash").
  const notMaths = {'add', 'by', 'over', 'less', 'x'};
  final sum = parseSpokenMath(rest.where((w) => !notMaths.contains(w)).join(' '));
  final value = sum == null ? null : double.tryParse(sum);
  final amount = value == null || value <= 0 ? null : (value * 100).round();

  // 4. Leftover name words, for a customer not in the book yet.
  final spokenName = rest
      .where((w) => !_fillerWords.contains(w) && !_isNumberish(w))
      .take(3)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  if (amount == null && matches.isEmpty) return null;
  return SpokenUdhaar(
    kind: kind,
    amountPaise: amount,
    matches: matches,
    spokenName: matches.isEmpty ? spokenName : '',
  );
}

/// Customers whose name appears in [text] (best matches only). Used for names
/// heard in Telugu/Hindi/Kannada/Tamil script, after writing them in English letters.
List<UdhaarCustomer> customersIn(String text, List<UdhaarCustomer> customers) {
  final words = text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  var best = 0;
  var matches = <UdhaarCustomer>[];
  for (final c in customers) {
    final hits = nameHits(c.name, words).length;
    if (hits == 0) continue;
    if (hits > best) {
      best = hits;
      matches = [c];
    } else if (hits == best) {
      matches.add(c);
    }
  }
  return matches;
}

/// The amount when [text] holds exactly one number written in digits
/// ("తేజ 500 ఇచ్చాడు" -> 50000 paise). Null otherwise.
int? digitsAmount(String text) {
  final numbers = RegExp(r'[0-9][0-9,]*(?:\.[0-9]{1,2})?')
      .allMatches(text)
      .map((m) => double.tryParse(m[0]!.replaceAll(',', '')))
      .whereType<double>()
      .toList();
  if (numbers.length != 1 || numbers.single <= 0) return null;
  return (numbers.single * 100).round();
}

/// Positions of [words] that match a word of [name] (allowing one wrong
/// letter in longer names, since speech recognition often misspells them).
Set<int> nameHits(String name, List<String> words) {
  final parts = name
      .toLowerCase()
      .split(RegExp(r'[^a-z]+'))
      .where((p) => p.length >= 2)
      .toList();
  final hits = <int>{};
  for (final part in parts) {
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      if (w == part || (part.length >= 4 && w.length >= 4 && _closeEnough(w, part))) {
        hits.add(i);
        break;
      }
    }
  }
  return hits;
}

/// True when [a] and [b] differ by at most one letter (added, removed or changed).
bool _closeEnough(String a, String b) {
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

const _numberWords = {
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
  'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen',
  'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty', 'thirty', 'forty',
  'fifty', 'sixty', 'seventy', 'eighty', 'ninety', 'hundred', 'thousand',
  'lakh', 'lakhs', 'lac', 'crore', 'point', 'oh', 'o',
};

bool _isNumberish(String w) => _numberWords.contains(w) || double.tryParse(w) != null;
