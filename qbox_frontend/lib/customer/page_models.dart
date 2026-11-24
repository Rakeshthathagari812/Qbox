import 'package:flutter/services.dart';

import '../udhaar/udhaar_models.dart' show newClientRef;

/// Checklist & Notes: what a list and a note are, reading typed, spoken or
/// pasted items, and joining changes made on two phones.

const maxItems = 200;
const maxItemChars = 120;
const maxQtyChars = 30;
const maxTitleChars = 80;
const maxNoteChars = 10000;

/// At most [max] characters, counted the way the server counts them (one Telugu
/// or Hindi letter can be several).
String cutTo(String text, int max) =>
    text.runes.length <= max ? text : String.fromCharCodes(text.runes.take(max));

/// On one line, with no spaces around it.
String oneLine(String text) => text.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Stops typing (or cuts a paste) at [max] characters.
class CharLimit extends TextInputFormatter {
  CharLimit(this.max);

  final int max;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.runes.length <= max) return newValue;
    final text = cutTo(newValue.text, max);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

class PageItem {
  const PageItem({required this.ref, required this.text, this.qty = '', this.done = false});

  PageItem.create(this.text, {this.qty = ''}) : ref = newClientRef(), done = false;

  final String ref;
  final String text;

  /// "2 kg", or empty.
  final String qty;
  final bool done;

  PageItem copyWith({String? text, String? qty, bool? done}) =>
      PageItem(ref: ref, text: text ?? this.text, qty: qty ?? this.qty, done: done ?? this.done);

  Map<String, dynamic> toJson() => {'ref': ref, 'text': text, 'qty': qty, 'done': done};

  static PageItem? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final ref = json['ref'];
    final text = json['text'];
    if (ref is! String || text is! String) return null;
    return PageItem(ref: ref, text: text, qty: json['qty'] is String ? json['qty'] as String : '', done: json['done'] == true);
  }

  @override
  bool operator ==(Object other) =>
      other is PageItem && other.ref == ref && other.text == text && other.qty == qty && other.done == done;

  @override
  int get hashCode => Object.hash(ref, text, qty, done);
}

/// One list ([isList]) or one note.
class QboxPage {
  const QboxPage({
    required this.ref,
    required this.isList,
    this.title = '',
    this.text = '',
    this.items = const [],
    this.pinned = false,
    this.version = 0,
    this.saveRef = '',
    required this.updatedAt,
  });

  final String ref;
  final bool isList;
  final String title;

  /// Notes only.
  final String text;

  /// Lists only.
  final List<PageItem> items;
  final bool pinned;

  /// The server's count of saves; 0 = not on the server yet.
  final int version;

  /// Which save made this version.
  final String saveRef;
  final DateTime updatedAt;

  int get doneCount => items.where((i) => i.done).length;

  List<PageItem> get left => items.where((i) => !i.done).toList();

  List<PageItem> get done => items.where((i) => i.done).toList();

  /// What to call it: a note without a title shows its first line.
  String get name {
    if (title.isNotEmpty) return title;
    return text.split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => 'Note');
  }

  bool get isEmptyNote => !isList && title.trim().isEmpty && text.trim().isEmpty;

  bool matches(String search) {
    final q = search.trim().toLowerCase();
    return q.isEmpty ||
        title.toLowerCase().contains(q) ||
        text.toLowerCase().contains(q) ||
        items.any((i) => i.text.toLowerCase().contains(q));
  }

  QboxPage copyWith({
    String? ref,
    String? title,
    String? text,
    List<PageItem>? items,
    bool? pinned,
    int? version,
    DateTime? updatedAt,
  }) => QboxPage(
    ref: ref ?? this.ref,
    isList: isList,
    title: title ?? this.title,
    text: text ?? this.text,
    items: items ?? this.items,
    pinned: pinned ?? this.pinned,
    version: version ?? this.version,
    saveRef: saveRef,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  bool sameContent(QboxPage other) =>
      other.title == title &&
      other.text == text &&
      other.pinned == pinned &&
      other.items.length == items.length &&
      [for (var i = 0; i < items.length; i++) items[i] == other.items[i]].every((same) => same);

  Map<String, dynamic> toJson() => {
    'ref': ref,
    'kind': isList ? 'LIST' : 'NOTE',
    'title': title,
    'text': text,
    'items': [for (final i in items) i.toJson()],
    'pinned': pinned,
    'version': version,
    'saveRef': saveRef,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static QboxPage? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final ref = json['ref'];
    final updatedAt = DateTime.tryParse('${json['updatedAt']}');
    if (ref is! String || updatedAt == null || (json['kind'] != 'LIST' && json['kind'] != 'NOTE')) return null;
    final items = json['items'];
    return QboxPage(
      ref: ref,
      isList: json['kind'] == 'LIST',
      title: json['title'] is String ? json['title'] as String : '',
      text: json['text'] is String ? json['text'] as String : '',
      items: items is List ? items.map(PageItem.fromJson).whereType<PageItem>().toList() : const [],
      pinned: json['pinned'] == true,
      version: json['version'] is int ? json['version'] as int : 0,
      saveRef: json['saveRef'] is String ? json['saveRef'] as String : '',
      updatedAt: updatedAt.toLocal(),
    );
  }
}

/// Pinned first, then last changed first.
List<QboxPage> sortPages(Iterable<QboxPage> pages) => pages.toList()
  ..sort((a, b) => a.pinned != b.pinned ? (a.pinned ? -1 : 1) : b.updatedAt.compareTo(a.updatedAt));

// ---------- reading items ----------

