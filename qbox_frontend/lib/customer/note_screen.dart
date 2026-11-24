import 'dart:async';

import 'package:flutter/material.dart';

import '../udhaar/udhaar_models.dart' show newClientRef;
import '../udhaar/udhaar_widgets.dart';
import '../widgets/whatsapp_icon.dart';
import 'page_models.dart';
import 'page_widgets.dart';
import 'pages_repository.dart';

/// One note, typed or spoken. Saves by itself. Closes with the note if it was
/// deleted.
class NoteScreen extends StatefulWidget {
  const NoteScreen({required this.pageRef, super.key});

  /// A note not saved yet starts empty.
  final String pageRef;

  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> with VoiceWords, WidgetsBindingObserver {
  final _title = TextEditingController();
  final _text = TextEditingController();
  late String _ref = widget.pageRef;

  /// The note as it was last read from, or given to, [_pages].
  QboxPage? _known;
  Timer? _timer;

  PagesRepository get _pages => app.pages;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onServices() {
    _known = _pages.page(_ref);
    _title.text = _known?.title ?? '';
    _text.text = _known?.text ?? '';
    _pages.addListener(_changedElsewhere);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.removeListener(_changedElsewhere);
    WidgetsBinding.instance.removeObserver(this);
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The phone may close QBOX while it is in the background.
    if (state != AppLifecycleState.resumed) _save();
  }

  bool get _empty => oneLine(_title.text).isEmpty && _text.text.trim().isEmpty;

  void _typed() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 800), _save);
    setState(() {});
  }

  /// Another phone's change came in: joined with what is being typed here.
  void _changedElsewhere() {
    final known = _known;
    final page = _pages.page(_ref);
    if (known == null || page == null) return;
    if (page.title != known.title && page.title != oneLine(_title.text)) _title.text = page.title;
    final text = joinText(known.text, _text.text, page.text);
    if (text != _text.text) {
      _text.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    }
    _known = page;
    if (mounted) setState(() {});
  }

  void _save() {
    _timer?.cancel();
    if (_empty) return; // an empty note is dropped on leaving
    final title = oneLine(_title.text);
    final now = _pages.page(_ref);
    if (now == null) {
      final known = _known;
      if (known != null) {
        // Deleted on another phone. Changed here since: kept as a new note.
        if (known.title == title && known.text == _text.text) return;
        _ref = newClientRef();
      }
      final made = QboxPage(
        ref: _ref,
        isList: false,
        title: title,
        text: _text.text,
        pinned: known?.pinned ?? false,
        updatedAt: DateTime.now(),
      );
      _known = made;
      _pages.put(made);
    } else {
      final changed = now.copyWith(title: title, text: _text.text);
      _known = changed;
      _pages.put(changed);
    }
  }

  void _leave() {
    final navigator = Navigator.of(context);
    final known = _known;
    if (_empty && known != null && _pages.page(_ref) != null) {
      _pages.remove(_ref);
      navigator.pop(known);
      return;
    }
    _save();
    navigator.pop();
  }

  void _heardWords(String words) {
    final before = _text.text;
    final gap = before.isEmpty || before.endsWith('\n') || before.endsWith(' ') ? '' : ' ';
    final text = cutTo('$before$gap$words', maxNoteChars);
    _text.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    _typed();
  }

  Future<void> _menu(String choice) async {
    _save();
    final page = _pages.page(_ref);
    if (page == null) return;
    switch (choice) {
      case 'pin':
        _pages.update(_ref, (p) => p.copyWith(pinned: !p.pinned));
      case 'delete':
        if (!await sureToDelete(context, page) || !mounted) return;
        _timer?.cancel();
        _pages.remove(_ref);
        Navigator.of(context).pop(page);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages.page(_ref);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: udBackground,
        body: SafeArea(
          child: Column(
            children: [
              UdHeader(
                title: 'Note',
                subtitle: 'Saves by itself',
                actions: [
                  IconButton(
                    key: const Key('note-whatsapp'),
                    onPressed: _empty
                        ? null
                        : () {
                            _save();
                            final saved = _pages.page(_ref);
                            if (saved != null) sendOnWhatsApp(saved);
                          },
                    icon: Opacity(opacity: _empty ? 0.4 : 1, child: const WhatsAppIcon()),
                    tooltip: 'Send on WhatsApp',
                  ),
                  PopupMenuButton<String>(
                    key: const Key('note-menu'),
                    enabled: !_empty,
                    iconColor: udPurple,
                    onSelected: _menu,
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'pin', child: Text(page?.pinned ?? false ? 'Unpin' : 'Pin to top')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete note')),
                    ],
                  ),
                ],
              ),
              ListenableBuilder(listenable: _pages, builder: (_, _) => PagesBanner(_pages)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: UdCard(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Column(
                      children: [
                        TextField(
                          key: const Key('note-title'),
                          controller: _title,
                          onChanged: (_) => _typed(),
                          textCapitalization: TextCapitalization.sentences,
                          inputFormatters: [CharLimit(maxTitleChars)],
                          style: udText(18, weight: FontWeight.w700),
                          decoration: const InputDecoration(hintText: 'Title (optional)', border: InputBorder.none),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: TextField(
                            key: const Key('note-text'),
                            controller: _text,
                            onChanged: (_) => _typed(),
                            expands: true,
                            maxLines: null,
                            textAlignVertical: TextAlignVertical.top,
                            textCapitalization: TextCapitalization.sentences,
                            inputFormatters: [CharLimit(maxNoteChars)],
                            style: udText(15),
                            decoration: const InputDecoration(hintText: 'Write or speak', border: InputBorder.none),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: [
                    heardBox('Listening…'),
                    Row(
                      children: [
                        Expanded(child: Align(alignment: Alignment.centerLeft, child: voiceChip())),
                        micButton(() => speak(_heardWords)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
