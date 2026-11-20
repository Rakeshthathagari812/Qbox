/// Writes Indian-script text in English letters, roughly as it sounds:
///   తేజ -> teja,  रमेश -> ramesha,  ಸುರೇಶ -> suresha,  தேஜா -> tejaa
///
/// Used to match spoken names against customers saved in English. It does
/// not need to be perfect: name matching already allows one wrong letter.
///
/// Devanagari, Bengali, Gurmukhi, Gujarati, Oriya, Tamil, Telugu, Kannada and
/// Malayalam all share one layout (each letter sits at the same position in
/// its Unicode block), so one table covers all of them.
String transliterate(String text) {
  final out = StringBuffer();
  final runes = text.runes.toList();
  for (var i = 0; i < runes.length; i++) {
    final cp = runes[i];
    if (cp < 0x0900 || cp > 0x0DFF) {
      out.writeCharCode(cp);
      continue;
    }
    final at = cp & 0x7F;
    final consonant = _consonants[at];
    if (consonant != null) {
      out.write(consonant);
      // A consonant carries "a" unless a vowel sign or virama follows.
      final next = i + 1 < runes.length ? runes[i + 1] : 0;
      final nextAt = _sameBlock(cp, next) ? next & 0x7F : -1;
      if (!_vowelSigns.containsKey(nextAt) && nextAt != _virama && nextAt != _nukta) {
        out.write('a');
      }
      continue;
    }
    final text = _vowels[at] ?? _vowelSigns[at] ?? _marks[at];
    if (text != null) {
      out.write(text);
    } else if (at >= 0x66 && at <= 0x6F) {
      out.write(at - 0x66); // Indian digits -> 0-9
    }
    // Anything else (virama, nukta, rare signs) is dropped.
  }
  return out.toString();
}

/// True if [text] has any Indian-script letters.
bool hasIndianScript(String text) => text.runes.any((cp) => cp >= 0x0900 && cp <= 0x0DFF);

bool _sameBlock(int a, int b) => b >= 0x0900 && b <= 0x0DFF && (a & ~0x7F) == (b & ~0x7F);

const _virama = 0x4D;
const _nukta = 0x3C;

const _vowels = {
  0x05: 'a', 0x06: 'aa', 0x07: 'i', 0x08: 'ii', 0x09: 'u', 0x0A: 'uu', 0x0B: 'ri',
  0x0E: 'e', 0x0F: 'e', 0x10: 'ai', 0x12: 'o', 0x13: 'o', 0x14: 'au',
};

const _vowelSigns = {
  0x3E: 'aa', 0x3F: 'i', 0x40: 'ii', 0x41: 'u', 0x42: 'uu', 0x43: 'ri',
  0x46: 'e', 0x47: 'e', 0x48: 'ai', 0x4A: 'o', 0x4B: 'o', 0x4C: 'au',
};

const _marks = {0x01: 'n', 0x02: 'n', 0x03: 'h'};

const _consonants = {
  0x15: 'k', 0x16: 'kh', 0x17: 'g', 0x18: 'gh', 0x19: 'ng',
  0x1A: 'ch', 0x1B: 'chh', 0x1C: 'j', 0x1D: 'jh', 0x1E: 'ny',
  0x1F: 't', 0x20: 'th', 0x21: 'd', 0x22: 'dh', 0x23: 'n',
  0x24: 't', 0x25: 'th', 0x26: 'd', 0x27: 'dh', 0x28: 'n', 0x29: 'n',
  0x2A: 'p', 0x2B: 'ph', 0x2C: 'b', 0x2D: 'bh', 0x2E: 'm',
  0x2F: 'y', 0x30: 'r', 0x31: 'r', 0x32: 'l', 0x33: 'l', 0x34: 'l', 0x35: 'v',
  0x36: 'sh', 0x37: 'sh', 0x38: 's', 0x39: 'h',
};
