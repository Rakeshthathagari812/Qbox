import 'package:flutter/material.dart';

import '../udhaar/udhaar_widgets.dart';
import '../widgets/whatsapp_icon.dart';
import 'page_models.dart';
import 'page_widgets.dart';
import 'pages_repository.dart';

/// "3 of 8 done", "All 8 done".
String doneLabel(QboxPage list) => list.left.isEmpty
    ? 'All ${list.items.length} done'
    : '${list.doneCount} of ${list.items.length} done';

/// One list: add items by typing, pasting or speaking; tap one to tick it.
/// Closes with the list if it was deleted.
class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({required this.pageRef, super.key});

  final String pageRef;

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> with VoiceWords {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  PagesRepository get _pages => app.pages;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _change(QboxPage Function(QboxPage list) change) => _pages.update(widget.pageRef, change);

  void _add() {
    final list = _pages.page(widget.pageRef);
    final added = readItems(_input.text);
    if (list == null || added.isEmpty) return;
    final already = <String>[];
    final items = addItems(list.items, added, already: already);
    if (items.length > maxItems) {
      udNotify(context, 'A list can have up to $maxItems items.');
      return;
    }
    _change((l) => l.copyWith(items: items));
    _input.clear();
    _focus.requestFocus();
    if (already.isNotEmpty) {
      udNotify(context, already.length == 1 ? '${already.single} is already here' : 'Already here: ${already.join(', ')}');
    }
    if (items.length > list.items.length) {
      // Show the newest one.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final at = (items.length - list.doneCount) * 56.0 - _scroll.position.viewportDimension + 56;
        _scroll.jumpTo(at.clamp(0, _scroll.position.maxScrollExtent));
      });
    }
  }

  /// The words go in the box first, to check them; then Add.
  void _heardWords(String words) {
    final before = _input.text.trim();
    _input.text = before.isEmpty ? words : '$before, $words';
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
  }

  void _tick(PageItem item) => _change(
    (l) => l.copyWith(items: [for (final i in l.items) i.ref == item.ref ? i.copyWith(done: !item.done) : i]),
  );

  Future<void> _edit(PageItem item) async {
    final answer = await showDialog<({bool remove, String text, String qty})>(
      context: context,
      builder: (_) => _ItemDialog(item),
    );
    if (answer == null || !mounted) return;
    if (!answer.remove) {
      _change(
        (l) => l.copyWith(
          items: [for (final i in l.items) i.ref == item.ref ? i.copyWith(text: answer.text, qty: answer.qty) : i],
        ),
      );
      return;
    }
    _removeItems((i) => i.ref == item.ref, '${item.text} removed');
  }

  void _removeItems(bool Function(PageItem item) which, String message) {
    final before = _pages.page(widget.pageRef)?.items ?? const <PageItem>[];
    _change((l) => l.copyWith(items: l.items.where((i) => !which(i)).toList()));
    notifyUndo(context, message, () {
      // Back in their old places, next to anything added since.
      _change((l) {
        final now = {for (final i in l.items) i.ref: i};
        final old = {for (final i in before) i.ref};
        return l.copyWith(
          items: [
            for (final i in before) ?(which(i) ? i : now[i.ref]),
            for (final i in l.items)
              if (!old.contains(i.ref)) i,
          ],
        );
      });
    });
  }

  Future<void> _menu(String choice, QboxPage list) async {
    switch (choice) {
      case 'again':
        _change((l) => l.copyWith(items: [for (final i in l.items) i.copyWith(done: false)]));
        udNotify(context, 'All items are ready to use again');
      case 'clear':
        _removeItems((i) => i.done, 'Ticked items removed');
      case 'pin':
        _change((l) => l.copyWith(pinned: !l.pinned));
      case 'rename':
        final name = await askListName(context, name: list.title);
        if (name != null && mounted) _change((l) => l.copyWith(title: name));
      case 'delete':
        if (!await sureToDelete(context, list) || !mounted) return;
        final page = _pages.page(widget.pageRef);
        _pages.remove(widget.pageRef);
        Navigator.of(context).pop(page);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _pages,
      builder: (context, _) {
        final list = _pages.page(widget.pageRef);
        return Scaffold(
          backgroundColor: udBackground,
          body: SafeArea(
            child: list == null
                ? const Column(
                    children: [
                      UdHeader(title: 'Checklist'),
                      Expanded(child: Center(child: Text('This list was deleted.', key: Key('list-gone')))),
                    ],
                  )
                : _body(list),
          ),
        );
      },
    );
  }

  Widget _body(QboxPage list) {
    final done = list.done;
    return Column(
      children: [
        UdHeader(
          title: list.title,
          subtitle: list.items.isEmpty ? 'No items yet' : doneLabel(list),
          actions: [
            IconButton(
              key: const Key('list-whatsapp'),
              onPressed: list.items.isEmpty ? null : () => sendOnWhatsApp(list),
              icon: Opacity(opacity: list.items.isEmpty ? 0.4 : 1, child: const WhatsAppIcon()),
              tooltip: 'Send on WhatsApp',
            ),
            PopupMenuButton<String>(
              key: const Key('list-menu'),
              iconColor: udPurple,
              onSelected: (choice) => _menu(choice, list),
              itemBuilder: (_) => [
                if (done.isNotEmpty) const PopupMenuItem(value: 'again', child: Text('Use again (untick all)')),
                if (done.isNotEmpty) const PopupMenuItem(value: 'clear', child: Text('Remove ticked items')),
                PopupMenuItem(value: 'pin', child: Text(list.pinned ? 'Unpin' : 'Pin to top')),
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                const PopupMenuItem(value: 'delete', child: Text('Delete list')),
              ],
            ),
          ],
        ),
        PagesBanner(_pages),
        if (list.items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                key: const Key('list-progress'),
                value: list.doneCount / list.items.length,
                minHeight: 8,
                color: udPaid,
                backgroundColor: udSoft,
              ),
            ),
          ),
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            children: [
              if (list.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text(
                    'Type or speak an item, like "Rice 2 kg".\nFor many at once, put commas between them.',
                    key: const Key('list-empty'),
                    textAlign: TextAlign.center,
                    style: udText(14, color: udBody),
                  ),
                ),
              for (final i in list.left) _tile(i),
              if (done.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                  child: Text('Done (${done.length})', style: udText(13, weight: FontWeight.w700, color: udBody)),
                ),
              for (final i in done) _tile(i),
            ],
          ),
        ),
        _bottom(),
      ],
    );
  }

  Widget _tile(PageItem item) => Padding(
    key: Key('item-${item.ref}'),
    padding: const EdgeInsets.only(bottom: 6),
    child: Material(
      color: item.done ? const Color(0xFFF1EEF7) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: CheckboxListTile(
        dense: true,
        value: item.done,
        onChanged: (_) => _tick(item),
        activeColor: udPaid,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.only(left: 4),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.text,
                style: udText(
                  15,
                  weight: FontWeight.w600,
                  color: item.done ? udBody : udInk,
                  decoration: item.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (item.qty.isNotEmpty)
              Container(
                padding: const EdgeInsets.only(left: 8),
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(
                  item.qty,
                  textAlign: TextAlign.end,
                  style: udText(14, weight: FontWeight.w700, color: item.done ? udBody : udPurple),
                ),
              ),
          ],
        ),
        secondary: IconButton(
          key: Key('item-edit-${item.ref}'),
          onPressed: () => _edit(item),
          icon: const Icon(Icons.edit_outlined, size: 20, color: udBody),
          tooltip: 'Change ${item.text}',
        ),
      ),
    ),
  );

  Widget _bottom() => Container(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    color: Colors.white,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        heardBox('Listening… say: rice 2 kg'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const Key('item-input'),
                controller: _input,
                focusNode: _focus,
                minLines: 1,
                maxLines: 3, // a pasted list keeps its lines
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.sentences,
                style: udText(15),
                decoration: InputDecoration(
                  hintText: 'Add item',
                  isDense: true,
                  filled: true,
                  fillColor: udBackground,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
                onEditingComplete: _add, // the keyboard stays open for the next one
              ),
            ),
            const SizedBox(width: 8),
            micButton(() => speak(_heardWords)),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const Key('item-add'),
              onPressed: listening ? null : _add,
              style: IconButton.styleFrom(backgroundColor: udPurple, minimumSize: const Size(50, 50)),
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Add',
            ),
          ],
        ),
        voiceChip(),
      ],
    ),
  );
}

class _ItemDialog extends StatefulWidget {
  const _ItemDialog(this.item);

  final PageItem item;

  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  late final _text = TextEditingController(text: widget.item.text);
  late final _qty = TextEditingController(text: widget.item.qty);
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    _qty.dispose();
    super.dispose();
  }

  void _save() {
    final text = oneLine(_text.text);
    if (text.isEmpty) {
      setState(() => _error = 'Enter the item');
    } else {
      Navigator.of(context).pop((remove: false, text: text, qty: oneLine(_qty.text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Change item'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('item-text'),
            controller: _text,
            inputFormatters: [CharLimit(maxItemChars)],
            decoration: InputDecoration(labelText: 'Item', errorText: _error),
          ),
          TextField(
            key: const Key('item-qty'),
            controller: _qty,
            inputFormatters: [CharLimit(maxQtyChars)],
            decoration: const InputDecoration(labelText: 'How much (optional)', hintText: '2 kg'),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('item-remove'),
          onPressed: () => Navigator.of(context).pop((remove: true, text: '', qty: '')),
          style: TextButton.styleFrom(foregroundColor: udDue),
          child: const Text('Remove'),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('item-save'),
          onPressed: _save,
          style: FilledButton.styleFrom(backgroundColor: udPurple),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