const _number = r'(?:\d+(?:\.\d+)?(?:\s*/\s*\d+)?|half|quarter|½|¼)';
const _unit =
    r'(?:kgs?|kilos?|kilograms?|g|gms?|grams?|l|ltrs?|lit(?:re|er)s?|ml|packets?|packs?|pkts?|pieces?|pcs?|'
    r'dozens?|bottles?|box(?:es)?|bunch(?:es)?|bags?|tins?|strips?)';
final _qtyOnly = RegExp('^($_number\\s*$_unit)\$', caseSensitive: false);
final _qtyFirst = RegExp('^($_number\\s*$_unit)\\s+(?:of\\s+)?(.+)\$', caseSensitive: false);
final _qtyLast = RegExp('^(.+?)[\\s:=–-]+($_number\\s*$_unit)\$', caseSensitive: false);
final _qtyGap = RegExp(r'(\d|½|¼)([a-z])', caseSensitive: false);

/// Bullets, ticks and numbering in front of a pasted line.
final _bullet = RegExp(r'^(?:[•●▪◦*✓✔☐☑✅-]+\s*|\d{1,3}[.)]\s+)+');

/// Several items typed, spoken or pasted: one on each line, or with commas
/// between them. "2 kg rice" and "Rice, 2 kg" both become Rice with 2 kg.
List<PageItem> readItems(String words) {
  final found = <PageItem>[];
  for (final line in words.split(RegExp(r'[\n;]'))) {
    // The *Name* line of a list sent on WhatsApp.
    if (RegExp(r'^\s*\*[^*]+\*\s*$').hasMatch(line)) continue;
    var first = true;
    for (final part in line.replaceFirst(_bullet, '').split(RegExp(r'[,،](?!\d)'))) {
      final text = part.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (text.isEmpty) continue;
      final qtyOnly = _qtyOnly.firstMatch(text);
      if (qtyOnly != null && !first && found.isNotEmpty && found.last.qty.isEmpty) {
        found.last = PageItem.create(found.last.text, qty: _tidyQty(text));
        continue;
      }
      first = false;
      found.add(_readOne(text));
    }
  }
  return found;
}

PageItem _readOne(String text) {
  final front = _qtyFirst.firstMatch(text);
  if (front != null) return _make(front[2]!, front[1]!);
  final back = _qtyLast.firstMatch(text);
  if (back != null) return _make(back[1]!, back[2]!);
  return _make(text, '');
}

PageItem _make(String text, String qty) {
  final cut = cutTo(text, maxItemChars).trim();
  return PageItem.create(cut.isEmpty ? cut : cut[0].toUpperCase() + cut.substring(1), qty: _tidyQty(qty));
}

String _tidyQty(String qty) => qty.replaceAllMapped(_qtyGap, (m) => '${m[1]} ${m[2]}').trim();

/// The list with [added]. One that is there already is not added twice; if it
/// was ticked, it is needed again. [already] gets the names of those.
List<PageItem> addItems(List<PageItem> items, List<PageItem> added, {List<String>? already}) {
  final out = List.of(items);
  for (final a in added) {
    final at = out.indexWhere((i) => i.text.toLowerCase() == a.text.toLowerCase() && (a.qty.isEmpty || i.done || i.qty == a.qty));
    if (at < 0) {
      out.add(a);
    } else if (out[at].done) {
      out[at] = out[at].copyWith(done: false, qty: a.qty.isEmpty ? null : a.qty);
    } else {
      already?.add(out[at].text);
    }
  }
  return out;
}

/// A list or note as a message.
String shareText(QboxPage page) {
  if (!page.isList) return page.title.isEmpty ? page.text : '*${page.title}*\n${page.text}';
  String line(PageItem i) => '${i.text}${i.qty.isEmpty ? '' : ' - ${i.qty}'}';
  return [
    '*${page.title}*',
    for (final i in page.left) '• ${line(i)}',
    for (final i in page.done) '✓ ${line(i)}',
  ].join('\n');
}

// ---------- two phones ----------

/// Joins this phone's changes ([mine]) with another phone's ([theirs]); both
/// started from [base] (null = nothing). Nothing written is lost.
QboxPage joinPages(QboxPage? base, QboxPage mine, QboxPage theirs) {
  final from = {for (final i in base?.items ?? const <PageItem>[]) i.ref: i};
  final my = {for (final i in mine.items) i.ref: i};
  final their = {for (final i in theirs.items) i.ref: i};
  final items = <PageItem>[];
  for (final t in theirs.items) {
    final m = my[t.ref];
    final b = from[t.ref];
    if (m == null) {
      // Removed here, unless it was changed there since.
      if (b == null || b != t) items.add(t);
    } else {
      items.add(
        PageItem(
          ref: t.ref,
          text: b != null && m.text == b.text ? t.text : m.text,
          qty: b != null && m.qty == b.qty ? t.qty : m.qty,
          done: b != null && m.done == b.done ? t.done : m.done,
        ),
      );
    }
  }
  for (final m in mine.items) {
    // Added here, or removed there but changed here since.
    if (!their.containsKey(m.ref) && from[m.ref] != m) items.add(m);
  }
  return mine.copyWith(
    title: base != null && mine.title == base.title ? theirs.title : mine.title,
    text: joinText(base?.text ?? '', mine.text, theirs.text),
    items: items.length > maxItems ? items.sublist(0, maxItems) : items,
    pinned: base != null && mine.pinned == base.pinned ? theirs.pinned : mine.pinned,
  );
}

/// When both changed the same note, both are kept, one after the other.
String joinText(String base, String mine, String theirs) {
  if (mine == theirs || theirs == base) return mine;
  if (mine == base) return theirs;
  if (mine.contains(theirs)) return mine;
  if (theirs.contains(mine)) return theirs;
  final both = '$theirs\n\n$mine';
  return cutTo(both, maxNoteChars);
}
